use crate::models::{
    ClaudeMessage, CodexThread, DailyCost, OverviewMetrics, PricingInfo, ProjectSummary,
    SessionDetail, SessionSummary, TurnMetrics,
};
use std::collections::HashMap;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;

fn get_claude_projects_dir() -> Option<PathBuf> {
    dirs::home_dir().map(|h| h.join(".claude").join("projects"))
}

fn get_codex_dir() -> Option<PathBuf> {
    dirs::home_dir().map(|h| h.join(".codex"))
}

fn decode_project_name(encoded: &str) -> String {
    encoded.replace("-", "/")
}

/// Normalize worktree paths to their parent repo path.
/// e.g. `/Users/dev/project/.worktrees/_9` → `/Users/dev/project`
/// Also handles `.claude/worktrees/` pattern.
fn normalize_project_path(path: &str) -> String {
    // Match /.worktrees/<name> at any position
    if let Some(idx) = path.find("/.worktrees/") {
        return path[..idx].to_string();
    }
    // Match /.claude/worktrees/<name> at any position
    if let Some(idx) = path.find("/.claude/worktrees/") {
        return path[..idx].to_string();
    }
    path.to_string()
}

fn parse_jsonl_file(path: &PathBuf) -> Vec<ClaudeMessage> {
    let file = match fs::File::open(path) {
        Ok(f) => f,
        Err(_) => return vec![],
    };
    let reader = BufReader::new(file);
    reader
        .lines()
        .filter_map(|line| {
            let line = line.ok()?;
            let trimmed = line.trim();
            if trimmed.is_empty() {
                return None;
            }
            serde_json::from_str::<ClaudeMessage>(trimmed).ok()
        })
        .collect()
}

fn summarize_session(
    session_id: &str,
    messages: &[ClaudeMessage],
    pricing: &PricingInfo,
    subagent_cost: f64,
    subagent_count: u32,
) -> SessionSummary {
    let mut total_input = 0u64;
    let mut total_output = 0u64;
    let mut total_cache_write = 0u64;
    let mut total_cache_read = 0u64;
    let mut total_eph_5m = 0u64;
    let mut total_eph_1h = 0u64;
    let mut msg_count = 0u32;
    let mut first_ts: Option<String> = None;
    let mut last_ts: Option<String> = None;
    let mut project = String::new();
    let mut git_branch: Option<String> = None;

    for msg in messages {
        let usage_opt = msg.message.as_ref().and_then(|m| m.usage.as_ref());
        if let Some(usage) = usage_opt {
            total_input += usage.input_tokens;
            total_output += usage.output_tokens;
            total_cache_write += usage.cache_creation_input_tokens;
            total_cache_read += usage.cache_read_input_tokens;
            if let Some(ref cd) = usage.cache_creation {
                total_eph_5m += cd.ephemeral_5m_input_tokens;
                total_eph_1h += cd.ephemeral_1h_input_tokens;
            }
        }
        if msg.r#type == "user" || msg.r#type == "assistant" {
            msg_count += 1;
        }
        if let Some(ref ts) = msg.timestamp {
            if first_ts.is_none() {
                first_ts = Some(ts.clone());
            }
            last_ts = Some(ts.clone());
        }
        if project.is_empty() {
            if let Some(ref cwd) = msg.cwd {
                project = normalize_project_path(cwd);
            }
        }
        if git_branch.is_none() {
            if let Some(ref branch) = msg.git_branch {
                git_branch = Some(branch.clone());
            }
        }
    }

    let total_context = total_cache_read + total_cache_write + total_input;
    let cache_hit_rate = if total_context > 0 {
        total_cache_read as f64 / total_context as f64
    } else {
        0.0
    };

    let cost = pricing.calculate_cost(total_input, total_cache_write, total_cache_read, total_output);

    SessionSummary {
        session_id: session_id.to_string(),
        project,
        git_branch,
        title: None,
        message_count: msg_count,
        total_input_tokens: total_input,
        total_output_tokens: total_output,
        total_cache_write_tokens: total_cache_write,
        total_cache_read_tokens: total_cache_read,
        cache_hit_rate,
        estimated_cost_usd: cost.total_cost + subagent_cost,
        first_timestamp: first_ts,
        last_timestamp: last_ts,
        subagent_count,
        subagent_cost_usd: subagent_cost,
        source: "claude".to_string(),
        ephemeral_5m_tokens: total_eph_5m,
        ephemeral_1h_tokens: total_eph_1h,
    }
}

pub fn get_session_detail(session_id: &str, pricing: &PricingInfo) -> Option<SessionDetail> {
    let projects_dir = get_claude_projects_dir()?;
    let pattern = format!("{}/**/{}.jsonl", projects_dir.display(), session_id);

    for entry in glob::glob(&pattern).ok()? {
        let path = match entry {
            Ok(p) => p,
            Err(_) => continue,
        };
        if path.to_string_lossy().contains("subagents") {
            continue;
        }

        let messages = parse_jsonl_file(&path);
        if messages.is_empty() {
            continue;
        }

        // Build per-turn metrics
        let mut turns = Vec::new();
        let mut turn_index = 0u32;
        let mut cumulative_context = 0u64;

        for msg in &messages {
            let usage_opt = msg.message.as_ref().and_then(|m| m.usage.as_ref());
            if let Some(usage) = usage_opt {
                let input = usage.input_tokens;
                let output = usage.output_tokens;
                let cw = usage.cache_creation_input_tokens;
                let cr = usage.cache_read_input_tokens;
                cumulative_context += input + cw + cr;

                let total_ctx = input + cw + cr;
                let hit_rate = if total_ctx > 0 { cr as f64 / total_ctx as f64 } else { 0.0 };
                let cost = pricing.calculate_cost(input, cw, cr, output);

                turns.push(TurnMetrics {
                    turn_index,
                    role: msg.r#type.clone(),
                    input_tokens: input,
                    output_tokens: output,
                    cache_write_tokens: cw,
                    cache_read_tokens: cr,
                    cumulative_context,
                    cache_hit_rate: hit_rate,
                    cost_usd: cost.total_cost,
                    timestamp: msg.timestamp.clone(),
                });
                turn_index += 1;
            }
        }

        // Build subagent info
        let subagent_dir = path.parent().map(|p| p.join(session_id).join("subagents"));
        let mut subagent_cost = 0.0;
        let mut subagent_count = 0u32;
        if let Some(ref sa_dir) = subagent_dir {
            if sa_dir.exists() {
                let sa_pattern = format!("{}/*.jsonl", sa_dir.display());
                for sa_entry in glob::glob(&sa_pattern).unwrap_or_else(|_| glob::glob("").unwrap()) {
                    if let Ok(sa_path) = sa_entry {
                        let sa_messages = parse_jsonl_file(&sa_path);
                        let sa_summary = summarize_session("", &sa_messages, pricing, 0.0, 0);
                        subagent_cost += sa_summary.estimated_cost_usd;
                        subagent_count += 1;
                    }
                }
            }
        }

        let summary = summarize_session(session_id, &messages, pricing, subagent_cost, subagent_count);
        return Some(SessionDetail { summary, turns });
    }

    None
}

pub fn load_claude_sessions(pricing: &PricingInfo) -> Vec<SessionSummary> {
    let projects_dir = match get_claude_projects_dir() {
        Some(d) => d,
        None => return vec![],
    };

    if !projects_dir.exists() {
        return vec![];
    }

    let mut sessions = vec![];

    let pattern = format!("{}/**/*.jsonl", projects_dir.display());
    for entry in glob::glob(&pattern).unwrap_or_else(|_| glob::glob("").unwrap()) {
        let path = match entry {
            Ok(p) => p,
            Err(_) => continue,
        };

        // Skip subagent files for main session parsing
        if path.to_string_lossy().contains("subagents") {
            continue;
        }

        let session_id = path
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default();

        // Parse subagent sessions
        let subagent_dir = path.parent().map(|p| p.join(&session_id).join("subagents"));
        let mut subagent_cost = 0.0;
        let mut subagent_count = 0u32;

        if let Some(ref sa_dir) = subagent_dir {
            if sa_dir.exists() {
                let sa_pattern = format!("{}/*.jsonl", sa_dir.display());
                for sa_entry in glob::glob(&sa_pattern).unwrap_or_else(|_| glob::glob("").unwrap()) {
                    if let Ok(sa_path) = sa_entry {
                        let sa_messages = parse_jsonl_file(&sa_path);
                        let sa_summary = summarize_session("", &sa_messages, pricing, 0.0, 0);
                        subagent_cost += sa_summary.estimated_cost_usd;
                        subagent_count += 1;
                    }
                }
            }
        }

        let messages = parse_jsonl_file(&path);
        if messages.is_empty() {
            continue;
        }

        let mut summary = summarize_session(&session_id, &messages, pricing, subagent_cost, subagent_count);

        // Try to get project name from path
        if summary.project.is_empty() {
            if let Some(parent) = path.parent() {
                if let Some(dir_name) = parent.file_name() {
                    let decoded = decode_project_name(&dir_name.to_string_lossy());
                    summary.project = normalize_project_path(&decoded);
                }
            }
        }

        sessions.push(summary);
    }

    sessions.sort_by(|a, b| {
        b.last_timestamp
            .as_deref()
            .unwrap_or("")
            .cmp(&a.last_timestamp.as_deref().unwrap_or(""))
    });

    sessions
}

pub fn load_codex_sessions(pricing: &PricingInfo) -> Vec<SessionSummary> {
    let codex_dir = match get_codex_dir() {
        Some(d) => d,
        None => return vec![],
    };

    let db_path = codex_dir.join("state_5.sqlite");
    if !db_path.exists() {
        return vec![];
    }

    let conn = match rusqlite::Connection::open_with_flags(
        &db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    ) {
        Ok(c) => c,
        Err(_) => return vec![],
    };

    let mut stmt = match conn.prepare(
        "SELECT id, tokens_used, model_provider, title, cwd, created_at, git_branch FROM threads ORDER BY created_at DESC",
    ) {
        Ok(s) => s,
        Err(_) => return vec![],
    };

    let rows = stmt
        .query_map([], |row| {
            let created_at_unix: Option<i64> = row.get(5)?;
            let created_at = created_at_unix.map(|ts| {
                chrono::DateTime::from_timestamp(ts, 0)
                    .map(|dt| dt.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string())
                    .unwrap_or_default()
            });
            Ok(CodexThread {
                id: row.get(0)?,
                tokens_used: row.get(1)?,
                model_provider: row.get(2)?,
                title: row.get(3)?,
                cwd: row.get(4)?,
                created_at,
                git_branch: row.get(6)?,
            })
        })
        .ok();

    let mut sessions = vec![];
    if let Some(rows) = rows {
        for row in rows.flatten() {
            let tokens = row.tokens_used.unwrap_or(0);
            // Codex doesn't separate cache tokens — treat all as input+output estimate
            let estimated_input = (tokens as f64 * 0.7) as u64;
            let estimated_output = tokens - estimated_input;
            let cost = pricing.calculate_cost(estimated_input, 0, 0, estimated_output);

            sessions.push(SessionSummary {
                session_id: row.id,
                project: normalize_project_path(&row.cwd.unwrap_or_default()),
                git_branch: row.git_branch,
                title: row.title,
                message_count: 0,
                total_input_tokens: estimated_input,
                total_output_tokens: estimated_output,
                total_cache_write_tokens: 0,
                total_cache_read_tokens: 0,
                cache_hit_rate: 0.0,
                estimated_cost_usd: cost.total_cost,
                first_timestamp: row.created_at.clone(),
                last_timestamp: row.created_at,
                subagent_count: 0,
                subagent_cost_usd: 0.0,
                source: "codex".to_string(),
                ephemeral_5m_tokens: 0,
                ephemeral_1h_tokens: 0,
            });
        }
    }

    sessions
}

pub fn build_overview(sessions: &[SessionSummary], pricing: &PricingInfo) -> OverviewMetrics {
    let mut total_input = 0u64;
    let mut total_output = 0u64;
    let mut total_cache_write = 0u64;
    let mut total_cache_read = 0u64;
    let mut total_cost = 0.0f64;
    let mut project_map: HashMap<String, Vec<&SessionSummary>> = HashMap::new();
    let mut daily_map: HashMap<String, DailyCost> = HashMap::new();

    // Estimate system overhead: first-turn cache_creation is mostly system prompt + tools
    let mut system_overhead = 0u64;

    for session in sessions {
        total_input += session.total_input_tokens;
        total_output += session.total_output_tokens;
        total_cache_write += session.total_cache_write_tokens;
        total_cache_read += session.total_cache_read_tokens;
        total_cost += session.estimated_cost_usd;

        // Group by project
        let project_key = if session.project.is_empty() {
            "unknown".to_string()
        } else {
            session.project.clone()
        };
        project_map
            .entry(project_key)
            .or_default()
            .push(session);

        // Group by day
        if let Some(ref ts) = session.first_timestamp {
            let date = ts.get(..10).unwrap_or("unknown").to_string();
            let entry = daily_map.entry(date.clone()).or_insert(DailyCost {
                date,
                cost_usd: 0.0,
                input_tokens: 0,
                output_tokens: 0,
                cache_write_tokens: 0,
                cache_read_tokens: 0,
                source: session.source.clone(),
            });
            entry.cost_usd += session.estimated_cost_usd;
            entry.input_tokens += session.total_input_tokens;
            entry.output_tokens += session.total_output_tokens;
            entry.cache_write_tokens += session.total_cache_write_tokens;
            entry.cache_read_tokens += session.total_cache_read_tokens;
        }

        // Each session's cache_write is roughly the system overhead
        if session.source == "claude" && session.total_cache_write_tokens > 0 {
            // Approximate: first session write ≈ system context size
            system_overhead = system_overhead.max(session.total_cache_write_tokens);
        }
    }

    let total_context = total_cache_read + total_cache_write + total_input;
    let avg_cache_hit_rate = if total_context > 0 {
        total_cache_read as f64 / total_context as f64
    } else {
        0.0
    };

    let cost_breakdown = pricing.calculate_cost(total_input, total_cache_write, total_cache_read, total_output);

    let mut project_summaries: Vec<ProjectSummary> = project_map
        .iter()
        .map(|(proj, sess)| {
            let p_input: u64 = sess.iter().map(|s| s.total_input_tokens).sum();
            let p_output: u64 = sess.iter().map(|s| s.total_output_tokens).sum();
            let p_cw: u64 = sess.iter().map(|s| s.total_cache_write_tokens).sum();
            let p_cr: u64 = sess.iter().map(|s| s.total_cache_read_tokens).sum();
            let p_cost: f64 = sess.iter().map(|s| s.estimated_cost_usd).sum();
            let p_total_ctx = p_cr + p_cw + p_input;
            let p_hit_rate = if p_total_ctx > 0 {
                p_cr as f64 / p_total_ctx as f64
            } else {
                0.0
            };
            ProjectSummary {
                project: proj.clone(),
                session_count: sess.len() as u32,
                total_cost_usd: p_cost,
                total_input_tokens: p_input,
                total_output_tokens: p_output,
                total_cache_write_tokens: p_cw,
                total_cache_read_tokens: p_cr,
                avg_cache_hit_rate: p_hit_rate,
            }
        })
        .collect();

    project_summaries.sort_by(|a, b| b.total_cost_usd.partial_cmp(&a.total_cost_usd).unwrap());

    let mut daily_costs: Vec<DailyCost> = daily_map.into_values().collect();
    daily_costs.sort_by(|a, b| a.date.cmp(&b.date));

    let mut top_sessions: Vec<SessionSummary> = sessions.to_vec();
    top_sessions.sort_by(|a, b| b.estimated_cost_usd.partial_cmp(&a.estimated_cost_usd).unwrap());
    top_sessions.truncate(20);

    OverviewMetrics {
        total_sessions: sessions.len() as u32,
        total_cost_usd: total_cost,
        total_input_tokens: total_input,
        total_output_tokens: total_output,
        total_cache_write_tokens: total_cache_write,
        total_cache_read_tokens: total_cache_read,
        avg_cache_hit_rate,
        cost_breakdown,
        estimated_system_overhead_tokens: system_overhead,
        daily_costs,
        project_summaries,
        top_sessions,
    }
}
