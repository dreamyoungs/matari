import Foundation

public struct ScanSummary: Sendable, Equatable {
    public var discoveredFiles: Int
    public var scannedFiles: Int
    public var parsedRelevantRecords: Int
    public var skippedInvalidRecords: Int
    public var counterRebases: Int
    public var failedFiles: Int
    public var lastSuccessfulScan: Date?

    public init(
        discoveredFiles: Int = 0,
        scannedFiles: Int = 0,
        parsedRelevantRecords: Int = 0,
        skippedInvalidRecords: Int = 0,
        counterRebases: Int = 0,
        failedFiles: Int = 0,
        lastSuccessfulScan: Date? = nil
    ) {
        self.discoveredFiles = discoveredFiles
        self.scannedFiles = scannedFiles
        self.parsedRelevantRecords = parsedRelevantRecords
        self.skippedInvalidRecords = skippedInvalidRecords
        self.counterRebases = counterRebases
        self.failedFiles = failedFiles
        self.lastSuccessfulScan = lastSuccessfulScan
    }
}

public actor TelemetryCoordinator {
    private let store: SQLiteStore
    private let parser: TelemetryParser
    private let reader: JSONLStreamReader
    private let fileScanner: SessionFileScanner
    private let fileManager: FileManager
    private let tokenNeedle = Data("\"token_count\"".utf8)
    private let metadataNeedle = Data("\"session_meta\"".utf8)

    public init(
        store: SQLiteStore,
        parser: TelemetryParser = TelemetryParser(),
        reader: JSONLStreamReader = JSONLStreamReader(),
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.parser = parser
        self.reader = reader
        self.fileManager = fileManager
        self.fileScanner = SessionFileScanner(fileManager: fileManager)
    }

    public func scan(paths: CodexPaths, now: Date = Date()) async -> ScanSummary {
        var summary = ScanSummary()
        let urls: [URL]
        do {
            urls = try fileScanner.files(in: paths)
        } catch {
            summary.failedFiles = 1
            return summary
        }
        summary.discoveredFiles = urls.count

        for url in urls {
            do {
                let result = try await scanFile(url)
                summary.scannedFiles += 1
                summary.parsedRelevantRecords += result.parsedRelevantRecords
                summary.skippedInvalidRecords += result.skippedInvalidRecords
                summary.counterRebases += result.counterRebases
            } catch {
                summary.failedFiles += 1
            }
        }

        if summary.failedFiles == 0 || summary.scannedFiles > 0 {
            summary.lastSuccessfulScan = now
        }
        return summary
    }

    private func scanFile(_ url: URL) async throws -> ScanSummary {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
        let initialMeta = try readSessionMetadata(from: url)
        let fallbackID = url.deletingPathExtension().lastPathComponent
        let fileID = initialMeta?.fileID ?? fallbackID
        var cursor = try await store.cursor(fileID: fileID) ?? FileCursor(
            fileID: fileID,
            currentPath: url.path,
            byteOffset: 0,
            lastTotalTokens: nil,
            fileSize: 0,
            modifiedAt: .distantPast,
            cliVersion: initialMeta?.cliVersion,
            threadSource: initialMeta?.threadSource ?? .unknown
        )

        if fileSize < cursor.byteOffset {
            cursor.byteOffset = 0
            cursor.lastTotalTokens = nil
        }

        if fileSize == cursor.fileSize, modifiedAt == cursor.modifiedAt, cursor.currentPath == url.path {
            return ScanSummary()
        }

        var previousTotal = cursor.lastTotalTokens
        var source = cursor.threadSource
        var cliVersion = cursor.cliVersion
        var contributions: [TokenContribution] = []
        var quotas: [QuotaSnapshot] = []
        var summary = ScanSummary()

        let readResult = try reader.consume(url: url, from: cursor.byteOffset) { line in
            guard line.data.range(of: tokenNeedle) != nil || line.data.range(of: metadataNeedle) != nil else {
                return
            }
            let parsedEvent = autoreleasepool {
                parser.parse(line: line.data, fileID: fileID, byteOffset: line.byteOffset)
            }
            guard let event = parsedEvent else {
                summary.skippedInvalidRecords += 1
                return
            }
            summary.parsedRelevantRecords += 1

            switch event {
            case let .sessionMeta(metadata):
                source = metadata.threadSource
                cliVersion = metadata.cliVersion ?? cliVersion
            case let .tokenCount(snapshot, parsedQuotas):
                let result = TokenAggregator().delta(for: snapshot, previousTotal: previousTotal)
                previousTotal = result.nextTotal
                if result.rebased { summary.counterRebases += 1 }
                if result.contribution.totalTokens > 0 {
                    contributions.append(
                        TokenContribution(
                            eventID: snapshot.eventID,
                            fileID: fileID,
                            occurredAt: snapshot.observedAt,
                            usage: result.contribution,
                            source: source
                        )
                    )
                }
                quotas.append(contentsOf: parsedQuotas)
            }
        }

        cursor.currentPath = url.path
        cursor.byteOffset = readResult.nextByteOffset
        cursor.lastTotalTokens = previousTotal
        cursor.fileSize = fileSize
        cursor.modifiedAt = modifiedAt
        cursor.cliVersion = cliVersion
        cursor.threadSource = source
        try await store.persist(cursor: cursor, contributions: contributions, quotas: quotas)
        return summary
    }

    private func readSessionMetadata(from url: URL) throws -> SessionDescriptor? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        let maximumBytes = 1024 * 1024

        while data.count < maximumBytes,
              let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes - data.count)),
              !chunk.isEmpty {
            data.append(chunk)
            if let newline = data.firstIndex(of: 0x0A) {
                let firstLine = Data(data[..<newline])
                if case let .sessionMeta(metadata) = parser.parse(
                    line: firstLine,
                    fileID: url.deletingPathExtension().lastPathComponent,
                    byteOffset: 0
                ) {
                    return metadata
                }
                return nil
            }
        }
        return nil
    }
}
