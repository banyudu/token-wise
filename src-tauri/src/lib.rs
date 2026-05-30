pub mod cache_savings;
pub mod cli;
pub mod models;
pub mod parser;
pub mod path_install;
#[cfg(feature = "updater")]
pub mod updater;

use models::{OverviewMetrics, SessionDetail, SessionSummary};

#[tauri::command]
async fn get_overview() -> OverviewMetrics {
    let pricing = parser::get_cached_pricing();
    let mut sessions = parser::load_claude_sessions(pricing);
    sessions.extend(parser::load_codex_sessions(pricing));
    parser::build_overview(&sessions)
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
    parser::get_session_detail_any(&session_id, pricing)
}

#[tauri::command]
fn cli_path_status() -> path_install::CliStatus {
    path_install::status()
}

#[tauri::command]
fn install_cli_path() -> path_install::CliInstallResult {
    path_install::install()
}

/// Relaunch the app to apply a downloaded update. No-op effect in the App Store
/// build (the `update-ready` event that triggers it is never emitted there).
#[tauri::command]
fn restart_app(app: tauri::AppHandle) {
    app.restart();
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[allow(unused_mut)]
    let mut builder = tauri::Builder::default();

    #[cfg(feature = "updater")]
    {
        builder = builder.plugin(tauri_plugin_updater::Builder::new().build());
    }

    builder
        .setup(|_app| {
            #[cfg(feature = "updater")]
            updater::spawn_check(_app.handle().clone());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_overview,
            get_sessions,
            refresh_sessions,
            get_session_detail,
            cli_path_status,
            install_cli_path,
            restart_app,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
