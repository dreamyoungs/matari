import Foundation
import Testing
import SQLite3
@testable import MatariCore

struct APICostTests {
    @Test func costSummariesRespectPeriodBoundariesAndKeepUnknownCoverage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(url: root.appendingPathComponent("test.sqlite"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(3600)
        let cursor = FileCursor(fileID: "test", currentPath: "/synthetic", byteOffset: 0,
            lastTotalTokens: nil, fileSize: 0, modifiedAt: start, cliVersion: nil, threadSource: .user)
        let records = [-1.0, 0, 1800, 3600].enumerated().map { index, offset in
            TokenContribution(eventID: EventID(rawValue: "event-\(index)"), fileID: "test",
                occurredAt: start.addingTimeInterval(offset), usage: usage(input: 100), source: .user,
                model: index == 2 ? nil : "gpt-6-astra", requestInputTokens: 100)
        }
        try await store.persist(cursor: cursor, contributions: records, quotas: [])
        let cost = try await store.costSummary(from: start, to: end)
        #expect(abs(cost.usd - 0.001) < 0.000001)
        #expect(cost.pricedTokens == 100)
        #expect(cost.unpricedTokens == 100)
        #expect(try await store.tokenTotal(from: start, to: end) == 200)
    }

    @Test func migratesVersionOneWithoutDeletingOldOrUnpricedHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("old.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        let sql = """
        CREATE TABLE token_contributions (
            event_id TEXT PRIMARY KEY, file_id TEXT NOT NULL, occurred_at REAL NOT NULL,
            input_tokens INTEGER NOT NULL, cached_input_tokens INTEGER NOT NULL,
            cache_write_input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,
            reasoning_output_tokens INTEGER NOT NULL, total_tokens INTEGER NOT NULL, thread_source TEXT NOT NULL);
        INSERT INTO token_contributions VALUES ('old','deleted-file',1800000000,100,0,0,0,0,100,'user');
        PRAGMA user_version = 1;
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let store = try SQLiteStore(url: url)
        let cost = try await store.costSummary(from: .distantPast, to: .distantFuture)
        #expect(cost.unpricedTokens == 100)
        #expect(cost.pricedTokens == 0)
        #expect(try await store.tokenTotal(from: .distantPast, to: .distantFuture) == 100)
        let reopened = try SQLiteStore(url: url)
        #expect(try await reopened.costSummary(from: .distantPast, to: .distantFuture) == cost)
    }

    func usage(input: Int64, cached: Int64 = 0, write: Int64 = 0, output: Int64 = 0, reasoning: Int64 = 0) -> TokenUsage {
        TokenUsage(inputTokens: input, cachedInputTokens: cached, cacheWriteInputTokens: write,
            outputTokens: output, reasoningOutputTokens: reasoning, totalTokens: input + output)
    }

    @Test func pricesDisjointInputCategoriesAndDoesNotDoubleCountReasoning() throws {
        let tokens = usage(input: 100_000, cached: 60_000, write: 20_000, output: 10_000, reasoning: 8_000)
        let price = try #require(APICost.estimate(usage: tokens, model: "gpt-6-astra", requestInputTokens: 100_000))
        #expect(abs(price - 1.01) < 0.000001) // 0.2 ordinary + 0.06 cached + 0.25 write + 0.5 output
    }

    @Test func longContextUsesRequestInputNotContextCapacityOrWeeklySum() throws {
        let short = try #require(APICost.estimate(usage: usage(input: 272_000, output: 1000),
            model: "gpt-6-astra", requestInputTokens: 272_000))
        let long = try #require(APICost.estimate(usage: usage(input: 272_001, output: 1000),
            model: "gpt-6-astra", requestInputTokens: 272_001))
        #expect(abs(short - 2.77) < 0.000001)
        #expect(abs(long - 5.51502) < 0.000001)
    }

    @Test func unknownModelMissingRequestOrInconsistentCountersAreUnpriced() {
        #expect(APICost.estimate(usage: usage(input: 10), model: nil, requestInputTokens: 10) == nil)
        #expect(APICost.estimate(usage: usage(input: 10), model: "gpt-6-astra-custom", requestInputTokens: 10) == nil)
        #expect(APICost.estimate(usage: usage(input: 10), model: "gpt-6-astra", requestInputTokens: nil) == nil)
        #expect(APICost.estimate(usage: usage(input: 10, cached: 8, write: 8), model: "gpt-6-astra", requestInputTokens: 10) == nil)
        #expect(APICost.estimate(usage: usage(input: 10, output: 1, reasoning: 2), model: "gpt-6-astra", requestInputTokens: 10) == nil)
    }

    @Test func contextModelSurvivesAppendAndChangesPerTurnWithoutDuplicateCost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("sample.jsonl")
        let context = #"{"type":"turn_context","payload":{"model":"gpt-6-astra","instructions":"not retained"}}"#
        try Data("\(context)\n\(line(total: 100, last: 100))\n".utf8).write(to: file)
        let store = try SQLiteStore(url: root.appendingPathComponent("test.sqlite"))
        let paths = CodexPaths(home: root, sessionDirectories: [sessions])
        let scanner = TelemetryCoordinator(store: store)
        _ = await scanner.scan(paths: paths)
        func append(_ text: String) throws {
            let h = try FileHandle(forWritingTo: file)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: Data(text.utf8))
        }
        try append("\(line(total: 200, last: 100))\n")
        _ = await scanner.scan(paths: paths)
        try append(#"{"type":"turn_context","payload":{"model":"gpt-6-sol"}}"# + "\n" + line(total: 300, last: 100) + "\n")
        _ = await scanner.scan(paths: paths)
        try append(#"{"type":"turn_context","payload":{}}"# + "\n" + line(total: 400, last: 100) + "\n")
        _ = await scanner.scan(paths: paths)
        _ = await scanner.scan(paths: paths)
        let cost = try await store.costSummary(from: .distantPast, to: .distantFuture)
        #expect(abs(cost.usd - 0.0022) < 0.000001)
        #expect(cost.pricedTokens == 300)
        #expect(cost.unpricedTokens == 100)
        #expect(try await store.tokenTotal(from: .distantPast, to: .distantFuture) == 400)
    }

    @Test func reprocessingOldCursorBackfillsCostWithoutChangingTokenTotals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("sample.jsonl")
        let context = #"{"type":"turn_context","payload":{"model":"gpt-6-astra"}}"# + "\n"
        let token = line(total: 100, last: 100)
        let data = Data((context + token + "\n").utf8)
        try data.write(to: file)
        let store = try SQLiteStore(url: root.appendingPathComponent("test.sqlite"))
        let date = try Date("2026-09-30T00:00:00Z", strategy: .iso8601)
        let modified = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        let cursor = FileCursor(fileID: "sample", currentPath: file.path, byteOffset: Int64(data.count),
            lastTotalTokens: usage(input: 100), fileSize: Int64(data.count), modifiedAt: modified,
            cliVersion: nil, threadSource: .unknown)
        let event = EventID(fileID: "sample", ordinal: nil, byteOffset: Int64(context.utf8.count), eventType: "token_count")
        try await store.persist(cursor: cursor, contributions: [TokenContribution(eventID: event, fileID: "sample",
            occurredAt: date, usage: usage(input: 100), source: .unknown)], quotas: [])
        #expect(try await store.costSummary(from: .distantPast, to: .distantFuture).unpricedTokens == 100)
        _ = await TelemetryCoordinator(store: store).scan(paths: CodexPaths(home: root, sessionDirectories: [sessions]))
        let cost = try await store.costSummary(from: .distantPast, to: .distantFuture)
        #expect(cost.pricedTokens == 100)
        #expect(cost.unpricedTokens == 0)
        #expect(abs(cost.usd - 0.001) < 0.000001)
        #expect(try await store.tokenTotal(from: .distantPast, to: .distantFuture) == 100)
        let reopened = try SQLiteStore(url: root.appendingPathComponent("test.sqlite"))
        #expect(try await reopened.costSummary(from: .distantPast, to: .distantFuture) == cost)
    }

    private func line(total: Int, last: Int) -> String {
        #"{"timestamp":"2026-09-30T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(total),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\#(total)},"last_token_usage":{"input_tokens":\#(last),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\#(last)}}}}"#
    }
}
