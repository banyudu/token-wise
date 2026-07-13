import Foundation

// Lightweight decode types for the hot summary path — they deliberately omit
// the heavy `content` tree, which dominates parse time across thousands of
// sessions. `content` is decoded (via TitleProbe) only for the first user
// message, to pull a title.
struct LiteInner: Decodable {
    var usage: TokenUsage?
    var role: String?
    var model: String?
}
struct LiteMessage: Decodable {
    var type: String?
    var message: LiteInner?
    var timestamp: String?
    var cwd: String?
    var sessionId: String?
    var gitBranch: String?
}
struct TitleProbe: Decodable {
    struct Inner: Decodable { var content: JSONValue? }
    var message: Inner?
}

public enum ClaudeParser {
    /// Decode one JSONL transcript into messages, skipping unparseable lines.
    static func parseFile(_ url: URL) -> [ClaudeMessage] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        var out: [ClaudeMessage] = []
        out.reserveCapacity(256)
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return }
            if let data = trimmed.data(using: .utf8),
               let msg = try? decoder.decode(ClaudeMessage.self, from: data) {
                out.append(msg)
            }
        }
        return out
    }

    static func summarize(sessionId: String, messages: [ClaudeMessage], pricing: PricingTable,
                          subagentCost: Double, subagentCount: UInt32) -> SessionSummary {
        var totalInput: UInt64 = 0, totalOutput: UInt64 = 0
        var totalCacheWrite: UInt64 = 0, totalCacheRead: UInt64 = 0
        var eph5m: UInt64 = 0, eph1h: UInt64 = 0
        var msgCount: UInt32 = 0
        var firstTs: String?, lastTs: String?
        var project = "", gitBranch: String?, title: String?, model: String?
        var breakdown = CostBreakdown()
        var firstTurnCacheWrite: UInt64 = 0
        var sawFirstUsage = false
        var usedFallback = false

        for msg in messages {
            let inner = msg.message
            let msgModel = inner?.model
            if let usage = inner?.usage {
                let input = usage.input_tokens ?? 0
                let output = usage.output_tokens ?? 0
                let cw = usage.cache_creation_input_tokens ?? 0
                let cr = usage.cache_read_input_tokens ?? 0
                totalInput += input; totalOutput += output
                totalCacheWrite += cw; totalCacheRead += cr
                eph5m += usage.cache_creation?.ephemeral_5m_input_tokens ?? 0
                eph1h += usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
                if !sawFirstUsage { firstTurnCacheWrite = cw; sawFirstUsage = true }
                let resolution = pricing.resolve(msgModel ?? "")
                if resolution.usedFallback { usedFallback = true }
                breakdown.add(resolution.info.cost(input: input, cacheWrite: cw, cacheRead: cr, output: output))
            }
            if let m = msgModel { model = m }
            if msg.type == "user" || msg.type == "assistant" { msgCount += 1 }
            if let ts = msg.timestamp {
                if firstTs == nil { firstTs = ts }
                lastTs = ts
            }
            if project.isEmpty, let cwd = msg.cwd { project = Paths.normalizeProjectPath(cwd) }
            if gitBranch == nil, let b = msg.gitBranch { gitBranch = b }
            if title == nil, msg.type == "user" {
                title = extractTitle(inner?.content)
            }
        }

        let totalContext = totalCacheRead + totalCacheWrite + totalInput
        let hitRate = totalContext > 0 ? Double(totalCacheRead) / Double(totalContext) : 0

        return SessionSummary(
            sessionId: sessionId, project: project, gitBranch: gitBranch, title: title,
            messageCount: msgCount, totalInputTokens: totalInput, totalOutputTokens: totalOutput,
            totalCacheWriteTokens: totalCacheWrite, totalCacheReadTokens: totalCacheRead,
            cacheHitRate: hitRate, estimatedCostUsd: breakdown.totalCost + subagentCost,
            costBreakdown: breakdown, firstTimestamp: firstTs, lastTimestamp: lastTs,
            firstTurnCacheWrite: firstTurnCacheWrite, subagentCount: subagentCount,
            subagentCostUsd: subagentCost, source: "claude", model: model,
            pricedByFallback: usedFallback, ephemeral5mTokens: eph5m, ephemeral1hTokens: eph1h
        )
    }

    private static func extractTitle(_ content: JSONValue?) -> String? {
        guard let content else { return nil }
        let text: String?
        switch content {
        case let .string(s): text = s
        case let .array(arr):
            text = arr.first { $0["type"]?.stringValue == "text" }?["text"]?.stringValue
        default: text = nil
        }
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
              !t.hasPrefix("<"), !t.hasPrefix("/") else { return nil }
        if t.count > 100 { t = String(t.prefix(97)) + "..." }
        return t.replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: Session loading (with count + mtime cache)

    private static let cache = SessionCache()

    public static func loadSessions(pricing: PricingTable, force: Bool = false) -> [SessionSummary] {
        guard let projectsDir = Paths.claudeProjects,
              FileManager.default.fileExists(atPath: projectsDir.path) else { return [] }

        let files = jsonlFiles(under: projectsDir).filter { !$0.path.contains("subagents") }
        let signature = cacheSignature(files)
        if !force, let cached = cache.get(signature: signature) { return cached }

        // Per-file disk cache: only re-parse sessions whose file changed. The
        // first run is cold (~seconds for thousands of files); every run after
        // reuses unchanged summaries, so `token-wise today` is near-instant.
        let disk = force ? [:] : DiskCache.load("claude-sessions")
        var fresh = [DiskCache.Entry?](repeating: nil, count: files.count)
        fresh.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: files.count) { i in
                let url = files[i]
                let stat = fileStat(url)
                if let hit = disk[url.path], hit.mtime == stat.mtime, hit.size == stat.size {
                    buffer[i] = hit
                } else if let summary = parseSessionFile(url, pricing: pricing) {
                    buffer[i] = DiskCache.Entry(mtime: stat.mtime, size: stat.size, summary: summary)
                }
            }
        }

        var byPath: [String: DiskCache.Entry] = [:]
        var sessions: [SessionSummary] = []
        for (i, entry) in fresh.enumerated() {
            guard let entry else { continue }
            byPath[files[i].path] = entry
            sessions.append(entry.summary)
        }
        sessions.sort { ($0.lastTimestamp ?? "") > ($1.lastTimestamp ?? "") }
        DiskCache.save("claude-sessions", byPath)
        cache.set(signature: signature, sessions: sessions)
        return sessions
    }

    private static func fileStat(_ url: URL) -> (mtime: Double, size: UInt64) {
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (v?.contentModificationDate?.timeIntervalSince1970 ?? 0, UInt64(v?.fileSize ?? 0))
    }

    private static func parseSessionFile(_ url: URL, pricing: PricingTable) -> SessionSummary? {
        let sessionId = url.deletingPathExtension().lastPathComponent

        var subagentCost = 0.0
        var subagentCount: UInt32 = 0
        let subDir = url.deletingPathExtension().appendingPathComponent("subagents")
        if let subFiles = try? FileManager.default.contentsOfDirectory(at: subDir, includingPropertiesForKeys: nil) {
            for sub in subFiles where sub.pathExtension == "jsonl" {
                if let s = summarizeStreaming(sessionId: "", url: sub, pricing: pricing, subagentCost: 0, subagentCount: 0) {
                    subagentCost += s.estimatedCostUsd
                    subagentCount += 1
                }
            }
        }

        guard var summary = summarizeStreaming(sessionId: sessionId, url: url, pricing: pricing,
                                               subagentCost: subagentCost, subagentCount: subagentCount)
        else { return nil }
        if summary.project.isEmpty {
            let dir = url.deletingLastPathComponent().lastPathComponent
            summary.project = Paths.normalizeProjectPath(Paths.decodeProjectName(dir))
        }
        return summary
    }

    /// Streaming summary that skips the heavy `content` tree. Returns nil for an
    /// empty/unparseable file (matching the old "no messages" behavior).
    static func summarizeStreaming(sessionId: String, url: URL, pricing: PricingTable,
                                   subagentCost: Double, subagentCount: UInt32) -> SessionSummary? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let decoder = JSONDecoder()
        var totalInput: UInt64 = 0, totalOutput: UInt64 = 0
        var totalCacheWrite: UInt64 = 0, totalCacheRead: UInt64 = 0
        var eph5m: UInt64 = 0, eph1h: UInt64 = 0
        var msgCount: UInt32 = 0
        var firstTs: String?, lastTs: String?
        var project = "", gitBranch: String?, title: String?, model: String?
        var breakdown = CostBreakdown()
        var firstTurnCacheWrite: UInt64 = 0
        var sawFirstUsage = false, usedFallback = false, any = false

        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return }
            guard let data = trimmed.data(using: .utf8),
                  let msg = try? decoder.decode(LiteMessage.self, from: data) else { return }
            any = true
            let inner = msg.message
            if let usage = inner?.usage {
                let input = usage.input_tokens ?? 0, output = usage.output_tokens ?? 0
                let cw = usage.cache_creation_input_tokens ?? 0, cr = usage.cache_read_input_tokens ?? 0
                totalInput += input; totalOutput += output
                totalCacheWrite += cw; totalCacheRead += cr
                eph5m += usage.cache_creation?.ephemeral_5m_input_tokens ?? 0
                eph1h += usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
                if !sawFirstUsage { firstTurnCacheWrite = cw; sawFirstUsage = true }
                let res = pricing.resolve(inner?.model ?? "")
                if res.usedFallback { usedFallback = true }
                breakdown.add(res.info.cost(input: input, cacheWrite: cw, cacheRead: cr, output: output))
            }
            if let m = inner?.model { model = m }
            if msg.type == "user" || msg.type == "assistant" { msgCount += 1 }
            if let ts = msg.timestamp {
                if firstTs == nil { firstTs = ts }
                lastTs = ts
            }
            if project.isEmpty, let cwd = msg.cwd { project = Paths.normalizeProjectPath(cwd) }
            if gitBranch == nil, let b = msg.gitBranch { gitBranch = b }
            if title == nil, msg.type == "user",
               let probe = try? decoder.decode(TitleProbe.self, from: data) {
                title = extractTitle(probe.message?.content)
            }
        }
        if !any { return nil }

        let totalContext = totalCacheRead + totalCacheWrite + totalInput
        let hitRate = totalContext > 0 ? Double(totalCacheRead) / Double(totalContext) : 0
        return SessionSummary(
            sessionId: sessionId, project: project, gitBranch: gitBranch, title: title,
            messageCount: msgCount, totalInputTokens: totalInput, totalOutputTokens: totalOutput,
            totalCacheWriteTokens: totalCacheWrite, totalCacheReadTokens: totalCacheRead,
            cacheHitRate: hitRate, estimatedCostUsd: breakdown.totalCost + subagentCost,
            costBreakdown: breakdown, firstTimestamp: firstTs, lastTimestamp: lastTs,
            firstTurnCacheWrite: firstTurnCacheWrite, subagentCount: subagentCount,
            subagentCostUsd: subagentCost, source: "claude", model: model,
            pricedByFallback: usedFallback, ephemeral5mTokens: eph5m, ephemeral1hTokens: eph1h
        )
    }

    // MARK: Session detail

    public static func sessionDetail(id: String, pricing: PricingTable) -> SessionDetail? {
        guard let projectsDir = Paths.claudeProjects else { return nil }
        guard let file = jsonlFiles(under: projectsDir).first(where: {
            $0.deletingPathExtension().lastPathComponent == id && !$0.path.contains("subagents")
        }) else { return nil }

        let messages = parseFile(file)
        if messages.isEmpty { return nil }

        var turns: [TurnMetrics] = []
        var turnIndex: UInt32 = 0
        var cumulative: UInt64 = 0
        for msg in messages {
            guard let usage = msg.message?.usage else { continue }
            let input = usage.input_tokens ?? 0, output = usage.output_tokens ?? 0
            let cw = usage.cache_creation_input_tokens ?? 0, cr = usage.cache_read_input_tokens ?? 0
            cumulative += input + cw + cr
            let ctx = input + cw + cr
            let hit = ctx > 0 ? Double(cr) / Double(ctx) : 0
            let cost = pricing.info(msg.message?.model ?? "").cost(input: input, cacheWrite: cw, cacheRead: cr, output: output)
            turns.append(TurnMetrics(turnIndex: turnIndex, role: msg.type ?? "", inputTokens: input,
                                     outputTokens: output, cacheWriteTokens: cw, cacheReadTokens: cr,
                                     cumulativeContext: cumulative, cacheHitRate: hit,
                                     costUsd: cost.totalCost, timestamp: msg.timestamp))
            turnIndex += 1
        }

        var subagentCost = 0.0, subagentCount: UInt32 = 0
        let subDir = file.deletingPathExtension().appendingPathComponent("subagents")
        if let subFiles = try? FileManager.default.contentsOfDirectory(at: subDir, includingPropertiesForKeys: nil) {
            for sub in subFiles where sub.pathExtension == "jsonl" {
                let s = summarize(sessionId: "", messages: parseFile(sub), pricing: pricing, subagentCost: 0, subagentCount: 0)
                subagentCost += s.estimatedCostUsd; subagentCount += 1
            }
        }

        var summary = summarize(sessionId: id, messages: messages, pricing: pricing,
                                subagentCost: subagentCost, subagentCount: subagentCount)
        if summary.project.isEmpty {
            let dir = file.deletingLastPathComponent().lastPathComponent
            summary.project = Paths.normalizeProjectPath(Paths.decodeProjectName(dir))
        }
        let analysis = ContentAnalyzer.analyze(messages)
        return SessionDetail(summary: summary, turns: turns, contentAnalysis: analysis)
    }

    // MARK: Helpers

    static func jsonlFiles(under dir: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in en where url.pathExtension == "jsonl" { out.append(url) }
        return out
    }

    private static func cacheSignature(_ files: [URL]) -> String {
        var newest = 0.0
        for f in files {
            if let mod = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                newest = max(newest, mod.timeIntervalSince1970)
            }
        }
        return "\(files.count):\(Int(newest))"
    }
}

/// In-memory cache keyed by file count + newest mtime, so appending turns to a
/// live session invalidates it (the old count-only cache did not).
final class SessionCache {
    private let lock = NSLock()
    private var signature: String?
    private var sessions: [SessionSummary] = []

    func get(signature: String) -> [SessionSummary]? {
        lock.lock(); defer { lock.unlock() }
        return self.signature == signature ? sessions : nil
    }

    func set(signature: String, sessions: [SessionSummary]) {
        lock.lock(); defer { lock.unlock() }
        self.signature = signature
        self.sessions = sessions
    }
}
