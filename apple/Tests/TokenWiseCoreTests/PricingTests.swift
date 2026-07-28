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

    func testGLMPricedAtZaiRatesNotSonnetFallback() {
        // GLM runs through Claude Code, so these sessions used to land on the
        // Sonnet-class fallback and read ~2× their real cost.
        let r = table.resolve("glm-5.2")
        XCTAssertFalse(r.usedFallback)
        XCTAssertEqual(r.info.inputPerMTok, 1.40)
        XCTAssertEqual(r.info.cacheReadPerMTok, 0.26)
        XCTAssertEqual(r.info.outputPerMTok, 4.40)
        XCTAssertEqual(r.info.cacheWritePerMTok, 0.0)

        let older = table.resolve("glm-4.7")
        XCTAssertFalse(older.usedFallback)
        XCTAssertEqual(older.info.inputPerMTok, 0.60)
        XCTAssertEqual(older.info.outputPerMTok, 2.20)
    }

    func testGLMFlashIsFree() {
        // The Flash tiers are free, and must beat the `glm-4.7` prefix.
        let r = table.resolve("glm-4.7-flash")
        XCTAssertFalse(r.usedFallback)
        XCTAssertEqual(r.info.outputPerMTok, 0.0)
        XCTAssertEqual(table.resolve("glm-4.5-air").info.inputPerMTok, 0.20)
    }

    func testCodexSparkResolvesToCodexTier() {
        // gpt-5.3-codex-spark must not settle for the plain gpt-5 rate.
        let r = table.resolve("gpt-5.3-codex-spark")
        XCTAssertFalse(r.usedFallback)
        XCTAssertEqual(r.info.inputPerMTok, 1.75)
        XCTAssertEqual(r.info.outputPerMTok, 14.0)
    }

    func testCurrentGPTTiersAreNotAllGPT5Rates() {
        // Regression: 5.2/5.4/5.5 each moved off the $1.25/$10 gpt-5 tier, and
        // the substring table silently priced them there.
        XCTAssertEqual(table.resolve("gpt-5.5").info.inputPerMTok, 5.0)
        XCTAssertEqual(table.resolve("gpt-5.5").info.outputPerMTok, 30.0)
        XCTAssertEqual(table.resolve("gpt-5.4").info.inputPerMTok, 2.50)
        XCTAssertEqual(table.resolve("gpt-5.2").info.outputPerMTok, 14.0)
        XCTAssertEqual(table.resolve("gpt-5").info.inputPerMTok, 1.25)
    }

    func testGPT56VariantsPriceSeparately() {
        // Luna is 10× cheaper than Sol — the shared `gpt-5.6` prefix must not
        // flatten them together.
        XCTAssertEqual(table.resolve("gpt-5.6-luna").info.inputPerMTok, 0.50)
        XCTAssertEqual(table.resolve("gpt-5.6-luna").info.outputPerMTok, 3.0)
        XCTAssertEqual(table.resolve("gpt-5.6-terra").info.outputPerMTok, 7.50)
        XCTAssertEqual(table.resolve("gpt-5.6-sol").info.inputPerMTok, 5.0)
    }

    func testSonnetFiveIsCheaperThanTheLegacySonnetTier() {
        let r = table.resolve("claude-sonnet-5")
        XCTAssertFalse(r.usedFallback)
        XCTAssertEqual(r.info.inputPerMTok, 2.0)
        XCTAssertEqual(r.info.cacheWritePerMTok, 2.50)
        XCTAssertEqual(r.info.cacheReadPerMTok, 0.20)
        XCTAssertEqual(r.info.outputPerMTok, 10.0)
        // Sonnet 4.6 and earlier stay at $3/$15.
        XCTAssertEqual(table.resolve("claude-sonnet-4-6").info.inputPerMTok, 3.0)
    }

    func testGeneratedTableCoversOtherVendors() {
        // Models the generated OpenRouter table brings in — none of these have
        // a curated entry.
        for model in ["gemini-3.1-pro-preview", "deepseek-chat", "minimax-m2.5",
                      "kimi-k2-thinking", "grok-4.5", "qwen3-max"] {
            let r = table.resolve(model)
            XCTAssertFalse(r.usedFallback, "\(model) should be priced")
            XCTAssertGreaterThan(r.info.outputPerMTok, 0, "\(model) needs an output rate")
        }
    }

    func testCuratedOverridesGeneratedAtEqualSpecificity() {
        // GLM is billed through z.ai directly, not an OpenRouter reseller, so
        // the curated z.ai list rate must win over the generated row.
        XCTAssertEqual(table.resolve("glm-5.2").info.inputPerMTok, 1.40)
        // A strictly more specific generated pattern still wins over a short
        // curated catch-all: `claude-opus` alone is the legacy $15/$75 tier.
        XCTAssertEqual(table.resolve("claude-opus-4-5").info.inputPerMTok, 5.0)
        XCTAssertEqual(table.resolve("claude-opus-4-1-20250805").info.inputPerMTok, 15.0)
    }

    func testFingerprintTracksBothTables() {
        // The disk cache keys on this; a stable digest across a rate change
        // would leave stale costs on screen.
        XCTAssertFalse(PricingTable().fingerprint.isEmpty)
        let overridden = PricingTable(explicit: ["glm-5.2": PricingInfo(input: 9, cacheWrite: 9, cacheRead: 9, output: 9)])
        XCTAssertNotEqual(PricingTable().fingerprint, overridden.fingerprint)
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
