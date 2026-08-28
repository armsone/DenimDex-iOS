import XCTest
@testable import DenimDex

final class CountdownFormatterTests: XCTestCase {
    func testRemainingSecondsCountsDownFromNinety() {
        XCTAssertEqual(CountdownFormatter.remainingSeconds(elapsed: 0), 90)
        XCTAssertEqual(CountdownFormatter.remainingSeconds(elapsed: 10), 80)
        XCTAssertEqual(CountdownFormatter.remainingSeconds(elapsed: 89.9), 1)
        XCTAssertEqual(CountdownFormatter.remainingSeconds(elapsed: 90), 0)
        XCTAssertEqual(CountdownFormatter.remainingSeconds(elapsed: 120), 0)
    }

    func testFormatMinutesSecondsMatchesSpecStyle() {
        XCTAssertEqual(CountdownFormatter.formatMinutesSeconds(90), "1:30")
        XCTAssertEqual(CountdownFormatter.formatMinutesSeconds(9), "0:09")
        XCTAssertEqual(CountdownFormatter.formatMinutesSeconds(0), "0:00")
        XCTAssertEqual(CountdownFormatter.formatMinutesSeconds(-5), "0:00")
    }

    func testProgressFractionDecreasesMonotonically() {
        let full = CountdownFormatter.progressFraction(elapsed: 0)
        let mid = CountdownFormatter.progressFraction(elapsed: 45)
        let empty = CountdownFormatter.progressFraction(elapsed: 90)
        XCTAssertEqual(full, 1.0, accuracy: 0.001)
        XCTAssertEqual(mid, 0.5, accuracy: 0.02)
        XCTAssertEqual(empty, 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(full, mid)
        XCTAssertGreaterThan(mid, empty)
    }

    func testIsExpiredBoundary() {
        XCTAssertFalse(CountdownFormatter.isExpired(elapsed: 89.999))
        XCTAssertTrue(CountdownFormatter.isExpired(elapsed: 90))
        XCTAssertTrue(CountdownFormatter.isExpired(elapsed: 91))
    }
}
