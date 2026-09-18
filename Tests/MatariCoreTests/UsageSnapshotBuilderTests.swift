import Foundation
import Testing
@testable import MatariCore

struct UsageSnapshotBuilderTests {
    @Test func koreanPeriodsStartAtMidnightAndMonday() {
        let now = date("2026-09-20T15:30:00+09:00")
        let boundaries = UsagePeriodBoundaries.korean(now: now)
        #expect(boundaries.todayStart == date("2026-09-20T00:00:00+09:00"))
        #expect(boundaries.weekStart == date("2026-09-14T00:00:00+09:00"))
    }

    @Test func consumptionRequiresBaselineAndAtLeastOnePercentForDisplay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(url: root.appendingPathComponent("matari.sqlite"))
        let now = date("2026-09-18T18:00:00+09:00")
        let boundaries = UsagePeriodBoundaries.korean(now: now)
        let reset = date("2026-09-21T09:00:00+09:00")
        let usage = TokenUsage(
            inputTokens: 1_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            reasoningOutputTokens: 0,
            totalTokens: 1_000
        )
        let cursor = FileCursor(
            fileID: "file",
            currentPath: "/tmp/file",
            byteOffset: 1,
            lastTotalTokens: usage,
            fileSize: 1,
            modifiedAt: now,
            cliVersion: nil,
            threadSource: .user
        )
        let contribution = TokenContribution(
            eventID: EventID(rawValue: "token"),
            fileID: "file",
            occurredAt: now.addingTimeInterval(-60),
            usage: usage,
            source: .user
        )
        let before = QuotaSnapshot(
            eventID: EventID(rawValue: "before"),
            bucketIndex: 0,
            observedAt: boundaries.todayStart.addingTimeInterval(-60),
            limitID: "codex",
            planType: "pro",
            windowMinutes: 10_080,
            usedPercent: 20,
            resetsAt: reset
        )
        let after = QuotaSnapshot(
            eventID: EventID(rawValue: "after"),
            bucketIndex: 0,
            observedAt: now.addingTimeInterval(-30),
            limitID: "codex",
            planType: "pro",
            windowMinutes: 10_080,
            usedPercent: 22,
            resetsAt: reset
        )
        try await store.persist(cursor: cursor, contributions: [contribution], quotas: [before, after])

        let snapshot = try await UsageSnapshotBuilder(store: store).build(now: now)
        #expect(snapshot.state == .ready)
        #expect(snapshot.todayTokens == 1_000)
        #expect(snapshot.weekTokens == 1_000)
        #expect(snapshot.todayTokensPerPercent == 500)
        #expect(snapshot.weekTokensPerPercent == nil)
        #expect(snapshot.buckets.map(\.remainingPercent) == [78])
    }

    @Test func noQuotaStillShowsLocalTokens() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(url: root.appendingPathComponent("matari.sqlite"))
        let snapshot = try await UsageSnapshotBuilder(store: store).build(now: date("2026-09-18T18:00:00+09:00"))
        #expect(snapshot.state == .noQuota)
        #expect(snapshot.todayTokens == 0)
        #expect(snapshot.weekTokens == 0)
    }

    private func date(_ value: String) -> Date {
        try! Date(value, strategy: .iso8601)
    }
}
