import Foundation

/// 기술서 9.1절 Quick Value 규칙과 10.1절 JSON 계약(V2)을 그대로 반영한 프롬프트 생성기.
/// AIBI 엔진과 분리되어 있으며, DenimDex 제품 지식은 전부 이 파일 안에만 있다.
/// 사진은 자유 촬영이므로 역할 이름 대신 결정론적 식별자(`photo_1` … `photo_20`)를 사용한다.
enum QuickValuePromptBuilder {
    static func buildPrompt(photoRoles: [String]) -> String {
        let roleList = photoRoles.enumerated()
            .map { index, role in "\(index + 1)번 사진: \(role)" }
            .joined(separator: "\n")

        return """
        너는 빈티지 데님 감정을 돕는 조사 보조원이다. 첨부된 사진 \(photoRoles.count)장을 보고 아래 JSON \
        스키마 하나만 출력해라. 설명 문장, 인사말, 마크다운 제목을 붙이지 말고 JSON 코드 블록 하나만 응답해라.

        사진 순서와 식별자 (관찰 근거를 적을 때 이 식별자를 evidencePhotoRole에 그대로 사용해라):
        \(roleList)

        규칙:
        - 이것은 빠른 참고용 추정이며 정품 감정이나 실제 매입가가 아니다. 이 사실을 caveats에 반드시 포함해라.
        - 한국(KRW)과 일본(JPY) 두 시장의 예상 판매가 범위를 각각 넓게 추정해라. 실시간 거래 데이터베이스는 \
        연결되어 있지 않으므로, 이는 일반 지식에 기반한 넓은 참고 범위이며 가격과 환율 모두 실시간으로 \
        검증되지 않았다는 사실을 caveats에 명시해라.
        - jpyToKrwRate는 "엔화 1엔당 원화" 환율로, 반드시 0보다 큰 값을 제시해라 (예: 9.1).
        - 사진에서 직접 보이지 않는 특징을 관찰된 사실처럼 적지 마라.
        - 판단이 어려우면 무리하게 브랜드나 모델을 단정하지 말고 confidence를 낮춰라.
        - 판단에 도움이 될 사진이 한 장 더 있으면 좋겠다면 nextPhotoInstruction에 한 문장으로 안내해라. \
        필요 없으면 생략해라.

        정확히 이 스키마를 따르는 JSON 코드 블록만 출력해라:
        ```json
        {
          "schemaVersion": 2,
          "task": "quick_value",
          "productGuess": { "brand": "string", "model": "string", "era": "string" },
          "summary": "string, 두 문장 이내",
          "confidence": "high | medium | low | unknown",
          "condition": "excellent | good | fair | poor | unknown",
          "koreaSaleRange": { "low": 0, "high": 0 },
          "japanSaleRange": { "low": 0, "high": 0 },
          "jpyToKrwRate": 9.1,
          "observations": [
            { "feature": "string", "value": "string", "evidencePhotoRole": "photo_1", "certainty": "observed | reported | inferred" }
          ],
          "valueReasons": ["string"],
          "nextPhotoInstruction": "string",
          "caveats": ["string"]
        }
        ```
        """
    }
}
