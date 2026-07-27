import XCTest
@testable import TokenWiseCore

final class CoreTests: XCTestCase {
    func testNormalizeWorktreePath() {
        XCTAssertEqual(
            Paths.normalizeProjectPath("/Users/x/dev/proj/.worktrees/_9"),
            "/Users/x/dev/proj"
        )
        XCTAssertEqual(
            Paths.normalizeProjectPath("/Users/x/dev/proj/.claude/worktrees/abc"),
            "/Users/x/dev/proj"
        )
        XCTAssertEqual(
            Paths.normalizeProjectPath("/Users/x/dev/proj"),
            "/Users/x/dev/proj"
        )
    }

    func testDecodeProjectName() {
        XCTAssertEqual(Paths.decodeProjectName("-Users-x-dev-proj"), "/Users/x/dev/proj")
    }

    func testFormatTokens() {
        XCTAssertEqual(Format.tokens(950), "950")
        XCTAssertEqual(Format.tokens(1_500), "1.5K")
        XCTAssertEqual(Format.tokens(2_500_000), "2.5M")
    }

    func testFormatDuration() {
        XCTAssertEqual(Format.duration(0), "—")
        XCTAssertEqual(Format.duration(30_000), "<1m")
        XCTAssertEqual(Format.duration(5 * 60_000), "5m")
        XCTAssertEqual(Format.duration(90 * 60_000), "1h 30m")
    }

    func testCostBreakdownAdd() {
        var a = CostBreakdown(inputCost: 1, outputCost: 2, cacheWriteCost: 3, cacheReadCost: 4, totalCost: 10)
        a.add(CostBreakdown(inputCost: 1, outputCost: 1, cacheWriteCost: 1, cacheReadCost: 1, totalCost: 4))
        XCTAssertEqual(a.totalCost, 14)
        XCTAssertEqual(a.inputCost, 2)
    }

    func testClaudeSummarizeFromFixture() {
        // Two assistant turns with usage; verify token sums and cost.
        let line1 = #"{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/x/proj","message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":1000,"cache_read_input_tokens":2000}}}"#
        let line2 = #"{"type":"assistant","timestamp":"2026-01-01T00:01:00.000Z","message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":0,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":3000}}}"#
        let decoder = JSONDecoder()
        let messages = [line1, line2].compactMap { try? decoder.decode(ClaudeMessage.self, from: Data($0.utf8)) }
        XCTAssertEqual(messages.count, 2)
        let s = ClaudeParser.summarize(sessionId: "t", messages: messages, pricing: PricingTable(), subagentCost: 0, subagentCount: 0)
        XCTAssertEqual(s.totalInputTokens, 100)
        XCTAssertEqual(s.totalOutputTokens, 60)
        XCTAssertEqual(s.totalCacheWriteTokens, 1000)
        XCTAssertEqual(s.totalCacheReadTokens, 5000)
        XCTAssertEqual(s.firstTurnCacheWrite, 1000)
        XCTAssertEqual(s.project, "/x/proj")
        // cost = 100/1e6*3 + 1000/1e6*3.75 + 5000/1e6*0.30 + 60/1e6*15
        XCTAssertEqual(s.estimatedCostUsd, 0.0003 + 0.00375 + 0.0015 + 0.0009, accuracy: 1e-9)
    }

    func testDuplicateUsageLinesCountedOnce() {
        // Streaming writes one line per content block, all carrying the SAME
        // message id + usage. Only the first may count.
        let usage = #""usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":1000,"cache_read_input_tokens":2000}"#
        let dup = #"{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","requestId":"req_1","message":{"id":"msg_A","role":"assistant","model":"claude-sonnet-4-6",\#(usage)}}"#
        let other = #"{"type":"assistant","timestamp":"2026-01-01T00:01:00.000Z","requestId":"req_2","message":{"id":"msg_B","role":"assistant","model":"claude-sonnet-4-6",\#(usage)}}"#
        let decoder = JSONDecoder()
        let messages = [dup, dup, dup, other].compactMap { try? decoder.decode(ClaudeMessage.self, from: Data($0.utf8)) }
        XCTAssertEqual(messages.count, 4)
        let s = ClaudeParser.summarize(sessionId: "t", messages: messages, pricing: PricingTable(), subagentCost: 0, subagentCount: 0)
        XCTAssertEqual(s.totalInputTokens, 200)      // 2 unique responses, not 4 lines
        XCTAssertEqual(s.totalOutputTokens, 100)
        XCTAssertEqual(s.totalCacheWriteTokens, 2000)
        XCTAssertEqual(s.totalCacheReadTokens, 4000)
    }

    func testDailyCostAttributionSplitsAcrossDays() {
        let mk = { (ts: String, id: String) in
            #"{"type":"assistant","timestamp":"\#(ts)","message":{"id":"\#(id)","role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        }
        // Noon UTC two days apart — distinct local days in any timezone.
        let decoder = JSONDecoder()
        let messages = [mk("2026-01-01T12:00:00.000Z", "m1"), mk("2026-01-03T12:00:00.000Z", "m2")]
            .compactMap { try? decoder.decode(ClaudeMessage.self, from: Data($0.utf8)) }
        let s = ClaudeParser.summarize(sessionId: "t", messages: messages, pricing: PricingTable(), subagentCost: 0, subagentCount: 0)
        let daily = s.dailyCostUsd ?? [:]
        XCTAssertEqual(daily.count, 2)
        // 1M input at Sonnet $3/MTok per day.
        for (_, cost) in daily { XCTAssertEqual(cost, 3.0, accuracy: 1e-9) }
        XCTAssertEqual(daily.values.reduce(0, +), s.estimatedCostUsd, accuracy: 1e-9)
    }

    func testAIPromptContainsSections() {
        let overview = OverviewMetrics(
            totalSessions: 1, totalCostUsd: 1, totalInputTokens: 1, totalOutputTokens: 1,
            totalCacheWriteTokens: 1, totalCacheReadTokens: 1, avgCacheHitRate: 0.5,
            costBreakdown: CostBreakdown(inputCost: 0.25, outputCost: 0.25, cacheWriteCost: 0.25, cacheReadCost: 0.25, totalCost: 1),
            estimatedSystemOverheadTokens: 1000, dailyCosts: [], hourlyCosts: [],
            projectSummaries: [], topSessions: [])
        let prompt = AIAnalyzer.buildPrompt(overview: overview, sessions: [])
        XCTAssertTrue(prompt.contains("## Actionable fixes"))
        XCTAssertTrue(prompt.contains("## Narrative"))
        XCTAssertTrue(prompt.contains("Total spend"))
    }
}
