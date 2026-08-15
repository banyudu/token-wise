import Foundation

/// Filesystem locations and project-path helpers. Non-sandboxed builds read
/// `~/.claude`, `~/.codex`, and OpenCode's `~/.local/share/opencode` directly; App Store (sandboxed) builds go
/// through the security-scoped bookmarks in `Grants`.
public enum Paths {
    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    public static var claudeRoot: URL? {
        guard let url = Grants.root(for: .claude) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static var claudeProjects: URL? {
        claudeRoot?.appendingPathComponent("projects", isDirectory: true)
    }

    public static var codexRoot: URL? {
        guard let url = Grants.root(for: .codex) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static var opencodeRoot: URL? {
        guard let url = Grants.root(for: .opencode) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Encoded project dir names use `-` for `/`.
    public static func decodeProjectName(_ encoded: String) -> String {
        encoded.replacingOccurrences(of: "-", with: "/")
    }

    /// Collapse a worktree path to its parent repo path so per-project
    /// aggregation groups a repo and its worktrees together.
    public static func normalizeProjectPath(_ path: String) -> String {
        for marker in ["/.worktrees/", "/.claude/worktrees/"] {
            if let range = path.range(of: marker) {
                return String(path[..<range.lowerBound])
            }
        }
        return path
    }
}
