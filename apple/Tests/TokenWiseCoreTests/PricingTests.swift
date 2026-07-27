import XCTest
@testable import TokenWiseCore

final class PricingTests: XCTestCase {
    let table = PricingTable()

    func testDatedOpusResolvesToOpusRates() {
        // Opus 4.5+ is the $5/$25 tier.
        let r = table.resolve("claude-opus-4-8-20260101")
        XCTAssertFalse(r.usedFallback)
        XCTAssertEqual(r.info.outputPerMTok, 25.0)
        XCTAssertEqual(r.info.inputPerMTok, 5.0)
    }

    func testOpusFiveCurrentTier() {
        let r = table.resolve("claude-opus-5")
        XCTAssertFalse(r.usedFallback)
        XCTAssertEqual(r.info.inputPerMTok, 5.0)
        XCTAssertEqual(r.info.cacheReadPerMTok, 0.50)
    }

    func testLegacyOpusKeepsOldTier() {
        // Opus 4.1 and earlier were $15/$75.
        let r = table.resolve("claude-opus-4-1-20250805")
        XCTAssertFalse(r.usedFallback)
        XCTAssertEqual(r.info.inputPerMTok, 15.0)
        XCTAssertEqual(r.info.outputPerMTok, 75.0)
    }

    func testFableFivePricedAtMythosTierNotFallback() {
        // Regression: an unknown current-gen model must not silently fall back
        // to Sonnet rates. Fable/Mythos 5 is the $10/$50 tier.
        let r = table.resolve("claude-fable-5")
        XCTAssertFalse(r.usedFallback)
        XCTAssertEqual(r.info.inputPerMTok, 10.0)
        XCTAssertEqual(r.info.outputPerMTok, 50.0)
    }

    func testOneHourCacheWritePremium() {
        // 1h ephemeral writes bill at 2× input; 5m at 1.25×.
        let info = PricingInfo(input: 5, cacheWrite: 6.25, cacheRead: 0.50, output: 25)
        let cost = info.cost(input: 0, cacheWrite: 2_000_000, cacheRead: 0, output: 0,
                             eph5m: 1_000_000, eph1h: 1_000_000)
        // 1M @ 6.25 (5m) + 1M @ 10.0 (1h)
        XCTAssertEqual(cost.cacheWriteCost, 16.25, accuracy: 1e-9)
        // Without the split: flat 5m rate.
        let flat = info.cost(input: 0, cacheWrite: 2_000_000, cacheRead: 0, output: 0)
        XCTAssertEqual(flat.cacheWriteCost, 12.5, accuracy: 1e-9)
    }

    func testLongestSubstringWins() {
        // gpt-5-mini must beat gpt-5.
        XCTAssertEqual(table.resolve("gpt-5-mini").info.inputPerMTok, 0.25)
        XCTAssertEqual(table.resolve("gpt-5").info.inputPerMTok, 1.25)
    }

    func testUnknownModelUsesFallbackAndIsFlagged() {
        let r = table.resolve("some-brand-new-model-x9")
        XCTAssertTrue(r.usedFallback)
        XCTAssertEqual(r.info, .fallback)
    }

    func testEmptyModelIsFallback() {
        XCTAssertTrue(table.resolve("").usedFallback)
    }

    func testExplicitOverrideWins() {
        let custom = PricingTable(explicit: ["claude-opus-4-8": PricingInfo(input: 1, cacheWrite: 2, cacheRead: 3, output: 4)])
        let r = custom.resolve("claude-opus-4-8")
        XCTAssertFalse(r.usedFallback)
        XCTAssertEqual(r.info.outputPerMTok, 4)
    }

    func testCostMath() {
        let info = PricingInfo(input: 3, cacheWrite: 3.75, cacheRead: 0.30, output: 15)
        let cost = info.cost(input: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000, output: 1_000_000)
        XCTAssertEqual(cost.inputCost, 3, accuracy: 1e-9)
        XCTAssertEqual(cost.outputCost, 15, accuracy: 1e-9)
        XCTAssertEqual(cost.cacheWriteCost, 3.75, accuracy: 1e-9)
        XCTAssertEqual(cost.cacheReadCost, 0.30, accuracy: 1e-9)
        XCTAssertEqual(cost.totalCost, 22.05, accuracy: 1e-9)
    }
}
