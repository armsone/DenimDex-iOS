import XCTest
@testable import DenimDex

final class QuickValuePromptBuilderTests: XCTestCase {
    func testPromptListsPhotoIdentifiersInOrder() {
        let prompt = QuickValuePromptBuilder.buildPrompt(photoRoles: ["photo_1", "photo_2"])
        XCTAssertTrue(prompt.contains("1번 사진: photo_1"))
        XCTAssertTrue(prompt.contains("2번 사진: photo_2"))
    }

    func testPromptRequestsSingleJSONCodeBlock() {
        let prompt = QuickValuePromptBuilder.buildPrompt(photoRoles: ["photo_1", "photo_2"])
        XCTAssertTrue(prompt.contains("```json"))
        XCTAssertTrue(prompt.contains("\"task\": \"quick_value\""))
        XCTAssertTrue(prompt.contains("\"schemaVersion\": 3"))
    }

    func testPromptStatesQuickEstimateDisclaimerRequirement() {
        let prompt = QuickValuePromptBuilder.buildPrompt(photoRoles: ["photo_1"])
        XCTAssertTrue(prompt.contains("caveats"))
        XCTAssertTrue(prompt.contains("실시간"))
    }

    func testPromptScalesWithPhotoCount() {
        let twoPhotoPrompt = QuickValuePromptBuilder.buildPrompt(photoRoles: QuickValuePhotoRoles.identifiers(count: 2))
        let twentyPhotoPrompt = QuickValuePromptBuilder.buildPrompt(photoRoles: QuickValuePhotoRoles.identifiers(count: 20))
        XCTAssertTrue(twoPhotoPrompt.contains("사진 2장"))
        XCTAssertTrue(twentyPhotoPrompt.contains("사진 20장"))
        XCTAssertTrue(twentyPhotoPrompt.contains("20번 사진: photo_20"))
    }

    func testPromptRequestsDualMarketSchemaFields() {
        let prompt = QuickValuePromptBuilder.buildPrompt(photoRoles: ["photo_1"])
        XCTAssertTrue(prompt.contains("koreaSaleRange"))
        XCTAssertTrue(prompt.contains("japanSaleRange"))
        XCTAssertTrue(prompt.contains("jpyToKrwRate"))
    }

    func testPromptRequestsRarityAndFairPurchaseFields() {
        let prompt = QuickValuePromptBuilder.buildPrompt(photoRoles: ["photo_1"])
        XCTAssertTrue(prompt.contains("rarityLevel"))
        XCTAssertTrue(prompt.contains("raritySummary"))
        XCTAssertTrue(prompt.contains("rarityReasons"))
        XCTAssertTrue(prompt.contains("koreaFairPurchaseRange"))
        XCTAssertTrue(prompt.contains("japanFairPurchaseRange"))
        XCTAssertTrue(prompt.contains("estimatedProductionYear"))
        XCTAssertTrue(prompt.contains("estimatedFactory"))
        XCTAssertTrue(prompt.contains("extremely_rare"))
    }
}
