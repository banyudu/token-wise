import Foundation

/// User-granted folder access for the App Sandbox. Port of the Rust
/// `grants.rs` + Objective-C FFI shim, now pure Foundation.
///
/// Apple rejects `temporary-exception.files.home-relative-path` (guideline
/// 2.4.5(i)), so a Mac App Store build can't read these dotfolders directly.
/// The user grants access once via a folder picker (in the app
/// layer); we persist a **security-scoped bookmark** so the grant survives
/// relaunches, and resolve it on demand while the app reads.
///
/// Non-sandboxed builds (Developer ID / direct distribution, and the CLI)
/// read the home directory directly: `isSandboxed` is false there, the
/// bookmark code is never exercised, and no onboarding is shown.
public enum GrantKind: String, CaseIterable {
    case claude
    case codex
    case opencode

    public var homeSubdir: String {
        switch self {
        case .claude: return ".claude"
        case .codex: return ".codex"
        case .opencode: return "opencode"
        }
    }

    public var homeRelativePath: String {
        switch self {
        case .opencode: return ".local/share/opencode"
        default: return homeSubdir
        }
    }

    var bookmarkFile: URL {
        Grants.grantsDir.appendingPathComponent("\(rawValue).bookmark")
    }
}

/// Whether each data folder is currently accessible. Non-sandboxed builds
/// report both as granted (they read the home dir directly).
public struct GrantStatus {
    public var sandboxed: Bool
    public var claude: Bool
    public var codex: Bool
    public var opencode: Bool
}

public enum GrantError: LocalizedError {
    case wrongFolder(expected: String, picked: String)
    case bookmarkFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .wrongFolder(expected, picked):
            return "Please select the \(expected) folder (you picked “\(picked)”). Press ⌘⇧. in the picker if the folder is hidden."
        case let .bookmarkFailed(reason):
            return "Could not save folder access: \(reason)"
        }
    }
}

public enum Grants {
    /// macOS sets `APP_SANDBOX_CONTAINER_ID` for sandboxed processes.
    public static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Where bookmarks persist. Under the App Sandbox this resolves to the
    /// app's writable container; elsewhere to `~/Library/Application Support`.
    static var grantsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? Paths.home.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("token-wise/grants", isDirectory: true)
    }

    /// Resolved roots, cached so each bookmark is only resolved once per launch.
    private static let lock = NSLock()
    private static var cachedRoots: [GrantKind: URL] = [:]
    /// Security-scoped URLs we've started access on — kept for the process
    /// lifetime so reads keep working (access is balanced against these).
    private static var heldURLs: [GrantKind: URL] = [:]

    public static func status() -> GrantStatus {
        guard isSandboxed else { return GrantStatus(sandboxed: false, claude: true, codex: true, opencode: true) }
        // Resolving here also primes the security scope early as a side effect.
        return GrantStatus(sandboxed: true,
                           claude: root(for: .claude) != nil,
                           codex: root(for: .codex) != nil,
                           opencode: root(for: .opencode) != nil)
    }

    /// The readable root for a kind directly when not
    /// sandboxed, the granted bookmark path when sandboxed (nil = not granted).
    public static func root(for kind: GrantKind) -> URL? {
        guard isSandboxed else {
            return Paths.home.appendingPathComponent(kind.homeRelativePath, isDirectory: true)
        }
        lock.lock(); defer { lock.unlock() }
        if let cached = cachedRoots[kind] { return cached }
        guard let url = resolvePersisted(kind) else { return nil }
        cachedRoots[kind] = url
        return url
    }

    /// Persist a user-picked folder as a security-scoped bookmark and begin
    /// access. The app layer runs the folder picker and calls this with the
    /// result. Throws when the wrong folder was picked.
    public static func persist(_ pickedURL: URL, for kind: GrantKind) throws {
        guard pickedURL.lastPathComponent == kind.homeSubdir else {
            throw GrantError.wrongFolder(expected: kind.homeSubdir, picked: pickedURL.path)
        }

        let bookmark: Data
        do {
            bookmark = try pickedURL.bookmarkData(options: .withSecurityScope,
                                                  includingResourceValuesForKeys: nil,
                                                  relativeTo: nil)
        } catch {
            throw GrantError.bookmarkFailed(error.localizedDescription)
        }

        try? FileManager.default.createDirectory(at: grantsDir, withIntermediateDirectories: true)
        do {
            try bookmark.write(to: kind.bookmarkFile)
        } catch {
            throw GrantError.bookmarkFailed(error.localizedDescription)
        }

        // Drop any previously-held scope and re-resolve from the fresh bookmark.
        lock.lock()
        if let old = heldURLs.removeValue(forKey: kind) {
            old.stopAccessingSecurityScopedResource()
        }
        cachedRoots[kind] = nil
        lock.unlock()

        if isSandboxed, root(for: kind) == nil {
            throw GrantError.bookmarkFailed("failed to resolve the granted folder")
        }
    }

    /// Reads the persisted bookmark for `kind` and begins security-scoped access.
    private static func resolvePersisted(_ kind: GrantKind) -> URL? {
        guard let data = try? Data(contentsOf: kind.bookmarkFile), !data.isEmpty else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        heldURLs[kind] = url

        // Refresh a stale bookmark in place so future launches keep working.
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            try? fresh.write(to: kind.bookmarkFile)
        }
        return url
    }
}
