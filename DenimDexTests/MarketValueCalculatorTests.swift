import XCTest
@testable import DenimDex

final class MarketValueCalculatorTests: XCTestCase {

    // MARK: - Net proceeds (domestic)

    func testKoreaNetProceedsAppliesFeeAndFlatShipping() {
        let range = MarketValueCalculator.koreaNetProceeds(saleRange: .init(low: 80_000, high: 180_000))
        XCTAssertEqual(range.low, 67_000)
        XCTAssertEqual(range.high, 157_000)
    }

    func testJapanNetProceedsAppliesFeeAndFlatShipping() {
        let range = MarketValueCalculator.japanNetProceeds(saleRange: .init(low: 8_000, high: 18_000))
        XCTAssertEqual(range.low, 6_200)
        XCTAssertEqual(range.high, 15_200)
    }

    func testNetProceedsClampsToZeroInsteadOfGoingNegative() {
        let range = MarketValueCalculator.koreaNetProceeds(saleRange: .init(low: 0, high: 1_000))
        XCTAssertEqual(range.low, 0)
        XCTAssertEqual(range.high, 0)
    }

    func testNetProceedsLowNeverExceedsHigh() {
        let range = MarketValueCalculator.japanNetProceeds(saleRange: .init(low: 500, high: 600))
        XCTAssertLessThanOrEqual(range.low, range.high)
    }

    // MARK: - Cross-market margin

    func testCrossMarketMarginCanBeNegativeAndIsNotClamped() {
        let comparison = MarketValueCalculator.crossMarketComparison(
            korea: .init(low: 100_000, high: 200_000),
            japan: .init(low: 8_000, high: 16_000),
            jpyToKrwRate: 9.0
        )
        XCTAssertEqual(comparison.japanToKorea.low, -84_000)
        XCTAssertEqual(comparison.japanToKorea.high, 78_000)
        XCTAssertEqual(comparison.koreaToJapan.low, -165_200)
        XCTAssertEqual(comparison.koreaToJapan.high, -400)
    }

    func testRecommendsNoClearAdvantageWhenBothMidpointsAreNonPositive() {
        let comparison = MarketValueCalculator.crossMarketComparison(
            korea: .init(low: 100_000, high: 200_000),
            japan: .init(low: 8_000, high: 16_000),
            jpyToKrwRate: 9.0
        )
        XCTAssertEqual(comparison.recommendation, .noClearAdvantage)
    }

    func testRecommendsJapanToKoreaWhenBuyingInJapanIsClearlyCheaper() {
        let comparison = MarketValueCalculator.crossMarketComparison(
            korea: .init(low: 300_000, high: 400_000),
            japan: .init(low: 5_000, high: 8_000),
            jpyToKrwRate: 9.0
        )
        XCTAssertEqual(comparison.recommendation, .japanToKorea)
    }

    func testRecommendsKoreaToJapanWhenBuyingInKoreaIsClearlyCheaper() {
        let comparison = MarketValueCalculator.crossMarketComparison(
            korea: .init(low: 10_000, high: 12_000),
            japan: .init(low: 50_000, high: 60_000),
            jpyToKrwRate: 1.0
        )
        XCTAssertEqual(comparison.recommendation, .koreaToJapan)
    }

    func testCrossMarketMarginConvertsJPYPurchaseUsingExchangeRate() {
        let margin = MarketValueCalculator.crossMarketMargin(
            purchaseRange: .init(low: 10_000, high: 10_000),
            purchaseCurrency: .jpy,
            saleRange: .init(low: 200_000, high: 200_000),
            saleCurrency: .krw,
            saleFeeRate: 0.10,
            jpyToKrwRate: 10.0
        )
        // purchase = 10,000 JPY * 10 = 100,000 KRW + 30,000 shipping = 130,000 KRW cost
        // sale net = 200,000 * 0.9 = 180,000 KRW
        // margin = 180,000 - 130,000 = 50,000
        XCTAssertEqual(margin.low, 50_000)
        XCTAssertEqual(margin.high, 50_000)
    }
}
