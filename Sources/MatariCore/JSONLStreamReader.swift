import Foundation

public struct JSONLLine: Sendable, Equatable {
    public let byteOffset: Int64
    public let data: Data

    public init(byteOffset: Int64, data: Data) {
        self.byteOffset = byteOffset
        self.data = data
    }
}

public struct JSONLReadResult: Sendable, Equatable {
    public let lines: [JSONLLine]
    public let nextByteOffset: Int64
    public let hasPartialLine: Bool

    public init(lines: [JSONLLine], nextByteOffset: Int64, hasPartialLine: Bool) {
        self.lines = lines
        self.nextByteOffset = nextByteOffset
        self.hasPartialLine = hasPartialLine
    }
}

public struct JSONLStreamReader: Sendable {
    public let chunkSize: Int
    public let maximumLineBytes: Int

    public init(chunkSize: Int = 256 * 1024, maximumLineBytes: Int = 1024 * 1024) {
        self.chunkSize = chunkSize
        self.maximumLineBytes = maximumLineBytes
    }

    public func read(url: URL, from initialOffset: Int64) throws -> JSONLReadResult {
        var lines: [JSONLLine] = []
        let progress = try consume(url: url, from: initialOffset) { line in
            lines.append(line)
        }
        return JSONLReadResult(
            lines: lines,
            nextByteOffset: progress.nextByteOffset,
            hasPartialLine: progress.hasPartialLine
        )
    }

    public func consume(
        url: URL,
        from initialOffset: Int64,
        _ body: (JSONLLine) throws -> Void
    ) throws -> JSONLReadResult {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(max(0, initialOffset)))

        var pending = Data()
        var lineOffset = max(0, initialOffset)
        var physicalLineBytes = 0
        var isDiscardingOversizedLine = false

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            var segmentStart = chunk.startIndex
            while segmentStart < chunk.endIndex {
                let newlineIndex = chunk[segmentStart...].firstIndex(of: 0x0A)
                let segmentEnd = newlineIndex ?? chunk.endIndex
                let segment = chunk[segmentStart..<segmentEnd]
                physicalLineBytes += segment.count

                if !isDiscardingOversizedLine {
                    if pending.count + segment.count <= maximumLineBytes {
                        pending.append(contentsOf: segment)
                    } else {
                        pending.removeAll(keepingCapacity: false)
                        isDiscardingOversizedLine = true
                    }
                }

                guard let newlineIndex else { break }
                if !isDiscardingOversizedLine {
                    if pending.last == 0x0D { pending.removeLast() }
                    try body(JSONLLine(byteOffset: lineOffset, data: pending))
                }
                lineOffset += Int64(physicalLineBytes + 1)
                pending.removeAll(keepingCapacity: true)
                physicalLineBytes = 0
                isDiscardingOversizedLine = false
                segmentStart = chunk.index(after: newlineIndex)
            }
        }

        return JSONLReadResult(
            lines: [],
            nextByteOffset: lineOffset,
            hasPartialLine: physicalLineBytes > 0
        )
    }
}

public struct SessionFileScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func files(in paths: CodexPaths) throws -> [URL] {
        var results: [URL] = []
        let keys: [URLResourceKey] = [.isRegularFileKey]

        for directory in paths.sessionDirectories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isRegularFile == true {
                    results.append(url)
                }
            }
        }

        return results.sorted { $0.path < $1.path }
    }
}
