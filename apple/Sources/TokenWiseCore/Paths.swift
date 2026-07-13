import Foundation

/// Filesystem locations and project-path helpers. The Swift build reads
/// `~/.claude` and `~/.codex` directly (no App Store sandbox bookmark layer yet
/// — that returns when we tackle distribution).
public enum Paths {
    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    public static var claudeRoot: URL? {
        let url = home.appendingPathComponent(".claude", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static var claudeProjects: URL? {
        claudeRoot?.appendingPathComponent("projects", isDirectory: true)
    }

    public static var codexRoot: URL? {
        let url = home.appendingPathComponent(".codex", isDirectory: true)
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
