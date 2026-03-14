mod models;
mod parser;

use models::{OverviewMetrics, PricingInfo, SessionDetail, SessionSummary};

#[tauri::command]
fn get_overview() -> OverviewMetrics {
    let pricing = PricingInfo::from_claude_pricing_file();
    let mut sessions = parser::load_claude_sessions(&pricing);
    sessions.extend(parser::load_codex_sessions(&pricing));
    parser::build_overview(&sessions, &pricing)
}

#[tauri::command]
fn get_sessions() -> Vec<SessionSummary> {
    let pricing = PricingInfo::from_claude_pricing_file();
    let mut sessions = parser::load_claude_sessions(&pricing);
    sessions.extend(parser::load_codex_sessions(&pricing));
    sessions
}

#[tauri::command]
fn get_session_detail(session_id: String) -> Option<SessionDetail> {
    let pricing = PricingInfo::from_claude_pricing_file();
    parser::get_session_detail(&session_id, &pricing)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![get_overview, get_sessions, get_session_detail])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
