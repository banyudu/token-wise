//! Exposure of the bundled CLI on the user's `PATH`.
//!
//! The app binary doubles as the `token-wise` CLI. To let users run it from a
//! shell without manually adding an alias, we symlink the running executable
//! into `~/.local/bin`.
//!
//! There are two entry points:
//! - [`ensure_cli_on_path`]: silent best-effort, run at startup. Skipped
//!   entirely when sandboxed, since the App Store build can't write outside
//!   its container.
//! - [`status`] / [`install`]: backing the in-app Settings panel, where the
//!   user explicitly triggers the install and we can surface actionable advice
//!   (e.g. add the manual alias when sandboxed, or add `~/.local/bin` to PATH).

use std::path::{Path, PathBuf};

use serde::Serialize;

const CLI_NAME: &str = "token-wise";

/// Snapshot of how the CLI is currently exposed, for the Settings UI.
#[derive(Serialize, Clone)]
pub struct CliStatus {
    /// A `token-wise` executable is resolvable on the current `PATH`.
    pub on_path: bool,
    /// A file or symlink already exists at the `~/.local/bin/token-wise` target.
    pub link_exists: bool,
    /// Absolute path of the install target (`~/.local/bin/token-wise`).
    pub link_path: String,
    /// `~/.local/bin` is one of the directories listed in `PATH`.
    pub bin_dir_on_path: bool,
    /// The process appears to be running under the macOS App Sandbox.
    pub sandboxed: bool,
    /// Absolute path of the running executable (the alias/symlink target).
    pub exe_path: String,
}

/// Outcome of an explicit install attempt from the Settings UI.
#[derive(Serialize, Clone)]
pub struct CliInstallResult {
    /// The CLI is now reachable (or already was).
    pub ok: bool,
    /// Machine-readable outcome: `installed` | `already` | `sandboxed` | `error`.
    pub outcome: String,
    /// Human-readable detail to show the user.
    pub message: String,
    /// Fresh status after the attempt.
    pub status: CliStatus,
}

/// Silent best-effort exposure, intended for app startup. Does nothing when
/// sandboxed and swallows every error.
pub fn ensure_cli_on_path() {
    if is_sandboxed() || cli_already_on_path() {
        return;
    }
    let (Some(exe), Some(bin), Some(link)) = (current_exe(), bin_dir(), link_path()) else {
        return;
    };
    if link.symlink_metadata().is_ok() {
        return;
    }
    if std::fs::create_dir_all(&bin).is_err() {
        return;
    }
    let _ = symlink(&exe, &link);
}

/// Current exposure status for the Settings UI.
pub fn status() -> CliStatus {
    let link = link_path();
    CliStatus {
        on_path: cli_already_on_path(),
        link_exists: link.as_ref().is_some_and(|l| l.symlink_metadata().is_ok()),
        link_path: link.map(path_string).unwrap_or_default(),
        bin_dir_on_path: bin_dir().is_some_and(|b| dir_on_path(&b)),
        sandboxed: is_sandboxed(),
        exe_path: current_exe().map(path_string).unwrap_or_default(),
    }
}

/// Explicitly attempt to install the CLI symlink, returning actionable detail.
pub fn install() -> CliInstallResult {
    let before = status();
    if before.on_path || before.link_exists {
        return result(true, "already", "token-wise is already available on your PATH.", before);
    }

    let (Some(exe), Some(bin), Some(link)) = (current_exe(), bin_dir(), link_path()) else {
        return result(false, "error", "Couldn't resolve the executable or home directory.", before);
    };

    if let Err(e) = std::fs::create_dir_all(&bin) {
        return install_failure(&e);
    }

    match symlink(&exe, &link) {
        Ok(()) => {
            let after = status();
            let message = if after.bin_dir_on_path {
                "Installed. Open a new terminal and run `token-wise`.".to_string()
            } else {
                format!(
                    "Linked to {}, but that directory isn't on your PATH yet. Add it, then open a new terminal.",
                    after.link_path
                )
            };
            result(true, "installed", &message, after)
        }
        Err(e) => install_failure(&e),
    }
}

fn install_failure(err: &std::io::Error) -> CliInstallResult {
    let status = status();
    if status.sandboxed {
        result(
            false,
            "sandboxed",
            "This sandboxed build can't modify your PATH automatically. Set it up manually with the steps below.",
            status,
        )
    } else {
        let message = format!("Couldn't create the symlink: {err}");
        result(false, "error", &message, status)
    }
}

fn result(ok: bool, outcome: &str, message: &str, status: CliStatus) -> CliInstallResult {
    CliInstallResult {
        ok,
        outcome: outcome.to_string(),
        message: message.to_string(),
        status,
    }
}

fn current_exe() -> Option<PathBuf> {
    std::env::current_exe().ok()
}

fn bin_dir() -> Option<PathBuf> {
    dirs::home_dir().map(|h| h.join(".local").join("bin"))
}

fn link_path() -> Option<PathBuf> {
    bin_dir().map(|b| b.join(CLI_NAME))
}

fn path_string(p: PathBuf) -> String {
    p.display().to_string()
}

/// macOS sets `APP_SANDBOX_CONTAINER_ID` for sandboxed processes.
fn is_sandboxed() -> bool {
    std::env::var_os("APP_SANDBOX_CONTAINER_ID").is_some()
}

/// Whether a resolvable `token-wise` executable already exists on `PATH`.
fn cli_already_on_path() -> bool {
    let Some(path) = std::env::var_os("PATH") else { return false };
    std::env::split_paths(&path).any(|dir| {
        std::fs::canonicalize(dir.join(CLI_NAME))
            .map(|resolved| resolved.is_file())
            .unwrap_or(false)
    })
}

/// Whether `dir` is one of the entries in `PATH`.
fn dir_on_path(dir: &Path) -> bool {
    let Some(path) = std::env::var_os("PATH") else { return false };
    std::env::split_paths(&path).any(|d| d == *dir)
}

#[cfg(unix)]
fn symlink(target: &Path, link: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(target, link)
}

#[cfg(not(unix))]
fn symlink(_target: &Path, _link: &Path) -> std::io::Result<()> {
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "symlinking the CLI is only supported on unix-like systems",
    ))
}
