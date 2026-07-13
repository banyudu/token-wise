import Foundation

/// Per-million-token USD rates for one model.
public struct PricingInfo: Equatable {
    public var inputPerMTok: Double
    public var cacheWritePerMTok: Double
    public var cacheReadPerMTok: Double
    public var outputPerMTok: Double

    public init(input: Double, cacheWrite: Double, cacheRead: Double, output: Double) {
        self.inputPerMTok = input
        self.cacheWritePerMTok = cacheWrite
        self.cacheReadPerMTok = cacheRead
        self.outputPerMTok = output
    }

    /// Sonnet-class rates — used when a model name is unrecognized.
    public static let fallback = PricingInfo(input: 3.0, cacheWrite: 3.75, cacheRead: 0.30, output: 15.0)

    public func cost(input: UInt64, cacheWrite: UInt64, cacheRead: UInt64, output: UInt64) -> CostBreakdown {
        let inputCost = Double(input) / 1_000_000.0 * inputPerMTok
        let cacheWriteCost = Double(cacheWrite) / 1_000_000.0 * cacheWritePerMTok
        let cacheReadCost = Double(cacheRead) / 1_000_000.0 * cacheReadPerMTok
        let outputCost = Double(output) / 1_000_000.0 * outputPerMTok
        return CostBreakdown(
            inputCost: inputCost,
            outputCost: outputCost,
            cacheWriteCost: cacheWriteCost,
            cacheReadCost: cacheReadCost,
            totalCost: inputCost + cacheWriteCost + cacheReadCost + outputCost
        )
    }
}

/// The outcome of resolving a model name to pricing.
public struct PricingResolution {
    public let info: PricingInfo
    /// True when no explicit or built-in entry matched and the Sonnet-class
    /// fallback was used — the caller can flag the session so a wrong estimate
    /// is never silent.
    public let usedFallback: Bool
}

/// Resolves any model name to pricing. Explicit overrides from
/// `~/.claude/readout-pricing.json` win, then built-in family defaults matched
/// by longest substring, then the Sonnet-class fallback.
public final class PricingTable {
    private let explicit: [String: PricingInfo]

    public init(explicit: [String: PricingInfo] = [:]) {
        self.explicit = explicit
    }

    public func resolve(_ model: String) -> PricingResolution {
        if model.isEmpty {
            return PricingResolution(info: .fallback, usedFallback: true)
        }
        if let p = explicit[model] {
            return PricingResolution(info: p, usedFallback: false)
        }
        if let p = Self.builtin(model) {
            return PricingResolution(info: p, usedFallback: false)
        }
        return PricingResolution(info: .fallback, usedFallback: true)
    }

    public func info(_ model: String) -> PricingInfo { resolve(model).info }

    // MARK: Built-in table

    // (pattern, input, cacheWrite, cacheRead, output). Matched by substring,
    // longest pattern wins, so `gpt-5-mini` beats `gpt-5` and dated suffixes
    // like `claude-sonnet-4-5-20250929` still resolve.
    private static let table: [(String, Double, Double, Double, Double)] = [
        // Anthropic Claude — current + recent generations
        ("claude-opus-4-8", 15.0, 18.75, 1.50, 75.0),
        ("claude-opus-4-7", 15.0, 18.75, 1.50, 75.0),
        ("claude-opus-4-6", 15.0, 18.75, 1.50, 75.0),
        ("claude-opus-4-5", 15.0, 18.75, 1.50, 75.0),
        ("claude-opus", 15.0, 18.75, 1.50, 75.0),
        ("opus-4-8", 15.0, 18.75, 1.50, 75.0),
        ("opus-4-7", 15.0, 18.75, 1.50, 75.0),
        ("opus-4-6", 15.0, 18.75, 1.50, 75.0),
        ("opus-4-5", 15.0, 18.75, 1.50, 75.0),
        // Mythos-class (Fable 5 / Mythos 5) — priced at Opus tier
        ("claude-fable-5", 15.0, 18.75, 1.50, 75.0),
        ("claude-mythos-5", 15.0, 18.75, 1.50, 75.0),
        ("fable-5", 15.0, 18.75, 1.50, 75.0),
        ("mythos-5", 15.0, 18.75, 1.50, 75.0),
        ("claude-sonnet-5", 3.0, 3.75, 0.30, 15.0),
        ("claude-sonnet-4-6", 3.0, 3.75, 0.30, 15.0),
        ("claude-sonnet-4-5", 3.0, 3.75, 0.30, 15.0),
        ("claude-sonnet", 3.0, 3.75, 0.30, 15.0),
        ("sonnet-5", 3.0, 3.75, 0.30, 15.0),
        ("sonnet-4-6", 3.0, 3.75, 0.30, 15.0),
        ("sonnet-4-5", 3.0, 3.75, 0.30, 15.0),
        ("claude-haiku-4-5", 1.0, 1.25, 0.10, 5.0),
        ("claude-haiku", 1.0, 1.25, 0.10, 5.0),
        ("haiku-4-5", 1.0, 1.25, 0.10, 5.0),
        // OpenAI / Codex (cacheWrite=0 — OpenAI bills cached_input directly)
        ("gpt-5-nano", 0.05, 0.0, 0.005, 0.40),
        ("gpt-5-mini", 0.25, 0.0, 0.025, 2.0),
        ("gpt-5.6", 1.25, 0.0, 0.125, 10.0),
        ("gpt-5.5", 1.25, 0.0, 0.125, 10.0),
        ("gpt-5.4", 1.25, 0.0, 0.125, 10.0),
        ("gpt-5.2", 1.25, 0.0, 0.125, 10.0),
        ("gpt-5", 1.25, 0.0, 0.125, 10.0),
        ("gpt-4.1-mini", 0.40, 0.0, 0.10, 1.60),
        ("gpt-4.1-nano", 0.10, 0.0, 0.025, 0.40),
        ("gpt-4.1", 2.0, 0.0, 0.50, 8.0),
        ("gpt-4o-mini", 0.15, 0.0, 0.075, 0.60),
        ("gpt-4o", 2.50, 0.0, 1.25, 10.0),
        ("o1-mini", 1.10, 0.0, 0.55, 4.40),
        ("o1", 15.0, 0.0, 7.50, 60.0),
        ("o3-mini", 1.10, 0.0, 0.55, 4.40),
        ("o3", 2.0, 0.0, 0.50, 8.0),
    ]

    static func builtin(_ model: String) -> PricingInfo? {
        let lower = model.lowercased()
        var best: (String, Double, Double, Double, Double)?
        for entry in table where lower.contains(entry.0) {
            if let b = best, b.0.count >= entry.0.count { continue }
            best = entry
        }
        return best.map { PricingInfo(input: $0.1, cacheWrite: $0.2, cacheRead: $0.3, output: $0.4) }
    }

    // MARK: Loading overrides

    /// Loads explicit rates from `~/.claude/readout-pricing.json` if present,
    /// accepting either a top-level map of models or a `{ "models": { ... } }`
    /// wrapper, with `input`/`inputPerMillion`-style keys.
    public static func load() -> PricingTable {
        guard let root = Paths.claudeRoot else { return PricingTable() }
        let path = root.appendingPathComponent("readout-pricing.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return PricingTable() }

        var explicit: [String: PricingInfo] = [:]
        let roots: [[String: Any]] = [json["models"] as? [String: Any], json].compactMap { $0 }
        for obj in roots {
            for (name, value) in obj {
                guard let entry = value as? [String: Any] else { continue }
                func num(_ keys: [String]) -> Double? {
                    for k in keys { if let n = entry[k] as? Double { return n }
                        if let i = entry[k] as? Int { return Double(i) } }
                    return nil
                }
                let input = num(["input", "inputPerMillion"])
                let output = num(["output", "outputPerMillion"])
                let cacheWrite = num(["cacheWrite", "cacheWritePerMillion"])
                let cacheRead = num(["cacheRead", "cacheReadPerMillion"])
                if input == nil && output == nil { continue }
                explicit[name] = PricingInfo(
                    input: input ?? 3.0,
                    cacheWrite: cacheWrite ?? 3.75,
                    cacheRead: cacheRead ?? 0.30,
                    output: output ?? 15.0
                )
            }
        }
        return PricingTable(explicit: explicit)
    }
}
