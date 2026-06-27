//! User-granted folder access for the App Sandbox.
//!
//! Apple rejects `com.apple.security.temporary-exception.files.home-relative-path`
//! (guideline 2.4.5(i)), so the Mac App Store build can't read `~/.claude` or
//! `~/.codex` directly. Instead the user grants access once via a native folder
//! picker (`grant_folder`); we persist a **security-scoped bookmark** so the
//! grant survives relaunches, and resolve it on demand while the app reads.
//!
//! Non-sandboxed builds (Developer ID / direct distribution, and the CLI) keep
//! reading the home directory directly: `is_sandboxed()` is false there, the
//! bookmark code is never exercised, and no onboarding is shown.

use serde::Serialize;
use std::collections::HashMap;
use std::ffi::{c_char, c_int, c_long, c_void, CStr, CString};
use std::path::PathBuf;
use std::sync::Mutex;

#[cfg(target_os = "macos")]
extern "C" {
    fn tw_pick_and_bookmark(
        default_path: *const c_char,
        out_path: *mut *mut c_char,
        out_bytes: *mut *mut c_void,
        out_len: *mut c_long,
    ) -> c_int;
    fn tw_resolve_bookmark(
        bytes: *const c_void,
        len: c_long,
        out_path: *mut *mut c_char,
        out_url_handle: *mut *mut c_void,
    ) -> c_int;
    fn tw_release_url(handle: *mut c_void);
    fn tw_free(ptr: *mut c_void);
}

/// Opaque, owned security-scoped URL handle returned by `tw_resolve_bookmark`.
/// Must be released via `tw_release_url`. `Send` is sound: the handle is only
/// ever used to balance `startAccessingSecurityScopedResource`/`stop…` on the
/// same process and is otherwise inert.
#[cfg(target_os = "macos")]
struct UrlHandle(*mut c_void);
#[cfg(target_os = "macos")]
unsafe impl Send for UrlHandle {}

#[derive(Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "lowercase")]
enum Kind {
    Claude,
    Codex,
}

impl Kind {
    fn parse(s: &str) -> Result<Self, String> {
        match s {
            "claude" => Ok(Kind::Claude),
            "codex" => Ok(Kind::Codex),
            other => Err(format!("unknown grant kind: {other}")),
        }
    }

    fn home_subdir(self) -> &'static str {
        match self {
            Kind::Claude => ".claude",
            Kind::Codex => ".codex",
        }
    }

    fn bookmark_file(self) -> PathBuf {
        grants_dir()
            .unwrap_or_default()
            .join(match self {
                Kind::Claude => "claude.bookmark",
                Kind::Codex => "codex.bookmark",
            })
    }
}

/// Where security-scoped bookmarks are persisted. Under the App Sandbox this
/// resolves to the app's writable container; elsewhere to `~/Library/Application Support`.
fn grants_dir() -> Option<PathBuf> {
    dirs::data_dir().map(|d| d.join("token-wise").join("grants"))
}

/// Whether we're running inside the App Store sandbox. macOS sets
/// `APP_SANDBOX_CONTAINER_ID` for sandboxed processes.
fn is_sandboxed() -> bool {
    std::env::var_os("APP_SANDBOX_CONTAINER_ID").is_some()
}

/// Resolved roots, cached so the bookmark is only resolved once per launch.
/// None entry = "not yet resolved this session".
static ROOTS: Mutex<Option<HashMap<Kind, PathBuf>>> = Mutex::new(None);

/// Security-scoped URL handles that must stay alive for the whole process while
/// we read the granted folders (the access is balanced against these).
#[cfg(target_os = "macos")]
static HELD: Mutex<Vec<(Kind, UrlHandle)>> = Mutex::new(Vec::new());

/// Reports whether each data folder is currently accessible. Non-sandboxed
/// builds report both as granted (they read the home dir directly).
#[derive(Clone, Serialize)]
pub struct GrantStatus {
    pub sandboxed: bool,
    pub claude: bool,
    pub codex: bool,
}

#[derive(Serialize)]
pub struct GrantResult {
    pub path: String,
}

/// Frontend-facing grant status. Non-sandboxed builds need no grants.
#[tauri::command]
pub fn grants_status() -> GrantStatus {
    let sandboxed = is_sandboxed();
    if !sandboxed {
        return GrantStatus {
            sandboxed,
            claude: true,
            codex: true,
        };
    }
    // Resolving here also primes the security scope early as a side effect.
    GrantStatus {
        sandboxed,
        claude: claude_root().is_some(),
        codex: codex_root().is_some(),
    }
}

/// Pops a native folder picker for the requested kind, persists a
/// security-scoped bookmark, and begins access. Errors when the user cancels
/// (`"cancelled"`) or picks the wrong folder.
#[tauri::command]
pub fn grant_folder(kind: String) -> Result<GrantResult, String> {
    let kind = Kind::parse(&kind)?;

    #[cfg(not(target_os = "macos"))]
    {
        let _ = kind;
        return Err("folder grants are only supported on macOS".into());
    }

    #[cfg(target_os = "macos")]
    {
        let home =
            dirs::home_dir().ok_or_else(|| "could not resolve home directory".to_string())?;
        // Pre-navigate the picker *into* the expected dotfolder, so the user
        // usually just clicks "Grant Access".
        let default_path = home.join(kind.home_subdir());
        let default_c =
            CString::new(default_path.to_string_lossy().as_bytes()).map_err(|e| e.to_string())?;

        let mut path_ptr: *mut c_char = std::ptr::null_mut();
        let mut bytes_ptr: *mut c_void = std::ptr::null_mut();
        let mut len: c_long = 0;
        // SAFETY: the picker runs on the main thread (handled inside the FFI);
        // out-pointers are valid locals. The returned buffers are owned by us.
        let rc = unsafe {
            tw_pick_and_bookmark(default_c.as_ptr(), &mut path_ptr, &mut bytes_ptr, &mut len)
        };
        if rc == 0 || path_ptr.is_null() {
            // Still free any bytes in case the picker wrote a partial buffer.
            if !bytes_ptr.is_null() {
                unsafe { tw_free(bytes_ptr) };
            }
            return Err("cancelled".to_string());
        }
        let picked = unsafe { CStr::from_ptr(path_ptr) }
            .to_string_lossy()
            .into_owned();
        unsafe { tw_free(path_ptr as *mut c_void) };
        let bookmark = unsafe {
            std::slice::from_raw_parts(bytes_ptr as *const u8, len.max(0) as usize).to_vec()
        };
        unsafe { tw_free(bytes_ptr) };

        // Guard against the user granting the wrong folder (e.g. their home dir).
        let expected = kind.home_subdir();
        let basename = std::path::Path::new(&picked)
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("");
        if basename != expected {
            return Err(format!(
                "Please select the {expected} folder (you picked “{picked}”). Press ⌘⇧. in the picker if the folder is hidden."
            ));
        }

        // Persist the bookmark, then drop any previously-held handle for this kind.
        if let Some(dir) = grants_dir() {
            let _ = std::fs::create_dir_all(&dir);
            let _ = std::fs::write(kind.bookmark_file(), &bookmark);
        }
        release_kind(kind);

        // Invalidate the cached root so resolve_root re-resolves from the fresh
        // bookmark, and prime access immediately.
        if let Ok(mut roots) = ROOTS.lock() {
            if let Some(map) = roots.as_mut() {
                map.remove(&kind);
            }
        }
        let resolved = resolve_persisted(kind)
            .ok_or_else(|| "failed to resolve the granted folder".to_string())?;
        Ok(GrantResult {
            path: resolved.to_string_lossy().into_owned(),
        })
    }
}

/// Resolved `~/.claude` root, granted in sandboxed builds or read directly
/// otherwise. `None` when sandboxed and the user hasn't granted access yet.
pub fn claude_root() -> Option<PathBuf> {
    resolve_root(Kind::Claude)
}

/// Resolved `~/.codex` root (see [`claude_root`]).
pub fn codex_root() -> Option<PathBuf> {
    resolve_root(Kind::Codex)
}

fn resolve_root(kind: Kind) -> Option<PathBuf> {
    if !is_sandboxed() {
        return dirs::home_dir().map(|h| h.join(kind.home_subdir()));
    }

    let mut roots = ROOTS.lock().ok()?;
    let map = roots.get_or_insert_with(HashMap::new);
    if let Some(p) = map.get(&kind) {
        return Some(p.clone());
    }

    #[cfg(target_os = "macos")]
    {
        if let Some(p) = resolve_persisted(kind) {
            map.insert(kind, p.clone());
            return Some(p);
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = kind;
    }
    None
}

/// Reads the persisted bookmark for `kind` and begins security-scoped access.
#[cfg(target_os = "macos")]
fn resolve_persisted(kind: Kind) -> Option<PathBuf> {
    let bytes = std::fs::read(kind.bookmark_file()).ok()?;
    if bytes.is_empty() {
        return None;
    }

    let mut path_ptr: *mut c_char = std::ptr::null_mut();
    let mut handle: *mut c_void = std::ptr::null_mut();
    // SAFETY: bytes is a valid buffer for its length; out-pointers are locals.
    let rc = unsafe {
        tw_resolve_bookmark(
            bytes.as_ptr() as *const c_void,
            bytes.len() as c_long,
            &mut path_ptr,
            &mut handle,
        )
    };
    if rc == 0 || path_ptr.is_null() {
        return None;
    }
    let path = unsafe { CStr::from_ptr(path_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { tw_free(path_ptr as *mut c_void) };

    if !handle.is_null() {
        if let Ok(mut held) = HELD.lock() {
            held.push((kind, UrlHandle(handle)));
        }
    }
    Some(PathBuf::from(path))
}

/// Stops access and releases any handles held for `kind`.
#[cfg(target_os = "macos")]
fn release_kind(kind: Kind) {
    let mut to_release: Vec<UrlHandle> = Vec::new();
    if let Ok(mut held) = HELD.lock() {
        let mut keep = Vec::with_capacity(held.len());
        for entry in held.drain(..) {
            if entry.0 == kind {
                to_release.push(entry.1);
            } else {
                keep.push(entry);
            }
        }
        *held = keep;
    }
    for h in to_release {
        // SAFETY: each handle came from tw_resolve_bookmark and is released once.
        unsafe { tw_release_url(h.0) };
    }
}
