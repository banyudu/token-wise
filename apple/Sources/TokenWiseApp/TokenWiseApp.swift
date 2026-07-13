import SwiftUI
import TokenWiseCore

@main
struct TokenWiseApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Token Wise", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { if model.sessions.isEmpty { model.load() } }
        }
        .windowResizability(.contentMinSize)

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

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Token Wise").font(.headline)
            Divider()
            row("Today", model.todayCost)
            row("All time", model.totalCost)
            row("Sessions", Double(model.sessions.count), isCount: true)
            Divider()
            HStack {
                Button("Open") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
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
