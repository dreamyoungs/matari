import Foundation

public struct CodexPaths: Sendable, Equatable {
    public let home: URL
    public let sessionDirectories: [URL]

    public init(home: URL, sessionDirectories: [URL]) {
        self.home = home
        self.sessionDirectories = sessionDirectories
    }
}

public enum CodexPathStatus: Sendable, Equatable {
    case available(CodexPaths)
    case missing
    case inaccessible(URL)
}

public struct CodexPathResolver {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func resolve(customPath: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> CodexPathStatus {
        let home: URL
        if let customPath {
            home = normalizeSelectedPath(customPath)
        } else if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
            home = URL(fileURLWithPath: codexHome, isDirectory: true)
        } else {
            home = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: home.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing
        }
        guard fileManager.isReadableFile(atPath: home.path) else {
            return .inaccessible(home)
        }

        let directories = ["sessions", "archived_sessions"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue }

        guard !directories.isEmpty else { return .missing }
        return .available(CodexPaths(home: home, sessionDirectories: directories))
    }

    private func normalizeSelectedPath(_ selected: URL) -> URL {
        switch selected.lastPathComponent {
        case "sessions", "archived_sessions":
            return selected.deletingLastPathComponent()
        default:
            return selected
        }
    }
}
