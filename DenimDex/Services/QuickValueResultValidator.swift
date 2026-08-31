import Foundation

/// 기술서 10.3절 "결과 검증" 규칙을 그대로 구현한다(V3, 한국·일본 이원 시장).
/// 규칙을 하나라도 어기면 결과를 거부하고, 호출자는 브라우저를 유지하거나 수동 가져오기를 안내해야 한다.
enum QuickValueValidationError: Error, Equatable {
    case jsonParsingFailed
    case schemaVersionMismatch
    case taskMismatch
    case disallowedEnumValue(field: String)
    case negativeValue
    case lowGreaterThanHigh
    case invalidExchangeRate
    case unobservedPhotoRoleUsed
    case emptyResult
}

enum QuickValueResultValidator {
    private static let allowedConfidence = Set(QuickValueConfidence.allCases.map(\.rawValue))
    private static let allowedCondition = Set(QuickValueCondition.allCases.map(\.rawValue))
    private static let allowedCertainty = Set(ObservationCertainty.allCases.map(\.rawValue))
    private static let allowedRarity = Set(QuickValueRarity.allCases.map(\.rawValue))

    /// - Parameter sentPhotoRoles: 이번 작업에서 실제로 전송한 사진 식별자(`photo_1` 등). 관찰 근거가
    ///   이 밖의 식별자를 가리키면 거부한다.
    static func validate(rawText: String, sentPhotoRoles: [String]) -> Result<QuickValueResult, QuickValueValidationError> {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyResult) }

        let jsonText = extractJSONBlock(from: trimmed)
        guard let data = jsonText.data(using: .utf8),
              let result = decodeResult(from: data) else {
            return .failure(.jsonParsingFailed)
        }

        guard result.schemaVersion == 3 else { return .failure(.schemaVersionMismatch) }
        guard result.task == "quick_value" else { return .failure(.taskMismatch) }

        guard allowedConfidence.contains(result.confidence) else { return .failure(.disallowedEnumValue(field: "confidence")) }
        guard allowedCondition.contains(result.condition) else { return .failure(.disallowedEnumValue(field: "condition")) }
        guard allowedRarity.contains(result.rarityLevel) else { return .failure(.disallowedEnumValue(field: "rarityLevel")) }
        for observation in result.observations {
            guard allowedCertainty.contains(observation.certainty) else {
                return .failure(.disallowedEnumValue(field: "observations.certainty"))
            }
        }

        guard result.koreaSaleRange.low >= 0, result.koreaSaleRange.high >= 0 else { return .failure(.negativeValue) }
        guard result.koreaSaleRange.low <= result.koreaSaleRange.high else { return .failure(.lowGreaterThanHigh) }
        guard result.japanSaleRange.low >= 0, result.japanSaleRange.high >= 0 else { return .failure(.negativeValue) }
        guard result.japanSaleRange.low <= result.japanSaleRange.high else { return .failure(.lowGreaterThanHigh) }
        guard result.koreaFairPurchaseRange.low >= 0, result.koreaFairPurchaseRange.high >= 0 else { return .failure(.negativeValue) }
        guard result.koreaFairPurchaseRange.low <= result.koreaFairPurchaseRange.high else { return .failure(.lowGreaterThanHigh) }
        guard result.japanFairPurchaseRange.low >= 0, result.japanFairPurchaseRange.high >= 0 else { return .failure(.negativeValue) }
        guard result.japanFairPurchaseRange.low <= result.japanFairPurchaseRange.high else { return .failure(.lowGreaterThanHigh) }
        guard result.jpyToKrwRate > 0 else { return .failure(.invalidExchangeRate) }

        var allowedRoles = Set(sentPhotoRoles)
        for i in 1...max(1, sentPhotoRoles.count) {
            allowedRoles.insert("photo_\(i)")
        }
        for observation in result.observations where observation.certainty == ObservationCertainty.observed.rawValue {
            guard allowedRoles.contains(observation.evidencePhotoRole) else {
                return .failure(.unobservedPhotoRoleUsed)
            }
        }

        return .success(result)
    }

    /// ChatGPT가 스키마 내용은 지켰지만 가격 숫자를 `"80,000"`처럼 문자열로
    /// 보내거나 선택 배열을 생략하는 가벼운 형식 차이는 보수적으로 정규화한다.
    /// schemaVersion, task, 가격 범위와 enum 검증은 위의 엄격한 규칙을 그대로 거친다.
    private static func decodeResult(from data: Data) -> QuickValueResult? {
        if let exact = try? JSONDecoder().decode(QuickValueResult.self, from: data) {
            return exact
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = root["productGuess"] as? [String: Any],
              let koreaRange = root["koreaSaleRange"] as? [String: Any],
              let koreaLow = integer(koreaRange["low"]),
              let koreaHigh = integer(koreaRange["high"]),
              let japanRange = root["japanSaleRange"] as? [String: Any],
              let japanLow = integer(japanRange["low"]),
              let japanHigh = integer(japanRange["high"]),
              let koreaFairRange = root["koreaFairPurchaseRange"] as? [String: Any],
              let koreaFairLow = integer(koreaFairRange["low"]),
              let koreaFairHigh = integer(koreaFairRange["high"]),
              let japanFairRange = root["japanFairPurchaseRange"] as? [String: Any],
              let japanFairLow = integer(japanFairRange["low"]),
              let japanFairHigh = integer(japanFairRange["high"]) else { return nil }

        let observations = (root["observations"] as? [[String: Any]] ?? []).compactMap { value -> QuickValueResult.Observation? in
            guard let feature = string(value["feature"]),
                  let observedValue = string(value["value"]),
                  let role = string(value["evidencePhotoRole"]),
                  let certainty = string(value["certainty"]) else { return nil }
            return .init(feature: feature, value: observedValue, evidencePhotoRole: role, certainty: certainty.lowercased())
        }

        return QuickValueResult(
            schemaVersion: integer(root["schemaVersion"]) ?? -1,
            task: string(root["task"]) ?? "",
            productGuess: .init(
                brand: string(product["brand"]) ?? "",
                model: string(product["model"]) ?? "",
                era: string(product["era"]) ?? "",
                variant: string(product["variant"]) ?? "",
                estimatedProductionYear: string(product["estimatedProductionYear"]) ?? "",
                estimatedFactory: string(product["estimatedFactory"]) ?? ""
            ),
            summary: string(root["summary"]) ?? "",
            confidence: (string(root["confidence"]) ?? "unknown").lowercased(),
            condition: (string(root["condition"]) ?? "unknown").lowercased(),
            rarityLevel: (string(root["rarityLevel"]) ?? "unknown").lowercased(),
            raritySummary: string(root["raritySummary"]) ?? "",
            rarityReasons: strings(root["rarityReasons"]),
            koreaFairPurchaseRange: .init(low: koreaFairLow, high: koreaFairHigh),
            koreaSaleRange: .init(low: koreaLow, high: koreaHigh),
            japanFairPurchaseRange: .init(low: japanFairLow, high: japanFairHigh),
            japanSaleRange: .init(low: japanLow, high: japanHigh),
            jpyToKrwRate: double(root["jpyToKrwRate"]) ?? -1,
            observations: observations,
            valueReasons: strings(root["valueReasons"]),
            nextPhotoInstruction: string(root["nextPhotoInstruction"]),
            caveats: strings(root["caveats"]),
            authenticityPossibility: string(root["authenticityPossibility"]),
            authenticitySummary: string(root["authenticitySummary"]),
            matches: strings(root["matches"]),
            conflicts: strings(root["conflicts"]),
            missingEvidence: strings(root["missingEvidence"])
        )
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        guard let text = value as? String else { return nil }
        let numeric = text.filter { $0.isNumber || $0 == "-" }
        return Int(numeric)
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        guard let text = value as? String else { return nil }
        let numeric = text.filter { $0.isNumber || $0 == "-" || $0 == "." }
        return Double(numeric)
    }

    private static func strings(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        if let value = value as? String, !value.isEmpty { return [value] }
        return []
    }

    /// AIBI 런타임의 `cleanOutput`이 이미 코드펜스를 제거하지만, 수동 붙여넣기 경로를 위해
    /// 여기서도 한 번 더 방어적으로 코드 블록을 벗겨낸다.
    static func extractJSONBlock(from text: String) -> String {
        if let range = text.range(of: #"```(?:json)?\s*([\s\S]*?)```"#, options: .regularExpression) {
            let fenced = String(text[range])
            let inner = fenced
                .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"```$"#, with: "", options: .regularExpression)
            return inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let openBrace = text.firstIndex(of: "{"), let closeBrace = text.lastIndex(of: "}"), openBrace < closeBrace {
            return String(text[openBrace...closeBrace])
        }
        return text
    }
}
