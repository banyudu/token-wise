import Foundation

// MARK: - Report models (port of the Rust cache_savings.rs output types)

public struct WastedWrite: Codable {
    public var turnIndex: UInt32
    public var wastedTokens: UInt64
    public var wastedCostUsd: Double
    public var reason: String
}

public struct InvalidationEvent: Codable {
    public var turnIndex: UInt32
    public var droppedTokens: UInt64
    public var rewriteCostUsd: Double
    public var suspectedCause: String?
    public var suspectedPreview: String?
}

public struct UnreferencedBlock: Codable {
    public var turnIndex: UInt32
    public var label: String
    public var estimatedTokens: UInt64
    public var carriedTurns: UInt32
    public var wastedCostUsd: Double
    public var preview: String
}

public struct RepeatedBlock: Codable {
    public var occurrences: UInt32
    public var firstTurn: UInt32
    public var lastTurn: UInt32
    public var estimatedTokensEach: UInt64
    public var totalWastedTokens: UInt64
    public var wastedCostUsd: Double
    public var category: String
    public var preview: String
}

public struct CacheSavingsReport: Codable {
    public var wastedCacheWrites: [WastedWrite]
    public var invalidationEvents: [InvalidationEvent]
    public var unreferencedBlocks: [UnreferencedBlock]
    public var repeatedBlocks: [RepeatedBlock]
    public var totalPotentialSavingsUsd: Double
}

// MARK: - Analyzer

/// Per-session cache-waste heuristics, ported from `cache_savings.rs`:
///  H1 wasted cache writes, H2 prefix invalidations, H3 unreferenced
///  context blocks, H4 repeated content blocks.
public enum CacheSavings {
    public static func analyze(messages: [ClaudeMessage], turns: [TurnMetrics],
                               pricing: PricingInfo) -> CacheSavingsReport {
        let wasted = detectWastedWrites(turns, pricing)
        let invalidations = detectInvalidations(turns, messages, pricing)
        let unreferenced = detectUnreferencedBlocks(messages, turns, pricing)
        let repeated = detectRepeatedBlocks(messages, pricing)

        let total = wasted.reduce(0.0) { $0 + $1.wastedCostUsd }
            + invalidations.reduce(0.0) { $0 + $1.rewriteCostUsd }
            + unreferenced.reduce(0.0) { $0 + $1.wastedCostUsd }
            + repeated.reduce(0.0) { $0 + $1.wastedCostUsd }

        return CacheSavingsReport(
            wastedCacheWrites: wasted, invalidationEvents: invalidations,
            unreferencedBlocks: unreferenced, repeatedBlocks: repeated,
            totalPotentialSavingsUsd: total
        )
    }

    // MARK: H1 — turns whose cache write was never read back later

    static func detectWastedWrites(_ turns: [TurnMetrics], _ pricing: PricingInfo) -> [WastedWrite] {
        guard turns.count >= 2 else { return [] }

        // Max future cache_read for each turn index.
        var maxFutureRead = [UInt64](repeating: 0, count: turns.count)
        var runningMax: UInt64 = 0
        for i in stride(from: turns.count - 1, through: 0, by: -1) {
            maxFutureRead[i] = runningMax
            if turns[i].cacheReadTokens > runningMax { runningMax = turns[i].cacheReadTokens }
        }

        var cumWrite: UInt64 = 0
        var results: [WastedWrite] = []

        for (i, turn) in turns.enumerated() {
            let prevCum = cumWrite
            cumWrite += turn.cacheWriteTokens

            // Skip turn 0: first-turn write is unavoidable system prompt boilerplate.
            if i == 0 || turn.cacheWriteTokens == 0 { continue }

            let mfr = maxFutureRead[i]
            // Wasted portion = how much of this turn's write was never included in any later read.
            let wasted: UInt64
            if mfr >= cumWrite { wasted = 0 }
            else if mfr > prevCum { wasted = cumWrite - mfr }
            else { wasted = turn.cacheWriteTokens }

            // Only report substantial waste (>1K tokens).
            if wasted < 1_000 { continue }

            let cost = Double(wasted) / 1_000_000.0 * pricing.cacheWritePerMTok
            let reason: String
            if mfr == 0 {
                reason = "Cache written but never read back before session ended."
            } else {
                let reused = mfr > prevCum ? mfr - prevCum : 0
                reason = "Only \(formatK(reused)) of \(formatK(turn.cacheWriteTokens)) cached tokens were reused later."
            }

            results.append(WastedWrite(turnIndex: turn.turnIndex, wastedTokens: wasted,
                                       wastedCostUsd: cost, reason: reason))
        }

        results.sort { $0.wastedCostUsd > $1.wastedCostUsd }
        return Array(results.prefix(20))
    }

    // MARK: H2 — sudden drops in cache_read indicating prefix invalidation

    static func detectInvalidations(_ turns: [TurnMetrics], _ messages: [ClaudeMessage],
                                    _ pricing: PricingInfo) -> [InvalidationEvent] {
        guard turns.count >= 2 else { return [] }

        let culprits = buildTurnCulpritMap(messages)
        var events: [InvalidationEvent] = []

        for i in 1..<turns.count {
            let prev = turns[i - 1], curr = turns[i]

            // Need meaningful prefix at previous turn.
            if prev.cacheReadTokens < 5_000 { continue }
            // Significant drop: current read is less than 70% of previous read.
            if Double(curr.cacheReadTokens) >= 0.7 * Double(prev.cacheReadTokens) { continue }

            let dropped = prev.cacheReadTokens - curr.cacheReadTokens
            if dropped < 5_000 { continue }

            // Cost: re-writing the dropped prefix at the cache-write rate.
            let cost = Double(dropped) / 1_000_000.0 * pricing.cacheWritePerMTok
            let culprit = culprits[UInt32(i - 1)]

            events.append(InvalidationEvent(turnIndex: curr.turnIndex, droppedTokens: dropped,
                                            rewriteCostUsd: cost,
                                            suspectedCause: culprit?.name,
                                            suspectedPreview: culprit?.preview))
        }

        events.sort { $0.rewriteCostUsd > $1.rewriteCostUsd }
        return Array(events.prefix(20))
    }

    /// For each turn, the largest content block entering context at that turn.
    static func buildTurnCulpritMap(_ messages: [ClaudeMessage]) -> [UInt32: (name: String, preview: String)] {
        var map: [UInt32: (size: UInt64, name: String, preview: String)] = [:]
        var turnIndex: UInt32 = 0

        for msg in messages {
            guard let inner = msg.message else { continue }
            if case let .array(arr)? = inner.content {
                for block in arr {
                    let blockType = block["type"]?.stringValue ?? ""
                    guard blockType == "tool_result" || blockType == "text" else { continue }
                    let size = measureBlockSize(block)
                    if size < 10_000 { continue }
                    let preview = blockPreview(block, 100)
                    if let existing = map[turnIndex], existing.size >= size { continue }
                    map[turnIndex] = (size, blockType, preview)
                }
            }
            if msg.type == "user" || msg.type == "assistant" { turnIndex += 1 }
        }

        return map.mapValues { (name: $0.name, preview: $0.preview) }
    }

    // MARK: H3 — large reminder/CLAUDE.md blocks never referenced downstream

    static func detectUnreferencedBlocks(_ messages: [ClaudeMessage], _ turns: [TurnMetrics],
                                         _ pricing: PricingInfo) -> [UnreferencedBlock] {
        struct Candidate {
            var turnIndex: UInt32
            var label: String
            var text: String
            var byteSize: UInt64
        }

        var candidates: [Candidate] = []
        var turnIndex: UInt32 = 0

        for msg in messages {
            guard let inner = msg.message else { continue }
            let role = inner.role ?? ""
            if role != "user" {
                if msg.type == "user" || msg.type == "assistant" { turnIndex += 1 }
                continue
            }
            if let content = inner.content {
                for text in collectUserTextBlocks(content) {
                    if text.utf8.count < 3_000 { continue }
                    if let label = classifyReminderBlock(text) {
                        candidates.append(Candidate(turnIndex: turnIndex, label: label,
                                                    text: text, byteSize: UInt64(text.utf8.count)))
                    }
                }
            }
            if msg.type == "user" || msg.type == "assistant" { turnIndex += 1 }
        }

        if candidates.isEmpty { return [] }

        let downstreamLower = buildDownstreamCorpus(messages).lowercased()
        var results: [UnreferencedBlock] = []

        for cand in candidates {
            let tokens = extractDistinctiveTokens(cand.text)
            if tokens.isEmpty { continue }
            var hits = 0
            for tok in tokens {
                if downstreamLower.contains(tok.lowercased()) {
                    hits += 1
                    if hits >= 2 { break }
                }
            }
            if hits >= 2 { continue } // referenced — skip

            // Wasted: billed once as cache_write, then cache_read for every
            // later assistant turn while it stays in context.
            let estTokens = cand.byteSize / 4
            let laterAsstTurns = turns.filter { $0.turnIndex >= cand.turnIndex && $0.role == "assistant" }.count
            let carried = UInt32(max(laterAsstTurns, 1))
            let readCost = Double(estTokens) / 1_000_000.0 * pricing.cacheReadPerMTok * Double(carried)
            let writeCost = Double(estTokens) / 1_000_000.0 * pricing.cacheWritePerMTok

            let preview = String(cand.text.prefix(120)).replacingOccurrences(of: "\n", with: " ")

            results.append(UnreferencedBlock(turnIndex: cand.turnIndex, label: cand.label,
                                             estimatedTokens: estTokens, carriedTurns: carried,
                                             wastedCostUsd: readCost + writeCost, preview: preview))
        }

        results.sort { $0.wastedCostUsd > $1.wastedCostUsd }
        return Array(results.prefix(20))
    }

    // MARK: H4 — content blocks appearing in multiple turns

    static func detectRepeatedBlocks(_ messages: [ClaudeMessage], _ pricing: PricingInfo) -> [RepeatedBlock] {
        struct Occ {
            var count: UInt32 = 0
            var firstTurn: UInt32
            var lastTurn: UInt32
            var size: UInt64
            var preview: String
            var category: String
        }

        var map: [UInt64: Occ] = [:]
        var turnIndex: UInt32 = 0

        for msg in messages {
            guard let inner = msg.message else { continue }
            if case let .array(arr)? = inner.content {
                for block in arr {
                    let blockType = block["type"]?.stringValue ?? ""
                    // Only count content blocks that can be re-sent.
                    guard blockType == "tool_result" || blockType == "text" else { continue }
                    let size = measureBlockSize(block)
                    if size < 2_000 { continue }
                    let preview = blockPreview(block, 100)
                    let hash = fnv1a(preview) ^ fnv1a(leBytes(size))
                    var occ = map[hash] ?? Occ(firstTurn: turnIndex, lastTurn: turnIndex,
                                               size: size, preview: preview, category: blockType)
                    occ.count += 1
                    occ.lastTurn = turnIndex
                    map[hash] = occ
                }
            }
            if msg.type == "user" || msg.type == "assistant" { turnIndex += 1 }
        }

        var results: [RepeatedBlock] = map.values.filter { $0.count >= 2 }.map { o in
            let eachTokens = o.size / 4
            let wastedTokens = eachTokens * UInt64(o.count - 1)
            let cost = Double(wastedTokens) / 1_000_000.0 * pricing.cacheReadPerMTok
            return RepeatedBlock(occurrences: o.count, firstTurn: o.firstTurn, lastTurn: o.lastTurn,
                                 estimatedTokensEach: eachTokens, totalWastedTokens: wastedTokens,
                                 wastedCostUsd: cost, category: o.category, preview: o.preview)
        }
        results.sort { $0.wastedCostUsd > $1.wastedCostUsd }
        return Array(results.prefix(10))
    }

    // MARK: Helpers

    /// Byte size mirroring the Rust `measure_block_size` (bool/null count 0).
    static func measureBlockSize(_ value: JSONValue) -> UInt64 {
        switch value {
        case let .string(s): return UInt64(s.utf8.count)
        case let .array(a): return a.reduce(0) { $0 + measureBlockSize($1) }
        case let .object(o): return o.values.reduce(0) { $0 + measureBlockSize($1) }
        case let .number(n): return UInt64(String(n).utf8.count)
        case .bool, .null: return 0
        }
    }

    static func blockPreview(_ block: JSONValue, _ maxLen: Int) -> String {
        let text: String
        if let s = block["text"]?.stringValue { text = s }
        else if let s = block["content"]?.stringValue { text = s }
        else { text = jsonString(block) }
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLen))
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }

    static func collectUserTextBlocks(_ content: JSONValue) -> [String] {
        switch content {
        case let .string(s): return [s]
        case let .array(arr):
            return arr.compactMap { block in
                let t = block["type"]?.stringValue ?? ""
                if t == "text" { return block["text"]?.stringValue }
                if t == "tool_result" { return block["content"]?.stringValue }
                return nil
            }
        default: return []
        }
    }

    static func classifyReminderBlock(_ text: String) -> String? {
        if text.contains("# claudeMd") || text.contains("CLAUDE.md") || text.contains("claude.md") {
            return "CLAUDE.md"
        }
        if text.contains("<system-reminder>") {
            if text.contains("skill") || text.contains("Skill") { return "Skills reminder" }
            if text.contains("task") || text.contains("Task") { return "Task reminder" }
            return "System reminder"
        }
        if text.contains("Available skills") || text.contains("available skills") {
            return "Skills listing"
        }
        return nil
    }

    static func buildDownstreamCorpus(_ messages: [ClaudeMessage]) -> String {
        var out = ""
        for msg in messages {
            guard let inner = msg.message, inner.role == "assistant",
                  case let .array(arr)? = inner.content else { continue }
            for block in arr {
                switch block["type"]?.stringValue ?? "" {
                case "text", "thinking":
                    if let s = block["text"]?.stringValue { out += s; out += "\n" }
                    if let s = block["thinking"]?.stringValue { out += s; out += "\n" }
                case "tool_use":
                    if let input = block["input"] { out += jsonString(input); out += "\n" }
                default: break
                }
            }
        }
        return out
    }

    /// Pull distinctive identifiers (backticked strings, headings, paths).
    static func extractDistinctiveTokens(_ text: String) -> [String] {
        var tokens = Set<String>()

        // Backticked identifiers: `foo.bar` or `MyClass`
        var buf = ""
        var inTick = false
        for c in text {
            if c == "`" {
                if inTick {
                    if buf.count >= 4 && buf.count <= 60 { tokens.insert(buf) }
                    buf = ""
                    inTick = false
                } else {
                    inTick = true
                }
            } else if inTick {
                buf.append(c)
            }
        }

        // Headings (lines starting with #)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            guard trimmed.hasPrefix("#") else { continue }
            let heading = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            if heading.count >= 4 && heading.count <= 80 { tokens.insert(heading) }
        }

        // File-path-looking tokens: /foo/bar.ext or ./foo
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;\""))
        for word in text.components(separatedBy: separators) {
            let w = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,()"))
            let pathy = w.contains("/") || w.hasSuffix(".md") || w.hasSuffix(".rs")
                || w.hasSuffix(".ts") || w.hasSuffix(".tsx")
            if pathy && w.count >= 6 && w.count <= 120 { tokens.insert(w) }
        }

        return Array(tokens.lazy
            .filter { $0.count >= 5 }
            .filter { !isTooCommon($0) }
            .prefix(50))
    }

    static func isTooCommon(_ s: String) -> Bool {
        ["claude", "user", "system", "claude.md", "readme", "readme.md", "todo", "note"]
            .contains(s.lowercased())
    }

    static func fnv1a(_ s: String) -> UInt64 {
        fnv1a(Array(s.utf8))
    }

    static func fnv1a(_ bytes: [UInt8]) -> UInt64 {
        var h: UInt64 = 1_469_598_103_934_665_603
        for b in bytes {
            h ^= UInt64(b)
            h = h &* 1_099_511_628_211
        }
        return h
    }

    static func leBytes(_ n: UInt64) -> [UInt8] {
        withUnsafeBytes(of: n.littleEndian, Array.init)
    }

    static func formatK(_ n: UInt64) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(n)
    }

    private static func jsonString(_ value: JSONValue) -> String {
        func toAny(_ v: JSONValue) -> Any {
            switch v {
            case let .string(s): return s
            case let .number(n): return n
            case let .bool(b): return b
            case .null: return NSNull()
            case let .array(a): return a.map(toAny)
            case let .object(o): return o.mapValues(toAny)
            }
        }
        let any = toAny(value)
        guard JSONSerialization.isValidJSONObject(any),
              let data = try? JSONSerialization.data(withJSONObject: any),
              let str = String(data: data, encoding: .utf8) else {
            if case let .string(s) = value { return s }
            return ""
        }
        return str
    }
}
