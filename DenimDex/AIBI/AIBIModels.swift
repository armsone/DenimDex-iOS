//
//  AIBIModels.swift
//  Portable AIBI core data models — adapted from the canonical AIBI Apple reference
//  (/Users/armsone/.codex/skills/aibi/assets/apple/AIBIEngine.swift).
//  This file has no DenimDex product knowledge; it is reusable by any host app.
//

import Foundation

enum AIBIPhase: String, Codable, Equatable, Hashable {
    case idle = "IDLE"
    case initializing = "INITIALIZING"
    case navigating = "NAVIGATING"
    case readyChecking = "READY_CHECKING"
    case attachingMedia = "ATTACHING_MEDIA"
    case injectingPrompt = "INJECTING_PROMPT"
    case submitting = "SUBMITTING"
    case generating = "GENERATING"
    case stabilizing = "STABILIZING"
    case completed = "COMPLETED"
    case fallbackRequired = "FALLBACK_REQUIRED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

enum AIBIFallbackReason: String, Codable, Equatable {
    case authenticationRequired = "AUTH_REQUIRED"
    case securityChallengePresented = "SECURITY_CHALLENGE_PRESENTED"
    case navigationDisallowed = "NAVIGATION_DISALLOWED"
    case inputMissing = "INPUT_NOT_FOUND"
    case attachmentFailed = "ATTACHMENT_FAILED"
    case readinessTimeout = "READINESS_TIMEOUT"
    case userInterventionRequested = "USER_INTERVENTION_REQUESTED"
}

enum AIBIPresentationPreference: String, Codable, Equatable {
    case alwaysVisible = "ALWAYS_VISIBLE"
    case visibleWhenNeeded = "VISIBLE_WHEN_NEEDED"
    case hiddenOnly = "HIDDEN_ONLY"
}

struct AIBITask: Identifiable, Equatable {
    let id: UUID
    let providerId: String
    let promptText: String
    let attachments: [AIBIMediaAttachment]
    let presentation: AIBIPresentationPreference
    let forceFill: Bool

    init(
        id: UUID = UUID(),
        providerId: String,
        promptText: String,
        attachments: [AIBIMediaAttachment] = [],
        presentation: AIBIPresentationPreference = .visibleWhenNeeded,
        forceFill: Bool = false
    ) {
        self.id = id
        self.providerId = providerId
        self.promptText = promptText
        self.attachments = attachments
        self.presentation = presentation
        self.forceFill = forceFill
    }
}

struct AIBIResult: Equatable {
    let taskId: UUID
    let providerId: String
    let rawText: String
    let cleanedText: String
    let isComplete: Bool
}

struct AIBIProgress: Equatable {
    let phase: AIBIPhase
    let elapsedSeconds: Double
    let statusMessage: String
    let isWaiting: Bool

    static let initial = AIBIProgress(phase: .idle, elapsedSeconds: 0, statusMessage: "대기 중", isWaiting: false)
}

/// 호스트 앱이 결과를 검증하고 커밋하는 결합 지점. `.success`를 반환해야만 브라우저가 자동으로 닫힌다.
@MainActor
protocol AIBIResultSink: AnyObject {
    func commitResult(_ result: AIBIResult) -> Result<Void, Error>
}

// MARK: - Provider configuration (decoded from aibi-providers.json)

struct AIBIProviderSelectors: Codable, Equatable {
    var promptInput: [String]
    var submitButton: [String]
    var stopButton: [String]
    var assistantMessage: [String]
    var preCode: [String]?
    var errorBanner: [String]
    var loginIndicator: [String]
    var challengeIndicator: [String]
    var attachmentInput: [String]?
    var attachmentTrigger: [String]?
    var attachmentMenuAction: [String]?
    var attachmentMenuActionText: [String]?
    var attachmentPreview: [String]?
}

struct AIBIMediaCapabilities: Codable, Equatable {
    var supportsImages: Bool = false
    var maxImagesPerTask: Int = 0
    var requiresMultipleInputForBatch: Bool = true
}

struct AIBIProviderConfig: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var initialUrl: String
    var allowedScriptOrigins: [String]
    var allowedAuthOrigins: [String]
    var selectors: AIBIProviderSelectors
    var mediaCapabilities: AIBIMediaCapabilities?
}

struct AIBITimingProfile {
    var readinessTimeout: TimeInterval = 35.0
    var readinessCadence: TimeInterval = 0.7
    var maxReadinessMisses: Int = 12
    var attachmentTimeout: TimeInterval = 30.0
    var attachmentCadence: TimeInterval = 0.35
    var submitTimeout: TimeInterval = 15.0
    var submitCadence: TimeInterval = 0.5
    var submitVerificationDelay: TimeInterval = 0.7
    var visibleAutoFillTimeout: TimeInterval = 45.0
    var observationCadence: TimeInterval = 0.7
    var stabilityRequiredTicks: Int = 2

    static let `default` = AIBITimingProfile()
}
