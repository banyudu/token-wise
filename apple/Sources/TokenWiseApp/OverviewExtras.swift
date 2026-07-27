import SwiftUI
import TokenWiseCore

// MARK: - Context composition stat row

struct ContextComposition: View {
    let overview: OverviewMetrics

    var body: some View {
        let totalContext = overview.totalInputTokens + overview.totalCacheWriteTokens + overview.totalCacheReadTokens
        if totalContext > 0 {
            let overhead = overview.estimatedSystemOverheadTokens
            let cwRate = overview.totalCacheWriteTokens > 0
                ? overview.costBreakdown.cacheWriteCost / (Double(overview.totalCacheWriteTokens) / 1e6) : 0
            let overheadCost = Double(overhead) / 1_000_000 * cwRate * Double(overview.totalSessions)
            GroupBox("Context Composition") {
                HStack(spacing: 24) {
                    stat(Format.tokens(overhead), "System Overhead / Session", "CLAUDE.md + skills + tools + system prompt")
                    stat(Format.cost(overheadCost), "Est. Overhead Cost", "across \(overview.totalSessions) sessions")
                    stat(Format.percent(Double(overview.totalCacheWriteTokens) / Double(totalContext)), "Cache Miss Rate", "tokens written vs total context")
                    stat(Format.percent(Double(overview.totalCacheReadTokens) / Double(totalContext)), "Cache Reuse Rate", "tokens read from cache")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ sub: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(sub).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Heuristic recommendations

struct RecommendationTip: Identifiable {
    enum Severity: String { case high, medium, low }
    let severity: Severity
    let text: String
    var id: String { text }
}

enum Recommendations {
    static func build(sessions: [SessionSummary], overview: OverviewMetrics) -> [RecommendationTip] {
        var result: [RecommendationTip] = []
        if overview.avgCacheHitRate < 0.5 {
            result.append(.init(severity: .high, text: "Cache hit rate is \(Format.percent(overview.avgCacheHitRate)) — below 50%. Short sessions cause frequent cache misses. Try longer, focused sessions to improve cache reuse."))
        } else if overview.avgCacheHitRate < 0.7 {
            result.append(.init(severity: .medium, text: "Cache hit rate is \(Format.percent(overview.avgCacheHitRate)). Consider consolidating related tasks into fewer sessions to improve cache efficiency."))
        }
        let totalCost = max(overview.costBreakdown.totalCost, 0.000001)
        let cacheWritePct = overview.costBreakdown.cacheWriteCost / totalCost
        if cacheWritePct > 0.3 {
            result.append(.init(severity: .high, text: "Cache writes account for \(Format.percent(cacheWritePct)) of total cost (\(Format.cost(overview.costBreakdown.cacheWriteCost))). Each new session pays the full cache write cost. Reduce session restarts and trim CLAUDE.md/skills to lower this."))
        }
        if overview.estimatedSystemOverheadTokens > 50_000 {
            result.append(.init(severity: .medium, text: "Estimated system overhead is \(Format.tokens(overview.estimatedSystemOverheadTokens)) tokens per session. Review your CLAUDE.md, installed skills, and plugins — each adds to the \"token tax\" paid on every session start."))
        }
        let shortSessions = sessions.filter { $0.source == "claude" && $0.messageCount <= 4 && $0.estimatedCostUsd > 0.5 }
        if shortSessions.count > 5 {
            result.append(.init(severity: .medium, text: "\(shortSessions.count) short sessions (≤4 messages, >$0.50 each) detected. These pay full cache write costs with minimal cache reuse. Consider batching related questions."))
        }
        let outputPct = overview.costBreakdown.outputCost / totalCost
        if outputPct > 0.5 {
            result.append(.init(severity: .medium, text: "Output tokens account for \(Format.percent(outputPct)) of costs. Consider asking for more concise responses or using diff-style edits instead of full file rewrites."))
        }
        let withDuration = sessions.filter { $0.source == "claude" && Format.sessionDurationMs($0) > 60_000 }
        if !withDuration.isEmpty {
            let avgPerHour = withDuration.reduce(0.0) { sum, s in
                let hours = Format.sessionDurationMs(s) / 3_600_000
                return sum + (hours > 0 ? s.estimatedCostUsd / hours : 0)
            } / Double(withDuration.count)
            if avgPerHour > 10 {
                result.append(.init(severity: .medium, text: "Average cost rate is \(Format.cost(avgPerHour))/hour across \(withDuration.count) sessions. High output volume or frequent cache misses may be driving costs up."))
            }
        }
        if result.isEmpty {
            result.append(.init(severity: .low, text: "Your usage patterns look efficient. Keep monitoring cache hit rates and session lengths."))
        }
        return result
    }
}

struct RecommendationsView: View {
    let sessions: [SessionSummary]
    let overview: OverviewMetrics

    var body: some View {
        let tips = Recommendations.build(sessions: sessions, overview: overview)
        GroupBox("Cost Optimization Recommendations") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tips) { tip in
                    HStack(alignment: .top, spacing: 10) {
                        Text(tip.severity.rawValue.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(color(tip.severity).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(color(tip.severity))
                        Text(tip.text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(color(tip.severity).opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func color(_ s: RecommendationTip.Severity) -> Color {
        switch s {
        case .high: return CostColors.output
        case .medium: return CostColors.cacheWrite
        case .low: return CostColors.input
        }
    }
}

// MARK: - Savings potential

struct SavingsPotentialView: View {
    let overview: OverviewMetrics
    let sessions: [SessionSummary]

    private struct Distribution {
        var poor = 0, mediocre = 0, good = 0
        var poorCost = 0.0, mediocreCost = 0.0
        var lowCacheCount: Int { poor + mediocre }
        var lowCacheCost: Double { poorCost + mediocreCost }
    }

    private var distribution: Distribution? {
        let claude = sessions.filter { $0.source == "claude" && $0.messageCount > 0 }
        guard !claude.isEmpty else { return nil }
        var d = Distribution()
        for s in claude {
            if s.cacheHitRate < 0.5 { d.poor += 1; d.poorCost += s.estimatedCostUsd }
            else if s.cacheHitRate < 0.8 { d.mediocre += 1; d.mediocreCost += s.estimatedCostUsd }
            else { d.good += 1 }
        }
        return d
    }

    private struct Projection {
        var currentRate: Double, targetRate: Double
        var currentCost: Double, projectedCost: Double
        var savedAmount: Double, savedPercent: Double
        var shortSessionCount: Int, shortSessionCost: Double
        var excellent: Bool
    }

    private var projection: Projection? {
        let currentRate = overview.avgCacheHitRate
        let totalContext = overview.totalInputTokens + overview.totalCacheWriteTokens + overview.totalCacheReadTokens
        guard totalContext > 0 else { return nil }

        let shortSessions = sessions.filter { $0.source == "claude" && $0.messageCount <= 3 }
        let shortCost = shortSessions.reduce(0.0) { $0 + $1.estimatedCostUsd }
        let currentCost = overview.costBreakdown.totalCost

        if currentRate >= 0.85 {
            return Projection(currentRate: currentRate, targetRate: currentRate,
                              currentCost: currentCost, projectedCost: currentCost,
                              savedAmount: 0, savedPercent: 0,
                              shortSessionCount: shortSessions.count, shortSessionCost: shortCost,
                              excellent: true)
        }

        // Effective per-MTok rates from the actual breakdown — no model
        // assumption needed since the core already priced sessions correctly.
        let inputRate = overview.totalInputTokens > 0
            ? overview.costBreakdown.inputCost / (Double(overview.totalInputTokens) / 1e6) : 3.0
        let cwRate = overview.totalCacheWriteTokens > 0
            ? overview.costBreakdown.cacheWriteCost / (Double(overview.totalCacheWriteTokens) / 1e6) : 3.75
        let crRate = overview.totalCacheReadTokens > 0
            ? overview.costBreakdown.cacheReadCost / (Double(overview.totalCacheReadTokens) / 1e6) : 0.30

        let targetRate = min(currentRate + 0.2, 0.85)
        let targetCacheRead = Double(totalContext) * targetRate
        let tokenShift = targetCacheRead - Double(overview.totalCacheReadTokens)
        let nonCache = Double(overview.totalInputTokens + overview.totalCacheWriteTokens)
        let inputRatio = nonCache > 0 ? Double(overview.totalInputTokens) / nonCache : 0.5

        let newInputCost = (Double(overview.totalInputTokens) - tokenShift * inputRatio) / 1e6 * inputRate
        let newCwCost = (Double(overview.totalCacheWriteTokens) - tokenShift * (1 - inputRatio)) / 1e6 * cwRate
        let newCrCost = targetCacheRead / 1e6 * crRate
        let projected = newInputCost + newCwCost + newCrCost + overview.costBreakdown.outputCost
        let saved = currentCost - projected

        return Projection(currentRate: currentRate, targetRate: targetRate,
                          currentCost: currentCost, projectedCost: max(0, projected),
                          savedAmount: max(0, saved),
                          savedPercent: currentCost > 0 ? max(0, saved) / currentCost : 0,
                          shortSessionCount: shortSessions.count, shortSessionCost: shortCost,
                          excellent: false)
    }

    var body: some View {
        if let savings = projection {
            let dist = distribution
            let hasDistInsight = (dist?.lowCacheCount ?? 0) > 0
            GroupBox("Savings Potential") {
                if savings.excellent && !hasDistInsight {
                    Text("Your cache hit rate is already excellent (\(Format.percent(savings.currentRate))). Keep it up!")
                        .font(.callout).foregroundStyle(CostColors.cacheRead)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        if !savings.excellent { projectionCard(savings) }
                        if hasDistInsight, let dist { distributionCard(dist, excellent: savings.excellent) }
                        if savings.shortSessionCount > 3 { shortSessionsCard(savings) }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func projectionCard(_ s: Projection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("CURRENT").font(.caption2).foregroundStyle(.secondary)
                    Text(Format.cost(s.currentCost)).font(.title3.bold())
                    Text("Cache: \(Format.percent(s.currentRate))").font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    Text("PROJECTED").font(.caption2).foregroundStyle(.secondary)
                    Text(Format.cost(s.projectedCost)).font(.title3.bold())
                    Text("Cache: \(Format.percent(s.targetRate))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Save \(Format.cost(s.savedAmount)) (\(Format.percent(s.savedPercent))) by improving cache hit rate to \(Format.percent(s.targetRate))")
                .font(.caption).foregroundStyle(CostColors.cacheRead)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func distributionCard(_ d: Distribution, excellent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-Session Cache Distribution").font(.caption.bold())
            GeometryReader { geo in
                let total = max(d.poor + d.mediocre + d.good, 1)
                HStack(spacing: 1) {
                    if d.good > 0 { Rectangle().fill(CostColors.cacheRead).frame(width: geo.size.width * Double(d.good) / Double(total)) }
                    if d.mediocre > 0 { Rectangle().fill(CostColors.cacheWrite).frame(width: geo.size.width * Double(d.mediocre) / Double(total)) }
                    if d.poor > 0 { Rectangle().fill(CostColors.output).frame(width: geo.size.width * Double(d.poor) / Double(total)) }
                }
            }
            .frame(height: 16).clipShape(RoundedRectangle(cornerRadius: 4))
            Text("\(d.good) good (>80%) · \(d.mediocre) mediocre (50–80%) · \(d.poor) poor (<50%)")
                .font(.caption2).foregroundStyle(.secondary)
            if d.lowCacheCost > 0.01 {
                Divider()
                Text("\(d.lowCacheCount) session\(d.lowCacheCount > 1 ? "s" : "") with sub-optimal cache (\(Format.cost(d.lowCacheCost)))\(excellent ? " despite excellent global rate" : "")")
                    .font(.caption).foregroundStyle(CostColors.cacheWrite)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func shortSessionsCard(_ s: Projection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(s.shortSessionCount) short sessions").font(.title3.bold())
            Text("\(Format.cost(s.shortSessionCost)) spent on sessions with ≤3 messages")
                .font(.caption2).foregroundStyle(.secondary)
            Divider()
            Text("Consolidating these into longer sessions could significantly reduce cache write overhead")
                .font(.caption).foregroundStyle(CostColors.cacheRead)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
