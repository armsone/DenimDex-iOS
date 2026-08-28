import Foundation

/// 기술서 요구사항: 가격 산술은 AI가 아니라 호스트가 결정론적으로 계산한다.
/// 순수익은 0 미만으로 내려가지 않도록 클램프하지만, 교차 시장 마진은 손해를 그대로 보여줘야
/// 하므로 클램프하지 않는다.
enum MarketValueDefaults {
    static let koreaFeeRate: Double = 0.10
    static let koreaLocalShippingKRW: Int = 5_000
    static let japanFeeRate: Double = 0.10
    static let japanLocalShippingJPY: Int = 1_000
    static let internationalShippingKRW: Int = 30_000
}

enum QuickValueCurrency {
    case krw
    case jpy
}

struct CrossMarketComparison: Equatable {
    enum Recommendation: Equatable {
        case japanToKorea
        case koreaToJapan
        case noClearAdvantage
    }

    /// 일본 구매 → 한국 판매 예상 마진 범위 (KRW). 음수일 수 있다.
    var japanToKorea: QuickValueResult.ValueRange
    /// 한국 구매 → 일본 판매 예상 마진 범위 (KRW). 음수일 수 있다.
    var koreaToJapan: QuickValueResult.ValueRange
    var recommendation: Recommendation
}

enum MarketValueCalculator {
    static func koreaNetProceeds(saleRange: QuickValueResult.ValueRange) -> QuickValueResult.ValueRange {
        netProceeds(
            saleRange: saleRange,
            feeRate: MarketValueDefaults.koreaFeeRate,
            flatShipping: MarketValueDefaults.koreaLocalShippingKRW
        )
    }

    static func japanNetProceeds(saleRange: QuickValueResult.ValueRange) -> QuickValueResult.ValueRange {
        netProceeds(
            saleRange: saleRange,
            feeRate: MarketValueDefaults.japanFeeRate,
            flatShipping: MarketValueDefaults.japanLocalShippingJPY
        )
    }

    /// 판매가 범위에서 수수료와 국내 배송비를 뺀 순수익 범위. 0 미만은 0으로 클램프한다.
    static func netProceeds(saleRange: QuickValueResult.ValueRange, feeRate: Double, flatShipping: Int) -> QuickValueResult.ValueRange {
        let low = max(0, Int((Double(saleRange.low) * (1 - feeRate)).rounded()) - flatShipping)
        let high = max(0, Int((Double(saleRange.high) * (1 - feeRate)).rounded()) - flatShipping)
        return .init(low: low, high: high)
    }

    /// 두 방향의 교차 시장 마진과 추천을 함께 계산한다.
    static func crossMarketComparison(
        korea: QuickValueResult.ValueRange,
        japan: QuickValueResult.ValueRange,
        jpyToKrwRate: Double
    ) -> CrossMarketComparison {
        let japanToKorea = crossMarketMargin(
            purchaseRange: japan, purchaseCurrency: .jpy,
            saleRange: korea, saleCurrency: .krw,
            saleFeeRate: MarketValueDefaults.koreaFeeRate,
            jpyToKrwRate: jpyToKrwRate
        )
        let koreaToJapan = crossMarketMargin(
            purchaseRange: korea, purchaseCurrency: .krw,
            saleRange: japan, saleCurrency: .jpy,
            saleFeeRate: MarketValueDefaults.japanFeeRate,
            jpyToKrwRate: jpyToKrwRate
        )

        let japanToKoreaMid = midpoint(japanToKorea)
        let koreaToJapanMid = midpoint(koreaToJapan)

        let recommendation: CrossMarketComparison.Recommendation
        if japanToKoreaMid > 0 && japanToKoreaMid >= koreaToJapanMid {
            recommendation = .japanToKorea
        } else if koreaToJapanMid > 0 {
            recommendation = .koreaToJapan
        } else {
            recommendation = .noClearAdvantage
        }

        return CrossMarketComparison(japanToKorea: japanToKorea, koreaToJapan: koreaToJapan, recommendation: recommendation)
    }

    /// 반대 시장 구매가 범위와 목적지 판매가 범위로부터 KRW 마진 범위를 보수적으로 계산한다.
    /// 저가 쪽은 "가장 비싸게 사서 가장 싸게 판" 경우, 고가 쪽은 그 반대를 사용해 범위를 만든다.
    /// 국제배송비만 더하고, 목적지 판매 수수료만 뺀다. 결과는 클램프하지 않는다(손해도 그대로 노출).
    static func crossMarketMargin(
        purchaseRange: QuickValueResult.ValueRange,
        purchaseCurrency: QuickValueCurrency,
        saleRange: QuickValueResult.ValueRange,
        saleCurrency: QuickValueCurrency,
        saleFeeRate: Double,
        jpyToKrwRate: Double,
        internationalShippingKRW: Int = MarketValueDefaults.internationalShippingKRW
    ) -> QuickValueResult.ValueRange {
        let purchaseLowKRW = toKRW(purchaseRange.low, currency: purchaseCurrency, jpyToKrwRate: jpyToKrwRate)
        let purchaseHighKRW = toKRW(purchaseRange.high, currency: purchaseCurrency, jpyToKrwRate: jpyToKrwRate)
        let saleLowKRW = toKRW(saleRange.low, currency: saleCurrency, jpyToKrwRate: jpyToKrwRate)
        let saleHighKRW = toKRW(saleRange.high, currency: saleCurrency, jpyToKrwRate: jpyToKrwRate)

        let netSaleLow = saleLowKRW * (1 - saleFeeRate)
        let netSaleHigh = saleHighKRW * (1 - saleFeeRate)

        let costHigh = purchaseHighKRW + Double(internationalShippingKRW)
        let costLow = purchaseLowKRW + Double(internationalShippingKRW)

        let marginA = (netSaleLow - costHigh).rounded()
        let marginB = (netSaleHigh - costLow).rounded()

        return .init(low: Int(min(marginA, marginB)), high: Int(max(marginA, marginB)))
    }

    private static func toKRW(_ value: Int, currency: QuickValueCurrency, jpyToKrwRate: Double) -> Double {
        switch currency {
        case .krw: return Double(value)
        case .jpy: return Double(value) * jpyToKrwRate
        }
    }

    private static func midpoint(_ range: QuickValueResult.ValueRange) -> Double {
        Double(range.low + range.high) / 2
    }
}
