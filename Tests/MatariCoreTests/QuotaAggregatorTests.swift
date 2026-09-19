import Foundation
import Testing
@testable import MatariCore

struct QuotaAggregatorTests {
    @Test func oneSecondResetDifferenceUsesLatestObservationAndSharedHighWater() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(600)
        let old = epoch(limit: "codex", window: 10_080, used: 0,
                        observed: now.addingTimeInterval(-60), reset: reset.addingTimeInterval(1), plan: "pro")
        let fresh = epoch(limit: "codex", window: 10_080, used: 1,
                          observed: now, reset: reset, plan: "pro")
        for records in [[old, fresh], [fresh, old]] {
            let buckets = QuotaAggregator().canonicalBuckets(from: records, now: now)
            #expect(buckets.map(\.remainingPercent) == [99])
            #expect(buckets.first?.epoch.key.resetsAt == reset)
        }
        let lower = epoch(limit: "codex", window: 10_080, used: 0,
                          observed: now.addingTimeInterval(1), reset: reset.addingTimeInterval(1), plan: "pro")
        let buckets = QuotaAggregator().canonicalBuckets(from: [fresh, lower], now: now)
        #expect(buckets.map(\.remainingPercent) == [99])
    }

    @Test func delayedPreviousPeriodDoesNotOverrideNewPeriod() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = epoch(limit: "codex", window: 10_080, used: 99,
                             observed: now, reset: now.addingTimeInterval(-60), plan: "pro")
        let current = epoch(limit: "codex", window: 10_080, used: 2,
                            observed: now.addingTimeInterval(-10), reset: now.addingTimeInterval(604_800), plan: "pro")
        let buckets = QuotaAggregator().canonicalBuckets(from: [previous, current], now: now)
        #expect(buckets.map(\.remainingPercent) == [98])
    }

    @Test func planChangeRemovesHistoricalShortWindowEvenBeforeItsReset() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldShort = epoch(limit: "codex", window: 300, used: 40,
                             observed: now.addingTimeInterval(-60),
                             reset: now.addingTimeInterval(600), plan: "plus")
        let weekly = epoch(limit: "codex", window: 10_080, used: 2,
                           observed: now, reset: now.addingTimeInterval(604_800), plan: "pro")
        let buckets = QuotaAggregator().canonicalBuckets(from: [oldShort, weekly], now: now)
        #expect(buckets.map { $0.epoch.key.windowMinutes } == [10_080])
        #expect(buckets.map(\.remainingPercent) == [98])
        let expired = QuotaAggregator().canonicalBuckets(
            from: [oldShort, weekly], now: now.addingTimeInterval(604_801))
        #expect(expired.count == 1)
        #expect(expired[0].status == .waitingForPostResetSnapshot)
    }

    @Test func newDualWindowSnapshotRestoresShortWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let buckets = QuotaAggregator().canonicalBuckets(from: [
            epoch(limit: "codex", window: 300, used: 10, observed: now,
                  reset: now.addingTimeInterval(600), plan: "plus"),
            epoch(limit: "codex", window: 10_080, used: 20, observed: now,
                  reset: now.addingTimeInterval(604_800), plan: "plus")
        ], now: now)
        #expect(buckets.map { $0.epoch.key.windowMinutes } == [300, 10_080])
    }

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
