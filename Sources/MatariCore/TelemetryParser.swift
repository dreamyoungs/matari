import Foundation

public enum ParsedTelemetryEvent: Sendable, Equatable {
    case sessionMeta(SessionDescriptor)
    case tokenCount(snapshot: TokenSnapshot, quotas: [QuotaSnapshot])
}

public struct TelemetryParser: Sendable {
    public init() {}

    public func parse(line: Data, fileID: String, byteOffset: Int64) -> ParsedTelemetryEvent? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line),
            let envelope = object as? [String: Any],
            let type = envelope["type"] as? String,
            let payload = envelope["payload"] as? [String: Any]
        else {
            return nil
        }

        switch type {
        case "session_meta":
            return parseSessionMeta(payload: payload, fallbackFileID: fileID)
        case "event_msg":
            guard payload["type"] as? String == "token_count" else { return nil }
            return parseTokenCount(
                envelope: envelope,
                payload: payload,
                fileID: fileID,
                byteOffset: byteOffset
            )
        default:
            return nil
        }
    }

    private func parseSessionMeta(payload: [String: Any], fallbackFileID: String) -> ParsedTelemetryEvent? {
        let sessionID = payload["id"] as? String
        let resolvedFileID = sessionID?.isEmpty == false ? sessionID! : fallbackFileID
        let timestamp = Self.parseDate(payload["timestamp"])
        let source = Self.stringValue(payload["source"])

        return .sessionMeta(
            SessionDescriptor(
                fileID: resolvedFileID,
                sessionID: sessionID,
                threadSource: ThreadSource(rawSource: source),
                cliVersion: payload["cli_version"] as? String,
                startedAt: timestamp
            )
        )
    }

    private func parseTokenCount(
        envelope: [String: Any],
        payload: [String: Any],
        fileID: String,
        byteOffset: Int64
    ) -> ParsedTelemetryEvent? {
        guard
            let observedAt = Self.parseDate(envelope["timestamp"] ?? payload["timestamp"]),
            let info = payload["info"] as? [String: Any],
            let totalObject = info["total_token_usage"] as? [String: Any],
            let lastObject = info["last_token_usage"] as? [String: Any],
            let total = Self.parseTokenUsage(totalObject),
            let last = Self.parseTokenUsage(lastObject)
        else {
            return nil
        }

        let ordinal = Self.intValue(envelope["ordinal"] ?? payload["ordinal"]).map(Int.init)
        let eventID = EventID(fileID: fileID, ordinal: ordinal, byteOffset: byteOffset, eventType: "token_count")
        let snapshot = TokenSnapshot(
            eventID: eventID,
            fileID: fileID,
            observedAt: observedAt,
            ordinal: ordinal,
            total: total,
            last: last
        )

        return .tokenCount(
            snapshot: snapshot,
            quotas: Self.parseQuotas(payload["rate_limits"], eventID: eventID, observedAt: observedAt)
        )
    }

    private static func parseTokenUsage(_ object: [String: Any]) -> TokenUsage? {
        guard
            let input = intValue(object["input_tokens"]),
            let cached = intValue(object["cached_input_tokens"]),
            let output = intValue(object["output_tokens"]),
            let reasoning = intValue(object["reasoning_output_tokens"]),
            let total = intValue(object["total_tokens"])
        else {
            return nil
        }

        let usage = TokenUsage(
            inputTokens: input,
            cachedInputTokens: cached,
            cacheWriteInputTokens: intValue(object["cache_write_input_tokens"]) ?? 0,
            outputTokens: output,
            reasoningOutputTokens: reasoning,
            totalTokens: total
        )
        return usage.isValid ? usage : nil
    }

    private static func parseQuotas(_ value: Any?, eventID: EventID, observedAt: Date) -> [QuotaSnapshot] {
        guard let limits = value as? [String: Any] else { return [] }
        let limitID = (limits["limit_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let limitID, !limitID.isEmpty else { return [] }
        let planType = limits["plan_type"] as? String

        return ["primary", "secondary"].enumerated().compactMap { index, key in
            guard
                let bucket = limits[key] as? [String: Any],
                let window = intValue(bucket["window_minutes"]), window > 0,
                let used = doubleValue(bucket["used_percent"]), (0 ... 100).contains(used),
                let resetSeconds = doubleValue(bucket["resets_at"]), resetSeconds > 0
            else {
                return nil
            }

            return QuotaSnapshot(
                eventID: eventID,
                bucketIndex: index,
                observedAt: observedAt,
                limitID: limitID,
                planType: planType,
                windowMinutes: Int(window),
                usedPercent: used,
                resetsAt: Date(timeIntervalSince1970: resetSeconds)
            )
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let dictionary = value as? [String: Any] else { return nil }
        return dictionary["type"] as? String
            ?? dictionary["kind"] as? String
            ?? dictionary.keys.sorted().first
    }

    private static func intValue(_ value: Any?) -> Int64? {
        switch value {
        case let value as Int64: value
        case let value as Int: Int64(value)
        case let value as NSNumber: value.int64Value
        default: nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        default: nil
        }
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let seconds = doubleValue(value), seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
