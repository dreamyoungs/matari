import Foundation
import Darwin

public enum QuotaPollingError: Error, LocalizedError, Sendable {
    case unavailable, timedOut, invalidResponse, requestFailed

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Codex 실행 파일을 찾을 수 없습니다. Codex 앱 또는 CLI를 설치하세요."
        case .timedOut: "계정 사용량 조회 시간이 초과되었습니다. 기존 관측값을 유지합니다."
        case .invalidResponse: "Codex 사용량 응답을 해석할 수 없습니다. Codex 버전을 확인하세요."
        case .requestFailed: "계정 사용량을 조회하지 못했습니다. Codex 로그인과 네트워크를 확인하세요."
        }
    }
}

public struct QuotaPollSchedule: Sendable {
    public private(set) var lastAttempt: Date?
    public init() {}

    public mutating func begin(at now: Date, force: Bool = false) -> Bool {
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < 30 * 60 { return false }
        lastAttempt = now
        return true
    }
}

public struct CodexQuotaClient: Sendable {
    public init() {}

    public func fetch(home: URL) async throws -> [QuotaSnapshot] {
        guard let executable = Self.executable() else { throw QuotaPollingError.unavailable }
        let worker = Task.detached(priority: .utility) {
            try Self.read(executable: executable, home: home)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func executable() -> URL? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    // Synchronous pipe I/O stays on the detached worker, never the UI executor.
    static func read(executable: URL, home: URL, arguments: [String] = ["app-server", "--stdio"],
                     timeout: TimeInterval = 30) throws -> [QuotaSnapshot] {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        // Never retain raw server logs, account payloads or credentials.
        process.standardError = FileHandle.nullDevice
        try Task.checkCancellation()
        do { try process.run() } catch { throw QuotaPollingError.unavailable }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                let deadline = ProcessInfo.processInfo.systemUptime + 0.5
                while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        let fd = output.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { throw QuotaPollingError.requestFailed }
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw QuotaPollingError.requestFailed
        }
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "matari", "version":
                Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"]
        ]])
        var initialized = false
        var buffer = Data()
        var bytes = [UInt8](repeating: 0, count: 8192)
        var total = 0
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count == 0 { throw QuotaPollingError.requestFailed }
            if count < 0 {
                guard errno == EAGAIN || errno == EINTR else { throw QuotaPollingError.requestFailed }
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            total += count
            guard total <= 4 * 1024 * 1024 else { throw QuotaPollingError.invalidResponse }
            buffer.append(contentsOf: bytes.prefix(count))
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw QuotaPollingError.invalidResponse
                }
                // Notifications and unrelated replies do not count as a fresh observation.
                guard let id = message["id"] as? Int, id == (initialized ? 2 : 1) else { continue }
                guard message["error"] == nil else { throw QuotaPollingError.requestFailed }
                guard let result = message["result"] as? [String: Any] else { throw QuotaPollingError.invalidResponse }
                if !initialized {
                    initialized = true
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else {
                    return try decode(result: JSONSerialization.data(withJSONObject: result), observedAt: Date())
                }
            }
            guard buffer.count <= 1024 * 1024 else { throw QuotaPollingError.invalidResponse }
        }
        throw QuotaPollingError.timedOut
    }

    static func decode(result: Data, observedAt: Date) throws -> [QuotaSnapshot] {
        struct Window: Decodable {
            let usedPercent: Double
            let windowDurationMins: Int
            let resetsAt: Double
        }
        struct Bucket: Decodable {
            let limitId: String?
            let planType: String?
            let primary: Window?
            let secondary: Window?
        }
        struct Response: Decodable {
            let rateLimits: Bucket?
            let rateLimitsByLimitId: [String: Bucket]?
        }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: result) }
        catch { throw QuotaPollingError.invalidResponse }
        let buckets: [String: Bucket]
        if let multiple = response.rateLimitsByLimitId, !multiple.isEmpty {
            buckets = multiple
        } else if let legacy = response.rateLimits {
            buckets = [legacy.limitId ?? "codex": legacy]
        } else { throw QuotaPollingError.invalidResponse }
        let event = EventID(rawValue: "poll:" + UUID().uuidString)
        var snapshots: [QuotaSnapshot] = []
        for key in buckets.keys.sorted() {
            guard let bucket = buckets[key] else { continue }
            for window in [bucket.primary, bucket.secondary].compactMap({ $0 }) {
                guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
                      window.windowDurationMins > 0, window.resetsAt.isFinite, window.resetsAt > 0 else {
                    throw QuotaPollingError.invalidResponse
                }
                snapshots.append(QuotaSnapshot(eventID: event, bucketIndex: snapshots.count,
                    observedAt: observedAt, limitID: key, planType: bucket.planType,
                    windowMinutes: window.windowDurationMins, usedPercent: window.usedPercent,
                    resetsAt: Date(timeIntervalSince1970: window.resetsAt)))
            }
        }
        guard !snapshots.isEmpty else { throw QuotaPollingError.invalidResponse }
        return snapshots
    }
}
