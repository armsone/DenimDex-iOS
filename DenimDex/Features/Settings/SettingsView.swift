import SwiftUI
import SwiftData
import WebKit

struct SettingsView: View {
    @StateObject private var loginStore = AIBILoginStatusStore()
    @ObservedObject private var diagnosticsStore = AIBIDiagnosticsStore.shared
    @State private var showLoginSheet = false
    @State private var showClearedConfirmation = false
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [CollectionItem]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        DenimEyebrow(text: "Privacy & Collection")
                        Text("당신의 기록을\n안전하게 관리합니다")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(DenimTheme.charcoal)
                        Text("로그인과 동기화, 사진의 보관 범위를 한곳에서 확인하세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    Button {
                        showLoginSheet = true
                    } label: {
                        HStack {
                            Text("ChatGPT").foregroundStyle(.primary)
                            Spacer()
                            Label(loginStore.status.title, systemImage: loginStore.status.iconName)
                                .font(.footnote)
                                .foregroundStyle(loginStore.status.color)
                        }
                    }
                    .accessibilityLabel("ChatGPT, \(loginStore.status.title)")
                    .accessibilityHint("공식 ChatGPT 로그인 화면을 앱 안에서 엽니다")

                    Button("ChatGPT 로그인 정보 지우기") { clearSessionData() }
                        .foregroundStyle(DenimTheme.signalRed)
                } header: {
                    Text("ChatGPT 연결")
                } footer: {
                    Text("로그인은 ChatGPT 공식 화면에서만 진행됩니다. DenimDex는 비밀번호와 로그인 쿠키를 읽거나 별도로 저장하지 않습니다.")
                }

                Section {
                    LabeledContent("연결 상태", value: "연결되지 않음")
                    Text("현재는 이 기기의 개인 아카이브만 사용합니다. 개인 NAS 연결은 준비 중입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("아카이브 동기화")
                }

                Section {
                    Text("원본 사진은 기본적으로 이 기기에만 보관됩니다. 감정을 시작하면 사진 사본과 분석 요청이 로그인된 ChatGPT로 전송되며, 전송용 사본은 작업 후 폐기됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("사진과 개인정보")
                }

                Section {
                    if let exportURL = diagnosticsStore.exportURL {
                        ShareLink(item: exportURL) {
                            Label("AI 진단 로그 공유", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityHint("가장 최근 AI 분석 실행의 단계 기록을 JSON 파일로 공유합니다")
                    } else {
                        Label("AI 진단 로그 공유", systemImage: "square.and.arrow.up")
                            .foregroundStyle(.secondary)
                        Text("아직 저장된 진단 로그가 없습니다. 가치 분석을 한 번 실행하면 로그가 만들어집니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let storageError = diagnosticsStore.storageError {
                        Text(storageError)
                            .font(.caption)
                            .foregroundStyle(DenimTheme.warningAmber)
                    }
                } header: {
                    Text("AI 진단 로그")
                } footer: {
                    Text("로그에는 실행 단계 이름, 경과 시간, 개수 같은 숫자만 담깁니다. 프롬프트·답변·사진·주소·오류 문구·로그인 정보는 기록되지 않으며, 이 버튼을 눌렀을 때만 공유됩니다.")
                }

                Section {
                    Button(role: .destructive) {
                        for item in items { modelContext.delete(item) }
                        try? modelContext.save()
                    } label: {
                        Label("내 아카이브 전체 삭제", systemImage: "trash")
                    }
                } header: {
                    Text("아카이브 관리")
                } footer: {
                    Text("보관 중인 데님 기록 \(items.count)개가 모두 삭제되며 되돌릴 수 없습니다.")
                }

                Section {
                    LabeledContent("현재 버전", value: appVersionDisplay)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DenimTheme.canvasGradient.ignoresSafeArea())
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.large)
            .tint(DenimTheme.indigo)
            .background(AIBILoginStatusProbeView(store: loginStore))
            .onAppear { loginStore.refresh() }
            .sheet(isPresented: $showLoginSheet) {
                AIBILoginSheet {
                    loginStore.markLoggedIn()
                }
            }
            .alert("ChatGPT 로그인 정보를 지웠어요", isPresented: $showClearedConfirmation) {
                Button("확인", role: .cancel) {}
            }
        }
    }

    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    private func clearSessionData() {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let origins = ["chatgpt.com", "chat.openai.com"]
        store.fetchDataRecords(ofTypes: types) { records in
            let matched = records.filter { record in origins.contains { record.displayName.contains($0) } }
            store.removeData(ofTypes: types, for: matched) {
                loginStore.refresh()
                showClearedConfirmation = true
            }
        }
    }
}
