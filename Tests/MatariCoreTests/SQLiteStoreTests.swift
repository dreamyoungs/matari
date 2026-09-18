import Foundation
import Testing
@testable import MatariCore

struct SQLiteStoreTests {
    @Test func persistsIdempotentContributionsAndQuotaHighWater() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(url: root.appendingPathComponent("matari.sqlite"))
        let observed = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = observed.addingTimeInterval(3_600)
        let eventID = EventID(rawValue: "event-1")
        let usage = TokenUsage(
            inputTokens: 80,
            cachedInputTokens: 20,
            cacheWriteInputTokens: 0,
            outputTokens: 20,
            reasoningOutputTokens: 5,
            totalTokens: 100
        )
        let cursor = FileCursor(
            fileID: "file-1",
            currentPath: "/tmp/file-1.jsonl",
            byteOffset: 100,
            lastTotalTokens: usage,
            fileSize: 100,
            modifiedAt: observed,
            cliVersion: "0.155.0",
            threadSource: .user
        )
        let contribution = TokenContribution(
            eventID: eventID,
            fileID: "file-1",
            occurredAt: observed,
            usage: usage,
            source: .user
        )
        let quota63 = QuotaSnapshot(
            eventID: eventID,
            bucketIndex: 0,
            observedAt: observed,
            limitID: "codex",
            planType: "plus",
            windowMinutes: 300,
            usedPercent: 63,
            resetsAt: reset
        )

        try await store.persist(cursor: cursor, contributions: [contribution], quotas: [quota63])
        try await store.persist(cursor: cursor, contributions: [contribution], quotas: [quota63])
        #expect(try await store.tokenTotal(from: observed.addingTimeInterval(-1), to: observed.addingTimeInterval(1)) == 100)
        #expect(try await store.sourceFileCount() == 1)
        #expect(try await store.cursor(fileID: "file-1") == cursor)

        let lower = QuotaSnapshot(
            eventID: EventID(rawValue: "event-2"),
            bucketIndex: 0,
            observedAt: observed.addingTimeInterval(10),
            limitID: "codex",
            planType: "plus",
            windowMinutes: 300,
            usedPercent: 61,
            resetsAt: reset
        )
        try await store.persist(cursor: cursor, contributions: [], quotas: [lower])
        let epochs = try await store.quotaEpochs()
        #expect(epochs.count == 1)
        #expect(epochs[0].highWaterUsedPercent == 63)
        #expect(epochs[0].lastObservedAt == lower.observedAt)
    }
}
