import Foundation
import SwiftUI
import TokenWiseCore

@MainActor
final class AppModel: ObservableObject {
    @Published var sessions: [SessionSummary] = []
    @Published var overview: OverviewMetrics?
    @Published var loading = true
    @Published var error: String?

    // AI analysis state
    @Published var analyzing = false
    @Published var analysisReport: String?
    @Published var analysisEngine: String?
    @Published var analysisError: String?

    private let pricing = PricingTable.load()

    var availableEngines: [AIEngine] { AIAnalyzer.availableEngines() }

    func load(force: Bool = false) {
        loading = true
        error = nil
        let pricing = self.pricing
        Task.detached(priority: .userInitiated) {
            let sessions = TokenWise.loadAllSessions(pricing: pricing, force: force)
            let overview = TokenWise.buildOverview(sessions)
            await MainActor.run {
                self.sessions = sessions
                self.overview = overview
                self.loading = false
            }
        }
    }

    /// Today's total cost in the user's local timezone — drives the menu bar.
    var todayCost: Double {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = .current
        let today = fmt.string(from: Date())
        return sessions.filter { s in
            guard let d = Format.parseDate(s.lastTimestamp) else { return false }
            return fmt.string(from: d) == today
        }.reduce(0.0) { $0 + $1.estimatedCostUsd }
    }

    var totalCost: Double { sessions.reduce(0.0) { $0 + $1.estimatedCostUsd } }

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
