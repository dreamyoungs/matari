import Foundation
import Testing
@testable import MatariCore

struct QuotaHistoryTests {
    @Test func bothBucketsHaveSeparateHistoriesAndSelectionFallsBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(url: root.appendingPathComponent("test.sqlite"))
        let quotas = [300, 10080].enumerated().map { index, minutes in
            QuotaSnapshot(eventID: EventID(rawValue: "poll:test"), bucketIndex: index,
                observedAt: now, limitID: "codex", planType: "plus", windowMinutes: minutes,
                usedPercent: minutes == 300 ? 20 : 70, resetsAt: now.addingTimeInterval(3600))
        }
        try await store.persistPolledQuotas(quotas)
        let snapshot = try await UsageSnapshotBuilder(store: store).build(now: now)
        #expect(snapshot.quotaHistories.map(\.windowMinutes) == [300, 10080])
        #expect(snapshot.quotaHistory(windowMinutes: nil)?.windowMinutes == 10080)
        #expect(snapshot.quotaHistory(windowMinutes: 300)?.points.last?.remaining == 80)
        #expect(snapshot.quotaHistory(windowMinutes: 10080)?.points.last?.remaining == 30)
        #expect(snapshot.quotaHistory(windowMinutes: 60)?.windowMinutes == 10080)

        try await store.persistPolledQuotas([QuotaSnapshot(eventID: EventID(rawValue: "poll:new-plan"),
            bucketIndex: 0, observedAt: now.addingTimeInterval(60), limitID: "codex", planType: "pro",
            windowMinutes: 10080, usedPercent: 71, resetsAt: now.addingTimeInterval(3600))])
        let single = try await UsageSnapshotBuilder(store: store).build(now: now.addingTimeInterval(60))
        #expect(single.quotaHistories.count == 1)
        #expect(single.quotaHistory(windowMinutes: 300)?.windowMinutes == 10080)
    }

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func sample(_ hoursAgo: Double, _ used: Double, reset: Double = 86400, plan: String = "pro") -> QuotaObservation {
        QuotaObservation(observedAt: now.addingTimeInterval(-hoursAgo * 3600), limitID: "codex",
            windowMinutes: 10080, usedPercent: used, resetsAt: now.addingTimeInterval(reset), planType: plan)
    }

    func history(_ samples: [QuotaObservation]) -> QuotaHistory {
        QuotaHistory(observations: samples, limitID: "codex", windowMinutes: 10080, now: now)
    }

    @Test func fixed48HoursExcludesOutsideRangeAndFutureWithoutPadding() {
        let result = history([sample(49, 10), sample(48, 20), sample(1, 70), sample(-1, 90)])
        #expect(result.start == now.addingTimeInterval(-172800))
        #expect(result.points.map(\.remaining) == [80, 30])
        #expect(result.points.last?.date == now.addingTimeInterval(-3600))
        #expect(result.points.first?.segment != result.points.last?.segment)
        #expect(history([]).points.isEmpty)
        #expect(history([sample(1, 70)]).points.count == 1)
    }

    @Test func continuousObservationsKeepHighWaterAcrossSmallResetJitter() {
        let result = history([sample(2, 50), sample(1.5, 49, reset: 86402), sample(1, 60)])
        #expect(result.points.map(\.remaining) == [50, 50, 40])
        #expect(Set(result.points.map(\.segment)).count == 1)
    }

    @Test func resetAndPlanChangesBreakTheLine() {
        let result = history([sample(2, 99, reset: -5400), sample(1, 2), sample(0.5, 1, plan: "plus")])
        #expect(result.points.map(\.remaining) == [1, 98, 99])
        #expect(Set(result.points.map(\.segment)).count == 3)
    }

    @Test func duplicateTimestampsAreStableAndDenseSamplesAreBounded() {
        let samples = (0..<1800).map { sample(Double($0) / 3600, 70) }
        let a = history(samples + [sample(0, 80)])
        let b = history(Array((samples + [sample(0, 80)]).reversed()))
        #expect(a == b)
        #expect(a.points.count <= 4)
        #expect(a.points.last?.remaining == 20)
        #expect(a.points.last?.date == now)
    }

    @Test func expiredObservationsDoNotInventPostResetUsage() {
        let result = history([sample(1, 40, reset: -7200)])
        #expect(result.points.isEmpty)
    }
}
