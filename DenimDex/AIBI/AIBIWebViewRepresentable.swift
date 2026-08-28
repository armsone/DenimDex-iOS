import SwiftUI
import WebKit

/// AIBISession이 소유한 visible WKWebView를 SwiftUI 계층에 그대로 붙인다.
struct AIBIWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// 숨김 실행에 필요한, 실제 뷰 계층에 붙어 있는 컨테이너.
/// AIBISession은 이 컨테이너 안에 375×667 크기의 숨김 WKWebView를 스스로 붙인다.
final class AIBIHiddenContainerHost: ObservableObject {
    let containerView = UIView(frame: .zero)
}

struct AIBIHiddenContainerRepresentable: UIViewRepresentable {
    let host: AIBIHiddenContainerHost

    func makeUIView(context: Context) -> UIView { host.containerView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// AIBI 실행 중 사용자에게 보여주는 visible 브라우저 시트.
/// 취소·수동 붙여넣기 폴백을 항상 제공한다 (기술서 16장).
struct AIBIVisibleBrowserSheet: View {
    @ObservedObject var session: AIBISession
    var providerDisplayName: String
    var onCancel: () -> Void
    var onManualImport: (String) -> Void
    var elapsedSinceSubmission: TimeInterval

    @State private var manualText: String = ""
    @State private var showManualImport = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AIBIProgressRow(session: session, onCancel: onCancel)
                if elapsedSinceSubmission > 0 {
                    let remaining = CountdownFormatter.remainingSeconds(elapsed: elapsedSinceSubmission)
                    VStack(spacing: 5) {
                        HStack {
                            Text("가치 분석 남은 시간")
                            Spacer()
                            Text(CountdownFormatter.formatMinutesSeconds(remaining))
                                .monospacedDigit()
                        }
                        .font(.caption.weight(.semibold))
                        ProgressView(value: CountdownFormatter.progressFraction(elapsed: elapsedSinceSubmission))
                            .tint(DenimTheme.indigo)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 9)
                    .background(Color(uiColor: .secondarySystemBackground))
                }
                if let webView = session.visibleWebView {
                    AIBIWebViewRepresentable(webView: webView)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(providerDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("문구 복사") { session.manualCopyPrompt() }
                        Button("결과 붙여넣기") { showManualImport = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("수동 복구 옵션")
                }
            }
            .sheet(isPresented: $showManualImport) {
                NavigationStack {
                    VStack(spacing: 16) {
                        Text("ChatGPT 화면에서 답변을 복사해 아래에 붙여넣으세요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $manualText)
                            .frame(minHeight: 180)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DenimTheme.hairline))
                        Button("이 내용으로 가져오기") {
                            onManualImport(manualText)
                            showManualImport = false
                        }
                        .buttonStyle(.denimPrimary)
                        .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("결과 붙여넣기")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("닫기") { showManualImport = false }
                        }
                    }
                }
            }
        }
    }
}

/// 숨김 실행 중 호스트 화면에 바로 아래 표시하는 진행 행. 남은 시간·진행 바·취소를 항상 보여준다.
struct AIBIProgressRow: View {
    @ObservedObject var session: AIBISession
    var onCancel: () -> Void

    var body: some View {
        if session.currentPhase != .idle {
            HStack(spacing: 10) {
                if session.currentPhase == .completed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DenimTheme.successGreen)
                } else if session.currentPhase == .failed {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DenimTheme.signalRed)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(session.progress.statusMessage)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if ![.completed, .failed, .cancelled].contains(session.currentPhase) {
                    Button("취소", action: onCancel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DenimTheme.signalRed)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }
}
