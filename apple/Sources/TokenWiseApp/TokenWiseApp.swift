import SwiftUI
import TokenWiseCore

@main
struct TokenWiseApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Token Wise", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear { if model.allSessions.isEmpty { model.load() } }
        }
        .windowResizability(.contentMinSize)

        // Native Settings window (⌘,).
        Settings {
            SettingsPane()
                .environmentObject(model)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            // Live today's-cost readout in the system menu bar.
            Text(model.loading ? "TW …" : "TW \(Format.cost(model.todayCost))")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Bring the main window to front. SwiftUI's `openWindow` is unreliable from
/// the menu-bar panel's scene context (silently no-ops), but the `Window`
/// scene's NSWindow persists after close (hidden, identifier "main") — so
/// order it front directly and only fall back to `openWindow` when it truly
/// doesn't exist yet.
@MainActor
func openMainWindow(_ openWindow: OpenWindowAction) {
    func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
    }
    if mainWindow() == nil { openWindow(id: "main") }
    NSApp.activate(ignoringOtherApps: true)
    mainWindow()?.makeKeyAndOrderFront(nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        mainWindow()?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Token Wise").font(.headline)
            Divider()
            row("Today", model.todayCost)
            row("All time", model.totalCost)
            row("Sessions", Double(model.allSessions.count), isCount: true)
            Divider()
            HStack {
                Button("Open") { openMainWindow(openWindow) }
                Button(model.loading ? "Loading…" : "Refresh") { model.load(force: true) }
                    .disabled(model.loading)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: Double, isCount: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(isCount ? String(Int(value)) : Format.cost(value)).monospacedDigit().bold()
        }
    }
}
