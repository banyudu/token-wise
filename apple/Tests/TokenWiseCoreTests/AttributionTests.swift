import XCTest
@testable import TokenWiseCore

final class AttributionTests: XCTestCase {
    /// A Claude session that ran across midnight: $30 on the 10th, $10 on the 11th.
    private func straddlingSession() -> SessionSummary {
        SessionSummary(
            sessionId: "s1", project: "/p", gitBranch: nil, title: nil, messageCount: 10,
            totalInputTokens: 1000, totalOutputTokens: 500,
            totalCacheWriteTokens: 2000, totalCacheReadTokens: 6500,
            cacheHitRate: 0.9, estimatedCostUsd: 40,
            costBreakdown: CostBreakdown(inputCost: 4, outputCost: 20, cacheWriteCost: 12,
                                         cacheReadCost: 4, totalCost: 40),
            firstTimestamp: "2026-07-10T22:00:00Z", lastTimestamp: "2026-07-11T02:00:00Z",
            firstTurnCacheWrite: 2000, subagentCount: 0, subagentCostUsd: 0,
            source: "claude", model: "claude-opus-5", pricedByFallback: false,
            ephemeral5mTokens: 0, ephemeral1hTokens: 0,
            dailyCostUsd: ["2026-07-10": 30, "2026-07-11": 10],
            dailyTokens: ["2026-07-10": 7500, "2026-07-11": 2500]
        )
    }

    /// Codex has no per-response timestamps, so the whole session lands on the
    /// day it ended.
    private func codexSession() -> SessionSummary {
        SessionSummary(
            sessionId: "s2", project: "/p", gitBranch: nil, title: nil, messageCount: 4,
            totalInputTokens: 100, totalOutputTokens: 50,
            totalCacheWriteTokens: 0, totalCacheReadTokens: 850,
            cacheHitRate: 0.8, estimatedCostUsd: 7,
            costBreakdown: CostBreakdown(totalCost: 7),
            firstTimestamp: "2026-07-10T22:00:00Z", lastTimestamp: "2026-07-11T02:00:00Z",
            firstTurnCacheWrite: 0, subagentCount: 0, subagentCostUsd: 0,
            source: "codex", model: "gpt-5.5", pricedByFallback: false,
            ephemeral5mTokens: 0, ephemeral1hTokens: 0,
            dailyCostUsd: nil, dailyTokens: nil
        )
    }

    private func localDay(_ iso: String) -> String {
        Format.localDay(iso)!
    }

    func testSpendSplitsAcrossTheDaysItRan() {
        let s = straddlingSession()
        XCTAssertEqual(s.cost(on: ["2026-07-10"]), 30)
        XCTAssertEqual(s.cost(on: ["2026-07-11"]), 10)
        XCTAssertEqual(s.cost(on: ["2026-07-10", "2026-07-11"]), 40)
        XCTAssertEqual(s.cost(on: ["2026-07-12"]), 0)
    }

    func testClippingScalesTokensAndBreakdownToTheRange() {
        // The day-2 slice is a quarter of the cost and a quarter of the tokens.
        let clipped = straddlingSession().clipped(to: ["2026-07-11"])
        XCTAssertNotNil(clipped)
        XCTAssertEqual(clipped!.estimatedCostUsd, 10)
        XCTAssertEqual(clipped!.costBreakdown.totalCost, 10, accuracy: 1e-9)
        XCTAssertEqual(clipped!.costBreakdown.outputCost, 5, accuracy: 1e-9)
        XCTAssertEqual(clipped!.totalInputTokens, 250)
        XCTAssertEqual(clipped!.totalOutputTokens, 125)
    }

    func testSessionFullyInsideRangeIsUntouched() {
        let s = straddlingSession()
        let clipped = s.clipped(to: ["2026-07-10", "2026-07-11", "2026-07-12"])
        XCTAssertEqual(clipped, s)
        XCTAssertEqual(clipped?.estimatedCostUsd, 40)
        XCTAssertEqual(clipped?.totalCacheReadTokens, 6500)
    }

    func testSessionOutsideRangeIsDropped() {
        XCTAssertNil(straddlingSession().clipped(to: ["2026-07-12"]))
    }

    func testCodexLandsWhollyOnItsClosingDay() {
        let s = codexSession()
        let opened = localDay(s.firstTimestamp!)
        let closed = localDay(s.lastTimestamp!)
        XCTAssertEqual(s.cost(on: [closed]), 7)
        XCTAssertEqual(s.clipped(to: [closed]), s)
        if opened != closed {
            XCTAssertEqual(s.cost(on: [opened]), 0)
            XCTAssertNil(s.clipped(to: [opened]))
        }
    }

    func testRangeTotalMatchesTheSumOfDailySlices() {
        // The invariant the menu bar and the window's range filter share: a
        // range total is exactly the per-day spend over those days.
        let sessions = [straddlingSession(), codexSession()]
        let days: Set<String> = [localDay("2026-07-11T02:00:00Z")]
        let windowTotal = sessions.compactMap { $0.clipped(to: days) }
            .reduce(0.0) { $0 + $1.estimatedCostUsd }
        let menuBarTotal = sessions.reduce(0.0) { $0 + $1.cost(on: days) }
        XCTAssertEqual(windowTotal, menuBarTotal, accuracy: 1e-9)
    }
}
