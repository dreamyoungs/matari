import Foundation
import Testing
@testable import MatariCore

struct TokenAggregatorTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func firstSnapshotUsesLastNotInheritedTotal() {
        let result = TokenAggregator().delta(
            for: snapshot(total: usage(1_000), last: usage(25)),
            previousTotal: nil
        )
        #expect(result.contribution.totalTokens == 25)
        #expect(!result.rebased)
    }

    @Test func increasingCounterUsesDifference() {
        let result = TokenAggregator().delta(
            for: snapshot(total: usage(1_075), last: usage(75)),
            previousTotal: usage(1_000)
        )
        #expect(result.contribution.totalTokens == 75)
    }

    @Test func equalCounterContributesNothing() {
        let result = TokenAggregator().delta(
            for: snapshot(total: usage(1_000), last: usage(99)),
            previousTotal: usage(1_000)
        )
        #expect(result.contribution == .zero)
    }

    @Test func decreaseWithZeroLastIsBaselineRebase() {
        let result = TokenAggregator().delta(
            for: snapshot(total: usage(100), last: .zero),
            previousTotal: usage(1_000)
        )
        #expect(result.contribution == .zero)
        #expect(result.rebased)
    }

    @Test func decreaseWithLastStartsNewEpoch() {
        let result = TokenAggregator().delta(
            for: snapshot(total: usage(100), last: usage(15)),
            previousTotal: usage(1_000)
        )
        #expect(result.contribution.totalTokens == 15)
        #expect(result.rebased)
    }

    private func snapshot(total: TokenUsage, last: TokenUsage) -> TokenSnapshot {
        TokenSnapshot(
            eventID: EventID(rawValue: UUID().uuidString),
            fileID: "file",
            observedAt: date,
            ordinal: nil,
            total: total,
            last: last
        )
    }

    private func usage(_ total: Int64) -> TokenUsage {
        TokenUsage(
            inputTokens: total,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            reasoningOutputTokens: 0,
            totalTokens: total
        )
    }
}
