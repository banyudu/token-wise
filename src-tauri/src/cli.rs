use clap::{Parser, Subcommand};
use serde_json::json;

use crate::models::SessionSummary;
use crate::parser;

const CLI_SUBCOMMANDS: &[&str] = &[
    "total", "today", "sessions", "help", "--help", "-h", "--version", "-V",
];

pub fn is_cli_arg(arg: &str) -> bool {
    CLI_SUBCOMMANDS.contains(&arg)
}

#[derive(Parser)]
#[command(name = "token-wise", about = "Token Wise CLI — quick AI token usage stats", version)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Print total cost across all sessions
    Total {
        #[arg(long, help = "Output as JSON")]
        json: bool,
    },
    /// Print today's cost
    Today {
        #[arg(long, help = "Output as JSON")]
        json: bool,
    },
    /// List top sessions by cost
    Sessions {
        #[arg(long, default_value_t = 10, help = "Number of sessions to show")]
        limit: usize,
        #[arg(long, help = "Output as JSON")]
        json: bool,
    },
}

pub fn run() -> i32 {
    let cli = Cli::parse();
    let pricing = parser::get_cached_pricing();
    let mut sessions = parser::load_claude_sessions(pricing);
    sessions.extend(parser::load_codex_sessions(pricing));

    match cli.command {
        Command::Total { json } => cmd_total(&sessions, json),
        Command::Today { json } => cmd_today(&sessions, json),
        Command::Sessions { limit, json } => cmd_sessions(&sessions, limit, json),
    }
}

fn cmd_total(sessions: &[SessionSummary], as_json: bool) -> i32 {
    let total_cost: f64 = sessions.iter().map(|s| s.estimated_cost_usd).sum();
    let session_count = sessions.len();
    let day_span = compute_day_span(sessions);

    if as_json {
        println!(
            "{}",
            json!({
                "total_cost_usd": total_cost,
                "session_count": session_count,
                "day_span": day_span,
            })
        );
    } else {
        match day_span {
            Some(days) => println!("Total: ${:.2} ({} days, {} sessions)", total_cost, days, session_count),
            None => println!("Total: ${:.2} ({} sessions)", total_cost, session_count),
        }
    }
    0
}

fn cmd_today(sessions: &[SessionSummary], as_json: bool) -> i32 {
    let today = chrono::Local::now().date_naive();
    let today_sessions: Vec<&SessionSummary> = sessions
        .iter()
        .filter(|s| {
            s.last_timestamp
                .as_deref()
                .and_then(parse_local_date)
                .map(|d| d == today)
                .unwrap_or(false)
        })
        .collect();

    let total_cost: f64 = today_sessions.iter().map(|s| s.estimated_cost_usd).sum();
    let count = today_sessions.len();
    let cache_hit_rate = weighted_cache_hit_rate(&today_sessions);

    if as_json {
        println!(
            "{}",
            json!({
                "date": today.to_string(),
                "total_cost_usd": total_cost,
                "session_count": count,
                "cache_hit_rate": cache_hit_rate,
            })
        );
    } else {
        println!("Today:  ${:.2} ({} sessions)", total_cost, count);
        if count > 0 {
            println!("        Cache hit rate: {:.0}%", cache_hit_rate * 100.0);
        }
    }
    0
}

fn cmd_sessions(sessions: &[SessionSummary], limit: usize, as_json: bool) -> i32 {
    let mut sorted: Vec<&SessionSummary> = sessions.iter().collect();
    sorted.sort_by(|a, b| b.estimated_cost_usd.partial_cmp(&a.estimated_cost_usd).unwrap_or(std::cmp::Ordering::Equal));
    let top = &sorted[..sorted.len().min(limit)];

    if as_json {
        let arr: Vec<serde_json::Value> = top
            .iter()
            .map(|s| {
                json!({
                    "session_id": s.session_id,
                    "project": s.project,
                    "cost_usd": s.estimated_cost_usd,
                    "total_tokens": s.total_input_tokens + s.total_output_tokens + s.total_cache_read_tokens + s.total_cache_write_tokens,
                    "cache_hit_rate": s.cache_hit_rate,
                })
            })
            .collect();
        println!("{}", json!(arr));
    } else {
        println!("{:<24} {:>10} {:>10} {:>7}", "PROJECT", "COST", "TOKENS", "CACHE");
        for s in top {
            let total_tokens = s.total_input_tokens + s.total_output_tokens + s.total_cache_read_tokens + s.total_cache_write_tokens;
            println!(
                "{:<24} {:>10} {:>10} {:>6.0}%",
                truncate(&s.project, 24),
                format!("${:.2}", s.estimated_cost_usd),
                format_tokens(total_tokens),
                s.cache_hit_rate * 100.0,
            );
        }
    }
    0
}

fn compute_day_span(sessions: &[SessionSummary]) -> Option<i64> {
    let mut earliest: Option<chrono::NaiveDate> = None;
    let mut latest: Option<chrono::NaiveDate> = None;
    for s in sessions {
        for ts in [s.first_timestamp.as_deref(), s.last_timestamp.as_deref()].into_iter().flatten() {
            if let Some(d) = parse_local_date(ts) {
                earliest = Some(earliest.map_or(d, |cur| cur.min(d)));
                latest = Some(latest.map_or(d, |cur| cur.max(d)));
            }
        }
    }
    match (earliest, latest) {
        (Some(e), Some(l)) => Some((l - e).num_days() + 1),
        _ => None,
    }
}

fn parse_local_date(ts: &str) -> Option<chrono::NaiveDate> {
    chrono::DateTime::parse_from_rfc3339(ts)
        .ok()
        .map(|dt| dt.with_timezone(&chrono::Local).date_naive())
}

fn weighted_cache_hit_rate(sessions: &[&SessionSummary]) -> f64 {
    let total_read: u64 = sessions.iter().map(|s| s.total_cache_read_tokens).sum();
    let total_input: u64 = sessions.iter().map(|s| s.total_input_tokens + s.total_cache_read_tokens + s.total_cache_write_tokens).sum();
    if total_input == 0 { 0.0 } else { total_read as f64 / total_input as f64 }
}

fn format_tokens(n: u64) -> String {
    if n >= 1_000_000 {
        format!("{:.1}M", n as f64 / 1_000_000.0)
    } else if n >= 1_000 {
        format!("{:.0}K", n as f64 / 1_000.0)
    } else {
        n.to_string()
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max { s.to_string() } else { format!("{}…", &s[..max.saturating_sub(1)]) }
}
