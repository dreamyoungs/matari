import Foundation
import Testing
@testable import MatariCore

struct TelemetryCoordinatorTests {
    @Test func scansAppendResumesAndTracksArchiveMoveWithoutDuplication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions/2026/09/18")
        let archived = root.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout.jsonl")
        let observed = "2026-09-18T01:00:00.000Z"
        let meta = #"{"timestamp":"2026-09-18T00:59:00.000Z","type":"session_meta","payload":{"id":"session-1","timestamp":"2026-09-18T00:59:00.000Z","source":"cli","cli_version":"0.155.0"}}"#
        let first = tokenLine(timestamp: observed, total: 1_000, last: 25, used: 10)
        try Data("\(meta)\n\(first)\n".utf8).write(to: file)

        let store = try SQLiteStore(url: root.appendingPathComponent("store/matari.sqlite"))
        let coordinator = TelemetryCoordinator(store: store)
        let paths = CodexPaths(home: root, sessionDirectories: [root.appendingPathComponent("sessions"), archived])
        let rangeStart = Date(timeIntervalSince1970: 0)
        let rangeEnd = Date(timeIntervalSince1970: 2_000_000_000)

        let initial = await coordinator.scan(paths: paths)
        #expect(initial.failedFiles == 0)
        #expect(try await store.tokenTotal(from: rangeStart, to: rangeEnd) == 25)

        _ = await coordinator.scan(paths: paths)
        #expect(try await store.tokenTotal(from: rangeStart, to: rangeEnd) == 25)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        let second = tokenLine(timestamp: "2026-09-18T01:01:00.000Z", total: 1_075, last: 75, used: 11)
        let split = second.index(second.startIndex, offsetBy: second.count / 2)
        try handle.write(contentsOf: Data(second[..<split].utf8))
        try handle.close()
        _ = await coordinator.scan(paths: paths)
        #expect(try await store.tokenTotal(from: rangeStart, to: rangeEnd) == 25)

        let append = try FileHandle(forWritingTo: file)
        try append.seekToEnd()
        try append.write(contentsOf: Data("\(second[split...])\n".utf8))
        try append.close()
        _ = await coordinator.scan(paths: paths)
        #expect(try await store.tokenTotal(from: rangeStart, to: rangeEnd) == 100)

        let archivedFile = archived.appendingPathComponent("rollout.jsonl")
        try FileManager.default.moveItem(at: file, to: archivedFile)
        _ = await coordinator.scan(paths: paths)
        #expect(try await store.tokenTotal(from: rangeStart, to: rangeEnd) == 100)
        let movedCursor = try await store.cursor(fileID: "session-1")
        #expect(
            movedCursor.map { URL(fileURLWithPath: $0.currentPath).standardizedFileURL }
                == archivedFile.standardizedFileURL
        )
    }

    private func tokenLine(timestamp: String, total: Int, last: Int, used: Int) -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(total),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\#(total)},"last_token_usage":{"input_tokens":\#(last),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\#(last)}},"rate_limits":{"limit_id":"codex","plan_type":"plus","primary":{"used_percent":\#(used),"window_minutes":300,"resets_at":1800100000}}}}"#
    }
}
