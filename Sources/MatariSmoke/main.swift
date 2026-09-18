import Foundation
import MatariCore

@main
struct MatariSmoke {
    static func main() async throws {
        guard case let .available(paths) = CodexPathResolver().resolve() else {
            print("status=path-unavailable")
            return
        }

        let databaseURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/smoke/matari.sqlite")
        let store = try SQLiteStore(url: databaseURL)
        let summary = await TelemetryCoordinator(store: store).scan(paths: paths)
        let snapshot = try await UsageSnapshotBuilder(store: store).build()
        let bucketSummary = snapshot.buckets.map { bucket in
            let remaining = bucket.remainingPercent.map { String($0) } ?? "waiting"
            return "\(bucket.epoch.key.windowMinutes):\(remaining)"
        }.joined(separator: ",")
        let todayPerPercent = snapshot.todayTokensPerPercent.map { String($0) } ?? "pending"
        let weekPerPercent = snapshot.weekTokensPerPercent.map { String($0) } ?? "pending"

        print("files=\(summary.discoveredFiles)")
        print("scanned=\(summary.scannedFiles)")
        print("failed=\(summary.failedFiles)")
        print("records=\(summary.parsedRelevantRecords)")
        print("invalid=\(summary.skippedInvalidRecords)")
        print("rebases=\(summary.counterRebases)")
        print("buckets=\(bucketSummary)")
        print("todayTokens=\(snapshot.todayTokens ?? -1)")
        print("weekTokens=\(snapshot.weekTokens ?? -1)")
        print("todayTokensPerPercent=\(todayPerPercent)")
        print("weekTokensPerPercent=\(weekPerPercent)")
    }
}
