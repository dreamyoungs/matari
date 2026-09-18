import Foundation

public enum MenuBarIndicator: Sendable, Equatable {
    case loading
    case percentages([Int])
    case unavailable
    case error
}

public struct UsagePresentation: Sendable, Equatable {
    public let menuBarIndicator: MenuBarIndicator
    public let footerText: String

    public init(menuBarIndicator: MenuBarIndicator, footerText: String) {
        self.menuBarIndicator = menuBarIndicator
        self.footerText = footerText
    }

    public static func make(snapshot: UsageSnapshot, isLoading: Bool, now: Date = Date()) -> UsagePresentation {
        let currentPercentages = snapshot.buckets
            .filter { $0.status == .current }
            .compactMap(\.remainingPercent)

        let indicator: MenuBarIndicator
        if isLoading, snapshot.lastQuotaObservation == nil {
            indicator = .loading
        } else {
            switch snapshot.state {
            case .noSessionDirectory, .inaccessiblePath, .readError:
                indicator = .error
            default:
                indicator = currentPercentages.isEmpty ? .unavailable : .percentages(currentPercentages)
            }
        }

        return UsagePresentation(
            menuBarIndicator: indicator,
            footerText: lastUpdatedText(snapshot.lastQuotaObservation, now: now)
        )
    }

    public static func lastUpdatedText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "마지막 갱신 –" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "방금 전 갱신" }
        if seconds < 3_600 { return "\(seconds / 60)분 전 갱신" }
        if seconds < 86_400 { return "\(seconds / 3_600)시간 전 · Codex 비활성" }
        return "\(seconds / 86_400)일 전 · Codex 비활성"
    }
}
