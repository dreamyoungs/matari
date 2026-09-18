import Foundation
import Testing
@testable import MatariCore

struct QuotaAggregatorTests {
    @Test func highWaterDoesNotRollBackOnStaleConcurrentSnapshot() {
        let reset = Date(timeIntervalSince1970: 1_800_100_000)
        let first = quota(used: 63, observed: 1_800_000_100, reset: reset)
        let stale = quota(used: 61, observed: 1_800_000_200, reset: reset)
        let aggregator = QuotaAggregator()

        let epoch = aggregator.applying(stale, to: aggregator.applying(first, to: nil))
        #expect(epoch.highWaterUsedPercent == 63)
        #expect(epoch.lastObservedAt == stale.observedAt)
    }

    @Test func choosesCodexGroupAndSortsDynamicWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = Date(timeIntervalSince1970: 1_800_100_000)
        let epochs = [
            epoch(limit: "other", window: 60, used: 1, observed: now, reset: reset, plan: "plus"),
            epoch(limit: "codex", window: 10_080, used: 73, observed: now, reset: reset, plan: "prolite"),
            epoch(limit: "codex", window: 300, used: 37, observed: now, reset: reset, plan: "prolite")
        ]

        let buckets = QuotaAggregator().canonicalBuckets(from: epochs, now: now)
        #expect(buckets.map { $0.epoch.key.windowMinutes } == [300, 10_080])
        #expect(buckets.map(\.remainingPercent) == [63, 27])
    }

    @Test func expiredLatestEpochWaitsInsteadOfShowingOneHundredPercent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = epoch(
            limit: "codex",
            window: 300,
            used: 90,
            observed: now.addingTimeInterval(-600),
            reset: now.addingTimeInterval(-1),
            plan: "plus"
        )
        let buckets = QuotaAggregator().canonicalBuckets(from: [expired], now: now)
        #expect(buckets.count == 1)
        #expect(buckets[0].remainingPercent == nil)
        #expect(buckets[0].status == .waitingForPostResetSnapshot)
    }

    private func quota(used: Double, observed: TimeInterval, reset: Date) -> QuotaSnapshot {
        QuotaSnapshot(
            eventID: EventID(rawValue: UUID().uuidString),
            bucketIndex: 0,
            observedAt: Date(timeIntervalSince1970: observed),
            limitID: "codex",
            planType: "plus",
            windowMinutes: 300,
            usedPercent: used,
            resetsAt: reset
        )
    }

    private func epoch(
        limit: String,
        window: Int,
        used: Double,
        observed: Date,
        reset: Date,
        plan: String?
    ) -> QuotaEpoch {
        QuotaEpoch(
            key: QuotaEpochKey(limitID: limit, windowMinutes: window, resetsAt: reset),
            planType: plan,
            firstObservedAt: observed,
            lastObservedAt: observed,
            highWaterUsedPercent: used
        )
    }
}
