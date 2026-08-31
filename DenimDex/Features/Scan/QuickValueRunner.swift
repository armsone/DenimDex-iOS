import SwiftUI
import Combine

enum QuickValueRunState: Equatable {
    case idle
    case running
    case succeeded(QuickValueResult, rawJSON: String)
    case failed(String)
    case timedOut
    case cancelled
}

/// Scan 화면과 AIBI 세션 사이의 호스트 오케스트레이터.
/// AIBI 자체 타이밍과 별개로, 전송 확인 이후 90초가 지나면 종료하는
/// 기술서 6.2/9.1절의 "호스트 소유" Quick Value 타임아웃을 여기서 강제한다.
@MainActor
final class QuickValueRunner: ObservableObject, AIBIResultSink {
    @Published private(set) var state: QuickValueRunState = .idle
    @Published private(set) var elapsedSinceSubmission: TimeInterval = 0
    @Published private(set) var sentPhotoCount = 0
    @Published private(set) var removedSimilarPhotoCount = 0
    @Published private(set) var omittedForTransferLimitCount = 0

    let session: AIBISession
    private var photoRoles: [String] = []
    private var submissionTimestamp: Date?
    private var timeoutTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var runID: UUID?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.session = AIBISession(runtimeJs: AIBIProviderRegistry.runtimeJavaScript)
        self.session.resultSink = self

        session.$currentPhase
            .sink { [weak self] phase in
                self?.handlePhaseChange(phase)
            }
            .store(in: &cancellables)
    }

    func start(
        photos: [Data],
        roles: [String]? = nil,
        missingRoles: [String] = [],
        hiddenContainer: UIView?
    ) {
        guard let config = AIBIProviderRegistry.chatGPT else {
            state = .failed("ChatGPT 설정을 불러오지 못했습니다.")
            return
        }
        guard (QuickValuePhotoRoles.minCount...QuickValueImagePolicy.captureMaximumCount).contains(photos.count) else {
            state = .failed("사진은 1장부터 30장까지 선택해주세요.")
            return
        }

        let requestID = UUID()
        runID = requestID
        let sourceImages = photos
        let sourceRoles = roles ?? QuickValuePhotoRoles.identifiers(count: sourceImages.count)
        photoRoles = []
        sentPhotoCount = 0
        removedSimilarPhotoCount = 0
        omittedForTransferLimitCount = 0
        submissionTimestamp = nil
        state = .running
        elapsedSinceSubmission = 0

        // StarManager 방식: 최대 20장의 리사이즈·압축·메타데이터 제거는 메인 스레드 밖에서 한다.
        // 큰 사진을 여러 장 골라도 화면과 카운트다운이 멈추지 않는다.
        preparationTask?.cancel()
        preparationTask = Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) {
                let selection = HanAIPhotoDeduplicator.selectRepresentatives(from: sourceImages)
                let transferImages = Array(selection.images.prefix(QuickValuePhotoRoles.maxCount))
                let transferRoles = Array(selection.keptIndices.map { index in
                    sourceRoles.indices.contains(index) ? sourceRoles[index] : "photo_\(index + 1)"
                }.prefix(QuickValuePhotoRoles.maxCount))
                let attachments = try? AIBIImageNormalizer.normalizeOrdered(
                    transferImages,
                    roles: transferRoles.map(Optional.some),
                    policy: QuickValueImagePolicy.normalizationPolicy(photoCount: transferImages.count)
                )
                return (selection, transferImages.count, transferRoles, attachments)
            }.value
            guard !Task.isCancelled, let self, self.runID == requestID else { return }
            self.preparationTask = nil
            guard let attachments = prepared.3, attachments.count == prepared.1 else {
                self.state = .failed("사진을 전송용으로 준비하지 못했습니다. 사진을 확인하고 다시 시도해주세요.")
                return
            }
            self.photoRoles = prepared.2
            self.sentPhotoCount = attachments.count
            self.removedSimilarPhotoCount = prepared.0.removedCount
            self.omittedForTransferLimitCount = max(0, prepared.0.images.count - prepared.1)
            let prompt = QuickValuePromptBuilder.buildPrompt(
                photoRoles: photoRoles,
                missingPhotoRoles: missingRoles
            )
            let task = AIBITask(
                providerId: config.id,
                promptText: prompt,
                attachments: attachments,
                presentation: .hiddenOnly
            )
            session.startTask(task: task, providerConfig: config, hiddenContainer: hiddenContainer)
        }
    }

    func cancel() {
        preparationTask?.cancel()
        preparationTask = nil
        runID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        session.cancelCurrentTask()
        state = .cancelled
    }

    func reset() {
        preparationTask?.cancel()
        preparationTask = nil
        runID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        session.fullReset()
        state = .idle
        elapsedSinceSubmission = 0
        sentPhotoCount = 0
        removedSimilarPhotoCount = 0
        omittedForTransferLimitCount = 0
        submissionTimestamp = nil
    }

    func importManualResult(_ text: String) {
        session.manualImportText(text)
    }

    // MARK: - AIBIResultSink

    func commitResult(_ result: AIBIResult) -> Result<Void, Error> {
        switch QuickValueResultValidator.validate(rawText: result.cleanedText, sentPhotoRoles: photoRoles) {
        case .success(let value):
            timeoutTask?.cancel()
            state = .succeeded(value, rawJSON: result.cleanedText)
            return .success(())
        case .failure(let error):
            return .failure(ValidationCommitError(underlying: error))
        }
    }

    // MARK: - Host-owned 90s timeout

    private func handlePhaseChange(_ phase: AIBIPhase) {
        let submissionPhases: Set<AIBIPhase> = [.generating, .stabilizing]
        if submissionTimestamp == nil, submissionPhases.contains(phase) {
            armTimeout()
        }

        switch phase {
        case .failed:
            timeoutTask?.cancel()
            state = .failed(session.lastErrorMessage ?? "가치 확인을 완료하지 못했어요. 잠시 후 다시 시도해주세요.")
        case .cancelled:
            timeoutTask?.cancel()
            if case .running = state { state = .cancelled }
        default:
            break
        }
    }

    private func armTimeout() {
        let startedAt = Date()
        submissionTimestamp = startedAt
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self else { return }
                await self.tickTimeout(startedAt: startedAt)
                if Task.isCancelled { return }
            }
        }
    }

    private func tickTimeout(startedAt: Date) async {
        let elapsed = Date().timeIntervalSince(startedAt)
        elapsedSinceSubmission = elapsed
        if CountdownFormatter.isExpired(elapsed: elapsed) {
            timeoutTask?.cancel()
            session.cancelCurrentTask()
            if case .succeeded = state {
                // 이미 결과를 받았다면 늦게 도착한 타임아웃 틱을 무시한다.
                return
            }
            state = .timedOut
        }
    }
}

private struct ValidationCommitError: LocalizedError {
    let underlying: QuickValueValidationError
    var errorDescription: String? { "결과 형식을 확인하지 못했습니다." }
}
