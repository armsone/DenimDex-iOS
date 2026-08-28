import SwiftUI
import WebKit

enum AIBILoginStatus: Equatable {
    case checking
    case loggedIn
    case needsLogin

    var title: String {
        switch self {
        case .checking: "확인 중"
        case .loggedIn: "로그인됨"
        case .needsLogin: "로그인 필요"
        }
    }

    var iconName: String {
        switch self {
        case .checking: "ellipsis.circle"
        case .loggedIn: "checkmark.circle.fill"
        case .needsLogin: "exclamationmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .checking: .secondary
        case .loggedIn: DenimTheme.successGreen
        case .needsLogin: DenimTheme.warningAmber
        }
    }
}

/// 설정 화면에 표시할 ChatGPT 로그인 상태 저장소.
/// 쿠키 존재나 로그인 버튼 부재만으로 판단하지 않고, 실제 화면에 붙인 375×667 숨김 브라우저에서
/// `checkReadiness` 런타임 결과(작성기 등장 + 로그인 표식 부재)를 근거로만 상태를 확정한다.
@MainActor
final class AIBILoginStatusStore: ObservableObject {
    @Published private(set) var status: AIBILoginStatus = .checking
    @Published fileprivate var refreshToken = 0

    func refresh() {
        status = .checking
        refreshToken += 1
    }

    func markLoggedIn() {
        status = .loggedIn
    }

    fileprivate func setStatus(_ newStatus: AIBILoginStatus) {
        if status == .loggedIn && newStatus == .checking { return }
        status = newStatus
    }
}

/// 화면에 보이지 않지만 실제 뷰 계층에 375×667로 붙는 로그인 상태 프로브.
struct AIBILoginStatusProbeView: View {
    @ObservedObject var store: AIBILoginStatusStore

    var body: some View {
        Group {
            if let config = AIBIProviderRegistry.chatGPT {
                AIBILoginProbeWebView(config: config) { result in
                    if result.hasLogin {
                        store.setStatus(.needsLogin)
                    } else if result.authenticated {
                        store.setStatus(.loggedIn)
                    }
                    // 애매한 경우 (챌린지, 타임아웃)에는 `.checking`을 유지하고 확정하지 않는다.
                }
                .id(store.refreshToken)
                .frame(width: 375, height: 667)
            }
        }
        .frame(width: 375, height: 667)
        .offset(x: -10_000, y: -10_000)
        .opacity(0.001)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct AIBIAuthProbeResult {
    let authenticated: Bool
    let hasLogin: Bool
    let hasChallenge: Bool
}

private struct AIBILoginProbeWebView: UIViewRepresentable {
    let config: AIBIProviderConfig
    var waitsForAuthentication = false
    let onResolved: (AIBIAuthProbeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            config: config,
            waitsForAuthentication: waitsForAuthentication,
            onResolved: onResolved
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        guard let url = URL(string: config.initialUrl) else { return webView }
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.cancel()
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let config: AIBIProviderConfig
        private let waitsForAuthentication: Bool
        private let onResolved: (AIBIAuthProbeResult) -> Void
        weak var webView: WKWebView?
        private var didResolve = false
        private var pollTask: Task<Void, Never>?

        init(
            config: AIBIProviderConfig,
            waitsForAuthentication: Bool,
            onResolved: @escaping (AIBIAuthProbeResult) -> Void
        ) {
            self.config = config
            self.waitsForAuthentication = waitsForAuthentication
            self.onResolved = onResolved
        }

        func cancel() {
            pollTask?.cancel()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pollTask?.cancel()
            pollTask = Task { [weak self] in
                await self?.pollUntilResolved(webView: webView)
            }
        }

        private func pollUntilResolved(webView: WKWebView) async {
            let deadline = Date().addingTimeInterval(waitsForAuthentication ? 600 : 8)
            while !Task.isCancelled, Date() < deadline, !didResolve {
                await ensureRuntime(webView: webView)
                if let result = try? await webView.evaluateJavaScript(
                    "window.__AIBI_RUNTIME__.checkReadiness(\(configJson()))"
                ) as? String, let parsed = parse(result) {
                    if parsed.authenticated {
                        resolve(parsed)
                        return
                    }
                    if parsed.hasLogin {
                        onResolved(parsed)
                        if !waitsForAuthentication {
                            didResolve = true
                            return
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        private func ensureRuntime(webView: WKWebView) async {
            let checkScript = "typeof window.__AIBI_RUNTIME__ !== 'undefined'"
            if let exists = try? await webView.evaluateJavaScript(checkScript) as? Bool, exists { return }
            _ = try? await webView.evaluateJavaScript(AIBIProviderRegistry.runtimeJavaScript)
        }

        private func configJson() -> String {
            guard let data = try? JSONEncoder().encode(config), let str = String(data: data, encoding: .utf8) else { return "{}" }
            return str
        }

        private func parse(_ raw: String) -> AIBIAuthProbeResult? {
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["success"] as? Bool == true,
                  let payload = json["data"] as? [String: Any] else { return nil }
            let isLoggedIn = payload["isLoggedIn"] as? Bool ?? true
            let isReady = payload["isReady"] as? Bool ?? false
            let hasChallenge = payload["hasChallenge"] as? Bool ?? false
            let reason = payload["reason"] as? String
            let hasLogin = reason == "AUTH_REQUIRED" || !isLoggedIn
            let authenticated = isLoggedIn && !hasChallenge && isReady
            return AIBIAuthProbeResult(authenticated: authenticated, hasLogin: hasLogin, hasChallenge: hasChallenge)
        }

        private func resolve(_ result: AIBIAuthProbeResult) {
            guard !didResolve else { return }
            didResolve = true
            onResolved(result)
        }
    }
}

/// 설정 화면에서 사용자가 직접 로그인만 하기 위한 공식 브라우저 시트.
/// 로그인 성공을 딱 한 번만 알리고 닫는다.
struct AIBILoginSheet: View {
    var onLoginConfirmed: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var didConfirm = false
    @State private var hasDismissed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if didConfirm {
                    Label("로그인을 확인했어요", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DenimTheme.successGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemBackground))
                } else {
                    Text("ChatGPT에 로그인해주세요. 로그인이 확인되면 이 창이 자동으로 닫히고 가치 분석을 계속합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground))
                }
                if let config = AIBIProviderRegistry.chatGPT {
                    AIBILoginProbeWebView(config: config, waitsForAuthentication: true) { result in
                        if result.authenticated {
                            confirmLogin()
                        }
                    }
                } else {
                    Text("ChatGPT 설정을 불러오지 못했습니다.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("ChatGPT 로그인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismissOnce() }
                }
            }
        }
    }

    private func confirmLogin() {
        guard !didConfirm else { return }
        didConfirm = true
        onLoginConfirmed?()
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            dismissOnce()
        }
    }

    private func dismissOnce() {
        guard !hasDismissed else { return }
        hasDismissed = true
        dismiss()
    }
}
