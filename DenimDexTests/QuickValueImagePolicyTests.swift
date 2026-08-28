import XCTest
@testable import DenimDex

final class QuickValueImagePolicyTests: XCTestCase {
    func testCaptureKeepsThirtyOriginalsWhileTransferStaysAtTwenty() {
        XCTAssertEqual(QuickValueImagePolicy.captureMaximumCount, 30)
        XCTAssertEqual(QuickValuePhotoRoles.maxCount, 20)
    }

    func testEightPhotosKeepOriginalQuickValueQualityCeiling() {
        let policy = QuickValueImagePolicy.normalizationPolicy(photoCount: 8)
        XCTAssertEqual(policy.maximumImageCount, 20)
        XCTAssertEqual(policy.maximumLongEdgePixels, 2_048)
        XCTAssertEqual(policy.maximumBytesPerImage, 2_000_000)
        XCTAssertEqual(policy.initialJPEGQuality, 0.84)
    }

    func testTwentyPhotosFitWithinSixteenMegabyteBudget() {
        let policy = QuickValueImagePolicy.normalizationPolicy(photoCount: 20)
        XCTAssertEqual(policy.maximumLongEdgePixels, 1_536)
        XCTAssertEqual(policy.maximumBytesPerImage, 800_000)
        XCTAssertLessThanOrEqual(policy.maximumBytesPerImage * 20, QuickValueImagePolicy.totalBatchBudgetBytes)
        XCTAssertGreaterThanOrEqual(policy.minimumJPEGQuality, 0.50)
    }

    func testPerImageBudgetDeclinesAsBatchGrows() {
        let eight = QuickValueImagePolicy.normalizationPolicy(photoCount: 8)
        let twelve = QuickValueImagePolicy.normalizationPolicy(photoCount: 12)
        let twenty = QuickValueImagePolicy.normalizationPolicy(photoCount: 20)
        XCTAssertGreaterThan(eight.maximumBytesPerImage, twelve.maximumBytesPerImage)
        XCTAssertGreaterThan(twelve.maximumBytesPerImage, twenty.maximumBytesPerImage)
    }
}
