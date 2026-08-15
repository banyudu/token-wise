import XCTest
import SQLite3
@testable import TokenWiseCore

final class OpencodeParserTests: XCTestCase {
    func testReadsSQLiteFixtureWithTokensCostAndCacheAttribution() throws {
        let db = try fixtureDatabase(
            sessionColumns: """
            tokens_input INTEGER NOT NULL DEFAULT 0, tokens_output INTEGER NOT NULL DEFAULT 0,
            tokens_cache_read INTEGER NOT NULL DEFAULT 0, tokens_cache_write INTEGER NOT NULL DEFAULT 0,
            cost REAL NOT NULL DEFAULT 0,
            """,
            sessionValues: """
            'ses_fixture', '/tmp/project/.worktrees/feature', 'Fixture session',
            '{"id":"gpt-5-mini","providerID":"openai"}', 1767268800000, 1767441600000,
            1000, 200, 3000, 0, 0
            """
        )
        defer { try? FileManager.default.removeItem(at: db) }
        try execute(db, """
        INSERT INTO message VALUES
        ('msg_user', 'ses_fixture', 1767268700000, '{"role":"user"}'),
        ('msg_one', 'ses_fixture', 1767268800000, '{"role":"assistant","tokens":{"input":500,"output":100,"reasoning":0,"cache":{"read":1500,"write":0}},"cost":0}'),
        ('msg_two', 'ses_fixture', 1767441600000, '{"role":"assistant","tokens":{"input":500,"output":100,"reasoning":0,"cache":{"read":1500,"write":0}},"cost":0}');
        """)

        let sessions = OpencodeParser.loadSessions(at: db, pricing: PricingTable())

        XCTAssertEqual(sessions.count, 1)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.source, "opencode")
        XCTAssertEqual(session.project, "/tmp/project")
        XCTAssertEqual(session.totalInputTokens, 1_000)
        XCTAssertEqual(session.totalOutputTokens, 200)
        XCTAssertEqual(session.totalCacheReadTokens, 3_000)
        XCTAssertEqual(session.totalCacheWriteTokens, 0)
        XCTAssertEqual(session.cacheHitRate, 0.75, accuracy: 0.000_001)
        // GPT-5 mini: $0.25 input, $0.025 cached input, $2 output / MTok.
        XCTAssertEqual(session.estimatedCostUsd, 0.000725, accuracy: 0.000_000_001)
        XCTAssertEqual(session.dailyCostUsd?.count, 2)
        XCTAssertEqual(try XCTUnwrap(session.dailyCostUsd).values.reduce(0, +),
                       session.estimatedCostUsd, accuracy: 0.000_000_001)
    }

    func testFallsBackToAssistantMessageUsageForOlderSchema() throws {
        let db = try fixtureDatabase(
            sessionColumns: "",
            sessionValues: """
            'ses_legacy', '/tmp/legacy', 'Legacy session',
            NULL, 1767268800000, 1767268800000
            """
        )
        defer { try? FileManager.default.removeItem(at: db) }
        try execute(db, """
        INSERT INTO message VALUES
        ('msg_user', 'ses_legacy', 1767268700000, '{"role":"user"}'),
        ('msg_assistant', 'ses_legacy', 1767268800000, '{"role":"assistant","modelID":"gpt-5-mini","tokens":{"input":400,"output":50,"reasoning":0,"cache":{"read":600,"write":0}},"cost":0.001}');
        """)

        let session = try XCTUnwrap(OpencodeParser.loadSessions(at: db, pricing: PricingTable()).first)

        XCTAssertEqual(session.model, "gpt-5-mini")
        XCTAssertEqual(session.totalInputTokens, 400)
        XCTAssertEqual(session.totalOutputTokens, 50)
        XCTAssertEqual(session.totalCacheReadTokens, 600)
        XCTAssertEqual(session.estimatedCostUsd, 0.001, accuracy: 0.000_000_001)
        XCTAssertEqual(session.costBreakdown.totalCost, 0.001, accuracy: 0.000_000_001)
    }

    func testFallsBackToStepFinishPartsWhenMessagesHaveNoUsage() throws {
        let db = try fixtureDatabase(
            sessionColumns: "",
            sessionValues: "'ses_parts', '/tmp/parts', 'Part session', '{\"id\":\"gpt-5-mini\"}', 1767268800000, 1767268800000"
        )
        defer { try? FileManager.default.removeItem(at: db) }
        try execute(db, """
        INSERT INTO message VALUES ('msg_user', 'ses_parts', 1767268700000, '{"role":"user"}');
        INSERT INTO part VALUES
        ('part_finish', 'ses_parts', 1767268800000, '{"type":"step-finish","tokens":{"input":200,"output":25,"reasoning":0,"cache":{"read":800,"write":0}},"cost":0.002}');
        """)

        let session = try XCTUnwrap(OpencodeParser.loadSessions(at: db, pricing: PricingTable()).first)

        XCTAssertEqual(session.totalInputTokens, 200)
        XCTAssertEqual(session.totalOutputTokens, 25)
        XCTAssertEqual(session.totalCacheReadTokens, 800)
        XCTAssertEqual(session.estimatedCostUsd, 0.002, accuracy: 0.000_000_001)
    }

    private func fixtureDatabase(sessionColumns: String, sessionValues: String) throws -> URL {
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-wise-opencode-\(UUID().uuidString).sqlite")
        try execute(db, """
        CREATE TABLE session (
            id TEXT PRIMARY KEY, directory TEXT NOT NULL, title TEXT, model TEXT,
            time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL,
            \(sessionColumns)
            time_archived INTEGER
        );
        CREATE TABLE message (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL
        );
        CREATE TABLE part (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL
        );
        """)
        let columns = sessionColumns.isEmpty
            ? "id, directory, title, model, time_created, time_updated"
            : "id, directory, title, model, time_created, time_updated, tokens_input, tokens_output, tokens_cache_read, tokens_cache_write, cost"
        try execute(db, "INSERT INTO session (\(columns)) VALUES (\(sessionValues));")
        return db
    }

    private func execute(_ url: URL, _ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw NSError(domain: "OpencodeParserTests", code: 1)
        }
        defer { sqlite3_close(db) }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(error)
            throw NSError(domain: "OpencodeParserTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
