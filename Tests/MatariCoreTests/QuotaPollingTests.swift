import Foundation
import Testing
@testable import MatariCore

struct QuotaPollingTests {
    private let response = #"{"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1900000000}},"rateLimitsByLimitId":{"codex":{"planType":"pro","primary":{"usedPercent":70,"windowDurationMins":10080,"resetsAt":1900000000},"secondary":null}}}"#

    @Test func unchangedSuccessfulPollsAreSeparateObservations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(url: root.appendingPathComponent("test.sqlite"))
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let second = first.addingTimeInterval(1800)
        let a = try CodexQuotaClient.decode(result: Data(response.utf8), observedAt: first)
        let b = try CodexQuotaClient.decode(result: Data(response.utf8), observedAt: second)
        #expect(a.count == 1)
        #expect(a[0].usedPercent == 70)
        #expect(a[0].planType == "pro")
        #expect(a[0].eventID != b[0].eventID)
        try await store.persistPolledQuotas(a)
        try await store.persistPolledQuotas(b)
        try await store.persistPolledQuotas(b)
        let observations = try await store.quotaObservations(limitID: "codex", windowMinutes: 10080,
            overlapping: first, through: second.addingTimeInterval(1))
        #expect(observations.map(\.observedAt) == [first, second])
        #expect(try await store.sourceFileCount() == 0)
        let snapshot = try await UsageSnapshotBuilder(store: store).build(now: second)
        #expect(snapshot.buckets.first?.remainingPercent == 30)
        #expect(snapshot.lastQuotaObservation == second)
        #expect(snapshot.todayTokens == 0)
        #expect(snapshot.quotaHistory(windowMinutes: nil)?.points.count == 2)
        #expect(snapshot.quotaHistory(windowMinutes: nil)?.points.last?.remaining == 30)
        #expect(observations.allSatisfy { $0.planType == "pro" })
    }

    @Test func legacyAndDynamicWindows() throws {
        let data = Data(#"{"rateLimits":{"limitId":"codex","planType":"plus","primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":1900000000}}}"#.utf8)
        let snapshots = try CodexQuotaClient.decode(result: data, observedAt: Date())
        #expect(snapshots.map(\.windowMinutes) == [300, 10080])
        #expect(snapshots.map(\.bucketIndex) == [0, 1])
    }

    @Test(arguments: ["{}", "{broken", #"{"rateLimits":{"primary":null}}"#,
        #"{"rateLimits":{"primary":{"usedPercent":101,"windowDurationMins":300,"resetsAt":1900000000}}}"#])
    func invalidResponsesCannotBecomeObservations(json: String) {
        #expect(throws: QuotaPollingError.self) {
            try CodexQuotaClient.decode(result: Data(json.utf8), observedAt: Date())
        }
    }

    @Test func scheduleDoesNotDependOnLocalUsageAndAllowsManualOrWakeRefresh() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var schedule = QuotaPollSchedule()
        let results = [schedule.begin(at: start),
            schedule.begin(at: start.addingTimeInterval(1799)),
            schedule.begin(at: start.addingTimeInterval(1800)),
            schedule.begin(at: start.addingTimeInterval(1810), force: true),
            schedule.begin(at: start.addingTimeInterval(1811)),
            schedule.begin(at: start.addingTimeInterval(7200))]
        #expect(results == [true, false, true, true, false, true])
    }

    @Test func processHandshakeIgnoresNotificationsAndReadsQuotaOnly() throws {
        let script = """
        IFS= read -r init
        case "$init" in *initialize*) ;; *) exit 1;; esac
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r ready
        IFS= read -r request
        case "$request" in *account/rateLimits/read*) ;; *) exit 2;; esac
        printf '%s\\n' '{"method":"account/updated","params":{}}'
        printf '%s\\n' '{"id":2,"result":\(response)}'
        IFS= read -r finish
        """
        let snapshots = try CodexQuotaClient.read(executable: URL(fileURLWithPath: "/bin/sh"),
            home: FileManager.default.temporaryDirectory, arguments: ["-c", script], timeout: 2)
        #expect(snapshots.first?.usedPercent == 70)
    }

    @Test func stalledProcessIsTerminatedWithinDeadline() {
        let start = ProcessInfo.processInfo.systemUptime
        #expect(throws: QuotaPollingError.self) {
            try CodexQuotaClient.read(executable: URL(fileURLWithPath: "/bin/sh"),
                home: FileManager.default.temporaryDirectory,
                arguments: ["-c", "IFS= read -r init; IFS= read -r next"], timeout: 0.1)
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 2)
    }

    @Test func cancelledWorkerStopsWithoutWaitingForTimeout() async throws {
        let worker = Task.detached {
            try CodexQuotaClient.read(executable: URL(fileURLWithPath: "/bin/sh"),
                home: FileManager.default.temporaryDirectory,
                arguments: ["-c", "IFS= read -r init; IFS= read -r next"], timeout: 10)
        }
        try await Task.sleep(for: .milliseconds(100))
        let start = ProcessInfo.processInfo.systemUptime
        worker.cancel()
        do {
            _ = try await worker.value
            Issue.record("Cancelled poll returned a successful observation")
        } catch is CancellationError {
            #expect(ProcessInfo.processInfo.systemUptime - start < 2)
        }
    }

    @Test func serverErrorAndEarlyExitFailWithoutRawErrorExposure() {
        for script in ["exit 1", "IFS= read -r init; printf '%s\\n' '{\"id\":1,\"error\":{\"message\":\"private details\"}}'; IFS= read -r next"] {
            #expect(throws: QuotaPollingError.self) {
                try CodexQuotaClient.read(executable: URL(fileURLWithPath: "/bin/sh"),
                    home: FileManager.default.temporaryDirectory, arguments: ["-c", script], timeout: 1)
            }
        }
    }
}
