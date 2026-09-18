import Foundation

public struct UsagePeriodBoundaries: Sendable, Equatable {
    public let todayStart: Date
    public let weekStart: Date
    public let end: Date

    public init(todayStart: Date, weekStart: Date, end: Date) {
        self.todayStart = todayStart
        self.weekStart = weekStart
        self.end = end
    }

    public static func korean(now: Date) -> UsagePeriodBoundaries {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 1
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let week = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today)!
        return UsagePeriodBoundaries(todayStart: today, weekStart: week, end: now.addingTimeInterval(0.001))
    }
}

public struct QuotaConsumptionCalculator: Sendable {
    public init() {}

    public func consumedPercent(
        observations: [QuotaObservation],
        from start: Date,
        to end: Date
    ) -> Double? {
        guard start < end, !observations.isEmpty else { return nil }
        let grouped = Dictionary(grouping: observations, by: \.resetsAt)
        let resetTimes = grouped.keys.sorted()
        var total = 0.0
        var evaluatedAnyEpoch = false

        for (index, resetAt) in resetTimes.enumerated() {
            guard resetAt > start else { continue }
            let epochStart = index > 0 ? resetTimes[index - 1] : nil
            guard epochStart == nil || epochStart! < end else { continue }
            let samples = (grouped[resetAt] ?? []).sorted { $0.observedAt < $1.observedAt }
            let segmentEnd = min(end, resetAt)
            let samplesThroughEnd = samples.filter { $0.observedAt < segmentEnd }
            guard let highAtEnd = samplesThroughEnd.map(\.usedPercent).max() else { continue }

            let baseline: Double
            if let epochStart, epochStart >= start {
                baseline = 0
            } else if let observedBaseline = samples
                .filter({ $0.observedAt <= start })
                .map(\.usedPercent)
                .max() {
                baseline = observedBaseline
            } else {
                return nil
            }

            total += max(0, highAtEnd - baseline)
            evaluatedAnyEpoch = true
        }

        return evaluatedAnyEpoch ? total : nil
    }
}

public struct UsageSnapshotBuilder: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func build(now: Date = Date(), stateHint: UsageDataState = .ready) async throws -> UsageSnapshot {
        let boundaries = UsagePeriodBoundaries.korean(now: now)
        let epochs = try await store.quotaEpochs()
        let buckets = QuotaAggregator().canonicalBuckets(from: epochs, now: now)
        let todayTokens = try await store.tokenTotal(from: boundaries.todayStart, to: boundaries.end)
        let weekTokens = try await store.tokenTotal(from: boundaries.weekStart, to: boundaries.end)
        let lastObservation = try await store.lastQuotaObservation()

        var todayPerPercent: Double?
        var weekPerPercent: Double?
        if let longTerm = buckets.max(by: { $0.epoch.key.windowMinutes < $1.epoch.key.windowMinutes }) {
            let key = longTerm.epoch.key
            let calculator = QuotaConsumptionCalculator()
            let todayObservations = try await store.quotaObservations(
                limitID: key.limitID,
                windowMinutes: key.windowMinutes,
                overlapping: boundaries.todayStart,
                through: boundaries.end
            )
            let weekObservations = try await store.quotaObservations(
                limitID: key.limitID,
                windowMinutes: key.windowMinutes,
                overlapping: boundaries.weekStart,
                through: boundaries.end
            )
            if let used = calculator.consumedPercent(
                observations: todayObservations,
                from: boundaries.todayStart,
                to: boundaries.end
            ), used >= 1 {
                todayPerPercent = Double(todayTokens) / used
            }
            if let used = calculator.consumedPercent(
                observations: weekObservations,
                from: boundaries.weekStart,
                to: boundaries.end
            ), used >= 1 {
                weekPerPercent = Double(weekTokens) / used
            }
        }

        let state: UsageDataState
        if stateHint != .ready {
            state = stateHint
        } else if buckets.isEmpty {
            state = .noQuota
        } else if buckets.allSatisfy({ $0.status == .waitingForPostResetSnapshot }) {
            state = .waitingForPostResetSnapshot
        } else {
            state = .ready
        }

        return UsageSnapshot(
            buckets: buckets,
            todayTokens: todayTokens,
            weekTokens: weekTokens,
            todayTokensPerPercent: todayPerPercent,
            weekTokensPerPercent: weekPerPercent,
            lastQuotaObservation: lastObservation,
            state: state
        )
    }
}
