import Foundation
import TokenWiseCore

// Minimal hand-rolled arg parsing — keeps the package dependency-free so it
// builds offline.

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("""
    token-wise — AI token usage stats

    Usage:
      token-wise total [--json]
      token-wise today [--json]
      token-wise sessions [--limit N] [--json]
      token-wise savings SESSION_ID [--json]
      token-wise analyze [--engine claude|codex] [--model NAME] [--json]
    """)
    exit(0)
}
let rest = Array(args.dropFirst())
func flag(_ name: String) -> Bool { rest.contains(name) }
func value(_ name: String) -> String? {
    guard let i = rest.firstIndex(of: name), i + 1 < rest.count else { return nil }
    return rest[i + 1]
}

let pricing = PricingTable.load()
let sessions = TokenWise.loadAllSessions(pricing: pricing)

func iso8601ToLocalDay(_ ts: String?) -> String? {
    guard let date = Format.parseDate(ts) else { return nil }
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    fmt.timeZone = .current
    return fmt.string(from: date)
}

switch command {
case "total":
    let total = sessions.reduce(0.0) { $0 + $1.estimatedCostUsd }
    if flag("--json") {
        printJSON(["total_cost_usd": total, "session_count": sessions.count])
    } else {
        print("Total: \(Format.cost(total)) (\(sessions.count) sessions)")
    }

case "today":
    let today = Format.localDay(of: Date())
    // Per-day attribution: only spend whose responses actually landed today.
    // Sessions without the map (Codex) fall back to last-activity attribution.
    var total = 0.0
    var bySource: [String: Double] = [:]
    var todays: [SessionSummary] = []
    for s in sessions {
        if let daily = s.dailyCostUsd {
            if let cost = daily[today], cost > 0 {
                total += cost; bySource[s.source, default: 0] += cost; todays.append(s)
            }
        } else if iso8601ToLocalDay(s.lastTimestamp) == today {
            total += s.estimatedCostUsd
            bySource[s.source, default: 0] += s.estimatedCostUsd
            todays.append(s)
        }
    }
    let read = todays.reduce(UInt64(0)) { $0 + $1.totalCacheReadTokens }
    let ctx = todays.reduce(UInt64(0)) { $0 + $1.totalInputTokens + $1.totalCacheReadTokens + $1.totalCacheWriteTokens }
    let hit = ctx > 0 ? Double(read) / Double(ctx) : 0
    if flag("--json") {
        printJSON(["date": today, "total_cost_usd": total, "session_count": todays.count,
                   "cache_hit_rate": hit, "by_source": bySource])
    } else {
        print("Today:  \(Format.cost(total)) (\(todays.count) sessions)")
        for (source, cost) in bySource.sorted(by: { $0.value > $1.value }) {
            print("        \(source): \(Format.cost(cost))")
        }
        if !todays.isEmpty { print("        Cache hit rate: \(Format.percent(hit))") }
    }

case "sessions":
    let limit = value("--limit").flatMap(Int.init) ?? 10
    let top = sessions.sorted { $0.estimatedCostUsd > $1.estimatedCostUsd }.prefix(limit)
    if flag("--json") {
        printJSON(top.map { [
            "session_id": $0.sessionId, "project": $0.project, "cost_usd": $0.estimatedCostUsd,
            "cache_hit_rate": $0.cacheHitRate, "source": $0.source,
        ] })
    } else {
        print("PROJECT".padding(toLength: 28, withPad: " ", startingAt: 0)
              + "COST".leftPad(10) + " " + "TOKENS".leftPad(8) + " " + "CACHE".leftPad(7))
        for s in top {
            let tokens = s.totalInputTokens + s.totalOutputTokens + s.totalCacheReadTokens + s.totalCacheWriteTokens
            let proj = String(Format.path(s.project).prefix(28))
            print(proj.padding(toLength: 28, withPad: " ", startingAt: 0)
                  + Format.cost(s.estimatedCostUsd).leftPad(10) + " "
                  + Format.tokens(tokens).leftPad(8) + " "
                  + Format.percent(s.cacheHitRate).leftPad(7))
        }
    }

case "savings":
    guard let sessionId = rest.first(where: { !$0.hasPrefix("--") }) else {
        fail("Usage: token-wise savings SESSION_ID [--json]")
    }
    guard let detail = ClaudeParser.sessionDetail(id: sessionId, pricing: pricing),
          let report = detail.cacheSavings else {
        fail("Session not found (savings analysis is Claude-only): \(sessionId)")
    }
    if flag("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    } else {
        print("Potential savings: \(Format.cost(report.totalPotentialSavingsUsd)) (heuristic)")
        if !report.wastedCacheWrites.isEmpty {
            print("\nWasted cache writes (\(report.wastedCacheWrites.count)):")
            for w in report.wastedCacheWrites.prefix(10) {
                print("  turn \(w.turnIndex + 1): \(Format.tokens(w.wastedTokens)) wasted (\(Format.cost(w.wastedCostUsd))) — \(w.reason)")
            }
        }
        if !report.invalidationEvents.isEmpty {
            print("\nCache prefix invalidations (\(report.invalidationEvents.count)):")
            for e in report.invalidationEvents.prefix(10) {
                let cause = e.suspectedCause.map { " — suspected: \($0)" } ?? ""
                print("  turn \(e.turnIndex + 1): \(Format.tokens(e.droppedTokens)) dropped (\(Format.cost(e.rewriteCostUsd)))\(cause)")
            }
        }
        if !report.unreferencedBlocks.isEmpty {
            print("\nUnreferenced context blocks (\(report.unreferencedBlocks.count)):")
            for b in report.unreferencedBlocks.prefix(10) {
                print("  turn \(b.turnIndex + 1): \(b.label), \(Format.tokens(b.estimatedTokens)) carried \(b.carriedTurns) turns (\(Format.cost(b.wastedCostUsd)))")
            }
        }
        if !report.repeatedBlocks.isEmpty {
            print("\nRepeated content blocks (\(report.repeatedBlocks.count)):")
            for b in report.repeatedBlocks.prefix(10) {
                print("  \(b.occurrences)x turns \(b.firstTurn + 1)–\(b.lastTurn + 1): \(Format.tokens(b.estimatedTokensEach)) each (\(Format.cost(b.wastedCostUsd)))")
            }
        }
    }

case "analyze":
    let overview = TokenWise.buildOverview(sessions)
    let engine = value("--engine").flatMap { AIEngine(rawValue: $0) }
    let engines = AIAnalyzer.availableEngines()
    if engines.isEmpty { fail("No `claude` or `codex` CLI found. Install one to use analyze.") }
    if !flag("--json") {
        FileHandle.standardError.write(Data("Analyzing with \(engine?.rawValue ?? engines.first!.rawValue) (this can take a minute)…\n".utf8))
    }
    do {
        let result = try AIAnalyzer.analyze(overview: overview, sessions: sessions,
                                            engine: engine, model: value("--model"))
        if flag("--json") {
            printJSON(["engine": result.engine.rawValue, "report": result.report])
        } else {
            print(result.report)
        }
    } catch {
        fail("\(error)")
    }

default:
    fail("Unknown command: \(command)")
}

// MARK: helpers

func printJSON(_ value: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
       let s = String(data: data, encoding: .utf8) {
        print(s)
    }
}

extension String {
    func leftPad(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
