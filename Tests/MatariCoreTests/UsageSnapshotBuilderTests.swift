import Foundation
import Testing
@testable import MatariCore

struct UsageSnapshotBuilderTests {
    @Test func measurementSharesJitterPolicyWithoutMergingOtherPeriods() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = start.addingTimeInterval(600)
        func sample(_ time: Double, _ used: Double, _ offset: Double) -> QuotaObservation {
            QuotaObservation(observedAt: start.addingTimeInterval(time), limitID: "codex",
                windowMinutes: 10_080, usedPercent: used, resetsAt: reset.addingTimeInterval(offset))
        }
        let interval = QuotaConsumptionCalculator().measurement(observations: [
            sample(0, 9, 2), sample(10, 10, 30), sample(20, 99, 80),
            sample(30, 19, 0), sample(40, 18, 2)
        ], reset: reset, from: start, to: start.addingTimeInterval(60))
        #expect(interval?.start == start)
        #expect(interval?.end == start.addingTimeInterval(40))
        #expect(interval?.consumedPercent == 10)
    }

    @Test func measurementIgnoresOldPeriodsAndMergesOneSecondResetDifference() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = start.addingTimeInterval(604_800)
        func sample(_ seconds: Double, _ used: Double, _ resetAt: Date) -> QuotaObservation {
            QuotaObservation(observedAt: start.addingTimeInterval(seconds), limitID: "codex",
                             windowMinutes: 10_080, usedPercent: used, resetsAt: resetAt)
        }
        let interval = QuotaConsumptionCalculator().measurement(observations: [
            sample(-60, 2, reset), sample(10, 2, reset),
            sample(20, 0, reset.addingTimeInterval(1)),
            sample(30, 99, reset.addingTimeInterval(-86_400)),
            sample(40, 4, reset), sample(50, 3, reset.addingTimeInterval(1))
        ], reset: reset, from: start, to: start.addingTimeInterval(60))
        #expect(interval?.consumedPercent == 2)
        #expect(interval?.start == start.addingTimeInterval(10))
        #expect(interval?.end == start.addingTimeInterval(50))
    }

    @Test func singleObservationDoesNotInventZeroBaseline() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = start.addingTimeInterval(600)
        let sample = QuotaObservation(observedAt: start, limitID: "codex", windowMinutes: 300,
                                      usedPercent: 50, resetsAt: reset)
        #expect(QuotaConsumptionCalculator().measurement(observations: [sample], reset: reset,
                from: start, to: start.addingTimeInterval(60)) == nil)
    }

    @Test func koreanPeriodsStartAtMidnightAndMonday() {
        let now = date("2026-09-20T15:30:00+09:00")
        let boundaries = UsagePeriodBoundaries.korean(now: now)
        #expect(boundaries.todayStart == date("2026-09-20T00:00:00+09:00"))
        #expect(boundaries.weekStart == date("2026-09-14T00:00:00+09:00"))
    }

    @Test(arguments: [0.0, 2.0, 30.0])
    func consumptionRequiresBaselineAndAtLeastOnePercentForDisplay(resetJitter: Double) async throws {
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
            observedAt: boundaries.todayStart,
            limitID: "codex",
            planType: "pro",
            windowMinutes: 10_080,
            usedPercent: 20,
            resetsAt: reset.addingTimeInterval(resetJitter)
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
        let beforeInterval = TokenContribution(eventID: EventID(rawValue: "outside-before"),
            fileID: "file", occurredAt: before.observedAt, usage: usage, source: .user)
        let afterInterval = TokenContribution(eventID: EventID(rawValue: "outside-after"),
            fileID: "file", occurredAt: now.addingTimeInterval(-10), usage: usage, source: .user)
        let priorPlan = QuotaSnapshot(eventID: EventID(rawValue: "prior-plan"), bucketIndex: 0,
            observedAt: now.addingTimeInterval(-45), limitID: "codex", planType: "plus",
            windowMinutes: 10_080, usedPercent: 99, resetsAt: reset)
        try await store.persist(cursor: cursor,
            contributions: [beforeInterval, contribution, afterInterval], quotas: [before, priorPlan, after])

        let snapshot = try await UsageSnapshotBuilder(store: store).build(now: now)
        #expect(snapshot.state == .ready)
        #expect(snapshot.todayTokens == 3_000)
        #expect(snapshot.weekTokens == 3_000)
        #expect(snapshot.todayTokensPerPercent == 500)
        #expect(snapshot.weekTokensPerPercent == 500)
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
