import Foundation

// 로컬 기록에 안정적인 기간 ID가 없어 최신 관측의 reset을 기준으로 비교한다.
// 60초는 앱의 허용폭이지 서버의 보장이 아니다. 연쇄적으로 결합하지 않는다.
enum QuotaPeriod {
    static func contains(reset candidate: Date, observedAt: Date, anchor: Date) -> Bool {
        abs(candidate.timeIntervalSince(anchor)) <= 60
            && observedAt < min(candidate, anchor)
    }
}

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
        // 이미 만료된 기간을 보고하는 지연 기록은 현재 버킷 구성도 되돌리지 못하게 한다.
        let valid = epochs.filter { $0.lastObservedAt < $0.key.resetsAt }
        guard let group = canonicalGroup(from: valid) else { return [] }
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
        guard var selected = candidates.max(by: { lhs, rhs in
            if lhs.lastObservedAt != rhs.lastObservedAt {
                return lhs.lastObservedAt < rhs.lastObservedAt
            }
            return lhs.key.resetsAt < rhs.key.resetsAt
        }) else { return nil }
        let samePeriod = candidates.filter {
            $0.planType == selected.planType
                && QuotaPeriod.contains(reset: $0.key.resetsAt,
                                        observedAt: $0.lastObservedAt, anchor: selected.key.resetsAt)
        }
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
