import Foundation

/// 기술서 10.1절 "빠른 가치 결과" JSON 계약(V3, 한국·일본 이원 시장)과 1:1 대응하는 디코딩 모델.
/// AIBI가 반환한 텍스트를 여기로 디코딩한 뒤 `QuickValueResultValidator`가 값 범위를 검증한다.
/// `koreaSaleRange`는 항상 KRW, `japanSaleRange`는 항상 JPY 기준이며, 순수익·교차 시장 마진은
/// AI가 계산하지 않고 `MarketValueCalculator`가 결정론적으로 산출한다.
/// `koreaFairPurchaseRange`/`japanFairPurchaseRange`는 "이 정도면 사도 괜찮다"고 볼 수 있는
/// 적정 매입가 범위이며, 예상 판매가(`koreaSaleRange`/`japanSaleRange`)와는 별개 개념이다.
struct QuickValueResult: Codable, Equatable {
    struct ProductGuess: Codable, Equatable {
        var brand: String
        var model: String
        var era: String
        /// 세부 변형/라인 정보(예: "빅E 셀비지"). 근거가 없으면 빈 문자열.
        var variant: String
        /// 사진 단서로 추정한 생산연도 또는 연도 범위. 근거가 없으면 빈 문자열.
        var estimatedProductionYear: String
        /// 사진 단서로 추정한 제조공장 또는 생산지. 근거가 없으면 빈 문자열.
        var estimatedFactory: String
    }

    struct ValueRange: Codable, Equatable {
        var low: Int
        var high: Int
    }

    struct Observation: Codable, Equatable {
        var feature: String
        var value: String
        var evidencePhotoRole: String
        var certainty: String
    }

    var schemaVersion: Int
    var task: String
    var productGuess: ProductGuess
    var summary: String
    var confidence: String
    var condition: String
    /// 희귀도 판단. 근거가 약하면 보수적으로 낮은 등급을 사용해야 한다.
    var rarityLevel: String
    /// 희귀도 판단에 대한 두 문장 이내 요약.
    var raritySummary: String
    /// 희귀도 판단 근거 목록. 근거가 없으면 빈 배열.
    var rarityReasons: [String]
    /// 한국(KRW) 적정 매입가 범위.
    var koreaFairPurchaseRange: ValueRange
    /// 한국 예상 판매가 범위 (KRW).
    var koreaSaleRange: ValueRange
    /// 일본(JPY) 적정 매입가 범위.
    var japanFairPurchaseRange: ValueRange
    /// 일본 예상 판매가 범위 (JPY).
    var japanSaleRange: ValueRange
    /// 엔화 1엔당 원화 환율 추정치. 항상 0보다 커야 한다.
    var jpyToKrwRate: Double
    var observations: [Observation]
    var valueReasons: [String]
    var nextPhotoInstruction: String?
    var caveats: [String]
}

enum QuickValueConfidence: String, CaseIterable {
    case high, medium, low, unknown

    var displayName: String {
        switch self {
        case .high: "신뢰도 높음"
        case .medium: "신뢰도 보통"
        case .low: "신뢰도 낮음"
        case .unknown: "판단 보류"
        }
    }

    var iconName: String {
        switch self {
        case .high: "checkmark.seal.fill"
        case .medium: "questionmark.circle.fill"
        case .low: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.diamond.fill"
        }
    }
}

enum QuickValueCondition: String, CaseIterable {
    case excellent, good, fair, poor, unknown

    var displayName: String {
        switch self {
        case .excellent: "최상"
        case .good: "양호"
        case .fair: "보통"
        case .poor: "사용감 많음"
        case .unknown: "확인되지 않음"
        }
    }
}

enum QuickValueBasis: String, CaseIterable {
    case aiGeneralEstimate = "ai_general_estimate"
    case askingPricesOnly = "asking_prices_only"
    case mixedSoldAndAsking = "mixed_sold_and_asking"
    case verifiedSoldComparables = "verified_sold_comparables"
    case insufficientMarketData = "insufficient_market_data"

    var badgeText: String {
        switch self {
        case .aiGeneralEstimate: "AI 가치 추정"
        case .askingPricesOnly: "판매 희망가 기준"
        case .mixedSoldAndAsking: "판매 완료·희망가 혼합"
        case .verifiedSoldComparables: "판매 완료가 확인됨"
        case .insufficientMarketData: "시장 자료 부족"
        }
    }
}

enum ObservationCertainty: String, CaseIterable {
    case observed, reported, inferred
}

/// 보수적인 희귀도 등급. 증거가 약할 때 객관적으로 검증된 희소성을 암시하지 않도록
/// 모든 표시 문구에 "~한 편"과 같은 완곡한 표현을 사용한다.
enum QuickValueRarity: String, CaseIterable {
    case unknown
    case common
    case uncommon
    case rare
    case extremelyRare = "extremely_rare"

    var displayName: String {
        switch self {
        case .unknown: "판단 보류"
        case .common: "흔한 편"
        case .uncommon: "약간 희소한 편"
        case .rare: "희소한 편"
        case .extremelyRare: "매우 희소한 편"
        }
    }

    var iconName: String {
        switch self {
        case .unknown: "questionmark.diamond.fill"
        case .common: "circle.fill"
        case .uncommon: "seal.fill"
        case .rare: "star.fill"
        case .extremelyRare: "star.circle.fill"
        }
    }
}
