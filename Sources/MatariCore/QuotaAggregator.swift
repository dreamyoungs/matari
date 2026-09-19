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
        guard let latestObservation = group.map(\.lastObservedAt).max() else { return [] }
        // 동일 스냅샷의 버킷은 관측 시각을 공유한다. 최신 구성에서 빠진 과거 버킷은 숨긴다.
        let activeWindows = Set(group.filter {
            $0.lastObservedAt == latestObservation
        }.map { $0.key.windowMinutes })

        let latestPerWindow = Dictionary(grouping: group.filter {
            activeWindows.contains($0.key.windowMinutes)
        }, by: { $0.key.windowMinutes })
            .compactMap { _, candidates in
                Self.currentEpoch(from: candidates)
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

    private static func currentEpoch(from candidates: [QuotaEpoch]) -> QuotaEpoch? {
        guard let latestReset = candidates.map(\.key.resetsAt).max() else { return nil }
        // 관측된 1초 기록 차이만 같은 기간으로 묶고, 연쇄적으로 다른 기간까지 합치지 않는다.
        let samePeriod = candidates.filter {
            latestReset.timeIntervalSince($0.key.resetsAt) <= 1
        }
        guard var selected = samePeriod.max(by: { lhs, rhs in
            if lhs.lastObservedAt != rhs.lastObservedAt {
                return lhs.lastObservedAt < rhs.lastObservedAt
            }
            return lhs.key.resetsAt < rhs.key.resetsAt
        }) else { return nil }
        selected.highWaterUsedPercent = samePeriod.map(\.highWaterUsedPercent).max() ?? selected.highWaterUsedPercent
        selected.firstObservedAt = samePeriod.map(\.firstObservedAt).min() ?? selected.firstObservedAt
        return selected
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
