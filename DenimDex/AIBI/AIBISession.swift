//
//  AIBISession.swift
//  Portable AIBI core orchestrator — adapted from the canonical AIBI Apple reference
//  (/Users/armsone/.codex/skills/aibi/assets/apple/AIBIEngine.swift).
//  No DenimDex product knowledge lives here: prompt text, result schema, and value
//  rules belong to the host layer (Services/, Features/Scan).
//

import Foundation
import WebKit
import Combine
import UIKit

@MainActor
final class AIBISession: NSObject, ObservableObject {
    @Published private(set) var currentPhase: AIBIPhase = .idle
    @Published private(set) var progress: AIBIProgress = .initial
    @Published private(set) var isVisibleBrowserPresented: Bool = false
    @Published private(set) var activeProviderId: String?
    @Published private(set) var pendingResult: AIBIResult?
    @Published private(set) var lastErrorMessage: String?

    var timingProfile: AIBITimingProfile = .default
    weak var resultSink: AIBIResultSink?

    private var activeTask: AIBITask?
    private var activeConfig: AIBIProviderConfig?
    private var generationId: UInt64 = 0

    private var hiddenWebView: WKWebView?
    private(set) var visibleWebView: WKWebView?

    private let webConfiguration: WKWebViewConfiguration

    private var stateTimer: Timer?
    private var elapsedTimer: Timer?
    private var taskStartTime: Date?
    private var consecutiveMisses: Int = 0
    private var submitAttemptCount: Int = 0
    private var baselineAssistantCount: Int = 0
    private var stabilityText: String?
    private var stabilityTickCount: Int = 0
    private var pendingAttachmentURLs: [URL] = []
    private var nativeAttachmentPanelHandled = false

    private var runtimeJavaScript: String = ""

    init(runtimeJs: String, configuration: WKWebViewConfiguration? = nil) {
        self.runtimeJavaScript = runtimeJs
        if let config = configuration {
            self.webConfiguration = config
        } else {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            self.webConfiguration = config
        }
        super.init()
    }

    // MARK: - Public Task Entrypoints

    func startTask(task: AIBITask, providerConfig: AIBIProviderConfig, hiddenContainer: UIView? = nil) {
        cancelCurrentTask()

        self.activeTask = task
        self.activeConfig = providerConfig
        self.activeProviderId = task.providerId
        self.generationId &+= 1
        self.taskStartTime = Date()
        self.lastErrorMessage = nil
        self.pendingResult = nil

        let media = providerConfig.mediaCapabilities
        if task.attachments.count > 20 ||
            (!task.attachments.isEmpty &&
                (media?.supportsImages != true || task.attachments.count > (media?.maxImagesPerTask ?? 0))) {
            failWithError("이 작업에서는 사진 첨부를 지원하지 않습니다.")
            return
        }

        updatePhase(.initializing, message: "\(providerConfig.displayName)에 연결하는 중…")
        startElapsedTimer()

        if task.presentation == .alwaysVisible {
            presentVisibleBrowser()
        } else if let hiddenContainer {
            mountHiddenBrowser(in: hiddenContainer)
        } else {
            presentVisibleBrowser()
        }

        guard let targetUrl = URL(string: providerConfig.initialUrl) else {
            failWithError("잘못된 제공자 주소입니다.")
            return
        }

        let currentGen = self.generationId
        let webView = activeWebView
        let request = URLRequest(url: targetUrl)
        updatePhase(.navigating, message: "\(providerConfig.displayName) 불러오는 중…")
        webView?.load(request)

        scheduleReadinessCheck(generation: currentGen)
    }

    func manualCopyPrompt() {
        guard let prompt = activeTask?.promptText else { return }
        UIPasteboard.general.string = prompt
    }

    func manualImportText(_ text: String) {
        guard let task = activeTask else { return }
        let cleaned = cleanOutputLocally(text)
        let result = AIBIResult(taskId: task.id, providerId: task.providerId, rawText: text, cleanedText: cleaned, isComplete: true)
        completeWithResult(result)
    }

    func cancelCurrentTask() {
        stopAllTimers()
        generationId &+= 1
        clearPendingAttachmentFiles()
        if currentPhase != .idle {
            updatePhase(.cancelled, message: "취소됨")
        }
        destroyHiddenBrowser()
    }

    func fullReset() {
        stopAllTimers()
        generationId &+= 1
        activeTask = nil
        activeConfig = nil
        activeProviderId = nil
        pendingResult = nil
        lastErrorMessage = nil
        clearPendingAttachmentFiles()
        destroyHiddenBrowser()
        destroyVisibleBrowser()
        updatePhase(.idle, message: "대기 중")
    }

    func dismissVisibleBrowserForCancel() {
        cancelCurrentTask()
        destroyVisibleBrowser()
    }

    // MARK: - State machine

    private func updatePhase(_ phase: AIBIPhase, message: String, isWaiting: Bool = false) {
        self.currentPhase = phase
        let elapsed = taskStartTime.map { Date().timeIntervalSince($0) } ?? 0
        self.progress = AIBIProgress(phase: phase, elapsedSeconds: elapsed, statusMessage: message, isWaiting: isWaiting)
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.taskStartTime != nil else { return }
                let elapsed = Date().timeIntervalSince(self.taskStartTime!)
                self.progress = AIBIProgress(phase: self.currentPhase, elapsedSeconds: elapsed, statusMessage: self.progress.statusMessage, isWaiting: self.progress.isWaiting)
            }
        }
    }

    private func stopAllTimers() {
        stateTimer?.invalidate(); stateTimer = nil
        elapsedTimer?.invalidate(); elapsedTimer = nil
    }

    // MARK: - Readiness

    private func scheduleReadinessCheck(generation: UInt64) {
        stateTimer?.invalidate()
        consecutiveMisses = 0
        let startTime = Date()

        stateTimer = Timer.scheduledTimer(withTimeInterval: timingProfile.readinessCadence, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self, self.generationId == generation else { timer.invalidate(); return }
                if Date().timeIntervalSince(startTime) > self.timingProfile.readinessTimeout {
                    timer.invalidate()
                    self.failWithError("ChatGPT 입력 화면을 준비하지 못했습니다. 잠시 후 다시 시도해주세요.")
                    return
                }
                await self.performReadinessProbe(generation: generation, timer: timer)
            }
        }
    }

    private func performReadinessProbe(generation: UInt64, timer: Timer) async {
        guard let config = activeConfig, let webView = activeWebView else { return }
        await ensureRuntimeInjected(webView: webView)

        let script = "window.__AIBI_RUNTIME__.checkReadiness(\(configJson(config)))"
        guard let result = try? await evaluateScript(script, on: webView) else { return }
        guard generationId == generation else { return }
        guard let json = parseJson(result), json["success"] as? Bool == true, let data = json["data"] as? [String: Any] else { return }

        let isReady = data["isReady"] as? Bool ?? false
        let isLoggedIn = data["isLoggedIn"] as? Bool ?? true
        let hasChallenge = data["hasChallenge"] as? Bool ?? false
        let reason = data["reason"] as? String

        if !isLoggedIn {
            timer.invalidate(); escalateToVisible(reason: .authenticationRequired); return
        }
        if hasChallenge {
            timer.invalidate(); escalateToVisible(reason: .securityChallengePresented); return
        }
        if isReady {
            timer.invalidate()
            await recordBaselineAndInject(generation: generation)
        } else if reason == "INPUT_NOT_FOUND" {
            consecutiveMisses += 1
            // ChatGPT의 모바일 화면은 로그인 세션 복원 뒤 작성기를 늦게 교체한다.
            // 숨김 실행을 몇 초 만에 포기해 브라우저를 노출하지 않고 전체 readinessTimeout 동안 기다린다.
        }
    }

    // MARK: - Injection & submission

    private func recordBaselineAndInject(generation: UInt64) async {
        guard let config = activeConfig, let webView = activeWebView, let task = activeTask else { return }
        updatePhase(.injectingPrompt, message: "프롬프트 준비하는 중…")

        let baselineScript = "window.__AIBI_RUNTIME__.getBaselineState(\(configJson(config)))"
        if let baselineResult = try? await evaluateScript(baselineScript, on: webView),
           let json = parseJson(baselineResult), let data = json["data"] as? [String: Any] {
            self.baselineAssistantCount = data["assistantCount"] as? Int ?? 0
        }

        if !task.attachments.isEmpty {
            let attached = await attachImagesAtomically(task.attachments, config: config, webView: webView, generation: generation)
            guard attached else {
                if generationId == generation {
                    failWithError("사진을 ChatGPT에 모두 첨부하지 못했습니다. 다시 시도해주세요.")
                }
                return
            }
        }

        // ChatGPT는 첨부 직후나 초기 hydration 중에 작성기 DOM 노드를 자주 교체한다
        // (aibi-providers.json chatgpt.quirks.lateDomReplacement). 첫 번째 일시적 실패나
        // 검증 불일치에서 바로 실패로 단정하지 않고, 유한한 횟수만큼 다시 찾아 재시도한다.
        let escapedPrompt = escapeJsString(task.promptText)
        // 숨김 WebView는 isUserInteractionEnabled = false라 사용자가 직접 타이핑할 수 없다.
        // 그 작성기에 남아 있는 내용은 실제 사용자 초안이 아니라 이전 자동화 시도의 잔여물뿐이므로
        // 안전하게 덮어써도 된다. 화면에 노출된 뒤에는(escalateToVisible 이후) 사용자가 실제로
        // 입력할 수 있으므로 기존의 보존 규칙을 그대로 따른다.
        let safeToOverwrite = task.forceFill || !isVisibleBrowserPresented
        let injectScript = "window.__AIBI_RUNTIME__.injectPrompt(\(configJson(config)), '\(escapedPrompt)', \(safeToOverwrite))"
        let verifyScript = "window.__AIBI_RUNTIME__.verifyPromptInjected(\(configJson(config)), '\(escapedPrompt)')"

        var attempt = 0
        while attempt < timingProfile.promptInjectionRetryLimit {
            attempt += 1
            guard generationId == generation else { return }

            guard let injectResult = try? await evaluateScript(injectScript, on: webView) else {
                try? await Task.sleep(nanoseconds: UInt64(timingProfile.promptInjectionRetryDelay * 1_000_000_000))
                continue
            }
            guard generationId == generation else { return }

            let injectJson = parseJson(injectResult)
            let injectSucceeded = injectJson?["success"] as? Bool ?? false
            let injectCode = injectJson?["code"] as? String

            var verifiedMatch = false
            if injectSucceeded {
                // JS 예외가 없다고 해서 프롬프트가 실제로 남아 있다는 뜻은 아니다.
                // injectPrompt와 이 검증 호출 사이에 작성기 노드가 교체될 수 있으므로 다시 읽어 확인한다.
                if let verifyResult = try? await evaluateScript(verifyScript, on: webView),
                   let verifyJson = parseJson(verifyResult),
                   let verifyData = verifyJson["data"] as? [String: Any] {
                    verifiedMatch = verifyData["matches"] as? Bool ?? false
                }
            }

            switch Self.classifyInjectionAttempt(injectSucceeded: injectSucceeded, injectCode: injectCode, verifiedMatch: verifiedMatch) {
            case .injected:
                startSubmissionLoop(generation: generation)
                return
            case .terminal:
                // 사용자가 입력창에 이미 다른 내용을 남겨둔 경우: force 없이는 절대 덮어쓰지 않고,
                // 재시도도 하지 않는다.
                failWithError("ChatGPT 입력창에 이미 다른 내용이 있어 자동 입력을 건너뛰었습니다. 직접 확인해주세요.")
                return
            case .retryable:
                try? await Task.sleep(nanoseconds: UInt64(timingProfile.promptInjectionRetryDelay * 1_000_000_000))
            }
        }

        guard generationId == generation else { return }
        failWithError("ChatGPT 입력 화면을 제어하지 못했습니다. 다시 시도해주세요.")
    }

    /// 순수 분류 함수: injectPrompt/verifyPromptInjected 결과만으로 다음 행동을 결정한다.
    /// WebView 없이 단위 테스트가 가능하도록 부수효과 없이 분리했다.
    nonisolated static func classifyInjectionAttempt(
        injectSucceeded: Bool,
        injectCode: String?,
        verifiedMatch: Bool
    ) -> AIBIPromptInjectionOutcome {
        if injectCode == "EXISTING_TEXT_PRESERVED" {
            return .terminal
        }
        if injectSucceeded && verifiedMatch {
            return .injected
        }
        return .retryable
    }

    private func attachImagesAtomically(_ attachments: [AIBIMediaAttachment], config: AIBIProviderConfig, webView: WKWebView, generation: UInt64) async -> Bool {
        updatePhase(.attachingMedia, message: "사진 \(attachments.count)장 첨부하는 중…", isWaiting: true)
        let encodedConfig = configJson(config)
        let stateScript = "window.__AIBI_RUNTIME__.getAttachmentState(\(encodedConfig))"
        let baseline = (try? await evaluateScript(stateScript, on: webView)).flatMap(parseAttachmentPreviewCount) ?? 0

        if #available(iOS 18.4, *) {
            do {
                pendingAttachmentURLs = try makeTemporaryAttachmentFiles(attachments)
                nativeAttachmentPanelHandled = false
                for _ in 0..<3 where generationId == generation && !nativeAttachmentPanelHandled {
                    _ = try? await evaluateScript("window.__AIBI_RUNTIME__.prepareAttachmentInput(\(encodedConfig))", on: webView)
                    _ = try? await evaluateScript("window.__AIBI_RUNTIME__.openAttachmentPanel(\(encodedConfig))", on: webView)
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
                if nativeAttachmentPanelHandled, await waitForAttachmentCount(baseline + attachments.count, stateScript: stateScript, webView: webView, generation: generation) {
                    clearPendingAttachmentFiles()
                    return true
                }
                clearPendingAttachmentFiles()
            } catch {
                clearPendingAttachmentFiles()
            }
        }

        for _ in 0..<2 where generationId == generation {
            _ = try? await evaluateScript("window.__AIBI_RUNTIME__.prepareAttachmentInput(\(encodedConfig))", on: webView)
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        guard generationId == generation else { return false }

        let ordered = attachments.sorted { $0.sourceIndex < $1.sourceIndex }
        guard let beginResult = try? await evaluateScript("window.__AIBI_RUNTIME__.beginAttachmentBatch(\(encodedConfig), \(ordered.count))", on: webView),
              parseJson(beginResult)?["success"] as? Bool == true else { return false }

        for (index, attachment) in ordered.enumerated() {
            let image = ["dataUrl": attachment.dataURL, "mimeType": attachment.mimeType, "filename": attachment.filename]
            guard let imageData = try? JSONSerialization.data(withJSONObject: image),
                  let imageJson = String(data: imageData, encoding: .utf8),
                  let staged = try? await evaluateScript("window.__AIBI_RUNTIME__.stageAttachment(\(imageJson), \(index))", on: webView),
                  parseJson(staged)?["success"] as? Bool == true else {
                _ = try? await evaluateScript("window.__AIBI_RUNTIME__.clearAttachmentBatch()", on: webView)
                return false
            }
        }
        guard let attachResult = try? await evaluateScript("window.__AIBI_RUNTIME__.commitAttachmentBatch(\(encodedConfig))", on: webView),
              parseJson(attachResult)?["success"] as? Bool == true else { return false }

        return await waitForAttachmentCount(baseline + attachments.count, stateScript: stateScript, webView: webView, generation: generation)
    }

    private func waitForAttachmentCount(_ expectedCount: Int, stateScript: String, webView: WKWebView, generation: UInt64) async -> Bool {
        let deadline = Date().addingTimeInterval(timingProfile.attachmentTimeout)
        while generationId == generation && Date() < deadline {
            if let state = try? await evaluateScript(stateScript, on: webView),
               let count = parseAttachmentPreviewCount(state), count == expectedCount {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(timingProfile.attachmentCadence * 1_000_000_000))
        }
        return false
    }

    private func makeTemporaryAttachmentFiles(_ attachments: [AIBIMediaAttachment]) throws -> [URL] {
        clearPendingAttachmentFiles()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIBIUploads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            return try attachments.sorted { $0.sourceIndex < $1.sourceIndex }.map { attachment in
                let url = directory.appendingPathComponent(attachment.filename)
                try attachment.data.write(to: url, options: .atomic)
                return url
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func clearPendingAttachmentFiles() {
        let directories = Set(pendingAttachmentURLs.map { $0.deletingLastPathComponent() })
        pendingAttachmentURLs = []
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func parseAttachmentPreviewCount(_ string: String) -> Int? {
        guard let data = parseJson(string)?["data"] as? [String: Any] else { return nil }
        return data["previewCount"] as? Int
    }

    private func startSubmissionLoop(generation: UInt64) {
        stateTimer?.invalidate()
        submitAttemptCount = 1
        let startTime = Date()
        updatePhase(.submitting, message: "프롬프트 전송하는 중…")

        stateTimer = Timer.scheduledTimer(withTimeInterval: timingProfile.submitCadence + timingProfile.submitVerificationDelay, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self, self.generationId == generation else { timer.invalidate(); return }
                if Date().timeIntervalSince(startTime) > self.timingProfile.submitTimeout {
                    timer.invalidate()
                    // ChatGPT가 전송을 받았어도 모바일 DOM의 확인 표식이 늦는 경우가 있다.
                    // 브라우저를 노출하거나 재전송하지 말고 기존 대화의 결과 관찰로 이어간다.
                    self.startObservationLoop(generation: generation)
                    return
                }
                await self.performSubmitAttempt(generation: generation, timer: timer)
            }
        }
    }

    private func performSubmitAttempt(generation: UInt64, timer: Timer) async {
        guard let config = activeConfig, let webView = activeWebView else { return }
        let submitScript = "window.__AIBI_RUNTIME__.submitPrompt(\(configJson(config)), \(submitAttemptCount))"
        _ = try? await evaluateScript(submitScript, on: webView)
        guard generationId == generation else { return }

        try? await Task.sleep(nanoseconds: UInt64(timingProfile.submitVerificationDelay * 1_000_000_000))
        guard generationId == generation else { return }

        let verifyScript = "window.__AIBI_RUNTIME__.verifySubmission(\(configJson(config)), \(baselineAssistantCount))"
        if let verifyResult = try? await evaluateScript(verifyScript, on: webView),
           let json = parseJson(verifyResult), let data = json["data"] as? [String: Any],
           data["submitted"] as? Bool == true {
            timer.invalidate()
            startObservationLoop(generation: generation)
        } else {
            submitAttemptCount += 1
        }
    }

    // MARK: - Observation & stability

    private func startObservationLoop(generation: UInt64) {
        stateTimer?.invalidate()
        // 숨김 브라우저의 작성기가 first responder로 남으면 iOS가 호스트 앱 하단에
        // 이전/다음/완료 입력 보조 막대를 띄운다. 전송이 끝난 뒤에는 입력 포커스가
        // 필요하지 않으므로 즉시 해제해 스캔 화면에 WebKit UI가 새어 나오지 않게 한다.
        dismissHiddenBrowserInputUI()
        stabilityText = nil
        stabilityTickCount = 0
        updatePhase(.generating, message: "답변을 기다리는 중…", isWaiting: true)

        stateTimer = Timer.scheduledTimer(withTimeInterval: timingProfile.observationCadence, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self, self.generationId == generation else { timer.invalidate(); return }
                await self.performObservationTick(generation: generation, timer: timer)
            }
        }
    }

    private func performObservationTick(generation: UInt64, timer: Timer) async {
        guard let config = activeConfig, let webView = activeWebView, let task = activeTask else { return }
        let script = "window.__AIBI_RUNTIME__.observeGeneration(\(configJson(config)), \(baselineAssistantCount))"
        guard let result = try? await evaluateScript(script, on: webView) else { return }
        guard generationId == generation else { return }
        guard let json = parseJson(result), json["success"] as? Bool == true, let data = json["data"] as? [String: Any] else { return }

        let phaseStr = data["phase"] as? String ?? "GENERATING"
        let isGenerating = data["isGenerating"] as? Bool ?? true
        let hasNewAnswer = data["hasNewAnswer"] as? Bool ?? false
        let rawText = data["rawText"] as? String ?? ""
        let errorMessage = data["errorMessage"] as? String

        if phaseStr == "FAILED", let err = errorMessage {
            timer.invalidate(); failWithError(err); return
        }
        if phaseStr == "FALLBACK_REQUIRED" {
            timer.invalidate(); escalateToVisible(reason: .securityChallengePresented); return
        }

        if hasNewAnswer && !isGenerating && !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let prev = stabilityText, prev == rawText {
                stabilityTickCount += 1
                if stabilityTickCount >= timingProfile.stabilityRequiredTicks {
                    timer.invalidate()
                    let cleanScript = "window.__AIBI_RUNTIME__.cleanOutput('\(escapeJsString(rawText))', '\(task.providerId)')"
                    var cleaned = rawText
                    if let cleanResult = try? await evaluateScript(cleanScript, on: webView),
                       let cleanJson = parseJson(cleanResult), let cleanData = cleanJson["data"] as? [String: Any],
                       let cleanText = cleanData["cleanedText"] as? String {
                        cleaned = cleanText
                    }
                    let finalResult = AIBIResult(taskId: task.id, providerId: task.providerId, rawText: rawText, cleanedText: cleaned, isComplete: true)
                    completeWithResult(finalResult)
                }
            } else {
                stabilityText = rawText
                stabilityTickCount = 0
                updatePhase(.stabilizing, message: "답변을 받는 중…", isWaiting: true)
            }
        } else {
            stabilityText = nil
            stabilityTickCount = 0
            updatePhase(.generating, message: "답변을 기다리는 중…", isWaiting: true)
        }
    }

    // MARK: - Completion & fallback

    private func completeWithResult(_ result: AIBIResult) {
        stopAllTimers()
        self.pendingResult = result
        UIPasteboard.general.string = result.cleanedText

        if let sink = resultSink {
            switch sink.commitResult(result) {
            case .success:
                updatePhase(.completed, message: "가져오기 완료")
                dismissVisibleBrowser()
                destroyHiddenBrowser()
            case .failure(let err):
                updatePhase(.failed, message: "결과 검증 실패: \(err.localizedDescription)")
            }
        } else {
            updatePhase(.completed, message: "결과 준비됨")
            dismissVisibleBrowser()
            destroyHiddenBrowser()
        }
    }

    private func failWithError(_ message: String) {
        stopAllTimers()
        self.lastErrorMessage = message
        updatePhase(.failed, message: message)
        destroyHiddenBrowser()
    }

    private func escalateToVisible(reason: AIBIFallbackReason) {
        if activeTask?.presentation == .hiddenOnly {
            let message: String
            switch reason {
            case .authenticationRequired:
                message = "ChatGPT 로그인이 필요합니다. 설정의 AI 로그인 관리에서 먼저 로그인해주세요."
            case .securityChallengePresented:
                message = "ChatGPT 보안 확인이 필요합니다. 설정의 AI 로그인 관리에서 확인해주세요."
            case .navigationDisallowed:
                message = "ChatGPT가 허용되지 않은 페이지로 이동했습니다. 설정에서 로그인 상태를 확인해주세요."
            default:
                message = "숨김 분석을 계속할 수 없습니다. 잠시 후 다시 시도해주세요."
            }
            failWithError(message)
            return
        }
        stopAllTimers()
        updatePhase(.fallbackRequired, message: "필요한 작업을 위해 브라우저를 여는 중…")
        promoteCurrentBrowserToVisible()

        guard let config = activeConfig else { return }
        if visibleWebView?.url == nil, let targetUrl = URL(string: config.initialUrl) {
            visibleWebView?.load(URLRequest(url: targetUrl))
        }

        // 로그인이나 보안 확인을 사용자가 마치면 같은 페이지와 첨부 상태에서 자동 실행을 재개한다.
        scheduleReadinessCheck(generation: generationId)
    }

    // MARK: - Browser lifecycle

    private var activeWebView: WKWebView? {
        isVisibleBrowserPresented ? visibleWebView : hiddenWebView
    }

    private func mountHiddenBrowser(in parent: UIView) {
        guard hiddenWebView == nil else { return }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: webConfiguration)
        // 화면 밖 컨테이너가 이미 사용자에게 보이지 않게 한다. WebKit 자체를 투명하게 만들면
        // 일부 SPA가 렌더링/수화 작업을 늦춰 작성기를 찾지 못할 수 있으므로 실제 표시 상태를 유지한다.
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.alpha = 1
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        parent.addSubview(webView)
        parent.sendSubviewToBack(webView)
        self.hiddenWebView = webView
    }

    private func destroyHiddenBrowser() {
        hiddenWebView?.stopLoading()
        hiddenWebView?.navigationDelegate = nil
        hiddenWebView?.uiDelegate = nil
        hiddenWebView?.removeFromSuperview()
        hiddenWebView = nil
    }

    private func presentVisibleBrowser() {
        if visibleWebView == nil {
            let webView = WKWebView(frame: .zero, configuration: webConfiguration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            self.visibleWebView = webView
        }
        self.isVisibleBrowserPresented = true
    }

    /// 숨김 실행 중이던 바로 그 WebView를 보이는 시트로 넘긴다.
    /// 새 페이지를 만들거나 다시 로드하면 로그인·첨부·작성기 상태가 사라져 seamless takeover가 깨진다.
    private func promoteCurrentBrowserToVisible() {
        if let hiddenWebView {
            hiddenWebView.removeFromSuperview()
            hiddenWebView.alpha = 1
            hiddenWebView.isOpaque = true
            hiddenWebView.backgroundColor = .systemBackground
            hiddenWebView.isUserInteractionEnabled = true
            hiddenWebView.accessibilityElementsHidden = false
            hiddenWebView.frame = .zero
            self.visibleWebView = hiddenWebView
            self.hiddenWebView = nil
        } else {
            presentVisibleBrowser()
        }
        isVisibleBrowserPresented = true
    }

    private func dismissVisibleBrowser() {
        self.isVisibleBrowserPresented = false
    }

    private func destroyVisibleBrowser() {
        visibleWebView?.stopLoading()
        visibleWebView?.navigationDelegate = nil
        visibleWebView?.uiDelegate = nil
        visibleWebView = nil
        isVisibleBrowserPresented = false
    }

    // MARK: - JS evaluation

    private func ensureRuntimeInjected(webView: WKWebView) async {
        guard !runtimeJavaScript.isEmpty, let url = webView.url, let config = activeConfig,
              originAllowed(url, in: config.allowedScriptOrigins) else { return }
        let checkScript = "typeof window.__AIBI_RUNTIME__ !== 'undefined'"
        if let exists = try? await webView.evaluateJavaScript(checkScript) as? Bool, exists { return }
        _ = try? await webView.evaluateJavaScript(runtimeJavaScript)
    }

    private func evaluateScript(_ script: String, on webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let str = result as? String {
                    continuation.resume(returning: str)
                } else if let result {
                    continuation.resume(returning: String(describing: result))
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func dismissHiddenBrowserInputUI() {
        guard !isVisibleBrowserPresented, let webView = hiddenWebView else { return }
        webView.endEditing(true)
        webView.evaluateJavaScript("document.activeElement && document.activeElement.blur()")
    }

    // MARK: - Utilities

    private func configJson(_ config: AIBIProviderConfig) -> String {
        guard let data = try? JSONEncoder().encode(config), let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func parseJson(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func escapeJsString(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func cleanOutputLocally(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") && text.hasSuffix("```") {
            let lines = text.components(separatedBy: "\n")
            if lines.count >= 2 {
                text = lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private func originAllowed(_ url: URL, in origins: [String]) -> Bool {
        origins.contains { candidate in
            guard let allowed = URL(string: candidate) else { return false }
            return url.scheme?.lowercased() == allowed.scheme?.lowercased()
                && url.host?.lowercased() == allowed.host?.lowercased()
                && url.port == allowed.port
        }
    }
}

// MARK: - WKNavigationDelegate (origin security)

extension AIBISession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // 사진 업로더와 보조 UI의 child frame에는 AIBI 스크립트를 주입하지 않는다.
        // about:/blob:/CDN frame 이동을 메인 ChatGPT 페이지 이탈로 오인하지 않는다.
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url, let config = activeConfig else {
            decisionHandler(.allow); return
        }
        let isScriptOrigin = originAllowed(url, in: config.allowedScriptOrigins)
        let isAuthOrigin = originAllowed(url, in: config.allowedAuthOrigins)
        if isScriptOrigin || isAuthOrigin {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if !isVisibleBrowserPresented {
                escalateToVisible(reason: .navigationDisallowed)
            } else {
                failWithError("허용되지 않은 로그인 페이지입니다.")
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, let config = activeConfig, originAllowed(url, in: config.allowedScriptOrigins) else { return }
        Task { @MainActor in await ensureRuntimeInjected(webView: webView) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handleNavError(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handleNavError(error) }

    private func handleNavError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        failWithError("네트워크 오류: \(nsError.localizedDescription)")
    }
}

// MARK: - Native file panel bridge

extension AIBISession: WKUIDelegate {
    @available(iOS 18.4, *)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let urls = pendingAttachmentURLs
        guard !urls.isEmpty, urls.count == 1 || parameters.allowsMultipleSelection else {
            completionHandler(nil); return
        }
        nativeAttachmentPanelHandled = true
        pendingAttachmentURLs = []
        completionHandler(urls)
        let directories = Set(urls.map { $0.deletingLastPathComponent() })
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            directories.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }
}
