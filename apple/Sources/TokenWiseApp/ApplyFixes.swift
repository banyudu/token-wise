import AppKit
import Foundation
import TokenWiseCore

/// Turns picked recommendations into something that can actually change the
/// user's setup.
///
/// Token Wise only reads usage data, and the fixes it surfaces ("trim the
/// CLAUDE.md import chain", "move routine work off Opus") are edits to config
/// it does not own — so applying them means handing them to an agent that can,
/// with the user approving each edit in that session.
enum FixApplier {
    enum Failure: LocalizedError {
        case claudeNotFound
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .claudeNotFound:
                return "The `claude` CLI wasn't found on PATH or in the usual install locations."
            case let .launchFailed(message):
                return "Couldn't open a terminal session: \(message)"
            }
        }
    }

    static var canApply: Bool { AIAnalyzer.locate(.claude) != nil }

    /// The instruction handed to the agent — the fixes verbatim, since they
    /// already carry the user's own numbers.
    static func prompt(for fixes: [AnalysisFix]) -> String {
        let body = fixes
            .map { "\($0.number). \($0.markdown)" }
            .joined(separator: "\n\n")
        let plural = fixes.count == 1 ? "this cost fix" : "these \(fixes.count) cost fixes"
        return """
        Token Wise analyzed my Claude Code / Codex usage and suggested \(plural). \
        Apply them to my setup, and tell me anything you can't do or disagree with \
        instead of guessing.

        \(body)
        """
    }

    static func copy(_ fixes: [AnalysisFix]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt(for: fixes), forType: .string)
    }

    /// Opens an interactive `claude` session seeded with the selected fixes.
    ///
    /// Interactive on purpose: the agent proposes each edit and the user
    /// approves it there, rather than this app mutating dotfiles behind a
    /// button. Starts in the home directory so `~/.claude` and `~/.agents` are
    /// both in reach.
    static func launchClaude(with fixes: [AnalysisFix]) throws {
        guard let binary = AIAnalyzer.locate(.claude) else { throw Failure.claudeNotFound }

        // Quoted heredoc so nothing in the prompt is expanded by the shell.
        let delimiter = "TOKEN_WISE_PROMPT_EOF"
        let body = prompt(for: fixes)
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces) != delimiter }
            .joined(separator: "\n")
        let script = """
        #!/bin/zsh
        cd "$HOME" || exit 1
        PROMPT=$(cat <<'\(delimiter)'
        \(body)
        \(delimiter)
        )
        exec \(shellQuoted(binary.path)) "$PROMPT"
        """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-wise-apply-\(UUID().uuidString.prefix(8)).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            throw Failure.launchFailed(error.localizedDescription)
        }

        let workspace = NSWorkspace.shared
        let terminal = ["com.googlecode.iterm2", "com.apple.Terminal"]
            .lazy
            .compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }
            .first
        guard let terminal else { throw Failure.launchFailed("no terminal application found") }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open([url], withApplicationAt: terminal, configuration: configuration) { _, error in
            if let error {
                NSLog("token-wise: apply-with-claude launch failed: \(error.localizedDescription)")
            }
        }
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
