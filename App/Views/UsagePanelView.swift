import SwiftUI
import Charts

struct UsagePanelView: View {
    @ObservedObject var viewModel: UsageViewModel
    var isPinned = false
    var togglePin: () -> Void = {}
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if viewModel.showsSettings {
                SettingsView(viewModel: viewModel, isPinned: isPinned)
            } else {
                usageContent
            }
        }
        .frame(width: 336)
        .background {
            if reduceTransparency || contrast == .increased {
                Color(nsColor: .windowBackgroundColor)
            } else {
                // Keep a little backdrop color without letting wallpaper determine text contrast.
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Color(white: colorScheme == .dark ? 0.12 : 0.97)
                        .opacity(colorScheme == .dark ? 0.78 : 0.82)
                }
            }
        }
        .onAppear { viewModel.panelOpened() }
    }

    private var usageContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mainContent
            if let credits = viewModel.accountCredits,
               credits.balance != nil || credits.availableResetCount != nil {
                Divider().padding(.horizontal, 16)
                AccountCreditsView(credits: credits)
            }
            if let message = viewModel.quotaPollingMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Codex 사용량")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: togglePin) {
                Text("⚓︎")
                    .font(.system(size: 17, weight: isPinned ? .bold : .regular))
                    .foregroundStyle(isPinned ? Color.accentColor : Color.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isPinned ? "메뉴바로 돌아가기" : "독립창으로 항상 보기 · 헤더를 드래그하여 이동")
            .accessibilityLabel(isPinned ? "독립창 고정 해제" : "독립창으로 고정")
            Button {
                viewModel.retry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isScanning || viewModel.isPollingQuota)
            .help("계정 잔여율 조회 및 로컬 사용 기록 새로고침 · 자동 조회는 30분 간격입니다")
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
        .overlay {
            if isPinned {
                // 16pt trailing padding + three 28pt buttons + two 8pt gaps.
                WindowDragRegion(trailingExclusion: 116)
                    .help("드래그하여 창 이동")
                    .accessibilityHidden(true)
            }
        }
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
                .foregroundStyle(Color.primary.opacity(0.85))
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
                    QuotaBucketView(bucket: bucket, now: viewModel.currentTime)
                }
            }
            Divider().padding(.horizontal, 16)
            if let history = viewModel.snapshot.quotaHistory(windowMinutes: viewModel.selectedHistoryWindow) {
                if viewModel.snapshot.quotaHistories.count > 1 {
                    Picker("그래프 제한", selection: Binding(
                        get: { history.windowMinutes },
                        set: { viewModel.selectedHistoryWindow = $0 }
                    )) {
                        ForEach(viewModel.snapshot.quotaHistories, id: \.windowMinutes) { item in
                            Text(UsageFormatters.bucketTitle(minutes: item.windowMinutes)
                                .replacingOccurrences(of: " 제한", with: ""))
                                .tag(item.windowMinutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                QuotaHistoryView(history: history)
                Divider().padding(.horizontal, 16)
            }
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
            .foregroundStyle(Color.primary.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct AccountCreditsView: View {
    let credits: AccountCreditStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("계정 크레딧").font(.subheadline.weight(.semibold))
            if let balance = credits.balance {
                DetailRow(title: "잔액", value: "\(UsageFormatters.creditBalance(balance)) 크레딧")
            }
            if let count = credits.availableResetCount {
                DetailRow(title: "사용 가능한 리셋권", value: "\(count)개")
                if let expiry = credits.nearestResetExpiry {
                    DetailRow(title: "가장 가까운 만료일", value: UsageFormatters.absoluteReset(expiry))
                }
            }
        }
        .padding(16)
    }
}

private struct QuotaHistoryView: View {
    let history: QuotaHistory
    private let yellow = Color(red: 211 / 255, green: 166 / 255, blue: 42 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("잔여율 추이").font(.subheadline.weight(.semibold))
                Spacer()
                Text("최근 2일").font(.caption).foregroundStyle(Color.primary.opacity(0.85))
            }
            Chart {
                ForEach(Array(history.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("시각", point.date), y: .value("남음", point.remaining),
                             series: .value("관측 구간", point.segment))
                        .foregroundStyle(yellow)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("시각", point.date), y: .value("남음", point.remaining))
                        .foregroundStyle(yellow)
                        .symbolSize(7)
                }
            }
            .chartXScale(domain: history.start...history.end)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percent = value.as(Int.self) {
                            Text("\(percent)%").foregroundStyle(Color.primary.opacity(0.85))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: [history.start, history.start.addingTimeInterval(86400), history.end]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.month().day().hour())
                                .foregroundStyle(Color.primary.opacity(0.85))
                        }
                    }
                }
            }
            .frame(height: 112)
            .overlay {
                if history.points.isEmpty {
                    Text("최근 2일의 관측 기록이 없습니다")
                        .font(.caption).foregroundStyle(Color.primary.opacity(0.85))
                }
            }
            .accessibilityLabel("최근 48시간 \(UsageFormatters.bucketTitle(minutes: history.windowMinutes)) 잔여율")
            Text("\(UsageFormatters.bucketTitle(minutes: history.windowMinutes)) · 점은 관측값, 빈 구간은 기록 없음")
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(0.85))
        }
        .padding(16)
    }
}

private struct QuotaBucketView: View {
    let bucket: UsageBucket
    let now: Date

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
                DetailRow(title: "남은 시간", value: UsageFormatters.remainingTime(until: bucket.epoch.key.resetsAt, now: now))
            } else {
                Text("초기화 후 새 데이터 대기 중")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.85))
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
                    .foregroundStyle(Color.primary.opacity(0.85))
            }
            DetailRow(title: "오늘", value: UsageFormatters.tokensWithCost(snapshot.todayTokens, cost: snapshot.todayCost))
            DetailRow(title: "이번 주", value: UsageFormatters.tokensWithCost(snapshot.weekTokens, cost: snapshot.weekCost))
            Text("API Standard 환산 · 실제 청구액 아님")
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(0.85))
                .help("이 Mac의 토큰을 2026-09-30 API Standard 단가로 환산합니다. 캐시·긴 입력 할증 반영, 속도·지역·도구 요금 제외. 모델 정보는 로컬 turn_context 기준입니다.")
            if let cost = snapshot.weekCost, cost.unpricedTokens > 0 {
                Text("이번 주 \(UsageFormatters.tokenCount(cost.unpricedTokens)) 토큰 미산정")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .help("모델·단가·요청별 입력량을 확인할 수 없거나 수량이 불일치한 기록은 금액에서 제외합니다. 0달러 사용으로 처리하지 않습니다.")
            }
            DetailRow(title: "오늘 1%당", value: UsageFormatters.tokensPerPercent(snapshot.todayTokensPerPercent))
                .help("오늘 중 현재 요금제·초기화 구간에서 관측한 토큰 증가량 ÷ 사용률 증가분. 전체 일간 합계와 계산 구간이 다를 수 있습니다.")
            DetailRow(title: "이번 주 1%당", value: UsageFormatters.tokensPerPercent(snapshot.weekTokensPerPercent))
                .help("이번 주 중 현재 요금제·초기화 구간의 관측분만 계산합니다. 요금제 변경·초기화 이전 기록은 제외합니다.")
        }
        .padding(16)
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Color.primary.opacity(0.85))
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
                .foregroundStyle(Color.primary.opacity(0.85))
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
                .foregroundStyle(Color.primary.opacity(0.85))
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
                .foregroundStyle(Color.primary.opacity(0.85))
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(16)
    }
}
