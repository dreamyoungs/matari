import Foundation
import SQLite3

public enum SQLiteStoreError: Error, Sendable, Equatable, LocalizedError {
    case openFailed(String)
    case statementFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .openFailed(message): "데이터베이스를 열 수 없습니다: \(message)"
        case let .statementFailed(message): "데이터베이스 명령을 준비할 수 없습니다: \(message)"
        case let .stepFailed(message): "데이터베이스 작업을 완료할 수 없습니다: \(message)"
        }
    }
}

public actor SQLiteStore {
    private var database: OpaquePointer?

    public init(url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw SQLiteStoreError.openFailed(message)
        }
        database = handle
        try Self.execute(on: handle, sql: "PRAGMA journal_mode = WAL")
        try Self.execute(on: handle, sql: "PRAGMA synchronous = NORMAL")
        try Self.migrate(handle)
    }

    public func cursor(fileID: String) throws -> FileCursor? {
        let sql = """
        SELECT current_path, byte_offset,
               last_input_tokens, last_cached_input_tokens, last_cache_write_input_tokens,
               last_output_tokens, last_reasoning_output_tokens, last_total_tokens,
               file_size, modified_at, cli_version, thread_source
        FROM source_files WHERE file_id = ?
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(fileID, at: 1, to: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let lastTotal: TokenUsage?
        if sqlite3_column_type(statement, 7) == SQLITE_NULL {
            lastTotal = nil
        } else {
            lastTotal = TokenUsage(
                inputTokens: sqlite3_column_int64(statement, 2),
                cachedInputTokens: sqlite3_column_int64(statement, 3),
                cacheWriteInputTokens: sqlite3_column_int64(statement, 4),
                outputTokens: sqlite3_column_int64(statement, 5),
                reasoningOutputTokens: sqlite3_column_int64(statement, 6),
                totalTokens: sqlite3_column_int64(statement, 7)
            )
        }

        return FileCursor(
            fileID: fileID,
            currentPath: columnText(statement, at: 0) ?? "",
            byteOffset: sqlite3_column_int64(statement, 1),
            lastTotalTokens: lastTotal,
            fileSize: sqlite3_column_int64(statement, 8),
            modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            cliVersion: columnText(statement, at: 10),
            threadSource: ThreadSource(rawValue: columnText(statement, at: 11) ?? "") ?? .unknown
        )
    }

    public func persist(
        cursor: FileCursor,
        contributions: [TokenContribution],
        quotas: [QuotaSnapshot]
    ) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try upsertCursor(cursor)
            for contribution in contributions where contribution.usage.totalTokens > 0 {
                try insert(contribution)
            }
            for quota in quotas {
                try insert(quota)
                try upsertEpoch(for: quota)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func tokenTotal(from start: Date, to end: Date) throws -> Int64 {
        let statement = try prepare(
            "SELECT COALESCE(SUM(total_tokens), 0) FROM token_contributions WHERE occurred_at >= ? AND occurred_at < ?"
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw stepError() }
        return sqlite3_column_int64(statement, 0)
    }

    public func quotaEpochs() throws -> [QuotaEpoch] {
        let sql = """
        SELECT limit_id, window_minutes, resets_at, plan_type,
               first_observed_at, last_observed_at, high_water_used_percent
        FROM quota_epochs
        ORDER BY last_observed_at ASC
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var epochs: [QuotaEpoch] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            epochs.append(
                QuotaEpoch(
                    key: QuotaEpochKey(
                        limitID: columnText(statement, at: 0) ?? "",
                        windowMinutes: Int(sqlite3_column_int64(statement, 1)),
                        resetsAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                    ),
                    planType: columnText(statement, at: 3),
                    firstObservedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    lastObservedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                    highWaterUsedPercent: sqlite3_column_double(statement, 6)
                )
            )
        }
        return epochs
    }

    public func lastQuotaObservation() throws -> Date? {
        let statement = try prepare("SELECT MAX(observed_at) FROM quota_snapshots")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
    }

    public func quotaObservations(
        limitID: String,
        windowMinutes: Int,
        overlapping start: Date,
        through end: Date,
        planType: String? = nil
    ) throws -> [QuotaObservation] {
        let sql = """
        SELECT observed_at, limit_id, window_minutes, used_percent, resets_at
        FROM quota_snapshots
        WHERE limit_id = ? AND window_minutes = ?
          AND observed_at < ? AND resets_at > ?
          AND (? IS NULL OR plan_type = ?)
        ORDER BY resets_at ASC, observed_at ASC
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(limitID, at: 1, to: statement)
        sqlite3_bind_int64(statement, 2, Int64(windowMinutes))
        sqlite3_bind_double(statement, 3, end.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, start.timeIntervalSince1970)
        bindOptionalText(planType, at: 5, to: statement)
        bindOptionalText(planType, at: 6, to: statement)

        var observations: [QuotaObservation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            observations.append(
                QuotaObservation(
                    observedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                    limitID: columnText(statement, at: 1) ?? "",
                    windowMinutes: Int(sqlite3_column_int64(statement, 2)),
                    usedPercent: sqlite3_column_double(statement, 3),
                    resetsAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                )
            )
        }
        return observations
    }

    public func sourceFileCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM source_files")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw stepError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func upsertCursor(_ cursor: FileCursor) throws {
        let sql = """
        INSERT INTO source_files (
            file_id, current_path, byte_offset,
            last_input_tokens, last_cached_input_tokens, last_cache_write_input_tokens,
            last_output_tokens, last_reasoning_output_tokens, last_total_tokens,
            file_size, modified_at, cli_version, thread_source
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(file_id) DO UPDATE SET
            current_path = excluded.current_path,
            byte_offset = excluded.byte_offset,
            last_input_tokens = excluded.last_input_tokens,
            last_cached_input_tokens = excluded.last_cached_input_tokens,
            last_cache_write_input_tokens = excluded.last_cache_write_input_tokens,
            last_output_tokens = excluded.last_output_tokens,
            last_reasoning_output_tokens = excluded.last_reasoning_output_tokens,
            last_total_tokens = excluded.last_total_tokens,
            file_size = excluded.file_size,
            modified_at = excluded.modified_at,
            cli_version = excluded.cli_version,
            thread_source = excluded.thread_source
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(cursor.fileID, at: 1, to: statement)
        bindText(cursor.currentPath, at: 2, to: statement)
        sqlite3_bind_int64(statement, 3, cursor.byteOffset)
        if let usage = cursor.lastTotalTokens {
            sqlite3_bind_int64(statement, 4, usage.inputTokens)
            sqlite3_bind_int64(statement, 5, usage.cachedInputTokens)
            sqlite3_bind_int64(statement, 6, usage.cacheWriteInputTokens)
            sqlite3_bind_int64(statement, 7, usage.outputTokens)
            sqlite3_bind_int64(statement, 8, usage.reasoningOutputTokens)
            sqlite3_bind_int64(statement, 9, usage.totalTokens)
        } else {
            for index in 4 ... 9 { sqlite3_bind_null(statement, Int32(index)) }
        }
        sqlite3_bind_int64(statement, 10, cursor.fileSize)
        sqlite3_bind_double(statement, 11, cursor.modifiedAt.timeIntervalSince1970)
        bindOptionalText(cursor.cliVersion, at: 12, to: statement)
        bindText(cursor.threadSource.rawValue, at: 13, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw stepError() }
    }

    private func insert(_ contribution: TokenContribution) throws {
        let sql = """
        INSERT OR IGNORE INTO token_contributions (
            event_id, file_id, occurred_at, input_tokens, cached_input_tokens,
            cache_write_input_tokens, output_tokens, reasoning_output_tokens,
            total_tokens, thread_source
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(contribution.eventID.rawValue, at: 1, to: statement)
        bindText(contribution.fileID, at: 2, to: statement)
        sqlite3_bind_double(statement, 3, contribution.occurredAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 4, contribution.usage.inputTokens)
        sqlite3_bind_int64(statement, 5, contribution.usage.cachedInputTokens)
        sqlite3_bind_int64(statement, 6, contribution.usage.cacheWriteInputTokens)
        sqlite3_bind_int64(statement, 7, contribution.usage.outputTokens)
        sqlite3_bind_int64(statement, 8, contribution.usage.reasoningOutputTokens)
        sqlite3_bind_int64(statement, 9, contribution.usage.totalTokens)
        bindText(contribution.source.rawValue, at: 10, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw stepError() }
    }

    private func insert(_ quota: QuotaSnapshot) throws {
        let sql = """
        INSERT OR IGNORE INTO quota_snapshots (
            event_id, bucket_index, observed_at, limit_id, plan_type,
            window_minutes, used_percent, resets_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(quota.eventID.rawValue, at: 1, to: statement)
        sqlite3_bind_int64(statement, 2, Int64(quota.bucketIndex))
        sqlite3_bind_double(statement, 3, quota.observedAt.timeIntervalSince1970)
        bindText(quota.limitID, at: 4, to: statement)
        bindOptionalText(quota.planType, at: 5, to: statement)
        sqlite3_bind_int64(statement, 6, Int64(quota.windowMinutes))
        sqlite3_bind_double(statement, 7, quota.usedPercent)
        sqlite3_bind_double(statement, 8, quota.resetsAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw stepError() }
    }

    private func upsertEpoch(for quota: QuotaSnapshot) throws {
        let sql = """
        INSERT INTO quota_epochs (
            limit_id, window_minutes, resets_at, plan_type,
            first_observed_at, last_observed_at, high_water_used_percent
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(limit_id, window_minutes, resets_at) DO UPDATE SET
            plan_type = COALESCE(excluded.plan_type, quota_epochs.plan_type),
            first_observed_at = MIN(quota_epochs.first_observed_at, excluded.first_observed_at),
            last_observed_at = MAX(quota_epochs.last_observed_at, excluded.last_observed_at),
            high_water_used_percent = MAX(quota_epochs.high_water_used_percent, excluded.high_water_used_percent)
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(quota.limitID, at: 1, to: statement)
        sqlite3_bind_int64(statement, 2, Int64(quota.windowMinutes))
        sqlite3_bind_double(statement, 3, quota.resetsAt.timeIntervalSince1970)
        bindOptionalText(quota.planType, at: 4, to: statement)
        sqlite3_bind_double(statement, 5, quota.observedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, quota.observedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 7, quota.usedPercent)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw stepError() }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw SQLiteStoreError.openFailed("closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statementFailed(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw SQLiteStoreError.openFailed("closed") }
        try Self.execute(on: database, sql: sql)
    }

    private func stepError() -> SQLiteStoreError {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "closed"
        return .stepFailed(message)
    }

    private static func execute(on database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SQLiteStoreError.stepFailed(message)
        }
    }

    private static func migrate(_ database: OpaquePointer) throws {
        try execute(on: database, sql: """
        CREATE TABLE IF NOT EXISTS source_files (
            file_id TEXT PRIMARY KEY,
            current_path TEXT NOT NULL,
            byte_offset INTEGER NOT NULL,
            last_input_tokens INTEGER,
            last_cached_input_tokens INTEGER,
            last_cache_write_input_tokens INTEGER,
            last_output_tokens INTEGER,
            last_reasoning_output_tokens INTEGER,
            last_total_tokens INTEGER,
            file_size INTEGER NOT NULL,
            modified_at REAL NOT NULL,
            cli_version TEXT,
            thread_source TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS token_contributions (
            event_id TEXT PRIMARY KEY,
            file_id TEXT NOT NULL,
            occurred_at REAL NOT NULL,
            input_tokens INTEGER NOT NULL,
            cached_input_tokens INTEGER NOT NULL,
            cache_write_input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            reasoning_output_tokens INTEGER NOT NULL,
            total_tokens INTEGER NOT NULL,
            thread_source TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS token_contributions_occurred_at
            ON token_contributions(occurred_at);
        CREATE TABLE IF NOT EXISTS quota_snapshots (
            event_id TEXT NOT NULL,
            bucket_index INTEGER NOT NULL,
            observed_at REAL NOT NULL,
            limit_id TEXT NOT NULL,
            plan_type TEXT,
            window_minutes INTEGER NOT NULL,
            used_percent REAL NOT NULL,
            resets_at REAL NOT NULL,
            PRIMARY KEY(event_id, bucket_index)
        );
        CREATE INDEX IF NOT EXISTS quota_snapshots_observed_at
            ON quota_snapshots(observed_at);
        CREATE TABLE IF NOT EXISTS quota_epochs (
            limit_id TEXT NOT NULL,
            window_minutes INTEGER NOT NULL,
            resets_at REAL NOT NULL,
            plan_type TEXT,
            first_observed_at REAL NOT NULL,
            last_observed_at REAL NOT NULL,
            high_water_used_percent REAL NOT NULL,
            PRIMARY KEY(limit_id, window_minutes, resets_at)
        );
        CREATE TABLE IF NOT EXISTS app_metadata (
            key TEXT PRIMARY KEY,
            value BLOB NOT NULL
        );
        PRAGMA user_version = 1;
        """)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func bindText(_ value: String, at index: Int32, to statement: OpaquePointer?) {
    sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
}

private func bindOptionalText(_ value: String?, at index: Int32, to statement: OpaquePointer?) {
    if let value {
        bindText(value, at: index, to: statement)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func columnText(_ statement: OpaquePointer?, at index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: value)
}
