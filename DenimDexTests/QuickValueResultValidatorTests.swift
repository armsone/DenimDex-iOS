import XCTest
@testable import DenimDex

final class QuickValueResultValidatorTests: XCTestCase {
    private let sentRoles = ["photo_1", "photo_2"]

    private func validJSON(overrides: (inout [String: Any]) -> Void = { _ in }) -> String {
        var dict: [String: Any] = [
            "schemaVersion": 2,
            "task": "quick_value",
            "productGuess": ["brand": "Levi's", "model": "501", "era": "판단 어려움"],
            "summary": "요약",
            "confidence": "medium",
            "condition": "fair",
            "koreaSaleRange": ["low": 80000, "high": 180000],
            "japanSaleRange": ["low": 8000, "high": 18000],
            "jpyToKrwRate": 9.1,
            "observations": [
                ["feature": "fly_type", "value": "button_fly", "evidencePhotoRole": "photo_1", "certainty": "observed"]
            ],
            "valueReasons": ["근거1"],
            "nextPhotoInstruction": "촬영 안내",
            "caveats": ["빠른 AI 추정"]
        ]
        overrides(&dict)
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return String(data: data, encoding: .utf8)!
    }

    func testValidResultParsesSuccessfully() {
        let result = QuickValueResultValidator.validate(rawText: validJSON(), sentPhotoRoles: sentRoles)
        switch result {
        case .success(let value):
            XCTAssertEqual(value.productGuess.brand, "Levi's")
            XCTAssertEqual(value.koreaSaleRange.low, 80000)
            XCTAssertEqual(value.japanSaleRange.low, 8000)
            XCTAssertEqual(value.jpyToKrwRate, 9.1)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testWrapsFencedJSONCodeBlock() {
        let fenced = "```json\n\(validJSON())\n```"
        let result = QuickValueResultValidator.validate(rawText: fenced, sentPhotoRoles: sentRoles)
        guard case .success = result else { XCTFail("Expected success"); return }
    }

    private func assertFails(_ result: Result<QuickValueResult, QuickValueValidationError>, _ expected: QuickValueValidationError, file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success:
            XCTFail("Expected failure \(expected)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    func testRejectsEmptyResult() {
        let result = QuickValueResultValidator.validate(rawText: "   ", sentPhotoRoles: sentRoles)
        assertFails(result, .emptyResult)
    }

    func testRejectsMalformedJSON() {
        let result = QuickValueResultValidator.validate(rawText: "not json at all", sentPhotoRoles: sentRoles)
        assertFails(result, .jsonParsingFailed)
    }

    func testRejectsSchemaVersionMismatch() {
        let json = validJSON { $0["schemaVersion"] = 1 }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .schemaVersionMismatch)
    }

    func testRejectsTaskMismatch() {
        let json = validJSON { $0["task"] = "deep_value" }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .taskMismatch)
    }

    func testRejectsDisallowedConfidenceValue() {
        let json = validJSON { $0["confidence"] = "extreme" }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .disallowedEnumValue(field: "confidence"))
    }

    func testRejectsDisallowedConditionValue() {
        let json = validJSON { $0["condition"] = "mint_and_perfect" }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .disallowedEnumValue(field: "condition"))
    }

    func testRejectsNegativeKoreaValue() {
        let json = validJSON { $0["koreaSaleRange"] = ["low": -1000, "high": 5000] }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .negativeValue)
    }

    func testRejectsKoreaLowGreaterThanHigh() {
        let json = validJSON { $0["koreaSaleRange"] = ["low": 200000, "high": 100000] }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .lowGreaterThanHigh)
    }

    func testRejectsNegativeJapanValue() {
        let json = validJSON { $0["japanSaleRange"] = ["low": -1000, "high": 5000] }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .negativeValue)
    }

    func testRejectsJapanLowGreaterThanHigh() {
        let json = validJSON { $0["japanSaleRange"] = ["low": 20000, "high": 10000] }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .lowGreaterThanHigh)
    }

    func testRejectsZeroExchangeRate() {
        let json = validJSON { $0["jpyToKrwRate"] = 0 }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .invalidExchangeRate)
    }

    func testRejectsNegativeExchangeRate() {
        let json = validJSON { $0["jpyToKrwRate"] = -9.1 }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .invalidExchangeRate)
    }

    func testRejectsObservedRoleThatWasNotSent() {
        let json = validJSON {
            $0["observations"] = [
                ["feature": "patch_material", "value": "leather", "evidencePhotoRole": "photo_5", "certainty": "observed"]
            ]
        }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        assertFails(result, .unobservedPhotoRoleUsed)
    }

    func testAllowsInferredObservationForRoleThatWasNotSent() {
        let json = validJSON {
            $0["observations"] = [
                ["feature": "era_guess", "value": "1990s", "evidencePhotoRole": "photo_7", "certainty": "inferred"]
            ]
        }
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        guard case .success = result else { XCTFail("Inferred observations should not require a sent photo role"); return }
    }

    func testNormalizesFormattedPriceStringsAndMissingOptionalArrays() {
        let json = """
        {
          "schemaVersion": "2",
          "task": "quick_value",
          "productGuess": {"brand": "Levi's", "model": "501", "era": "1990s"},
          "summary": "빠른 추정",
          "confidence": "MEDIUM",
          "condition": "GOOD",
          "koreaSaleRange": {"low": "80,000원", "high": "150,000원"},
          "japanSaleRange": {"low": "8,000엔", "high": "15,000엔"},
          "jpyToKrwRate": "9.1"
        }
        """
        let result = QuickValueResultValidator.validate(rawText: json, sentPhotoRoles: sentRoles)
        switch result {
        case .success(let value):
            XCTAssertEqual(value.koreaSaleRange.low, 80_000)
            XCTAssertEqual(value.koreaSaleRange.high, 150_000)
            XCTAssertEqual(value.japanSaleRange.low, 8_000)
            XCTAssertEqual(value.japanSaleRange.high, 15_000)
            XCTAssertEqual(value.jpyToKrwRate, 9.1)
        case .failure(let error):
            XCTFail("Expected normalized result, got \(error)")
        }
    }
}
