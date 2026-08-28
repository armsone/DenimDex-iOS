import Foundation
import SwiftData

/// `verificationState` — AI 결과는 저장 시점에 절대 `sourceVerified`가 될 수 없다 (기술서 11.1절).
enum VerificationState: String, Codable, CaseIterable {
    case aiEstimate = "ai_estimate"
    case userConfirmed = "user_confirmed"
    case sourceVerified = "source_verified"

    var displayName: String {
        switch self {
        case .aiEstimate: "AI 추정"
        case .userConfirmed: "사용자 확인"
        case .sourceVerified: "출처 확인됨"
        }
    }
}

/// 도감 동기화 대기 목록에서의 카드 상태. 기술서 11.4절 "동기화 대기 카드" 개념을 로컬에서 추적한다.
enum SyncEligibilityState: String, Codable {
    case notEligible = "not_eligible"
    case pending
    case excluded
    case uploaded
}

/// 개인 도감의 저장 단위. 서버 없이 기기 안에서만 존재한다.
@Model
final class CollectionItem {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var userTitle: String

    // 저장된 증거 사진 사본 (원본은 사진 보관함에 남는다).
    var photosData: [Data]
    var photoRoleRawValues: [String]

    var brandGuess: String
    var modelGuess: String
    var eraGuess: String
    var summary: String
    var confidenceRaw: String
    var conditionRaw: String
    var currency: String
    var valueLow: Int
    var valueHigh: Int
    var valueBasisRaw: String
    var valueReasons: [String]
    var caveats: [String]

    // Quick Value V2 — 일본 시장(엔화) 예상 판매가와 환율. 기존 저장 항목은 nil로 남아 있을 수 있다.
    var japanValueLow: Int?
    var japanValueHigh: Int?
    var jpyToKrwRateStored: Double?

    /// 검증을 통과한 원본 Quick Value JSON. 근거 조사 등 후속 기능이 참조할 수 있도록 보관한다.
    var quickValueJSON: String

    var userNotes: String
    var verificationStateRaw: String
    var syncStateRaw: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        userTitle: String,
        photosData: [Data],
        photoRoleRawValues: [String],
        result: QuickValueResult,
        quickValueJSON: String,
        userNotes: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.userTitle = userTitle
        self.photosData = photosData
        self.photoRoleRawValues = photoRoleRawValues
        self.brandGuess = result.productGuess.brand
        self.modelGuess = result.productGuess.model
        self.eraGuess = result.productGuess.era
        self.summary = result.summary
        self.confidenceRaw = result.confidence
        self.conditionRaw = result.condition
        // 한국(KRW) 예상 판매가를 기존 "대표 가격 범위" 필드에 담아, 도감·동기화 화면을
        // 수정하지 않고도 계속 동작하도록 한다. `valueBasis`는 V2에서 항상 AI 일반 추정이다.
        self.currency = "KRW"
        self.valueLow = result.koreaSaleRange.low
        self.valueHigh = result.koreaSaleRange.high
        self.valueBasisRaw = QuickValueBasis.aiGeneralEstimate.rawValue
        self.valueReasons = result.valueReasons
        self.caveats = result.caveats
        self.japanValueLow = result.japanSaleRange.low
        self.japanValueHigh = result.japanSaleRange.high
        self.jpyToKrwRateStored = result.jpyToKrwRate
        self.quickValueJSON = quickValueJSON
        self.userNotes = userNotes
        self.verificationStateRaw = VerificationState.aiEstimate.rawValue
        self.syncStateRaw = SyncEligibilityState.notEligible.rawValue
    }

    var verificationState: VerificationState {
        get { VerificationState(rawValue: verificationStateRaw) ?? .aiEstimate }
        set { verificationStateRaw = newValue.rawValue }
    }

    var syncState: SyncEligibilityState {
        get { SyncEligibilityState(rawValue: syncStateRaw) ?? .notEligible }
        set { syncStateRaw = newValue.rawValue }
    }

    var confidence: QuickValueConfidence { QuickValueConfidence(rawValue: confidenceRaw) ?? .unknown }
    var condition: QuickValueCondition { QuickValueCondition(rawValue: conditionRaw) ?? .unknown }
    var valueBasis: QuickValueBasis { QuickValueBasis(rawValue: valueBasisRaw) ?? .aiGeneralEstimate }

    /// 한국(KRW) 예상 판매가 범위.
    var koreaSaleRange: QuickValueResult.ValueRange { .init(low: valueLow, high: valueHigh) }

    /// 일본(JPY) 예상 판매가 범위. V2 이전에 저장된 항목은 nil이다.
    var japanSaleRange: QuickValueResult.ValueRange? {
        guard let low = japanValueLow, let high = japanValueHigh else { return nil }
        return .init(low: low, high: high)
    }

    var displayTitle: String {
        userTitle.isEmpty ? [brandGuess, modelGuess].filter { !$0.isEmpty }.joined(separator: " ") : userTitle
    }

    var formattedValueRange: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let low = formatter.string(from: NSNumber(value: valueLow)) ?? "\(valueLow)"
        let high = formatter.string(from: NSNumber(value: valueHigh)) ?? "\(valueHigh)"
        return "\(currency) \(low) ~ \(high)"
    }

    /// 사용자가 제품 추정을 확인/수정하고 저장했다는 전제 아래, 동기화 대기 카드 자격을 부여한다.
    func markEligibleForSyncIfNeeded() {
        if syncState == .notEligible {
            syncState = .pending
        }
    }
}
