import XCTest
@testable import DenimDex

final class QuickValuePhotoRolesTests: XCTestCase {
    func testGeneratesOneIdentifierForSinglePhoto() {
        XCTAssertEqual(QuickValuePhotoRoles.identifiers(count: 1), ["photo_1"])
    }

    func testGeneratesTwentyIdentifiersForMaximumPhotos() {
        let identifiers = QuickValuePhotoRoles.identifiers(count: 20)
        XCTAssertEqual(identifiers.count, 20)
        XCTAssertEqual(identifiers.first, "photo_1")
        XCTAssertEqual(identifiers.last, "photo_20")
    }

    func testClampsBeyondTwentyPhotosToTheMaximum() {
        let identifiers = QuickValuePhotoRoles.identifiers(count: 21)
        XCTAssertEqual(identifiers.count, 20)
        XCTAssertEqual(identifiers.last, "photo_20")
    }

    func testReturnsEmptyForZeroPhotos() {
        XCTAssertEqual(QuickValuePhotoRoles.identifiers(count: 0), [])
    }
}
