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
        grants.sandboxed && !(grants.claude && grants.codex)
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
        var result = filterByDateRange(allSessions)
        switch sourceFilter {
        case .all: break
        case .claude: result = result.filter { $0.source == "claude" }
        case .codex: result = result.filter { $0.source == "codex" }
        }
        if let project = projectFilter {
            result = result.filter { $0.project == project }
        }
        sessions = result
        overview = TokenWise.buildOverview(result)
    }

    private func filterByDateRange(_ sessions: [SessionSummary]) -> [SessionSummary] {
        let cal = Calendar.current
        let now = Date()
        let interval: DateInterval?
        switch dateRange {
        case .all:
            interval = nil
        case .today:
            let start = cal.startOfDay(for: now)
            interval = DateInterval(start: start, duration: 86_400)
        case .yesterday:
            let start = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
            interval = DateInterval(start: start, duration: 86_400)
        case .last7, .last30, .last90:
            let days = dateRange == .last7 ? 7 : dateRange == .last30 ? 30 : 90
            interval = DateInterval(start: cal.date(byAdding: .day, value: -days, to: now)!, end: now)
        case .custom:
            let start = cal.startOfDay(for: customFrom)
            let end = cal.startOfDay(for: customTo).addingTimeInterval(86_400)
            interval = DateInterval(start: min(start, end), end: max(start, end))
        }
        guard let interval else { return sessions }
        return sessions.filter { s in
            guard let d = Format.parseDate(s.firstTimestamp) else { return false }
            return interval.contains(d)
        }
    }

    /// Today's total cost in the user's local timezone — drives the menu bar.
    var todayCost: Double {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = .current
        let today = fmt.string(from: Date())
        return allSessions.filter { s in
            guard let d = Format.parseDate(s.lastTimestamp) else { return false }
            return fmt.string(from: d) == today
        }.reduce(0.0) { $0 + $1.estimatedCostUsd }
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
