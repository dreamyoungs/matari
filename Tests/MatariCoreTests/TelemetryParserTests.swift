import Foundation
import Testing
@testable import MatariCore

struct TelemetryParserTests {
    @Test func parsesSessionMetadataWithoutRetainingOtherPayload() throws {
        let line = #"{"timestamp":"2026-09-18T01:02:03.456Z","type":"session_meta","payload":{"id":"session-1","timestamp":"2026-09-18T01:02:03.456Z","source":"cli","cli_version":"0.155.0","sensitive":"must not persist"}}"#.data(using: .utf8)!

        let parsed = TelemetryParser().parse(line: line, fileID: "fallback", byteOffset: 0)
        guard case let .sessionMeta(meta) = parsed else {
            Issue.record("Expected session metadata")
            return
        }
        #expect(meta.fileID == "session-1")
        #expect(meta.threadSource == .user)
        #expect(meta.cliVersion == "0.155.0")
    }

    @Test func parsesTokenAndDynamicQuotaBuckets() throws {
        let line = #"{"timestamp":"2026-09-18T01:02:03.456Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"last_token_usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":2,"reasoning_output_tokens":1,"total_tokens":12}},"rate_limits":{"limit_id":"codex","plan_type":"prolite","primary":{"used_percent":37,"window_minutes":300,"resets_at":1800000000},"secondary":{"used_percent":73,"window_minutes":10080,"resets_at":1800500000}}}}"#.data(using: .utf8)!

        let parsed = TelemetryParser().parse(line: line, fileID: "file-1", byteOffset: 128)
        guard case let .tokenCount(snapshot, quotas) = parsed else {
            Issue.record("Expected token count")
            return
        }
        #expect(snapshot.total.totalTokens == 120)
        #expect(snapshot.last.totalTokens == 12)
        #expect(quotas.map(\.windowMinutes) == [300, 10_080])
        #expect(quotas.map(\.usedPercent) == [37, 73])
    }

    @Test func rejectsNegativeTokenRecord() {
        let line = #"{"timestamp":"2026-09-18T01:02:03.456Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":-1,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":-1},"last_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":0}}}}"#.data(using: .utf8)!
        #expect(TelemetryParser().parse(line: line, fileID: "file", byteOffset: 0) == nil)
    }
}
