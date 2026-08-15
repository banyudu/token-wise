import Foundation

/// Which local days a session's spend belongs to.
///
/// Claude sessions carry a per-response timestamp, so a session that ran across
/// midnight is split across the days it actually ran. OpenCode sessions use
/// their assistant-message timestamps too. Codex rollouts have no per-response
/// data, so the whole session lands on the day it ended.
///
/// Every surface that reports a date range goes through these — the menu bar's
/// "today" and the window's range filter used to disagree because each had its
/// own rule, and a session started yesterday would either vanish from the
/// window or drop its whole cost on the wrong day.
extension SessionSummary {
    public func cost(on days: Set<String>) -> Double {
        if let daily = dailyCostUsd {
            return days.reduce(0.0) { $0 + (daily[$1] ?? 0) }
        }
        guard let last = Format.localDay(lastTimestamp), days.contains(last) else { return 0 }
        return estimatedCostUsd
    }

    public func tokens(on days: Set<String>) -> UInt64 {
        if let daily = dailyTokens {
            return days.reduce(UInt64(0)) { $0 + (daily[$1] ?? 0) }
        }
        guard let last = Format.localDay(lastTimestamp), days.contains(last) else { return 0 }
        return totalTokens
    }

    public var totalTokens: UInt64 {
        totalInputTokens + totalOutputTokens + totalCacheReadTokens + totalCacheWriteTokens
    }

    /// This session restricted to `days`, or nil when it did nothing on them.
    ///
    /// A session that ran entirely inside the range comes back untouched. One
    /// that straddles the edge is scaled to its in-range share: the cost is
    /// exact (it comes straight from the per-day map) while the token split and
    /// cost breakdown are prorated, since the per-day maps record totals rather
    /// than a per-bucket split.
    public func clipped(to days: Set<String>) -> SessionSummary? {
        let rangeCost = cost(on: days)
        guard rangeCost > 0 else { return nil }
        guard estimatedCostUsd > 0, rangeCost < estimatedCostUsd else { return self }

        var clipped = self
        clipped.estimatedCostUsd = rangeCost
        clipped.costBreakdown.scale(by: rangeCost / estimatedCostUsd)

        let share = totalTokens > 0
            ? Double(tokens(on: days)) / Double(totalTokens)
            : rangeCost / estimatedCostUsd
        func prorate(_ value: UInt64) -> UInt64 { UInt64((Double(value) * share).rounded()) }
        clipped.totalInputTokens = prorate(totalInputTokens)
        clipped.totalOutputTokens = prorate(totalOutputTokens)
        clipped.totalCacheReadTokens = prorate(totalCacheReadTokens)
        clipped.totalCacheWriteTokens = prorate(totalCacheWriteTokens)
        return clipped
    }
}
