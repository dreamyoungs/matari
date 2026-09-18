import SwiftUI

struct MenuBarLabelView: View {
    let snapshot: UsageSnapshot
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 5) {
            MatariFlowerSymbol()
                .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(labelText)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var currentBuckets: [UsageBucket] {
        snapshot.buckets.filter { $0.status == .current && $0.remainingPercent != nil }
    }

    private var labelText: String {
        switch UsagePresentation.make(snapshot: snapshot, isLoading: isLoading).menuBarIndicator {
        case .loading:
            return "…"
        case let .percentages(values):
            return values.map { "\($0)%" }.joined(separator: " · ")
        case .unavailable:
            return "–"
        case .error:
            return "!"
        }
    }

    private var accessibilityText: String {
        let values = currentBuckets.map {
            "\(UsageFormatters.bucketTitle(minutes: $0.epoch.key.windowMinutes)) \($0.remainingPercent ?? 0)퍼센트 남음"
        }
        return values.isEmpty ? "MATARI, 사용 한도 데이터 없음" : "MATARI, " + values.joined(separator: ", ")
    }
}

struct MatariFlowerSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        let bottom = rect.maxY - 1
        let branchY = rect.minY + rect.height * 0.55
        path.move(to: CGPoint(x: centerX, y: bottom))
        path.addLine(to: CGPoint(x: centerX, y: rect.minY + 3))
        path.move(to: CGPoint(x: centerX, y: branchY))
        path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.minY + 5))
        path.move(to: CGPoint(x: centerX, y: branchY + 1))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 6))
        for point in [
            CGPoint(x: centerX, y: rect.minY + 2),
            CGPoint(x: rect.minX + 3, y: rect.minY + 4),
            CGPoint(x: rect.maxX - 3, y: rect.minY + 5),
            CGPoint(x: rect.minX + 5, y: rect.minY + 8),
            CGPoint(x: rect.maxX - 5, y: rect.minY + 9)
        ] {
            path.addEllipse(in: CGRect(x: point.x - 1.4, y: point.y - 1.4, width: 2.8, height: 2.8))
        }
        return path
    }
}
