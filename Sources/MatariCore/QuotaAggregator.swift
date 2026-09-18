import Foundation

public struct QuotaAggregator: Sendable {
    public init() {}

    public func applying(_ snapshot: QuotaSnapshot, to existing: QuotaEpoch?) -> QuotaEpoch {
        let key = QuotaEpochKey(
            limitID: snapshot.limitID,
            windowMinutes: snapshot.windowMinutes,
            resetsAt: snapshot.resetsAt
        )

        guard var epoch = existing else {
            return QuotaEpoch(
                key: key,
                planType: snapshot.planType,
                firstObservedAt: snapshot.observedAt,
                lastObservedAt: snapshot.observedAt,
                highWaterUsedPercent: snapshot.usedPercent
            )
        }

        precondition(epoch.key == key)
        epoch.planType = snapshot.planType ?? epoch.planType
        epoch.firstObservedAt = min(epoch.firstObservedAt, snapshot.observedAt)
        epoch.lastObservedAt = max(epoch.lastObservedAt, snapshot.observedAt)
        epoch.highWaterUsedPercent = max(epoch.highWaterUsedPercent, snapshot.usedPercent)
        return epoch
    }

    public func canonicalBuckets(from epochs: [QuotaEpoch], now: Date) -> [UsageBucket] {
        guard let group = canonicalGroup(from: epochs) else { return [] }

        let latestPerWindow = Dictionary(grouping: group, by: { $0.key.windowMinutes })
            .compactMap { _, candidates in
                candidates.max { lhs, rhs in
                    if lhs.key.resetsAt != rhs.key.resetsAt {
                        return lhs.key.resetsAt < rhs.key.resetsAt
                    }
                    return lhs.lastObservedAt < rhs.lastObservedAt
                }
            }
            .sorted { $0.key.windowMinutes < $1.key.windowMinutes }

        return latestPerWindow.map { epoch in
            if epoch.key.resetsAt <= now {
                return UsageBucket(epoch: epoch, remainingPercent: nil, status: .waitingForPostResetSnapshot)
            }
            let remaining = Int((100 - epoch.highWaterUsedPercent).rounded())
            return UsageBucket(epoch: epoch, remainingPercent: max(0, min(100, remaining)), status: .current)
        }
    }

    private func canonicalGroup(from epochs: [QuotaEpoch]) -> [QuotaEpoch]? {
        let grouped = Dictionary(grouping: epochs, by: { $0.key.limitID })
        if let codex = grouped["codex"], !codex.isEmpty {
            return codex
        }

        return grouped.values
            .filter { group in group.contains(where: { $0.planType != nil }) }
            .max { lhs, rhs in
                (lhs.map(\.lastObservedAt).max() ?? .distantPast)
                    < (rhs.map(\.lastObservedAt).max() ?? .distantPast)
            }
    }
}
