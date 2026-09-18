import Foundation
import Testing
@testable import MatariCore

struct JSONLStreamReaderTests {
    @Test func returnsOnlyCompleteLinesAndResumesPartialLine() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        defer { try? FileManager.default.removeItem(at: temporary) }

        try Data("one\ntwo\npar".utf8).write(to: temporary)
        let reader = JSONLStreamReader(chunkSize: 3)
        let first = try reader.read(url: temporary, from: 0)
        #expect(first.lines.map { String(decoding: $0.data, as: UTF8.self) } == ["one", "two"])
        #expect(first.lines.map(\.byteOffset) == [0, 4])
        #expect(first.nextByteOffset == 8)
        #expect(first.hasPartialLine)

        let handle = try FileHandle(forWritingTo: temporary)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("tial\n".utf8))
        try handle.close()

        let second = try reader.read(url: temporary, from: first.nextByteOffset)
        #expect(second.lines.map { String(decoding: $0.data, as: UTF8.self) } == ["partial"])
        #expect(second.nextByteOffset == 16)
        #expect(!second.hasPartialLine)
    }

    @Test func discoversActiveAndArchivedJSONLFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions/2026/09/18")
        let archived = root.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sessions.appendingPathComponent("a.jsonl").path, contents: Data())
        FileManager.default.createFile(atPath: archived.appendingPathComponent("b.jsonl").path, contents: Data())
        FileManager.default.createFile(atPath: sessions.appendingPathComponent("ignored.txt").path, contents: Data())

        let paths = CodexPaths(home: root, sessionDirectories: [root.appendingPathComponent("sessions"), archived])
        let files = try SessionFileScanner().files(in: paths)
        #expect(files.map(\.lastPathComponent) == ["b.jsonl", "a.jsonl"] || files.map(\.lastPathComponent) == ["a.jsonl", "b.jsonl"])
        #expect(files.count == 2)
    }
}
