import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    viewModel.showsSettings = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                        Text("설정").font(.headline)
                    }
                    .frame(minWidth: 80, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("사용량으로 돌아가기")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Toggle(
                    "로그인 시 MATARI 실행",
                    isOn: Binding(
                        get: { viewModel.loginAtLaunch },
                        set: { enabled in viewModel.setLoginAtLaunch(enabled) }
                    )
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Codex 데이터 경로")
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.displayedDataPath)
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack {
                        Button("폴더 선택") { viewModel.chooseDataFolder() }
                        Button("기본값으로 재설정") { viewModel.resetDataFolder() }
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("개인정보")
                        .font(.subheadline.weight(.semibold))
                    Text("필요한 사용량 숫자만 읽습니다. 대화 본문과 인증 정보는 저장하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text("MATARI 0.1.0")
                    Spacer()
                    Link("오픈소스", destination: URL(string: "https://github.com/dreamyoungs/matari")!)
                }
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.75))

                if let message = viewModel.diagnosticMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
    }
}
