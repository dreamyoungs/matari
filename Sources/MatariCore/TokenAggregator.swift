import Foundation

public struct TokenDeltaResult: Sendable, Equatable {
    public let contribution: TokenUsage
    public let nextTotal: TokenUsage
    public let rebased: Bool

    public init(contribution: TokenUsage, nextTotal: TokenUsage, rebased: Bool) {
        self.contribution = contribution
        self.nextTotal = nextTotal
        self.rebased = rebased
    }
}

public struct TokenAggregator: Sendable {
    public init() {}

    public func delta(for snapshot: TokenSnapshot, previousTotal: TokenUsage?) -> TokenDeltaResult {
        guard let previousTotal else {
            return TokenDeltaResult(
                contribution: snapshot.last,
                nextTotal: snapshot.total,
                rebased: false
            )
        }

        if snapshot.total.totalTokens > previousTotal.totalTokens {
            return TokenDeltaResult(
                contribution: snapshot.total.subtractingClamped(previousTotal),
                nextTotal: snapshot.total,
                rebased: false
            )
        }

        if snapshot.total.totalTokens == previousTotal.totalTokens {
            return TokenDeltaResult(contribution: .zero, nextTotal: snapshot.total, rebased: false)
        }

        return TokenDeltaResult(
            contribution: snapshot.last.totalTokens == 0 ? .zero : snapshot.last,
            nextTotal: snapshot.total,
            rebased: true
        )
    }
}
