import SwiftUI
import WebKit

enum AIBILoginStatus: Equatable {
    case checking
    case loggedIn
    case needsLogin
    /// 정해진 확인 시간 안에 계정 표지도 로그인 표지도 확정하지 못했다(챌린지, 로딩 지연, 접힌 사이드바 등).
    case unknown

    var title: String {
        switch self {
        case .checking: "확인 중"
        case .loggedIn: "로그인됨"
        case .needsLogin: "로그인 필요"
        case .unknown: "확인 불가"
        }
    }

    var iconName: String {
        switch self {
        case .checking: "ellipsis.circle"
        case .loggedIn: "checkmark.circle.fill"
        case .needsLogin: "exclamationmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .checking: .secondary
        case .loggedIn: DenimTheme.successGreen
        case .needsLogin: DenimTheme.warningAmber
        case .unknown: .secondary
        }
    }
}

/// 설정 화면에 표시할 ChatGPT 로그인 상태 저장소.
/// 쿠키 존재, 로그인 버튼 부재, 작성기 준비(`checkReadiness`)만으로 판단하지 않고, 실제 화면에 붙인
/// 375×667 숨김 브라우저에서 보이는 제공사 계정 표지(`authenticatedIndicator`)를 근거로만 로그인됨을 확정한다.
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
        // 로그인 시트가 확인한 상태를 이전 프로브의 늦은 미확정 결과가 덮지 않는다.
        if status == .loggedIn && (newStatus == .checking || newStatus == .unknown) { return }
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
                    switch result {
                    case .needsLogin: store.setStatus(.needsLogin)
                    case .authenticated: store.setStatus(.loggedIn)
                    // 확인 시간 안에 확정하지 못하면(챌린지, 타임아웃, 모호한 사이드바) 로그인됨으로 추정하지 않는다.
                    case .inconclusive: store.setStatus(.unknown)
                    }
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

enum AIBIAuthProbeResult: Equatable {
    case authenticated
    case needsLogin
    /// 정해진 확인 시간이 끝날 때까지 확정하지 못했다. 로그인됨으로 다루지 않는다.
    case inconclusive
}

/// DenimDex 전용 ChatGPT 로그인 상태 판정. 작성기 준비(런타임 `checkReadiness`)와 분리한다.
/// 문구·DOM·URL은 돌려주지 않고 고정된 상태 이름만 돌려준다.
enum AIBIAuthProbeScripts {
    /// 보이는 챌린지·로그인 표지가 계정 표지보다 먼저다. 문서 로드가 끝난 뒤 보이는(숨김/inert 조상 없음,
    /// 크기 있음) 로딩 중이 아닌(`aria-busy` 조상 없음) 제공사 계정 표지가 있을 때만 `authenticated`다.
    /// 작성기만 보이는 화면은 증거가 아니다(`unknown`).
    static let authStateFunction = """
    function (selectors) {
      try {
        function isVisible(el) {
          if (!el) return false;
          if (el.closest("[aria-hidden='true'], [inert]")) return false;
          for (let node = el; node && node.nodeType === 1; node = node.parentElement) {
            const style = window.getComputedStyle(node);
            if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
            if (node.hidden) return false;
          }
          const rect = el.getBoundingClientRect();
          return rect.width > 0 && rect.height > 0;
        }
        function visibleIn(list) {
          const found = [];
          for (const sel of (list || [])) {
            try {
              document.querySelectorAll(sel).forEach(function (el) {
                if (found.indexOf(el) === -1 && isVisible(el)) found.push(el);
              });
            } catch (_) {}
          }
          return found;
        }
        if (visibleIn(selectors.challenge).length > 0) return JSON.stringify({ state: 'challenge' });
        const host = String(location.hostname || '').toLowerCase();
        const path = String(location.pathname || '').toLowerCase();
        if (host === 'auth.openai.com' || path.indexOf('/auth/login') === 0) return JSON.stringify({ state: 'login' });
        if (visibleIn(selectors.login).length > 0) return JSON.stringify({ state: 'login' });
        const loginNames = ['로그인', '로그인하기', 'log in', 'login', 'sign in'];
        for (const el of document.querySelectorAll("button, a, [role='button']")) {
          if (!isVisible(el)) continue;
          const name = String(el.innerText || el.getAttribute('aria-label') || '').replace(/\\s+/g, ' ').trim().toLowerCase();
          if (loginNames.indexOf(name) !== -1) return JSON.stringify({ state: 'login' });
        }
        if (document.readyState === 'loading') return JSON.stringify({ state: 'unknown' });
        const markers = visibleIn(selectors.authenticated).filter(function (el) {
          return !el.closest("[aria-busy='true']");
        });
        return JSON.stringify({ state: markers.length > 0 ? 'authenticated' : 'unknown' });
      } catch (_) {
        return JSON.stringify({ state: 'unknown' });
      }
    }
    """

    /// 모바일 ChatGPT는 접힌 사이드바 안에 계정 메뉴가 있다. Stargram iOS에서 실기기로 확인된 닫힌 사이드바
    /// 열기 표지와 같은 정확한 선택자만 쓰며, 보이는·크기 있는 후보가 정확히 하나이고, 비활성·펼침
    /// (`aria-expanded='true'`)·닫기 이름이 아닐 때만 한 번 누른다. 로그인 판정은 하지 않는다.
    static let revealSidebarFunction = """
    function () {
      try {
        function isVisible(el) {
          if (!el) return false;
          if (el.closest("[aria-hidden='true'], [inert]")) return false;
          for (let node = el; node && node.nodeType === 1; node = node.parentElement) {
            const style = window.getComputedStyle(node);
            if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
            if (node.hidden) return false;
          }
          const rect = el.getBoundingClientRect();
          return rect.width > 0 && rect.height > 0;
        }
        const openSelectors = [
          "[data-testid='open-sidebar-button']",
          "button[aria-label='Open sidebar']",
          "button[aria-label='사이드바 열기']",
          "button[aria-label='사이드바열기']",
          "button[title='Open sidebar']",
          "button[title='사이드바 열기']",
          "button[aria-label='사이드바 표시/숨기기'][aria-controls='app-shell-sidebar'][aria-expanded='false']",
          "button[aria-label='사이드바 보기'][aria-controls='browser-sidebar-popover'][aria-expanded='false']"
        ];
        const candidates = [];
        for (const sel of openSelectors) {
          try {
            document.querySelectorAll(sel).forEach(function (el) {
              if (candidates.indexOf(el) === -1) candidates.push(el);
            });
          } catch (_) {}
        }
        const visible = candidates.filter(isVisible).filter(function (el) {
          const label = String(el.getAttribute('aria-label') || el.getAttribute('title') || '').toLowerCase();
          return label.indexOf('close') === -1 && label.indexOf('닫기') === -1;
        });
        if (visible.length !== 1) return false;
        const target = visible[0];
        if (target.disabled || target.getAttribute('aria-disabled') === 'true' || target.getAttribute('aria-expanded') === 'true') return false;
        target.click();
        return true;
      } catch (_) {
        return false;
      }
    }
    """
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
        private enum PageState {
            case authenticated, login, challenge, unknown
        }

        /// 문서당 사이드바 열기 클릭 상한(Stargram iOS와 같은 값). 모호한 확인에서만 누르고 새 문서에서만 초기화한다.
        private static let maxSidebarOpenAttempts = 6

        private let config: AIBIProviderConfig
        private let waitsForAuthentication: Bool
        private let onResolved: (AIBIAuthProbeResult) -> Void
        weak var webView: WKWebView?
        private var didResolve = false
        private var pollTask: Task<Void, Never>?
        /// 첫 문서 커밋에서 한 번만 정한다. 리디렉션·재로드가 확인 시간을 늘리지 않는다.
        private var deadline: Date?
        private var sidebarOpenAttempts = 0

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

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            sidebarOpenAttempts = 0
            if deadline == nil {
                deadline = Date().addingTimeInterval(waitsForAuthentication ? 600 : 8)
            }
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                await self?.pollUntilResolved(webView: webView)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // 첫 문서조차 열지 못하면 정해진 시간 안의 확인이 불가능하다. 리디렉션 취소(-999)는 실패가 아니다.
            guard deadline == nil, (error as NSError).code != NSURLErrorCancelled else { return }
            finishInconclusive()
        }

        private func pollUntilResolved(webView: WKWebView) async {
            while !Task.isCancelled, !didResolve, let deadline, Date() < deadline {
                switch await pageState(webView: webView) {
                case .authenticated:
                    resolve(.authenticated)
                    return
                case .login:
                    onResolved(.needsLogin)
                    if !waitsForAuthentication {
                        didResolve = true
                        return
                    }
                case .challenge:
                    break
                case .unknown:
                    if sidebarOpenAttempts < Self.maxSidebarOpenAttempts, await revealSidebar(webView: webView) {
                        sidebarOpenAttempts += 1
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        continue
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            if !Task.isCancelled { finishInconclusive() }
        }

        private func pageState(webView: WKWebView) async -> PageState {
            let script = "(\(AIBIAuthProbeScripts.authStateFunction))(\(selectorsJson()))"
            guard let raw = try? await webView.evaluateJavaScript(script) as? String,
                  let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unknown }
            switch json["state"] as? String {
            case "authenticated": return .authenticated
            case "login": return .login
            case "challenge": return .challenge
            default: return .unknown
            }
        }

        private func revealSidebar(webView: WKWebView) async -> Bool {
            let script = "(\(AIBIAuthProbeScripts.revealSidebarFunction))()"
            return (try? await webView.evaluateJavaScript(script) as? Bool) == true
        }

        private func selectorsJson() -> String {
            let selectors: [String: [String]] = [
                "authenticated": config.selectors.authenticatedIndicator ?? [],
                "login": config.selectors.loginIndicator,
                "challenge": config.selectors.challengeIndicator
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: selectors),
                  let str = String(data: data, encoding: .utf8) else { return "{}" }
            return str
        }

        private func resolve(_ result: AIBIAuthProbeResult) {
            guard !didResolve else { return }
            didResolve = true
            onResolved(result)
        }

        private func finishInconclusive() {
            resolve(.inconclusive)
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
                        if result == .authenticated {
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
