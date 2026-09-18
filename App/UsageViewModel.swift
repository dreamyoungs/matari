import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot(
        buckets: [],
        todayTokens: nil,
        weekTokens: nil,
        todayTokensPerPercent: nil,
        weekTokensPerPercent: nil,
        lastQuotaObservation: nil,
        state: .loading(hasCachedData: false)
    )
    @Published private(set) var isScanning = true
    @Published private(set) var diagnosticMessage: String?
    @Published var showsSettings = false
    @Published var loginAtLaunch = false
    @Published private(set) var displayedDataPath: String = "자동 감지"

    private var store: SQLiteStore?
    private var coordinator: TelemetryCoordinator?
    private var snapshotBuilder: UsageSnapshotBuilder?
    private var minuteTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var watcherDebounceTask: Task<Void, Never>?
    private var directoryWatcher: DirectoryWatcher?
    private var watchedPaths: [String] = []
    private var scanRequested = false

    init() {
        loginAtLaunch = SMAppService.mainApp.status == .enabled
        Task { await prepareAndScan() }
        minuteTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                self.scan()
            }
        }
    }

    deinit {
        minuteTask?.cancel()
        scanTask?.cancel()
        watcherDebounceTask?.cancel()
        directoryWatcher?.stop()
    }

    func panelOpened() {
        scan()
    }

    func retry() {
        scan()
    }

    func chooseDataFolder() {
        let panel = NSOpenPanel()
        panel.title = "Codex 데이터 폴더 선택"
        panel.message = "CODEX_HOME 또는 sessions 폴더를 선택하세요."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: SettingsKey.customCodexPath)
        displayedDataPath = url.path
        scan()
    }

    func resetDataFolder() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.customCodexPath)
        displayedDataPath = "자동 감지"
        scan()
    }

    func setLoginAtLaunch(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginAtLaunch = SMAppService.mainApp.status == .enabled
            diagnosticMessage = nil
        } catch {
            loginAtLaunch = SMAppService.mainApp.status == .enabled
            diagnosticMessage = "로그인 항목을 변경할 수 없습니다."
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func prepareAndScan() async {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("MATARI", isDirectory: true)
            let store = try SQLiteStore(url: support.appendingPathComponent("matari.sqlite"))
            self.store = store
            coordinator = TelemetryCoordinator(store: store)
            snapshotBuilder = UsageSnapshotBuilder(store: store)
            isScanning = false
            scan()
        } catch {
            isScanning = false
            diagnosticMessage = error.localizedDescription
            snapshot = emptySnapshot(state: .readError(recoverable: false))
        }
    }

    private func scan() {
        guard let coordinator, let snapshotBuilder else { return }
        guard !isScanning else {
            scanRequested = true
            return
        }
        isScanning = true
        diagnosticMessage = nil
        let customPath = UserDefaults.standard.string(forKey: SettingsKey.customCodexPath).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        displayedDataPath = customPath?.path ?? "자동 감지 (~/.codex)"

        scanTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isScanning = false
                self.scanTask = nil
                if self.scanRequested {
                    self.scanRequested = false
                    self.scan()
                }
            }
            let status = CodexPathResolver().resolve(customPath: customPath)
            guard !Task.isCancelled else { return }
            switch status {
            case .missing:
                self.stopWatching()
                self.snapshot = self.emptySnapshot(state: .noSessionDirectory)
                self.isScanning = false
                self.scanTask = nil
            case .inaccessible:
                self.stopWatching()
                self.snapshot = self.emptySnapshot(state: .inaccessiblePath)
                self.isScanning = false
                self.scanTask = nil
            case let .available(paths):
                self.startWatching(paths)
                let summary = await coordinator.scan(paths: paths)
                guard !Task.isCancelled else { return }
                do {
                    let hint: UsageDataState
                    if summary.discoveredFiles == 0 {
                        hint = .noSessions
                    } else if summary.failedFiles > 0, summary.scannedFiles == 0 {
                        hint = .readError(recoverable: true)
                    } else {
                        hint = .ready
                    }
                    self.snapshot = try await snapshotBuilder.build(stateHint: hint)
                    if summary.failedFiles > 0 {
                        self.diagnosticMessage = "일부 사용 기록을 읽을 수 없습니다."
                    }
                } catch {
                    self.diagnosticMessage = error.localizedDescription
                    self.snapshot = self.emptySnapshot(state: .readError(recoverable: true))
                }
                self.isScanning = false
                self.scanTask = nil
            }
        }
    }

    private func startWatching(_ paths: CodexPaths) {
        let signature = paths.sessionDirectories.map { $0.standardizedFileURL.path }.sorted()
        guard signature != watchedPaths else { return }
        stopWatching()
        watchedPaths = signature
        directoryWatcher = DirectoryWatcher(paths: paths.sessionDirectories) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleWatchedScan()
            }
        }
    }

    private func stopWatching() {
        directoryWatcher?.stop()
        directoryWatcher = nil
        watchedPaths = []
    }

    private func scheduleWatchedScan() {
        watcherDebounceTask?.cancel()
        watcherDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.scan()
        }
    }

    private func refreshSnapshotOnly() async {
        guard let snapshotBuilder, !isScanning else { return }
        do {
            snapshot = try await snapshotBuilder.build()
        } catch {
            diagnosticMessage = error.localizedDescription
        }
    }

    private func emptySnapshot(state: UsageDataState) -> UsageSnapshot {
        UsageSnapshot(
            buckets: [],
            todayTokens: snapshot.todayTokens,
            weekTokens: snapshot.weekTokens,
            todayTokensPerPercent: snapshot.todayTokensPerPercent,
            weekTokensPerPercent: snapshot.weekTokensPerPercent,
            lastQuotaObservation: snapshot.lastQuotaObservation,
            state: state
        )
    }
}

private enum SettingsKey {
    static let customCodexPath = "customCodexPath"
}
