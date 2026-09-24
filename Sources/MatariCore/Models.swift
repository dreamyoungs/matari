import Foundation

public enum ThreadSource: String, Sendable, Codable, Equatable {
    case user
    case subagent
    case agentCreated = "agent_created"
    case guardian
    case unknown

    public init(rawSource: String?) {
        guard let rawSource else {
            self = .unknown
            return
        }

        let normalized = rawSource.lowercased()
        if normalized.contains("subagent") {
            self = .subagent
        } else if normalized.contains("agent_created") {
            self = .agentCreated
        } else if normalized.contains("guardian") {
            self = .guardian
        } else if normalized.contains("user") || normalized.contains("cli") || normalized.contains("vscode") {
            self = .user
        } else {
            self = .unknown
        }
    }
}

public struct EventID: RawRepresentable, Hashable, Sendable, Codable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(fileID: String, ordinal: Int?, byteOffset: Int64, eventType: String) {
        if let ordinal {
            rawValue = "\(fileID):ordinal:\(ordinal)"
        } else {
            rawValue = "\(fileID):offset:\(byteOffset):\(eventType)"
        }
    }
}

public struct SessionDescriptor: Sendable, Equatable {
    public let fileID: String
    public let sessionID: String?
    public let threadSource: ThreadSource
    public let cliVersion: String?
    public let startedAt: Date?

    public init(
        fileID: String,
        sessionID: String?,
        threadSource: ThreadSource,
        cliVersion: String?,
        startedAt: Date?
    ) {
        self.fileID = fileID
        self.sessionID = sessionID
        self.threadSource = threadSource
        self.cliVersion = cliVersion
        self.startedAt = startedAt
    }
}

public struct TokenUsage: Sendable, Equatable, Codable {
    public var inputTokens: Int64
    public var cachedInputTokens: Int64
    public var cacheWriteInputTokens: Int64
    public var outputTokens: Int64
    public var reasoningOutputTokens: Int64
    public var totalTokens: Int64

    public static let zero = TokenUsage(
        inputTokens: 0,
        cachedInputTokens: 0,
        cacheWriteInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        totalTokens: 0
    )

    public init(
        inputTokens: Int64,
        cachedInputTokens: Int64,
        cacheWriteInputTokens: Int64,
        outputTokens: Int64,
        reasoningOutputTokens: Int64,
        totalTokens: Int64
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    public var isValid: Bool {
        inputTokens >= 0
            && cachedInputTokens >= 0
            && cacheWriteInputTokens >= 0
            && outputTokens >= 0
            && reasoningOutputTokens >= 0
            && totalTokens >= 0
    }

    public func subtractingClamped(_ previous: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: max(0, inputTokens - previous.inputTokens),
            cachedInputTokens: max(0, cachedInputTokens - previous.cachedInputTokens),
            cacheWriteInputTokens: max(0, cacheWriteInputTokens - previous.cacheWriteInputTokens),
            outputTokens: max(0, outputTokens - previous.outputTokens),
            reasoningOutputTokens: max(0, reasoningOutputTokens - previous.reasoningOutputTokens),
            totalTokens: max(0, totalTokens - previous.totalTokens)
        )
    }
}

public struct TokenSnapshot: Sendable, Equatable {
    public let eventID: EventID
    public let fileID: String
    public let observedAt: Date
    public let ordinal: Int?
    public let total: TokenUsage
    public let last: TokenUsage

    public init(
        eventID: EventID,
        fileID: String,
        observedAt: Date,
        ordinal: Int?,
        total: TokenUsage,
        last: TokenUsage
    ) {
        self.eventID = eventID
        self.fileID = fileID
        self.observedAt = observedAt
        self.ordinal = ordinal
        self.total = total
        self.last = last
    }
}

public struct QuotaSnapshot: Sendable, Equatable {
    public let eventID: EventID
    public let bucketIndex: Int
    public let observedAt: Date
    public let limitID: String
    public let planType: String?
    public let windowMinutes: Int
    public let usedPercent: Double
    public let resetsAt: Date

    public init(
        eventID: EventID,
        bucketIndex: Int,
        observedAt: Date,
        limitID: String,
        planType: String?,
        windowMinutes: Int,
        usedPercent: Double,
        resetsAt: Date
    ) {
        self.eventID = eventID
        self.bucketIndex = bucketIndex
        self.observedAt = observedAt
        self.limitID = limitID
        self.planType = planType
        self.windowMinutes = windowMinutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct TokenContribution: Sendable, Equatable {
    public let eventID: EventID
    public let fileID: String
    public let occurredAt: Date
    public let usage: TokenUsage
    public let source: ThreadSource

    public init(eventID: EventID, fileID: String, occurredAt: Date, usage: TokenUsage, source: ThreadSource) {
        self.eventID = eventID
        self.fileID = fileID
        self.occurredAt = occurredAt
        self.usage = usage
        self.source = source
    }
}

public struct QuotaEpochKey: Hashable, Sendable, Equatable {
    public let limitID: String
    public let windowMinutes: Int
    public let resetsAt: Date

    public init(limitID: String, windowMinutes: Int, resetsAt: Date) {
        self.limitID = limitID
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct QuotaEpoch: Sendable, Equatable {
    public let key: QuotaEpochKey
    public var planType: String?
    public var firstObservedAt: Date
    public var lastObservedAt: Date
    public var highWaterUsedPercent: Double

    public init(
        key: QuotaEpochKey,
        planType: String?,
        firstObservedAt: Date,
        lastObservedAt: Date,
        highWaterUsedPercent: Double
    ) {
        self.key = key
        self.planType = planType
        self.firstObservedAt = firstObservedAt
        self.lastObservedAt = lastObservedAt
        self.highWaterUsedPercent = highWaterUsedPercent
    }
}

public enum UsageDataState: Sendable, Equatable {
    case loading(hasCachedData: Bool)
    case ready
    case noSessionDirectory
    case noSessions
    case noQuota
    case waitingForPostResetSnapshot
    case inaccessiblePath
    case readError(recoverable: Bool)
}

public enum UsageBucketStatus: Sendable, Equatable {
    case current
    case waitingForPostResetSnapshot
}

public struct UsageBucket: Sendable, Equatable, Identifiable {
    public var id: QuotaEpochKey { epoch.key }
    public let epoch: QuotaEpoch
    public let remainingPercent: Int?
    public let status: UsageBucketStatus

    public init(epoch: QuotaEpoch, remainingPercent: Int?, status: UsageBucketStatus) {
        self.epoch = epoch
        self.remainingPercent = remainingPercent
        self.status = status
    }
}

public struct UsageSnapshot: Sendable, Equatable {
    public let quotaHistories: [QuotaHistory]

    public func quotaHistory(windowMinutes: Int?) -> QuotaHistory? {
        quotaHistories.first { $0.windowMinutes == windowMinutes }
            ?? quotaHistories.max { $0.windowMinutes < $1.windowMinutes }
    }
    public let buckets: [UsageBucket]
    public let todayTokens: Int64?
    public let weekTokens: Int64?
    public let todayTokensPerPercent: Double?
    public let weekTokensPerPercent: Double?
    public let lastQuotaObservation: Date?
    public let state: UsageDataState

    public init(
        buckets: [UsageBucket],
        todayTokens: Int64?,
        weekTokens: Int64?,
        todayTokensPerPercent: Double?,
        weekTokensPerPercent: Double?,
        lastQuotaObservation: Date?,
        state: UsageDataState,
        quotaHistories: [QuotaHistory] = []
    ) {
        self.buckets = buckets
        self.todayTokens = todayTokens
        self.weekTokens = weekTokens
        self.todayTokensPerPercent = todayTokensPerPercent
        self.weekTokensPerPercent = weekTokensPerPercent
        self.lastQuotaObservation = lastQuotaObservation
        self.state = state
        self.quotaHistories = quotaHistories
    }
}

public struct FileCursor: Sendable, Equatable {
    public let fileID: String
    public var currentPath: String
    public var byteOffset: Int64
    public var lastTotalTokens: TokenUsage?
    public var fileSize: Int64
    public var modifiedAt: Date
    public var cliVersion: String?
    public var threadSource: ThreadSource

    public init(
        fileID: String,
        currentPath: String,
        byteOffset: Int64,
        lastTotalTokens: TokenUsage?,
        fileSize: Int64,
        modifiedAt: Date,
        cliVersion: String?,
        threadSource: ThreadSource
    ) {
        self.fileID = fileID
        self.currentPath = currentPath
        self.byteOffset = byteOffset
        self.lastTotalTokens = lastTotalTokens
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.cliVersion = cliVersion
        self.threadSource = threadSource
    }
}

public struct QuotaObservation: Sendable, Equatable {
    public let planType: String?
    public let observedAt: Date
    public let limitID: String
    public let windowMinutes: Int
    public let usedPercent: Double
    public let resetsAt: Date

    public init(observedAt: Date, limitID: String, windowMinutes: Int, usedPercent: Double, resetsAt: Date, planType: String? = nil) {
        self.planType = planType
        self.observedAt = observedAt
        self.limitID = limitID
        self.windowMinutes = windowMinutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct QuotaHistory: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public let date: Date
        public let remaining: Double
        public let segment: Int
    }
    public let start: Date
    public let end: Date
    public let windowMinutes: Int
    public let points: [Point]

    public init(observations: [QuotaObservation], limitID: String, windowMinutes: Int, now: Date) {
        let start = now.addingTimeInterval(-48 * 3600)
        self.start = start
        end = now
        self.windowMinutes = windowMinutes
        let samples = observations.filter {
            $0.limitID == limitID && $0.windowMinutes == windowMinutes
                && $0.observedAt >= start && $0.observedAt <= now && $0.observedAt < $0.resetsAt
                && $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
        }.sorted {
            if $0.observedAt != $1.observedAt { return $0.observedAt < $1.observedAt }
            if $0.resetsAt != $1.resetsAt { return $0.resetsAt < $1.resetsAt }
            return $0.usedPercent < $1.usedPercent
        }
        // One deterministic observation per timestamp, preferring the newer reset.
        let grouped = Dictionary(grouping: samples, by: \.observedAt)
        let unique = grouped.keys.sorted().compactMap { grouped[$0]?.last }
        var anchor: QuotaObservation?
        var previous: Date?
        var highWater = 0.0
        var segment = 0
        var output: [Point] = []
        for sample in unique {
            let samePeriod = anchor.map {
                $0.planType == sample.planType
                    && QuotaPeriod.contains(reset: sample.resetsAt, observedAt: sample.observedAt, anchor: $0.resetsAt)
            } ?? false
            if !samePeriod {
                anchor = sample
                highWater = 0
            }
            if !samePeriod || previous.map({ sample.observedAt.timeIntervalSince($0) > 3600 }) == true {
                segment += 1
            }
            highWater = max(highWater, sample.usedPercent)
            let point = Point(date: sample.observedAt, remaining: 100 - highWater, segment: segment)
            // Keep first and last observations in each half-hour bin, never bridge segments.
            if output.count >= 2,
               output[output.count - 2].segment == segment,
               Int(output[output.count - 2].date.timeIntervalSince1970 / 1800)
                    == Int(point.date.timeIntervalSince1970 / 1800) {
                output[output.count - 1] = point
            } else {
                output.append(point)
            }
            previous = sample.observedAt
        }
        points = output
    }
}
