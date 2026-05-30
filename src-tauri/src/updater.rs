//! Self-update path for the Developer ID / direct-distribution build.
//!
//! Compiled only when the `updater` feature is enabled. The App Store build is
//! built with `--no-default-features`, so none of this code (nor the
//! `tauri-plugin-updater` dependency) is present in the MAS binary.

use tauri::{AppHandle, Emitter};
use tauri_plugin_updater::UpdaterExt;

/// Check for an update in the background, install it silently if found, then
/// emit `update-ready` (payload: new version string) so the UI can offer to
/// relaunch. Failures are non-fatal — the app keeps running on the old version.
pub fn spawn_check(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let updater = match app.updater() {
            Ok(updater) => updater,
            Err(_) => return,
        };
        if let Ok(Some(update)) = updater.check().await {
            let version = update.version.clone();
            if update.download_and_install(|_, _| {}, || {}).await.is_ok() {
                let _ = app.emit("update-ready", version);
            }
        }
    });
}
