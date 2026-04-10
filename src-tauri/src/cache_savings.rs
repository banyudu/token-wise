use crate::models::{
    CacheSavingsReport, ClaudeMessage, InvalidationEvent, PricingInfo, RepeatedBlock,
    TurnMetrics, UnreferencedBlock, WastedWrite,
};
use std::collections::{HashMap, HashSet};

/// Top-level analyzer producing all four heuristics.
pub fn analyze_cache_savings(
    messages: &[ClaudeMessage],
    turns: &[TurnMetrics],
    pricing: &PricingInfo,
) -> CacheSavingsReport {
    let wasted_cache_writes = detect_wasted_writes(turns, pricing);
    let invalidation_events = detect_invalidations(turns, messages, pricing);
    let unreferenced_blocks = detect_unreferenced_blocks(messages, turns, pricing);
    let repeated_blocks = detect_repeated_blocks(messages, pricing);

    let total = wasted_cache_writes.iter().map(|w| w.wasted_cost_usd).sum::<f64>()
        + invalidation_events.iter().map(|i| i.rewrite_cost_usd).sum::<f64>()
        + unreferenced_blocks.iter().map(|u| u.wasted_cost_usd).sum::<f64>()
        + repeated_blocks.iter().map(|r| r.wasted_cost_usd).sum::<f64>();

    CacheSavingsReport {
        wasted_cache_writes,
        invalidation_events,
        unreferenced_blocks,
        repeated_blocks,
        total_potential_savings_usd: total,
    }
}

/// H1: Turns whose cache_write was never read back by any subsequent turn.
fn detect_wasted_writes(turns: &[TurnMetrics], pricing: &PricingInfo) -> Vec<WastedWrite> {
    if turns.len() < 2 {
        return vec![];
    }

    // Precompute max future cache_read for each turn index.
    let mut max_future_read = vec![0u64; turns.len()];
    let mut running_max = 0u64;
    for i in (0..turns.len()).rev() {
        max_future_read[i] = running_max;
        if turns[i].cache_read_tokens > running_max {
            running_max = turns[i].cache_read_tokens;
        }
    }

    // Cumulative cache write up to and including each turn.
    let mut cum_write = 0u64;
    let mut results = Vec::new();

    for (i, turn) in turns.iter().enumerate() {
        let prev_cum = cum_write;
        cum_write += turn.cache_write_tokens;

        // Skip turn 0: first-turn write is unavoidable system prompt boilerplate.
        if i == 0 || turn.cache_write_tokens == 0 {
            continue;
        }

        let mfr = max_future_read[i];
        // Wasted portion = how much of this turn's write was never included in any later read.
        let wasted = if mfr >= cum_write {
            0
        } else if mfr > prev_cum {
            cum_write - mfr
        } else {
            turn.cache_write_tokens
        };

        if wasted == 0 {
            continue;
        }

        // Only report substantial waste (>1K tokens).
        if wasted < 1_000 {
            continue;
        }

        let cost = (wasted as f64 / 1_000_000.0) * pricing.cache_write_per_mtok;
        let reason = if mfr == 0 {
            "Cache written but never read back before session ended.".to_string()
        } else {
            format!(
                "Only {} of {} cached tokens were reused later.",
                format_k(mfr.saturating_sub(prev_cum)),
                format_k(turn.cache_write_tokens),
            )
        };

        results.push(WastedWrite {
            turn_index: turn.turn_index,
            wasted_tokens: wasted,
            wasted_cost_usd: cost,
            reason,
        });
    }

    results.sort_by(|a, b| b.wasted_cost_usd.partial_cmp(&a.wasted_cost_usd).unwrap_or(std::cmp::Ordering::Equal));
    results.truncate(20);
    results
}

/// H2: Detect sudden drops in cache_read indicating prefix invalidation.
fn detect_invalidations(
    turns: &[TurnMetrics],
    messages: &[ClaudeMessage],
    pricing: &PricingInfo,
) -> Vec<InvalidationEvent> {
    if turns.len() < 2 {
        return vec![];
    }

    // Build a map turn_index → (preview, tool_name) from messages for culprit hinting.
    let culprits = build_turn_culprit_map(messages);

    let mut events = Vec::new();
    for i in 1..turns.len() {
        let prev = &turns[i - 1];
        let curr = &turns[i];

        // Need meaningful prefix at previous turn.
        if prev.cache_read_tokens < 5_000 {
            continue;
        }

        // Significant drop: current read is less than 70% of previous read.
        if (curr.cache_read_tokens as f64) >= 0.7 * (prev.cache_read_tokens as f64) {
            continue;
        }

        let dropped = prev.cache_read_tokens - curr.cache_read_tokens;
        if dropped < 5_000 {
            continue;
        }

        // Cost: re-writing the dropped prefix costs cache_write_per_mtok.
        let cost = (dropped as f64 / 1_000_000.0) * pricing.cache_write_per_mtok;

        let (suspect_name, suspect_preview) = culprits
            .get(&(i as u32 - 1))
            .cloned()
            .unwrap_or((None, None));

        events.push(InvalidationEvent {
            turn_index: curr.turn_index,
            dropped_tokens: dropped,
            rewrite_cost_usd: cost,
            suspected_cause: suspect_name,
            suspected_preview: suspect_preview,
        });
    }

    events.sort_by(|a, b| b.rewrite_cost_usd.partial_cmp(&a.rewrite_cost_usd).unwrap_or(std::cmp::Ordering::Equal));
    events.truncate(20);
    events
}

/// For each turn, find the largest content block entering context at that turn.
fn build_turn_culprit_map(
    messages: &[ClaudeMessage],
) -> HashMap<u32, (Option<String>, Option<String>)> {
    let mut map: HashMap<u32, (u64, String, String)> = HashMap::new();
    let mut turn_index = 0u32;

    for msg in messages {
        let inner = match msg.message.as_ref() {
            Some(m) => m,
            None => continue,
        };
        if let Some(content) = inner.content.as_ref() {
            if let serde_json::Value::Array(arr) = content {
                for block in arr {
                    let block_type = block.get("type").and_then(|t| t.as_str()).unwrap_or("");
                    if block_type != "tool_result" && block_type != "text" {
                        continue;
                    }
                    let size = measure_block_size(block);
                    if size < 10_000 {
                        continue;
                    }
                    let label = if block_type == "tool_result" {
                        "tool_result".to_string()
                    } else {
                        "text".to_string()
                    };
                    let preview = block_preview(block, 100);
                    let entry = map.entry(turn_index).or_insert((0, String::new(), String::new()));
                    if size > entry.0 {
                        *entry = (size, label, preview);
                    }
                }
            }
        }
        if msg.r#type == "user" || msg.r#type == "assistant" {
            turn_index += 1;
        }
    }

    map.into_iter()
        .map(|(k, (_, name, preview))| (k, (Some(name), Some(preview))))
        .collect()
}

/// H3: Large system-reminder / CLAUDE.md blocks that are never referenced downstream.
fn detect_unreferenced_blocks(
    messages: &[ClaudeMessage],
    turns: &[TurnMetrics],
    pricing: &PricingInfo,
) -> Vec<UnreferencedBlock> {
    // Step 1: collect candidate blocks (early large user content with system-reminder markers)
    struct Candidate {
        turn_index: u32,
        label: String,
        text: String,
        byte_size: u64,
    }

    let mut candidates: Vec<Candidate> = Vec::new();
    let mut turn_index = 0u32;

    for msg in messages {
        let inner = match msg.message.as_ref() {
            Some(m) => m,
            None => continue,
        };
        let role = inner.role.as_deref().unwrap_or("");
        if role != "user" {
            if msg.r#type == "user" || msg.r#type == "assistant" {
                turn_index += 1;
            }
            continue;
        }
        if let Some(content) = inner.content.as_ref() {
            let texts = collect_user_text_blocks(content);
            for text in texts {
                if text.len() < 3_000 {
                    continue;
                }
                let label = classify_reminder_block(&text);
                if let Some(label) = label {
                    candidates.push(Candidate {
                        turn_index,
                        label,
                        byte_size: text.len() as u64,
                        text,
                    });
                }
            }
        }
        if msg.r#type == "user" || msg.r#type == "assistant" {
            turn_index += 1;
        }
    }

    if candidates.is_empty() {
        return vec![];
    }

    // Step 2: build a downstream-text corpus from all later assistant text + tool_use inputs.
    let downstream = build_downstream_corpus(messages);
    let downstream_lower = downstream.to_lowercase();

    // Step 3: for each candidate, extract distinctive tokens and search the corpus.
    let mut results: Vec<UnreferencedBlock> = Vec::new();
    for cand in candidates {
        let tokens = extract_distinctive_tokens(&cand.text);
        if tokens.is_empty() {
            continue;
        }
        let mut hits = 0;
        for tok in &tokens {
            if downstream_lower.contains(&tok.to_lowercase()) {
                hits += 1;
                if hits >= 2 {
                    break;
                }
            }
        }
        if hits >= 2 {
            continue; // referenced — skip
        }

        // Wasted: the block is in-context for every remaining turn after it loads.
        // Billed once as cache_write, then cache_read per subsequent assistant request.
        let est_tokens = cand.byte_size / 4;
        let later_asst_turns = turns
            .iter()
            .filter(|t| t.turn_index >= cand.turn_index && t.role == "assistant")
            .count() as u32;
        let carried = later_asst_turns.max(1);
        let read_cost = (est_tokens as f64 / 1_000_000.0)
            * pricing.cache_read_per_mtok
            * carried as f64;
        let write_cost = (est_tokens as f64 / 1_000_000.0) * pricing.cache_write_per_mtok;
        let wasted_cost = read_cost + write_cost;

        let preview: String = cand.text.chars().take(120).collect::<String>().replace('\n', " ");

        results.push(UnreferencedBlock {
            turn_index: cand.turn_index,
            label: cand.label,
            estimated_tokens: est_tokens,
            carried_turns: carried,
            wasted_cost_usd: wasted_cost,
            preview,
        });
    }

    results.sort_by(|a, b| b.wasted_cost_usd.partial_cmp(&a.wasted_cost_usd).unwrap_or(std::cmp::Ordering::Equal));
    results.truncate(20);
    results
}

/// H4: Content blocks (via content hash) appearing in multiple turns.
fn detect_repeated_blocks(messages: &[ClaudeMessage], pricing: &PricingInfo) -> Vec<RepeatedBlock> {
    #[derive(Default)]
    struct Occ {
        count: u32,
        first_turn: u32,
        last_turn: u32,
        size: u64,
        preview: String,
        category: String,
    }

    let mut map: HashMap<u64, Occ> = HashMap::new();
    let mut turn_index = 0u32;

    for msg in messages {
        let inner = match msg.message.as_ref() {
            Some(m) => m,
            None => continue,
        };
        if let Some(content) = inner.content.as_ref() {
            if let serde_json::Value::Array(arr) = content {
                for block in arr {
                    let block_type = block.get("type").and_then(|t| t.as_str()).unwrap_or("");
                    // Only count content blocks that can be re-sent.
                    if block_type != "tool_result" && block_type != "text" {
                        continue;
                    }
                    let size = measure_block_size(block);
                    if size < 2_000 {
                        continue;
                    }
                    let preview = block_preview(block, 100);
                    let hash = simple_hash(&preview) ^ simple_hash_u64(&size.to_le_bytes());
                    let entry = map.entry(hash).or_insert_with(|| Occ {
                        count: 0,
                        first_turn: turn_index,
                        last_turn: turn_index,
                        size,
                        preview: preview.clone(),
                        category: block_type.to_string(),
                    });
                    entry.count += 1;
                    entry.last_turn = turn_index;
                }
            }
        }
        if msg.r#type == "user" || msg.r#type == "assistant" {
            turn_index += 1;
        }
    }

    let mut results: Vec<RepeatedBlock> = map
        .into_iter()
        .filter(|(_, o)| o.count >= 2)
        .map(|(_, o)| {
            let each_tokens = o.size / 4;
            let wasted_tokens = each_tokens * (o.count as u64 - 1);
            let cost = (wasted_tokens as f64 / 1_000_000.0) * pricing.cache_read_per_mtok;
            RepeatedBlock {
                occurrences: o.count,
                first_turn: o.first_turn,
                last_turn: o.last_turn,
                estimated_tokens_each: each_tokens,
                total_wasted_tokens: wasted_tokens,
                wasted_cost_usd: cost,
                category: o.category,
                preview: o.preview,
            }
        })
        .collect();

    results.sort_by(|a, b| b.wasted_cost_usd.partial_cmp(&a.wasted_cost_usd).unwrap_or(std::cmp::Ordering::Equal));
    results.truncate(10);
    results
}

// --- Helpers ---

fn measure_block_size(block: &serde_json::Value) -> u64 {
    fn walk(v: &serde_json::Value) -> u64 {
        match v {
            serde_json::Value::String(s) => s.len() as u64,
            serde_json::Value::Array(a) => a.iter().map(walk).sum(),
            serde_json::Value::Object(m) => m.values().map(walk).sum(),
            serde_json::Value::Number(n) => n.to_string().len() as u64,
            _ => 0,
        }
    }
    walk(block)
}

fn block_preview(block: &serde_json::Value, max_len: usize) -> String {
    let text = if let Some(s) = block.get("text").and_then(|v| v.as_str()) {
        s.to_string()
    } else if let Some(s) = block.get("content").and_then(|v| v.as_str()) {
        s.to_string()
    } else {
        serde_json::to_string(block).unwrap_or_default()
    };
    let trimmed: String = text.trim().chars().take(max_len).collect();
    trimmed.replace('\n', " ")
}

fn collect_user_text_blocks(content: &serde_json::Value) -> Vec<String> {
    match content {
        serde_json::Value::String(s) => vec![s.clone()],
        serde_json::Value::Array(arr) => arr
            .iter()
            .filter_map(|block| {
                let t = block.get("type").and_then(|v| v.as_str()).unwrap_or("");
                if t == "text" {
                    block.get("text").and_then(|v| v.as_str()).map(|s| s.to_string())
                } else if t == "tool_result" {
                    // user tool_result wrapping — include its text
                    block
                        .get("content")
                        .and_then(|c| c.as_str())
                        .map(|s| s.to_string())
                } else {
                    None
                }
            })
            .collect(),
        _ => vec![],
    }
}

fn classify_reminder_block(text: &str) -> Option<String> {
    if text.contains("# claudeMd") || text.contains("CLAUDE.md") || text.contains("claude.md") {
        return Some("CLAUDE.md".to_string());
    }
    if text.contains("<system-reminder>") {
        // Try to pull a meaningful label
        if text.contains("skill") || text.contains("Skill") {
            return Some("Skills reminder".to_string());
        }
        if text.contains("task") || text.contains("Task") {
            return Some("Task reminder".to_string());
        }
        return Some("System reminder".to_string());
    }
    if text.contains("Available skills") || text.contains("available skills") {
        return Some("Skills listing".to_string());
    }
    None
}

fn build_downstream_corpus(messages: &[ClaudeMessage]) -> String {
    let mut out = String::new();
    for msg in messages {
        let inner = match msg.message.as_ref() {
            Some(m) => m,
            None => continue,
        };
        if inner.role.as_deref() != Some("assistant") {
            continue;
        }
        if let Some(content) = inner.content.as_ref() {
            if let serde_json::Value::Array(arr) = content {
                for block in arr {
                    let t = block.get("type").and_then(|v| v.as_str()).unwrap_or("");
                    match t {
                        "text" | "thinking" => {
                            if let Some(s) = block.get("text").and_then(|v| v.as_str()) {
                                out.push_str(s);
                                out.push('\n');
                            }
                            if let Some(s) = block.get("thinking").and_then(|v| v.as_str()) {
                                out.push_str(s);
                                out.push('\n');
                            }
                        }
                        "tool_use" => {
                            if let Some(input) = block.get("input") {
                                out.push_str(&serde_json::to_string(input).unwrap_or_default());
                                out.push('\n');
                            }
                        }
                        _ => {}
                    }
                }
            }
        }
    }
    out
}

/// Pull distinctive identifiers (backticked strings, CamelCase words, paths, headings).
fn extract_distinctive_tokens(text: &str) -> Vec<String> {
    let mut tokens: HashSet<String> = HashSet::new();

    // Backticked identifiers: `foo.bar` or `MyClass`
    let mut chars = text.chars().peekable();
    let mut buf = String::new();
    let mut in_tick = false;
    while let Some(c) = chars.next() {
        if c == '`' {
            if in_tick {
                if buf.len() >= 4 && buf.len() <= 60 {
                    tokens.insert(buf.clone());
                }
                buf.clear();
                in_tick = false;
            } else {
                in_tick = true;
            }
        } else if in_tick {
            buf.push(c);
        }
    }

    // Headings (lines starting with #)
    for line in text.lines() {
        let trimmed = line.trim_start();
        if let Some(rest) = trimmed.strip_prefix('#') {
            let heading = rest.trim_start_matches('#').trim();
            if heading.len() >= 4 && heading.len() <= 80 {
                tokens.insert(heading.to_string());
            }
        }
    }

    // File-path-looking tokens: /foo/bar.ext or ./foo
    for word in text.split(|c: char| c.is_whitespace() || c == ',' || c == ';' || c == '"') {
        let w = word.trim_matches(|c: char| c == '.' || c == ',' || c == ')' || c == '(');
        if (w.contains('/') || w.ends_with(".md") || w.ends_with(".rs") || w.ends_with(".ts") || w.ends_with(".tsx"))
            && w.len() >= 6
            && w.len() <= 120
        {
            tokens.insert(w.to_string());
        }
    }

    // Filter out noise: very short, numeric-only, common words
    tokens
        .into_iter()
        .filter(|t| t.len() >= 5)
        .filter(|t| !is_too_common(t))
        .take(50)
        .collect()
}

fn is_too_common(s: &str) -> bool {
    matches!(
        s.to_lowercase().as_str(),
        "claude" | "user" | "system" | "claude.md" | "readme" | "readme.md" | "todo" | "note"
    )
}

fn simple_hash(s: &str) -> u64 {
    let mut h: u64 = 1469598103934665603;
    for b in s.bytes() {
        h ^= b as u64;
        h = h.wrapping_mul(1099511628211);
    }
    h
}

fn simple_hash_u64(bytes: &[u8]) -> u64 {
    let mut h: u64 = 1469598103934665603;
    for b in bytes {
        h ^= *b as u64;
        h = h.wrapping_mul(1099511628211);
    }
    h
}

fn format_k(n: u64) -> String {
    if n >= 1_000_000 {
        format!("{:.1}M", n as f64 / 1_000_000.0)
    } else if n >= 1_000 {
        format!("{:.1}K", n as f64 / 1_000.0)
    } else {
        n.to_string()
    }
}
