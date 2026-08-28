import Foundation

/// 기술서 10.1절 "빠른 가치 결과" JSON 계약(V2, 한국·일본 이원 시장)과 1:1 대응하는 디코딩 모델.
/// AIBI가 반환한 텍스트를 여기로 디코딩한 뒤 `QuickValueResultValidator`가 값 범위를 검증한다.
/// `koreaSaleRange`는 항상 KRW, `japanSaleRange`는 항상 JPY 기준이며, 순수익·교차 시장 마진은
/// AI가 계산하지 않고 `MarketValueCalculator`가 결정론적으로 산출한다.
struct QuickValueResult: Codable, Equatable {
    struct ProductGuess: Codable, Equatable {
        var brand: String
        var model: String
        var era: String
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
    /// 한국 예상 판매가 범위 (KRW).
    var koreaSaleRange: ValueRange
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
