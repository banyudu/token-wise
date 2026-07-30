import AppKit
import SwiftUI
import TokenWiseCore

/// Folder-grant onboarding for sandboxed (App Store) builds.
enum GrantPicker {
    /// The user's *real* home (not the sandbox container), for pre-navigating
    /// the picker into the expected dotfolder.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return Paths.home
    }

    /// Pops a folder picker for `kind`, persists a security-scoped bookmark on
    /// success. Returns nil when the user cancels; throws on a wrong folder.
    @MainActor
    static func pick(_ kind: GrantKind) throws -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Grant Access"
        panel.message = "Select your \(kind.homeSubdir) folder to let Token Wise read your usage data."
        panel.directoryURL = realHome.appendingPathComponent(kind.homeSubdir, isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try Grants.persist(url, for: kind)
        return url
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var error: String?

    private struct Folder: Identifiable {
        let kind: GrantKind
        let desc: String
        let granted: Bool
        var id: String { kind.rawValue }
    }

    private var folders: [Folder] {
        [Folder(kind: .claude, desc: "Claude Code session transcripts & pricing", granted: model.grants.claude),
         Folder(kind: .codex, desc: "Codex usage logs", granted: model.grants.codex)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Grant folder access").font(.title2.bold())
            Text("Token Wise reads your AI usage data from your home folder. To respect macOS privacy, grant access to each folder once — you won't be asked again.")
                .font(.callout).foregroundStyle(.secondary)

            ForEach(folders) { f in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.kind.homeSubdir).font(.system(.body, design: .monospaced)).bold()
                        Text(f.desc).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if f.granted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    } else {
                        Button("Grant access") { grant(f.kind) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("In the picker, the expected folder is pre-selected — just click **Grant Access**. If a folder isn't visible, press ⌘⇧. to reveal hidden folders.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grant(_ kind: GrantKind) {
        error = nil
        do {
            guard try GrantPicker.pick(kind) != nil else { return } // cancelled
            model.refreshGrants()
            if !model.needsOnboarding { model.load() }
        } catch let e {
            error = e.localizedDescription
        }
    }
}
