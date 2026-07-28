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
///
/// Extra care for real-world setups:
/// - close the status panel first (its focus-loss dismissal can race the
///   window ordering),
/// - `.moveToActiveSpace` so the window follows you to the CURRENT Space
///   (without it, on multi-Space/yabai setups "nothing happens" because the
///   window surfaces on another Space),
/// - `orderFrontRegardless` + deminiaturize as belt-and-braces.
@MainActor
func openMainWindow(_ openWindow: OpenWindowAction) {
    func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
    }

    func surface(_ label: String) {
        guard let win = mainWindow() else {
            openLog("\(label): main window not found")
            return
        }
        win.collectionBehavior.insert(.moveToActiveSpace)
        if win.isMiniaturized { win.deminiaturize(nil) }
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        openLog("\(label): visible=\(win.isVisible) key=\(win.isKeyWindow) miniaturized=\(win.isMiniaturized) screen=\(win.screen != nil)")
    }

    openLog("clicked; windows=\(NSApp.windows.map { "\($0.identifier?.rawValue ?? type(of: $0).description())/vis=\($0.isVisible)" })")

    // Dismiss the menu-bar panel before touching window order.
    if let key = NSApp.keyWindow, key.identifier?.rawValue != "main" { key.close() }

    if mainWindow() == nil { openWindow(id: "main") }
    NSApp.activate(ignoringOtherApps: true)
    surface("immediate")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        NSApp.activate(ignoringOtherApps: true)
        surface("delayed")
    }
}

/// Append-only diagnostics for the Open flow — tiny, and invaluable when a
/// window-manager setup (Spaces, yabai) swallows the window.
private func openLog(_ line: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let msg = "[\(ts)] \(line)\n"
    let path = "/tmp/token-wise-open.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(Data(msg.utf8))
        try? handle.close()
    } else {
        try? msg.write(toFile: path, atomically: true, encoding: .utf8)
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
