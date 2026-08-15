import Foundation

/// Top-level facade: loads Claude, Codex, and OpenCode sessions and builds aggregates.
public enum TokenWise {
    public static func loadAllSessions(pricing: PricingTable, force: Bool = false) -> [SessionSummary] {
        var sessions = ClaudeParser.loadSessions(pricing: pricing, force: force)
        sessions.append(contentsOf: CodexParser.loadSessions(pricing: pricing, force: force))
        sessions.append(contentsOf: OpencodeParser.loadSessions(pricing: pricing, force: force))
        return sessions
    }

    public static func buildOverview(_ sessions: [SessionSummary]) -> OverviewMetrics {
        Overview.build(sessions)
    }
}

enum Overview {
    static func build(_ sessions: [SessionSummary]) -> OverviewMetrics {
        var totalInput: UInt64 = 0, totalOutput: UInt64 = 0
        var totalCacheWrite: UInt64 = 0, totalCacheRead: UInt64 = 0
        var totalCost = 0.0
        var breakdown = CostBreakdown()
        var projectMap: [String: [SessionSummary]] = [:]
        var dailyMap: [String: DailyCost] = [:]
        var hourlyMap: [String: HourlyCost] = [:]
        var firstTurnWrites: [UInt64] = []

        for s in sessions {
            totalInput += s.totalInputTokens
            totalOutput += s.totalOutputTokens
            totalCacheWrite += s.totalCacheWriteTokens
            totalCacheRead += s.totalCacheReadTokens
            totalCost += s.estimatedCostUsd
            breakdown.add(s.costBreakdown)

            projectMap[s.project.isEmpty ? "unknown" : s.project, default: []].append(s)

            if let ts = s.firstTimestamp, ts.count >= 13 {
                let day = String(ts.prefix(10))
                let hour = String(ts.prefix(13))
                accumulate(&dailyMap, key: day, session: s) {
                    DailyCost(date: day, costUsd: 0, costBreakdown: CostBreakdown(),
                              inputTokens: 0, outputTokens: 0, cacheWriteTokens: 0,
                              cacheReadTokens: 0, source: s.source)
                } update: { d in
                    d.costUsd += s.estimatedCostUsd; d.costBreakdown.add(s.costBreakdown)
                    d.inputTokens += s.totalInputTokens; d.outputTokens += s.totalOutputTokens
                    d.cacheWriteTokens += s.totalCacheWriteTokens; d.cacheReadTokens += s.totalCacheReadTokens
                }
                accumulate(&hourlyMap, key: hour, session: s) {
                    HourlyCost(hour: hour, costUsd: 0, costBreakdown: CostBreakdown(),
                               inputTokens: 0, outputTokens: 0, cacheWriteTokens: 0,
                               cacheReadTokens: 0, source: s.source)
                } update: { h in
                    h.costUsd += s.estimatedCostUsd; h.costBreakdown.add(s.costBreakdown)
                    h.inputTokens += s.totalInputTokens; h.outputTokens += s.totalOutputTokens
                    h.cacheWriteTokens += s.totalCacheWriteTokens; h.cacheReadTokens += s.totalCacheReadTokens
                }
            }
            if s.source == "claude", s.firstTurnCacheWrite > 0 {
                firstTurnWrites.append(s.firstTurnCacheWrite)
            }
        }

        let totalContext = totalCacheRead + totalCacheWrite + totalInput
        let avgHit = totalContext > 0 ? Double(totalCacheRead) / Double(totalContext) : 0

        var projects = projectMap.map { proj, sess -> ProjectSummary in
            let input = sess.reduce(UInt64(0)) { $0 + $1.totalInputTokens }
            let output = sess.reduce(UInt64(0)) { $0 + $1.totalOutputTokens }
            let cw = sess.reduce(UInt64(0)) { $0 + $1.totalCacheWriteTokens }
            let cr = sess.reduce(UInt64(0)) { $0 + $1.totalCacheReadTokens }
            let cost = sess.reduce(0.0) { $0 + $1.estimatedCostUsd }
            let ctx = cr + cw + input
            return ProjectSummary(project: proj, sessionCount: UInt32(sess.count), totalCostUsd: cost,
                                  totalInputTokens: input, totalOutputTokens: output,
                                  totalCacheWriteTokens: cw, totalCacheReadTokens: cr,
                                  avgCacheHitRate: ctx > 0 ? Double(cr) / Double(ctx) : 0)
        }
        projects.sort { $0.totalCostUsd > $1.totalCostUsd }

        let daily = dailyMap.values.sorted { $0.date < $1.date }
        let hourly = hourlyMap.values.sorted { $0.hour < $1.hour }
        let top = sessions.sorted { $0.estimatedCostUsd > $1.estimatedCostUsd }.prefix(20)

        // System overhead: the median first-turn cache write (system prompt +
        // tools + CLAUDE.md) is a far better "typical" estimate than the max,
        // which a single invalidation-heavy session would dominate.
        let overhead = median(firstTurnWrites)

        return OverviewMetrics(
            totalSessions: UInt32(sessions.count), totalCostUsd: totalCost,
            totalInputTokens: totalInput, totalOutputTokens: totalOutput,
            totalCacheWriteTokens: totalCacheWrite, totalCacheReadTokens: totalCacheRead,
            avgCacheHitRate: avgHit, costBreakdown: breakdown,
            estimatedSystemOverheadTokens: overhead, dailyCosts: daily, hourlyCosts: hourly,
            projectSummaries: projects, topSessions: Array(top)
        )
    }

    private static func accumulate<T>(_ map: inout [String: T], key: String, session: SessionSummary,
                                      make: () -> T, update: (inout T) -> Void) {
        var entry = map[key] ?? make()
        update(&entry)
        map[key] = entry
    }

    private static func median(_ values: [UInt64]) -> UInt64 {
        if values.isEmpty { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
