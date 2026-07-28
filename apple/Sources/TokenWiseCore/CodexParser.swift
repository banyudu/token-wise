import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct CodexRolloutUsage {
    var inputTokens: UInt64 = 0
    var cachedInputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var messageCount: UInt32 = 0
    var firstTimestamp: String?
    var lastTimestamp: String?
    var model: String?
}

struct CodexRow {
    var id: String
    var cwd: String
    var tokensUsed: UInt64
    var title: String?
    var gitBranch: String?
    var rolloutPath: String?
    var threadModel: String?
    var createdAt: String?
}

public enum CodexParser {
    private static let cache = SessionCache()

    public static func loadSessions(pricing: PricingTable, force: Bool = false) -> [SessionSummary] {
        guard let codexDir = Paths.codexRoot else { return [] }
        let dbPath = codexDir.appendingPathComponent("state_5.sqlite")
        guard FileManager.default.fileExists(atPath: dbPath.path) else { return [] }

        // Cache keyed by the sqlite file's mtime; rollout files are append-only
        // and the DB updates whenever a thread does, so this is a safe signal.
        let sig = (try? dbPath.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { "\(Int($0.timeIntervalSince1970))" } ?? "0"
        if !force, let cached = cache.get(signature: sig) { return cached }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db); return []
        }
        defer { sqlite3_close(db) }

        // Collect all rows first, then parse rollouts in parallel — the rollout
        // JSONL parse is the expensive part and was previously serial.
        let sql = """
        SELECT id, tokens_used, model_provider, title, cwd, created_at, git_branch, rollout_path, model
        FROM threads ORDER BY created_at DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        var rows: [CodexRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let createdUnix = sqlite3_column_int64(stmt, 5)
            rows.append(CodexRow(
                id: text(stmt, 0) ?? "", cwd: text(stmt, 4) ?? "",
                tokensUsed: UInt64(bitPattern: sqlite3_column_int64(stmt, 1)),
                title: text(stmt, 3), gitBranch: text(stmt, 6), rolloutPath: text(stmt, 7),
                threadModel: text(stmt, 8), createdAt: createdUnix > 0 ? iso(fromUnix: createdUnix) : nil))
        }
        sqlite3_finalize(stmt)

        let rates = pricing.fingerprint
        let disk = force ? [:] : DiskCache.load("codex-sessions", pricing: rates)
        var out = [DiskCache.Entry?](repeating: nil, count: rows.count)
        out.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: rows.count) { i in
                let row = rows[i]
                let stat = row.rolloutPath.map(fileStat) ?? (0, row.tokensUsed)
                if let hit = disk[row.id], hit.mtime == stat.0, hit.size == stat.1 {
                    buffer[i] = hit
                    return
                }
                let summary = buildSummary(row: row, pricing: pricing)
                buffer[i] = DiskCache.Entry(mtime: stat.0, size: stat.1, summary: summary)
            }
        }

        var byId: [String: DiskCache.Entry] = [:]
        var sessions: [SessionSummary] = []
        for entry in out {
            guard let entry else { continue }
            byId[entry.summary.sessionId] = entry
            sessions.append(entry.summary)
        }
        DiskCache.save("codex-sessions", pricing: rates, byId)
        cache.set(signature: sig, sessions: sessions)
        return sessions
    }

    private static func buildSummary(row: CodexRow, pricing: PricingTable) -> SessionSummary {
        let rollout = row.rolloutPath.flatMap(parseRollout)
        let inputTokens: UInt64, outputTokens: UInt64, cacheRead: UInt64
        let messageCount: UInt32, firstTs: String?, lastTs: String?, model: String?
        if let r = rollout {
            inputTokens = r.inputTokens >= r.cachedInputTokens ? r.inputTokens - r.cachedInputTokens : 0
            outputTokens = r.outputTokens
            cacheRead = r.cachedInputTokens
            messageCount = r.messageCount
            firstTs = r.firstTimestamp ?? row.createdAt
            lastTs = r.lastTimestamp ?? row.createdAt
            model = r.model ?? row.threadModel
        } else {
            inputTokens = UInt64(Double(row.tokensUsed) * 0.7)
            outputTokens = row.tokensUsed - inputTokens
            cacheRead = 0
            messageCount = 0
            firstTs = row.createdAt; lastTs = row.createdAt
            model = row.threadModel
        }
        let totalContext = cacheRead + inputTokens
        let hitRate = totalContext > 0 ? Double(cacheRead) / Double(totalContext) : 0
        let resolution = pricing.resolve(model ?? "gpt-5")
        let cost = resolution.info.cost(input: inputTokens, cacheWrite: 0, cacheRead: cacheRead, output: outputTokens)
        return SessionSummary(
            sessionId: row.id, project: Paths.normalizeProjectPath(row.cwd), gitBranch: row.gitBranch,
            title: row.title, messageCount: messageCount, totalInputTokens: inputTokens,
            totalOutputTokens: outputTokens, totalCacheWriteTokens: 0, totalCacheReadTokens: cacheRead,
            cacheHitRate: hitRate, estimatedCostUsd: cost.totalCost, costBreakdown: cost,
            firstTimestamp: firstTs, lastTimestamp: lastTs, firstTurnCacheWrite: 0,
            subagentCount: 0, subagentCostUsd: 0, source: "codex", model: model,
            pricedByFallback: resolution.usedFallback, ephemeral5mTokens: 0, ephemeral1hTokens: 0
        )
    }

    private static func fileStat(_ path: String) -> (Double, UInt64) {
        let url = URL(fileURLWithPath: path)
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (v?.contentModificationDate?.timeIntervalSince1970 ?? 0, UInt64(v?.fileSize ?? 0))
    }

    static func parseRollout(_ path: String) -> CodexRolloutUsage? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var usage = CodexRolloutUsage()
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return }
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            if let ts = obj["timestamp"] as? String {
                if usage.firstTimestamp == nil { usage.firstTimestamp = ts }
                usage.lastTimestamp = ts
            }
            let outerType = obj["type"] as? String ?? ""
            let payload = obj["payload"] as? [String: Any]
            if outerType == "session_meta" || outerType == "turn_context" {
                if let m = payload?["model"] as? String, !m.isEmpty { usage.model = m }
            }
            let payloadType = payload?["type"] as? String ?? ""
            if payloadType == "user_message" { usage.messageCount += 1 }
            guard payloadType == "token_count",
                  let info = payload?["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any] else { return }
            if let v = total["input_tokens"] as? UInt64 { usage.inputTokens = v }
            else if let v = total["input_tokens"] as? Int { usage.inputTokens = UInt64(max(0, v)) }
            if let v = total["cached_input_tokens"] as? UInt64 { usage.cachedInputTokens = v }
            else if let v = total["cached_input_tokens"] as? Int { usage.cachedInputTokens = UInt64(max(0, v)) }
            if let v = total["output_tokens"] as? UInt64 { usage.outputTokens = v }
            else if let v = total["output_tokens"] as? Int { usage.outputTokens = UInt64(max(0, v)) }
        }
        return (usage.inputTokens > 0 || usage.outputTokens > 0) ? usage : nil
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: c)
    }

    private static func iso(fromUnix ts: Int64) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
