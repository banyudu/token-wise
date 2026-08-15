import Foundation
import SQLite3

private struct OpencodeUsage {
    var input: UInt64 = 0
    var output: UInt64 = 0
    var cacheRead: UInt64 = 0
    var cacheWrite: UInt64 = 0
    var cost: Double = 0
    var timestamp: String?
}

private let OPENCODE_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Reads OpenCode's local SQLite history. Newer OpenCode versions maintain
/// token totals on `session`; older layouts are reconstructed from assistant
/// message JSON, which carries the same per-response token data.
public enum OpencodeParser {
    public static func loadSessions(pricing: PricingTable, force: Bool = false) -> [SessionSummary] {
        guard let root = Paths.opencodeRoot else { return [] }
        return loadSessions(at: root.appendingPathComponent("opencode.db"), pricing: pricing)
    }

    static func loadSessions(at databaseURL: URL, pricing: PricingTable) -> [SessionSummary] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        let columns = tableColumns(db, table: "session")
        guard columns.contains("id"), columns.contains("directory") else { return [] }
        let tokenColumns = ["tokens_input", "tokens_output", "tokens_cache_read", "tokens_cache_write"]
        let tokenSelect = tokenColumns.map { columns.contains($0) ? "COALESCE(s.\($0), 0)" : "0" }
            .joined(separator: ", ")
        let costSelect = columns.contains("cost") ? "COALESCE(s.cost, 0)" : "0"
        let modelSelect = columns.contains("model") ? "s.model" : "NULL"
        let createdSelect = columns.contains("time_created") ? "s.time_created" : "0"
        let updatedSelect = columns.contains("time_updated") ? "s.time_updated" : createdSelect
        let titleSelect = columns.contains("title") ? "s.title" : "NULL"
        let sql = """
        SELECT s.id, s.directory, \(titleSelect), \(modelSelect), \(createdSelect), \(updatedSelect),
               \(tokenSelect), \(costSelect),
               (SELECT COUNT(*) FROM message m WHERE m.session_id = s.id
                 AND json_extract(m.data, '$.role') = 'user')
        FROM session s
        WHERE \(columns.contains("time_archived") ? "s.time_archived IS NULL" : "1")
        ORDER BY \(updatedSelect) DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var sessions: [SessionSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = string(stmt, 0) ?? ""
            guard !id.isEmpty else { continue }
            var usages = messageUsage(db, sessionID: id)
            if usages.isEmpty { usages = partUsage(db, sessionID: id) }
            let stored = OpencodeUsage(input: uint(stmt, 6), output: uint(stmt, 7),
                                       cacheRead: uint(stmt, 8), cacheWrite: uint(stmt, 9), cost: double(stmt, 10))
            let totals = stored.input + stored.output + stored.cacheRead + stored.cacheWrite > 0
                ? stored : sum(usages)
            let model = modelID(string(stmt, 3)) ?? usagesModel(db, sessionID: id)
            let fallback = pricing.resolve(model ?? "").usedFallback
            let priced = pricing.info(model ?? "").cost(input: totals.input, cacheWrite: totals.cacheWrite,
                                                           cacheRead: totals.cacheRead, output: totals.output)
            let actualCost = stored.cost > 0 ? stored.cost : (totals.cost > 0 ? totals.cost : priced.totalCost)
            let breakdown = scaled(priced, to: actualCost)
            let first = iso(uint64(stmt, 4))
            let last = iso(uint64(stmt, 5))
            let daily = dailyUsage(usages, pricing: pricing, model: model, totalCost: actualCost)
            let context = totals.input + totals.cacheRead + totals.cacheWrite
            sessions.append(SessionSummary(
                sessionId: id, project: Paths.normalizeProjectPath(string(stmt, 1) ?? ""), gitBranch: nil,
                title: string(stmt, 2), messageCount: UInt32(clamping: Int64(sqlite3_column_int64(stmt, 11))),
                totalInputTokens: totals.input, totalOutputTokens: totals.output,
                totalCacheWriteTokens: totals.cacheWrite, totalCacheReadTokens: totals.cacheRead,
                cacheHitRate: context > 0 ? Double(totals.cacheRead) / Double(context) : 0,
                estimatedCostUsd: actualCost, costBreakdown: breakdown, firstTimestamp: first,
                lastTimestamp: last, firstTurnCacheWrite: 0, subagentCount: 0, subagentCostUsd: 0,
                source: "opencode", model: model, pricedByFallback: fallback,
                ephemeral5mTokens: 0, ephemeral1hTokens: 0,
                dailyCostUsd: daily.cost, dailyTokens: daily.tokens
            ))
        }
        return sessions
    }

    private static func messageUsage(_ db: OpaquePointer?, sessionID: String) -> [OpencodeUsage] {
        usage(db, sessionID: sessionID, table: "message", predicate: "json_extract(data, '$.role') = 'assistant'")
    }

    private static func usagesModel(_ db: OpaquePointer?, sessionID: String) -> String? {
        let sql = "SELECT data FROM message WHERE session_id = ? AND json_extract(data, '$.role') = 'assistant' ORDER BY time_created DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sessionID, -1, OPENCODE_SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW ? modelID(string(stmt, 0)) : nil
    }

    /// Step-finish parts mirror assistant usage in some older storage layouts.
    /// They are used only when message rows have no usable token payload, so
    /// current databases never double-count a response.
    private static func partUsage(_ db: OpaquePointer?, sessionID: String) -> [OpencodeUsage] {
        usage(db, sessionID: sessionID, table: "part", predicate: "json_extract(data, '$.type') = 'step-finish'")
    }

    private static func usage(_ db: OpaquePointer?, sessionID: String, table: String,
                              predicate: String) -> [OpencodeUsage] {
        let sql = """
        SELECT json_extract(data, '$.tokens.input'), json_extract(data, '$.tokens.output'),
               json_extract(data, '$.tokens.cache.read'), json_extract(data, '$.tokens.cache.write'),
               json_extract(data, '$.cost'), time_created
        FROM \(table) WHERE session_id = ? AND \(predicate)
        ORDER BY time_created ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sessionID, -1, OPENCODE_SQLITE_TRANSIENT)
        var result: [OpencodeUsage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let item = OpencodeUsage(input: uint(stmt, 0), output: uint(stmt, 1), cacheRead: uint(stmt, 2),
                                     cacheWrite: uint(stmt, 3), cost: double(stmt, 4), timestamp: iso(uint64(stmt, 5)))
            if item.input + item.output + item.cacheRead + item.cacheWrite > 0 { result.append(item) }
        }
        return result
    }

    private static func dailyUsage(_ usages: [OpencodeUsage], pricing: PricingTable, model: String?, totalCost: Double) -> (cost: [String: Double]?, tokens: [String: UInt64]?) {
        var cost: [String: Double] = [:], tokens: [String: UInt64] = [:]
        for usage in usages {
            guard let day = Format.localDay(usage.timestamp) else { continue }
            let estimated = usage.cost > 0 ? usage.cost : pricing.info(model ?? "").cost(input: usage.input, cacheWrite: usage.cacheWrite, cacheRead: usage.cacheRead, output: usage.output).totalCost
            cost[day, default: 0] += estimated
            tokens[day, default: 0] += usage.input + usage.output + usage.cacheRead + usage.cacheWrite
        }
        let sumCost = cost.values.reduce(0, +)
        if sumCost > 0, totalCost > 0 {
            let factor = totalCost / sumCost
            for day in cost.keys { cost[day]! *= factor }
        }
        return cost.isEmpty ? (nil, nil) : (cost, tokens)
    }

    private static func sum(_ usages: [OpencodeUsage]) -> OpencodeUsage {
        usages.reduce(OpencodeUsage()) { partial, next in
            OpencodeUsage(input: partial.input + next.input, output: partial.output + next.output,
                          cacheRead: partial.cacheRead + next.cacheRead, cacheWrite: partial.cacheWrite + next.cacheWrite,
                          cost: partial.cost + next.cost)
        }
    }

    private static func scaled(_ breakdown: CostBreakdown, to total: Double) -> CostBreakdown {
        guard breakdown.totalCost > 0 else { return CostBreakdown(inputCost: total, totalCost: total) }
        var result = breakdown
        result.scale(by: total / breakdown.totalCost)
        return result
    }

    private static func modelID(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return raw }
        return (object["id"] as? String) ?? (object["modelID"] as? String)
    }

    private static func tableColumns(_ db: OpaquePointer?, table: String) -> Set<String> {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var columns = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW { if let name = string(stmt, 1) { columns.insert(name) } }
        return columns
    }

    private static func string(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: value)
    }
    private static func uint(_ stmt: OpaquePointer?, _ index: Int32) -> UInt64 { UInt64(max(0, sqlite3_column_int64(stmt, index))) }
    private static func uint64(_ stmt: OpaquePointer?, _ index: Int32) -> UInt64 { uint(stmt, index) }
    private static func double(_ stmt: OpaquePointer?, _ index: Int32) -> Double { sqlite3_column_double(stmt, index) }
    private static func iso(_ milliseconds: UInt64) -> String? {
        guard milliseconds > 0 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000))
    }
}
