import Foundation

enum UsageFormatters {
    static func bucketTitle(minutes: Int) -> String {
        switch minutes {
        case 300: "5시간 제한"
        case 10_080: "주간 제한"
        case let value where value % 43_200 == 0: "\(value / 43_200)개월 제한"
        case let value where value % 1_440 == 0: "\(value / 1_440)일 제한"
        case let value where value % 60 == 0: "\(value / 60)시간 제한"
        default: "\(minutes)분 제한"
        }
    }

    static func tokenCount(_ value: Int64?) -> String {
        guard let value else { return "–" }
        return compactNumber(Double(value))
    }

    static func tokensPerPercent(_ value: Double?) -> String {
        guard let value else { return "계산 중" }
        return "≈ " + compactNumber(value)
    }

    static func compactNumber(_ value: Double) -> String {
        let magnitude: (divisor: Double, suffix: String)
        switch abs(value) {
        case 1_000_000_000...: magnitude = (1_000_000_000, "B")
        case 1_000_000...: magnitude = (1_000_000, "M")
        case 1_000...: magnitude = (1_000, "K")
        default: return String(Int(value.rounded()))
        }
        let scaled = value / magnitude.divisor
        let digits = scaled >= 100 ? 0 : (scaled >= 10 ? 1 : 2)
        return String(format: "%.*f%@", digits, scaled, magnitude.suffix)
            .replacingOccurrences(of: ".00", with: "")
            .replacingOccurrences(of: #"(\.\d)0([KMB])$"#, with: "$1$2", options: .regularExpression)
    }

    static func absoluteReset(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        formatter.dateFormat = year == currentYear ? "M월 d일(E) HH:mm" : "yyyy년 M월 d일(E) HH:mm"
        return formatter.string(from: date)
    }

    static func remainingTime(until date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)일 \(hours)시간" }
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        return "\(minutes)분"
    }

}
