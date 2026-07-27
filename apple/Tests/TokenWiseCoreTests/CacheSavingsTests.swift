import XCTest
@testable import TokenWiseCore

final class CacheSavingsTests: XCTestCase {
    private let pricing = PricingInfo(input: 3.0, cacheWrite: 3.75, cacheRead: 0.30, output: 15.0)

    private func turn(_ i: UInt32, role: String = "assistant",
                      write: UInt64 = 0, read: UInt64 = 0) -> TurnMetrics {
        TurnMetrics(turnIndex: i, role: role, inputTokens: 0, outputTokens: 0,
                    cacheWriteTokens: write, cacheReadTokens: read,
                    cumulativeContext: 0, cacheHitRate: 0, costUsd: 0, timestamp: nil)
    }

    private func decode(_ lines: [String]) -> [ClaudeMessage] {
        let decoder = JSONDecoder()
        return lines.compactMap { try? decoder.decode(ClaudeMessage.self, from: Data($0.utf8)) }
    }

    // MARK: H1 — wasted writes

    func testWastedWriteDetectedWhenNeverReadBack() {
        // Turn 1 writes 50K that no later turn ever reads back.
        let turns = [
            turn(0, write: 10_000, read: 0),
            turn(1, write: 50_000, read: 10_000),
            turn(2, write: 0, read: 10_000),
        ]
        let result = CacheSavings.detectWastedWrites(turns, pricing)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].turnIndex, 1)
        XCTAssertEqual(result[0].wastedTokens, 50_000)
        XCTAssertEqual(result[0].wastedCostUsd, 50_000.0 / 1_000_000.0 * 3.75, accuracy: 1e-9)
    }

    func testNoWasteWhenFullyReadBack() {
        let turns = [
            turn(0, write: 10_000, read: 0),
            turn(1, write: 50_000, read: 10_000),
            turn(2, write: 0, read: 60_000), // reads everything written so far
        ]
        XCTAssertTrue(CacheSavings.detectWastedWrites(turns, pricing).isEmpty)
    }

    func testFirstTurnWriteNeverReported() {
        let turns = [turn(0, write: 100_000, read: 0), turn(1, write: 0, read: 0)]
        XCTAssertTrue(CacheSavings.detectWastedWrites(turns, pricing).isEmpty)
    }

    func testTinyWasteBelowThresholdSkipped() {
        let turns = [
            turn(0, write: 10_000, read: 0),
            turn(1, write: 500, read: 10_000), // wasted but < 1K
            turn(2, write: 0, read: 10_000),
        ]
        XCTAssertTrue(CacheSavings.detectWastedWrites(turns, pricing).isEmpty)
    }

    // MARK: H2 — invalidations

    func testInvalidationDetectedOnCacheReadDrop() {
        let turns = [
            turn(0, read: 100_000),
            turn(1, read: 20_000), // 80% drop
        ]
        let events = CacheSavings.detectInvalidations(turns, [], pricing)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].turnIndex, 1)
        XCTAssertEqual(events[0].droppedTokens, 80_000)
        XCTAssertEqual(events[0].rewriteCostUsd, 80_000.0 / 1_000_000.0 * 3.75, accuracy: 1e-9)
    }

    func testNoInvalidationOnSmallDrop() {
        let turns = [turn(0, read: 100_000), turn(1, read: 90_000)]
        XCTAssertTrue(CacheSavings.detectInvalidations(turns, [], pricing).isEmpty)
    }

    func testInvalidationCulpritFromLargeBlock() {
        let big = String(repeating: "x", count: 12_000)
        let msg = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"\#(big)"}]}}"#
        let messages = decode([msg])
        let turns = [turn(0, read: 100_000), turn(1, read: 10_000)]
        let events = CacheSavings.detectInvalidations(turns, messages, pricing)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].suspectedCause, "tool_result")
    }

    // MARK: H3 — unreferenced blocks

    func testUnreferencedClaudeMdBlockDetected() {
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 200)
        let reminderText = "# claudeMd\n## `UniqueConventionAlpha` rules\nUse `veryDistinctiveHelperFn` always.\n" + filler
        let userMsg = """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":\(jsonEscape(reminderText))}]}}
        """
        let asstMsg = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done, nothing related"}]}}"#
        let messages = decode([userMsg, asstMsg])
        let turns = [turn(0, role: "user"), turn(1, role: "assistant")]
        let blocks = CacheSavings.detectUnreferencedBlocks(messages, turns, pricing)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].label, "CLAUDE.md")
        XCTAssertGreaterThan(blocks[0].wastedCostUsd, 0)
    }

    func testReferencedBlockSkipped() {
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 200)
        let reminderText = "# claudeMd\n## `UniqueConventionAlpha` rules\nUse `veryDistinctiveHelperFn` always.\n" + filler
        let userMsg = """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":\(jsonEscape(reminderText))}]}}
        """
        // Downstream references two distinctive tokens.
        let asstMsg = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Applying UniqueConventionAlpha rules via veryDistinctiveHelperFn"}]}}"#
        let messages = decode([userMsg, asstMsg])
        let turns = [turn(0, role: "user"), turn(1, role: "assistant")]
        XCTAssertTrue(CacheSavings.detectUnreferencedBlocks(messages, turns, pricing).isEmpty)
    }

    // MARK: H4 — repeated blocks

    func testRepeatedBlockDetected() {
        let big = String(repeating: "same content here ", count: 200) // > 2000 bytes
        let line = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"\#(big)"}]}}"#
        let messages = decode([line, line, line])
        let blocks = CacheSavings.detectRepeatedBlocks(messages, pricing)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].occurrences, 3)
        XCTAssertEqual(blocks[0].firstTurn, 0)
        XCTAssertEqual(blocks[0].lastTurn, 2)
        // Block size walks every object value: content + the "tool_result" type string.
        let eachTokens = (UInt64(big.utf8.count) + UInt64("tool_result".utf8.count)) / 4
        XCTAssertEqual(blocks[0].estimatedTokensEach, eachTokens)
        XCTAssertEqual(blocks[0].totalWastedTokens, eachTokens * 2)
    }

    func testDistinctBlocksNotRepeated() {
        let a = String(repeating: "aaaa content ", count: 200)
        let b = String(repeating: "bbbb content ", count: 200)
        let lineA = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"\#(a)"}]}}"#
        let lineB = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"\#(b)"}]}}"#
        XCTAssertTrue(CacheSavings.detectRepeatedBlocks(decode([lineA, lineB]), pricing).isEmpty)
    }

    // MARK: Report totals

    func testReportTotalsSumAllHeuristics() {
        let turns = [
            turn(0, write: 10_000, read: 0),
            turn(1, write: 50_000, read: 100_000),
            turn(2, write: 0, read: 10_000), // invalidation + turn-1 write partly wasted
        ]
        let report = CacheSavings.analyze(messages: [], turns: turns, pricing: pricing)
        let expected = report.wastedCacheWrites.reduce(0.0) { $0 + $1.wastedCostUsd }
            + report.invalidationEvents.reduce(0.0) { $0 + $1.rewriteCostUsd }
            + report.unreferencedBlocks.reduce(0.0) { $0 + $1.wastedCostUsd }
            + report.repeatedBlocks.reduce(0.0) { $0 + $1.wastedCostUsd }
        XCTAssertEqual(report.totalPotentialSavingsUsd, expected, accuracy: 1e-9)
        XCTAssertFalse(report.invalidationEvents.isEmpty)
    }

    // MARK: token extraction

    func testExtractDistinctiveTokens() {
        let text = "Use `myHelperFunc` from /src/utils/helpers.ts\n## Setup Instructions\nplain words"
        let tokens = Set(CacheSavings.extractDistinctiveTokens(text))
        XCTAssertTrue(tokens.contains("myHelperFunc"))
        XCTAssertTrue(tokens.contains("/src/utils/helpers.ts"))
        XCTAssertTrue(tokens.contains("Setup Instructions"))
    }

    func testCommonTokensFiltered() {
        let tokens = CacheSavings.extractDistinctiveTokens("see `claude` and `README.md` docs")
        XCTAssertFalse(tokens.contains("claude"))
        XCTAssertFalse(tokens.contains("README.md"))
    }
}

private func jsonEscape(_ s: String) -> String {
    let data = try! JSONEncoder().encode(s)
    return String(data: data, encoding: .utf8)!
}
