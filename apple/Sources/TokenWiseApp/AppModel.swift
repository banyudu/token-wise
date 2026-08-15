import Foundation
import SwiftUI
import TokenWiseCore

enum DateRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last7 = "7 Days"
    case last30 = "30 Days"
    case last90 = "90 Days"
    case all = "All Time"
    case custom = "Custom"

    var id: String { rawValue }
}

enum SourceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case claude = "Claude"
    case codex = "Codex"
    case opencode = "OpenCode"

    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    /// Every loaded session (unfiltered).
    @Published var allSessions: [SessionSummary] = []
    @Published var loading = true
    @Published var error: String?

    // Filters — every change re-derives `sessions` + `overview`.
    @Published var dateRange: DateRange = .last30 { didSet { applyFilters() } }
    @Published var customFrom = Calendar.current.date(byAdding: .day, value: -7, to: Date())! { didSet { applyFilters() } }
    @Published var customTo = Date() { didSet { applyFilters() } }
    @Published var sourceFilter: SourceFilter = .all { didSet { applyFilters() } }
    @Published var projectFilter: String? { didSet { applyFilters() } }

    // Derived from filters.
    @Published var sessions: [SessionSummary] = []
    @Published var overview: OverviewMetrics?

    // Sandbox folder grants (App Store builds only).
    @Published var grants = Grants.status()

    // AI analysis state
    @Published var analyzing = false
    @Published var analysisReport: String?
    @Published var analysisEngine: String?
    @Published var analysisError: String?

    private let pricing = PricingTable.load()
    private var refreshTimer: Timer?

    /// Keep the menu-bar readout fresh: re-scan every 5 minutes. Unchanged
    /// files hit the per-file cache, so a periodic reload is cheap.
    init() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.loading else { return }
                self.load()
            }
        }
    }

    var availableEngines: [AIEngine] { AIAnalyzer.availableEngines() }

    /// Hour-resolution chart for day-scale ranges (Today/Yesterday/custom ≤48h).
    var showHourly: Bool {
        switch dateRange {
        case .today, .yesterday: return true
        case .custom:
            let span = customTo.addingTimeInterval(86_400).timeIntervalSince(customFrom)
            return span <= 48 * 3_600
        default: return false
        }
    }

    var needsOnboarding: Bool {
        grants.sandboxed && !(grants.claude && grants.codex && grants.opencode)
    }

    func refreshGrants() {
        grants = Grants.status()
    }

    func load(force: Bool = false) {
        guard !needsOnboarding else { return }
        loading = true
        error = nil
        let pricing = self.pricing
        Task.detached(priority: .userInitiated) {
            let sessions = TokenWise.loadAllSessions(pricing: pricing, force: force)
            await MainActor.run {
                self.allSessions = sessions
                self.loading = false
                self.applyFilters()
            }
        }
    }

    private func applyFilters() {
        var result = clipToDateRange(allSessions)
        switch sourceFilter {
        case .all: break
        case .claude: result = result.filter { $0.source == "claude" }
        case .codex: result = result.filter { $0.source == "codex" }
        case .opencode: result = result.filter { $0.source == "opencode" }
        }
        if let project = projectFilter {
            result = result.filter { $0.project == project }
        }
        sessions = result
        overview = TokenWise.buildOverview(result)
    }

    /// The local days the active range covers, or nil for "All Time".
    ///
    /// Ranges are whole local days because that is the granularity the per-day
    /// attribution maps carry — "7 Days" means today plus the six before it.
    private var daysInRange: Set<String>? {
        let cal = Calendar.current
        let now = Date()
        func days(from start: Date, count: Int) -> Set<String> {
            Set((0..<count).compactMap { offset in
                cal.date(byAdding: .day, value: offset, to: start).map(Format.localDay(of:))
            })
        }
        switch dateRange {
        case .all:
            return nil
        case .today:
            return [Format.localDay(of: now)]
        case .yesterday:
            return [Format.localDay(of: cal.date(byAdding: .day, value: -1, to: now)!)]
        case .last7, .last30, .last90:
            let count = dateRange == .last7 ? 7 : dateRange == .last30 ? 30 : 90
            return days(from: cal.date(byAdding: .day, value: -(count - 1), to: cal.startOfDay(for: now))!,
                        count: count)
        case .custom:
            let from = cal.startOfDay(for: min(customFrom, customTo))
            let to = cal.startOfDay(for: max(customFrom, customTo))
            let span = (cal.dateComponents([.day], from: from, to: to).day ?? 0) + 1
            return days(from: from, count: span)
        }
    }

    /// Restricts each session to the active range, dropping those with no
    /// activity in it, so a range total matches what the menu bar reports for
    /// the same days instead of counting a long session's whole cost on the day
    /// it began.
    private func clipToDateRange(_ sessions: [SessionSummary]) -> [SessionSummary] {
        guard let days = daysInRange else { return sessions }
        return sessions.compactMap { $0.clipped(to: days) }
    }

    /// Today's total cost in the user's local timezone — drives the menu bar.
    /// Shares `SessionSummary.cost(on:)` with the window's range filter so the
    /// two readouts can never drift apart.
    var todayCost: Double {
        let today: Set<String> = [Format.localDay(of: Date())]
        return allSessions.reduce(0.0) { $0 + $1.cost(on: today) }
    }

    /// Tokens processed today (input + output + cache read/write), same
    /// attribution rules as `todayCost`.
    var todayTokens: UInt64 {
        let today: Set<String> = [Format.localDay(of: Date())]
        return allSessions.reduce(UInt64(0)) { $0 + $1.tokens(on: today) }
    }

    var totalCost: Double { allSessions.reduce(0.0) { $0 + $1.estimatedCostUsd } }

    func runAnalysis(engine: AIEngine?) {
        guard let overview else { return }
        analyzing = true
        analysisError = nil
        analysisReport = nil
        let sessions = self.sessions
        Task.detached(priority: .userInitiated) {
            do {
                let result = try AIAnalyzer.analyze(overview: overview, sessions: sessions, engine: engine)
                await MainActor.run {
                    self.analysisReport = result.report
                    self.analysisEngine = result.engine.rawValue
                    self.analyzing = false
                }
            } catch {
                await MainActor.run {
                    self.analysisError = "\(error)"
                    self.analyzing = false
                }
            }
        }
    }
}
