import Foundation
import Testing
@testable import MatariCore

struct UsagePresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func normalStateShowsAllCurrentBucketsInOrder() {
        let presentation = UsagePresentation.make(
            snapshot: snapshot(buckets: [bucket(window: 300, remaining: 63), bucket(window: 10_080, remaining: 27)]),
            isLoading: false,
            now: now
        )
        #expect(presentation.menuBarIndicator == .percentages([63, 27]))
    }

    @Test func singleBucketShowsOnlyOnePercentage() {
        let presentation = UsagePresentation.make(
            snapshot: snapshot(buckets: [bucket(window: 10_080, remaining: 27)]),
            isLoading: false,
            now: now
        )
        #expect(presentation.menuBarIndicator == .percentages([27]))
    }

    @Test func missingQuotaAndPostResetWaitingDoNotInventPercentages() {
        let noQuota = UsagePresentation.make(
            snapshot: snapshot(buckets: [], state: .noQuota),
            isLoading: false,
            now: now
        )
        let waiting = UsagePresentation.make(
            snapshot: snapshot(buckets: [waitingBucket(window: 300)], state: .waitingForPostResetSnapshot),
            isLoading: false,
            now: now
        )
        #expect(noQuota.menuBarIndicator == .unavailable)
        #expect(waiting.menuBarIndicator == .unavailable)
    }

    @Test func pathAndReadErrorsUseErrorIndicator() {
        for state in [UsageDataState.noSessionDirectory, .inaccessiblePath, .readError(recoverable: true)] {
            let presentation = UsagePresentation.make(
                snapshot: snapshot(buckets: [], state: state),
                isLoading: false,
                now: now
            )
            #expect(presentation.menuBarIndicator == .error)
        }
    }

    @Test func inactivityKeepsPercentageAndExplainsLastObservation() {
        let observation = now.addingTimeInterval(-2 * 3_600)
        let presentation = UsagePresentation.make(
            snapshot: snapshot(buckets: [bucket(window: 10_080, remaining: 42)], observation: observation),
            isLoading: false,
            now: now
        )
        #expect(presentation.menuBarIndicator == .percentages([42]))
        #expect(presentation.footerText == "2시간 전 · Codex 비활성")
    }

    @Test func firstLoadingStateShowsEllipsis() {
        let presentation = UsagePresentation.make(
            snapshot: snapshot(buckets: [], state: .loading(hasCachedData: false), observation: nil),
            isLoading: true,
            now: now
        )
        #expect(presentation.menuBarIndicator == .loading)
    }

    private func snapshot(
        buckets: [UsageBucket],
        state: UsageDataState = .ready,
        observation: Date? = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> UsageSnapshot {
        UsageSnapshot(
            buckets: buckets,
            todayTokens: 100,
            weekTokens: 200,
            todayTokensPerPercent: nil,
            weekTokensPerPercent: nil,
            lastQuotaObservation: observation,
            state: state
        )
    }

    private func bucket(window: Int, remaining: Int) -> UsageBucket {
        UsageBucket(
            epoch: epoch(window: window),
            remainingPercent: remaining,
            status: .current
        )
    }

    private func waitingBucket(window: Int) -> UsageBucket {
        UsageBucket(
            epoch: epoch(window: window),
            remainingPercent: nil,
            status: .waitingForPostResetSnapshot
        )
    }

    private func epoch(window: Int) -> QuotaEpoch {
        QuotaEpoch(
            key: QuotaEpochKey(limitID: "codex", windowMinutes: window, resetsAt: now.addingTimeInterval(3_600)),
            planType: "plus",
            firstObservedAt: now.addingTimeInterval(-60),
            lastObservedAt: now,
            highWaterUsedPercent: 50
        )
    }
}
