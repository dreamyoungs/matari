import SwiftUI

struct UsagePanelView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if viewModel.showsSettings {
                SettingsView(viewModel: viewModel)
            } else {
                usageContent
            }
        }
        .frame(width: 336)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .onAppear { viewModel.panelOpened() }
    }

    private var usageContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mainContent
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("Codex 사용량")
                .font(.headline)
            Spacer()
            Button {
                viewModel.retry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isScanning)
            .help("로컬 사용 기록 다시 읽기 · Codex가 기록한 최신 정보로 갱신합니다")
            .accessibilityLabel("사용 기록 새로고침")
            Button {
                viewModel.showsSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("설정")
            .accessibilityLabel("설정")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.snapshot.state {
        case let .loading(hasCachedData) where !hasCachedData:
            loadingView
        case .noSessionDirectory:
            MissingPathView(chooseFolder: viewModel.chooseDataFolder)
        case .inaccessiblePath:
            ErrorStateView(
                title: "Codex 사용 기록을 읽을 수 없습니다",
                detail: "폴더 접근 권한을 확인하거나 다른 폴더를 선택하세요.",
                actionTitle: "폴더 다시 선택",
                action: viewModel.chooseDataFolder
            )
        case .noSessions:
            EmptyStateView(
                title: "아직 기록된 Codex 사용량이 없습니다",
                detail: "Codex를 사용하면 여기에 자동으로 표시됩니다."
            )
        case .readError:
            ErrorStateView(
                title: "사용 기록을 읽을 수 없습니다",
                detail: "기존 데이터는 유지됩니다. 잠시 후 다시 시도하세요.",
                actionTitle: "다시 시도",
                action: viewModel.retry
            )
        default:
            usageSections
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Codex 사용 기록 읽는 중…")
                .foregroundStyle(Color.primary.opacity(0.75))
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(16)
    }

    private var usageSections: some View {
        VStack(spacing: 0) {
            if viewModel.snapshot.buckets.isEmpty {
                EmptyStateView(
                    title: "사용 한도 데이터 없음",
                    detail: "Codex가 새 사용량 정보를 기록하면 자동으로 표시됩니다."
                )
            } else {
                ForEach(Array(viewModel.snapshot.buckets.enumerated()), id: \.element.id) { index, bucket in
                    if index > 0 { Divider().padding(.horizontal, 16) }
                    QuotaBucketView(bucket: bucket)
                }
            }
            Divider().padding(.horizontal, 16)
            TokenUsageView(snapshot: viewModel.snapshot)
        }
    }

    private var footer: some View {
        VStack(spacing: 7) {
            HStack {
                if viewModel.isScanning {
                    Text("새 데이터 확인 중…")
                } else if let message = viewModel.diagnosticMessage {
                    Text(message)
                } else {
                    Text(UsagePresentation.lastUpdatedText(viewModel.snapshot.lastQuotaObservation))
                }
                Spacer()
                Button("MATARI 종료", action: viewModel.quit)
                    .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundStyle(Color.primary.opacity(0.75))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct QuotaBucketView: View {
    let bucket: UsageBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UsageFormatters.bucketTitle(minutes: bucket.epoch.key.windowMinutes))
                .font(.subheadline.weight(.semibold))
            HStack {
                Text("남음")
                Spacer()
                if let remaining = bucket.remainingPercent {
                    Text("\(remaining)%")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(progressColor(remaining))
                } else {
                    Text("확인 중")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if let remaining = bucket.remainingPercent {
                ProgressView(value: Double(remaining), total: 100)
                    .tint(progressColor(remaining))
                    .accessibilityLabel(UsageFormatters.bucketTitle(minutes: bucket.epoch.key.windowMinutes))
                    .accessibilityValue("\(remaining)퍼센트 남음")
                DetailRow(title: "초기화", value: UsageFormatters.absoluteReset(bucket.epoch.key.resetsAt))
                DetailRow(title: "남은 시간", value: UsageFormatters.remainingTime(until: bucket.epoch.key.resetsAt))
            } else {
                Text("초기화 후 새 데이터 대기 중")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
        }
        .padding(16)
    }

    private func progressColor(_ remaining: Int) -> Color {
        if remaining <= 10 { return .red }
        if remaining <= 20 { return .orange }
        return Color(red: 211 / 255, green: 166 / 255, blue: 42 / 255)
    }
}

private struct TokenUsageView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("토큰 사용량")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("이 Mac에서 관측")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
            DetailRow(title: "오늘", value: UsageFormatters.tokenCount(snapshot.todayTokens))
            DetailRow(title: "이번 주", value: UsageFormatters.tokenCount(snapshot.weekTokens))
            DetailRow(title: "오늘 1%당", value: UsageFormatters.tokensPerPercent(snapshot.todayTokensPerPercent))
            DetailRow(title: "이번 주 1%당", value: UsageFormatters.tokensPerPercent(snapshot.weekTokensPerPercent))
        }
        .padding(16)
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Color.primary.opacity(0.75))
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}

private struct EmptyStateView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .padding(16)
    }
}

private struct MissingPathView: View {
    let chooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Codex 사용 기록을 찾을 수 없습니다")
                .font(.subheadline.weight(.semibold))
            Text("기본 위치에서 세션 폴더를 찾지 못했습니다.")
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.75))
            Button("폴더 선택", action: chooseFolder)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(16)
    }
}

private struct ErrorStateView: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.75))
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(16)
    }
}
