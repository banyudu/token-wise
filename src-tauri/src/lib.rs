mod models;
mod parser;

use models::{OverviewMetrics, PricingInfo, SessionDetail, SessionSummary};

#[tauri::command]
async fn get_overview() -> OverviewMetrics {
    let pricing = parser::get_cached_pricing();
    let mut sessions = parser::load_claude_sessions(pricing);
    sessions.extend(parser::load_codex_sessions(pricing));
    parser::build_overview(&sessions, pricing)
}

#[tauri::command]
async fn get_sessions() -> Vec<SessionSummary> {
    let pricing = parser::get_cached_pricing();
    let mut sessions = parser::load_claude_sessions(pricing);
    sessions.extend(parser::load_codex_sessions(pricing));
    sessions
}

#[tauri::command]
async fn refresh_sessions() -> Vec<SessionSummary> {
    let pricing = parser::get_cached_pricing();
    let mut sessions = parser::load_claude_sessions_force(pricing);
    sessions.extend(parser::load_codex_sessions(pricing));
    sessions
}

#[tauri::command]
async fn get_session_detail(session_id: String) -> Option<SessionDetail> {
    let pricing = parser::get_cached_pricing();
    parser::get_session_detail(&session_id, pricing)
}

#[tauri::command]
fn get_pricing() -> PricingInfo {
    parser::get_cached_pricing().clone()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            get_overview,
            get_sessions,
            refresh_sessions,
            get_session_detail,
            get_pricing,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
