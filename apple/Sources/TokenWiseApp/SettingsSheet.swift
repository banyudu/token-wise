import SwiftUI
import TokenWiseCore

/// Native Settings window (⌘,): folder re-grants (sandboxed builds) + CLI
/// install to PATH.
enum CliInstall {
    static var linkURL: URL {
        GrantPicker.realHome.appendingPathComponent(".local/bin/token-wise")
    }

    /// The CLI binary that ships next to the app executable in the bundle,
    /// falling back to the GUI executable's own directory in dev builds.
    static var cliURL: URL? {
        let dir = Bundle.main.executableURL?.deletingLastPathComponent()
        guard let url = dir?.appendingPathComponent("token-wise"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static var isInstalled: Bool {
        let link = linkURL
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else {
            return FileManager.default.fileExists(atPath: link.path)
        }
        return FileManager.default.fileExists(atPath: dest)
    }

    /// Symlink the bundled CLI onto `~/.local/bin`. Throws when sandboxed
    /// (can't write outside the container) — caller shows manual steps.
    static func install() throws {
        guard let cli = cliURL else {
            throw NSError(domain: "token-wise", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "CLI binary not found in the app bundle."])
        }
        let fm = FileManager.default
        try fm.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: linkURL)
        try fm.createSymbolicLink(at: linkURL, withDestinationURL: cli)
    }
}

struct SettingsPane: View {
    @EnvironmentObject var model: AppModel
    @State private var message: String?
    @State private var messageIsError = false
    @State private var installed = CliInstall.isInstalled

    var body: some View {
        Form {
            if model.grants.sandboxed {
                Section {
                    LabeledContent(".claude") {
                        grantButton(.claude, granted: model.grants.claude)
                    }
                    LabeledContent(".codex") {
                        grantButton(.codex, granted: model.grants.codex)
                    }
                    LabeledContent(".local/share/opencode") {
                        grantButton(.opencode, granted: model.grants.opencode)
                    }
                } header: {
                    Text("Data folder access")
                } footer: {
                    Text("Token Wise reads these folders from your home directory. Re-grant if the app stops seeing your data after a macOS update or restore.")
                }
            }

            Section {
                LabeledContent("token-wise CLI") {
                    HStack(spacing: 8) {
                        Label(installed ? "Installed" : "Not on PATH",
                              systemImage: installed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(installed ? .green : .secondary)
                        if !installed {
                            Button("Install to PATH") { install() }
                        }
                    }
                }
                if let message {
                    Text(message).font(.caption)
                        .foregroundStyle(messageIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }
                if model.grants.sandboxed || messageIsError {
                    let exe = CliInstall.cliURL?.path ?? "/Applications/token-wise.app/Contents/MacOS/token-wise"
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.grants.sandboxed
                             ? "This build is sandboxed (App Store), so it can't modify your PATH. Set it up manually:"
                             : "Manual setup:")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("ln -sf '\(exe)' ~/.local/bin/token-wise")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("Command-line tool")
            } footer: {
                Text("Run `token-wise total`, `today`, `sessions`, `savings`, or `analyze` from any terminal.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func grantButton(_ kind: GrantKind, granted: Bool) -> some View {
        HStack(spacing: 8) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Button(granted ? "Re-grant…" : "Grant…") { regrant(kind) }
        }
    }

    private func regrant(_ kind: GrantKind) {
        message = nil
        do {
            guard try GrantPicker.pick(kind) != nil else { return }
            model.refreshGrants()
            model.load(force: true)
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func install() {
        message = nil
        do {
            try CliInstall.install()
            installed = CliInstall.isInstalled
            message = "Symlinked to ~/.local/bin/token-wise. Make sure ~/.local/bin is on your PATH."
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }
}
