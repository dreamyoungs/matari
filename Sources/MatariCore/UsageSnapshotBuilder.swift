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

public struct QuotaMeasurement: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let consumedPercent: Double
}

public struct QuotaConsumptionCalculator: Sendable {
    public init() {}

    // 현재 초기화 구간 안의 실제 관측 두 점을 비교한다. 시작값을 0으로 추정하지 않는다.
    public func measurement(
        observations: [QuotaObservation],
        reset: Date,
        from start: Date,
        to end: Date
    ) -> QuotaMeasurement? {
        let samples = observations.filter {
            QuotaPeriod.contains(reset: $0.resetsAt, observedAt: $0.observedAt, anchor: reset)
                && $0.observedAt < end
        }.sorted { $0.observedAt < $1.observedAt }
        var highWater = 0.0
        var baseline: (Date, Double)?
        var last: (Date, Double)?
        let byTime = Dictionary(grouping: samples, by: \.observedAt)
        for time in byTime.keys.sorted() {
            let used = byTime[time]?.map(\.usedPercent).max() ?? 0
            highWater = max(highWater, used)
            guard time >= start else { continue }
            if baseline == nil { baseline = (time, highWater) }
            last = (time, highWater)
        }
        guard let baseline, let last, last.0 > baseline.0,
              last.1 - baseline.1 >= 1 else { return nil }
        return QuotaMeasurement(start: baseline.0, end: last.0,
                                consumedPercent: last.1 - baseline.1)
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
        let todayCost = try await store.costSummary(from: boundaries.todayStart, to: boundaries.end)
        let weekCost = try await store.costSummary(from: boundaries.weekStart, to: boundaries.end)
        let lastObservation = try await store.lastQuotaObservation()
        var histories: [QuotaHistory] = []
        for bucket in buckets {
            let key = bucket.epoch.key
            let observations = try await store.quotaObservations(limitID: key.limitID,
                windowMinutes: key.windowMinutes, overlapping: now.addingTimeInterval(-48 * 3600),
                through: boundaries.end)
            histories.append(QuotaHistory(observations: observations, limitID: key.limitID,
                windowMinutes: key.windowMinutes, now: now))
        }

        var todayPerPercent: Double?
        var weekPerPercent: Double?
        if let longTerm = buckets.filter({ $0.status == .current }).max(by: { $0.epoch.key.windowMinutes < $1.epoch.key.windowMinutes }) {
            let key = longTerm.epoch.key
            let calculator = QuotaConsumptionCalculator()
            let todayObservations = try await store.quotaObservations(
                limitID: key.limitID,
                windowMinutes: key.windowMinutes,
                overlapping: boundaries.todayStart,
                through: boundaries.end,
                planType: longTerm.epoch.planType
            )
            let weekObservations = try await store.quotaObservations(
                limitID: key.limitID,
                windowMinutes: key.windowMinutes,
                overlapping: boundaries.weekStart,
                through: boundaries.end,
                planType: longTerm.epoch.planType
            )
            if let interval = calculator.measurement(
                observations: todayObservations, reset: key.resetsAt,
                from: boundaries.todayStart, to: boundaries.end
            ) {
                let tokens = try await store.tokenTotal(
                    from: interval.start.addingTimeInterval(0.000001),
                    to: interval.end.addingTimeInterval(0.000001))
                todayPerPercent = Double(tokens) / interval.consumedPercent
            }
            if let interval = calculator.measurement(
                observations: weekObservations, reset: key.resetsAt,
                from: boundaries.weekStart, to: boundaries.end
            ) {
                let tokens = try await store.tokenTotal(
                    from: interval.start.addingTimeInterval(0.000001),
                    to: interval.end.addingTimeInterval(0.000001))
                weekPerPercent = Double(tokens) / interval.consumedPercent
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
            state: state,
            quotaHistories: histories,
            todayCost: todayCost,
            weekCost: weekCost
        )
    }
}
