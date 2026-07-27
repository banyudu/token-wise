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
            // Two-row readout: today's cost (green) over today's tokens.
            // Rendered as a non-template NSImage because the menu bar forces
            // template (monochrome) rendering on plain Text.
            Image(nsImage: model.loading && model.allSessions.isEmpty
                ? menuBarStatusImage(cost: "…", tokens: nil)
                : menuBarStatusImage(cost: Format.compactCost(model.todayCost),
                                     tokens: Format.tokens(model.todayTokens)))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Render the status as a colored, non-template image — the menu bar strips
/// color from plain SwiftUI Text (template rendering), so draw it ourselves.
/// Two rows: cost (green) on top, tokens (secondary) below.
func menuBarStatusImage(cost: String, tokens: String?) -> NSImage {
    let costLine = NSAttributedString(string: cost, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.systemGreen,
    ])
    let tokenLine = tokens.map {
        NSAttributedString(string: $0, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    let costSize = costLine.size()
    let tokenSize = tokenLine?.size() ?? .zero
    let width = ceil(max(costSize.width, tokenSize.width))
    let height = ceil(costSize.height + tokenSize.height)

    let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
        // Bottom-left origin: token row at the bottom, cost row above it.
        if let tokenLine {
            tokenLine.draw(at: NSPoint(x: (width - tokenSize.width) / 2, y: 0))
        }
        costLine.draw(at: NSPoint(x: (width - costSize.width) / 2, y: tokenSize.height))
        return true
    }
    image.isTemplate = false
    return image
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
