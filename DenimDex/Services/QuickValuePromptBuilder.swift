import Foundation

/// 기술서 9.1절 Quick Value 규칙과 정밀 가이드 교차 검증 계약을 반영한 프롬프트 생성기.
/// AIBI 엔진과 분리되어 있으며, DenimDex 제품 지식은 전부 이 파일 안에만 있다.
/// 사진은 자유 촬영 식별자(`photo_1`…)와 가이드 정밀 역할(`pants_front`, `jacket_chest_pocket`…)을 모두 지원한다.
enum QuickValuePromptBuilder {
    static func buildPrompt(photoRoles: [String], missingPhotoRoles: [String] = []) -> String {
        let roleList = photoRoles.enumerated()
            .map { index, role in
                let desc = roleDisplayName(for: role)
                return "\(index + 1)번 사진: \(role)\(desc.isEmpty ? "" : " (\(desc))")"
            }
            .joined(separator: "\n")
        let missingRoleList = missingPhotoRoles
            .map { role in
                let desc = roleDisplayName(for: role)
                return "- \(role)\(desc.isEmpty ? "" : " (\(desc))")"
            }
            .joined(separator: "\n")
        let missingRoleSection = missingRoleList.isEmpty
            ? "빠진 촬영 항목: 없음"
            : "빠졌거나 건너뛴 촬영 항목:\n\(missingRoleList)"

        return """
        너는 빈티지 데님 정밀 감정과 세부 디테일 교차 검증(Cross-Check)을 돕는 전문 조사 보조원이다. \
        첨부된 사진 \(photoRoles.count)장을 면밀히 관찰하고 아래 JSON 스키마 하나만 출력해라. \
        설명 문장, 인사말, 마크다운 제목을 붙이지 말고 JSON 코드 블록 하나만 응답해라.

        사진 순서와 식별자 (관찰 근거를 적을 때 이 식별자를 evidencePhotoRole에 그대로 사용해라):
        \(roleList)

        \(missingRoleSection)
        빠진 촬영 항목은 사진에서 확인한 것처럼 추측하지 말고 missingEvidence에 그대로 반영해라.

        핵심 원칙 - 세부 디테일 상호 교차 검증 (Cross-Check):
        - 절대 단 하나의 디테일(예: 레드탭이나 패치 하나만)에 의존해 성급히 결론을 내리지 마라.
        - 가죽·종이 패치, 레드탭(빅E/스몰e/폰트/원단), 버튼 뒷면 각인(공장 번호), 안쪽 케어라벨(생산주차/공장코드/원산지), 리벳(숨은 리벳/바택), 지퍼 또는 버튼 플라이(V스티치/톱니), 봉제선(싱글/체인스티치, 아큐에이트, 요크), 원단(셀비지 유무/직조) 등 사진에 포함된 모든 디테일을 상호 비교해라.
        - matches: 여러 디테일 간 연대와 특징이 서로 맞아떨어지는 일치 근거 목록을 나열해라 (예: "버튼 뒷면 각인 555와 90년대 발렌시아 공장 라벨 표기 일치", "V스티치와 히든리벳 생략 시점의 60년대 중반 디테일 일치"). 일치 근거가 없으면 빈 배열.
        - conflicts: 디테일 간 연대가 상충되거나 부자연스러운 점, 주의해야 할 불일치 단서를 나열해라 (예: "빅E 탭이나 케어라벨 형식은 80년대 이후 형태", "패치 로트 표기와 핏 디테일 불일치"). 이상이 없으면 빈 배열.
        - missingEvidence: 더 확실한 연대 판정 및 감정을 위해 꼭 필요하지만 첨부 사진에서 빠진 핵심 단서/부위를 나열해라 (예: "케어라벨 뒷면 생산주차 미확인", "버튼 뒷면 각인 미확인"). 없으면 빈 배열.

        진품 및 복각 가능성 판정 (Authenticity & Reproduction):
        - 이것은 사진 기반의 참고용 AI 추정일 뿐 절대 법적·공식적 정품 인증서가 아니다. 이 사실을 caveats에 반드시 포함해라.
        - authenticityPossibility: 디테일들의 상호 일치도와 품질을 종합해 판정 소견을 간결하게 제시해라 (예: "진품 가능성 높음", "LVC 또는 공식 복각판 추정", "연대 불일치로 정밀 실물 확인 필요", "단서 부족으로 판단 보류").
        - authenticitySummary: 왜 그렇게 판단했는지 두 문장 이내로 근거를 요약해라.

        가격 및 시장 규칙:
        - 이것은 빠른 참고용 추정이며 정품 감정이나 실제 매입가가 아니다. 이 사실을 caveats에 반드시 포함해라.
        - 한국(KRW)과 일본(JPY) 두 시장의 예상 판매가 범위를 각각 넓게 추정해라. 실시간 거래 데이터베이스는 \
        연결되어 있지 않으므로, 이는 일반 지식에 기반한 넓은 참고 범위이며 가격과 환율 모두 실시간으로 \
        검증되지 않았다는 사실을 caveats에 명시해라.
        - jpyToKrwRate는 "엔화 1엔당 원화" 환율로, 반드시 0보다 큰 값을 제시해라 (예: 9.1).
        - koreaFairPurchaseRange/japanFairPurchaseRange는 "이 정도 가격이면 사도 합리적이다"라고 볼 수 \
        있는 적정 매입가 범위이며, koreaSaleRange/japanSaleRange(예상 판매가)와는 다른 개념이다. 둘을 \
        혼동하지 말고, 적정 매입가는 예상 판매가보다 낮게 설정해라.

        기타 규칙:
        - 사진에서 직접 보이지 않는 특징을 관찰된 사실처럼 적지 마라.
        - 판단이 어려우면 무리하게 브랜드나 모델을 단정하지 말고 confidence를 낮춰라.
        - productGuess.variant에는 세부 변형/라인 정보(예: "빅E 셀비지", "LVC 1947", "66 전기")를 사진 근거로 \
        확인 가능한 경우만 적어라. 확신이 없으면 빈 문자열로 둬라.
        - productGuess.estimatedProductionYear에는 사진 속 케어라벨, 로트 번호, 탭, 지퍼, 리벳 등으로 \
        추정 가능한 생산연도 또는 연도 범위를 적어라. productGuess.estimatedFactory에는 공장 코드나 \
        원산지 표기 등 사진 근거로 추정한 제조공장 또는 생산지를 적어라. 근거가 부족하면 각각 빈 문자열로 \
        두고, 근거가 있으면 observations에 해당 사진과 certainty를 남겨라.
        - rarityLevel은 "unknown | common | uncommon | rare | extremely_rare" 중 하나다. 근거가 \
        약하거나 일반적으로 흔한 제품이면 절대 rare나 extremely_rare로 단정하지 말고 보수적으로 낮은 \
        등급을 선택해라. raritySummary에 두 문장 이내로 왜 그 등급인지 설명하고, rarityReasons에 구체적 \
        근거를 나열해라. 근거가 없으면 rarityReasons를 빈 배열로 둬라. 객관적으로 검증된 희소성처럼 \
        단정하지 말고 항상 추정임을 분명히 해라.
        - 판단에 도움이 될 사진이 한 장 더 있으면 좋겠다면 nextPhotoInstruction에 한 문장으로 안내해라. \
        필요 없으면 생략해라.

        정확히 이 스키마를 따르는 JSON 코드 블록만 출력해라:
        ```json
        {
          "schemaVersion": 3,
          "task": "quick_value",
          "productGuess": { "brand": "string", "model": "string", "era": "string", "variant": "string", "estimatedProductionYear": "string", "estimatedFactory": "string" },
          "summary": "string, 두 문장 이내",
          "confidence": "high | medium | low | unknown",
          "condition": "excellent | good | fair | poor | unknown",
          "rarityLevel": "unknown | common | uncommon | rare | extremely_rare",
          "raritySummary": "string, 두 문장 이내",
          "rarityReasons": ["string"],
          "authenticityPossibility": "string",
          "authenticitySummary": "string, 두 문장 이내",
          "matches": ["string"],
          "conflicts": ["string"],
          "missingEvidence": ["string"],
          "koreaFairPurchaseRange": { "low": 0, "high": 0 },
          "koreaSaleRange": { "low": 0, "high": 0 },
          "japanFairPurchaseRange": { "low": 0, "high": 0 },
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

    private static func roleDisplayName(for role: String) -> String {
        switch role {
        // 팬츠 가이드 샷
        case "pants_front": "바지 전체 앞면"
        case "pants_inside_hem_selvedge": "바지 안쪽 밑단·아웃심 셀비지"
        case "pants_back": "바지 전체 뒷면"
        case "pants_patch": "바지 가죽·종이 패치"
        case "pants_red_tab": "바지 레드탭"
        case "pants_waist_button_back": "바지 허리 상단 버튼 뒷면 각인"
        case "pants_care_tag": "바지 케어라벨 앞뒤"
        case "pants_inside_back_pocket": "바지 뒷포켓 안쪽 히든리벳·바택"
        case "pants_fly": "바지 플라이 전체 V스티치·지퍼·버튼"

        // 재킷 가이드 샷
        case "jacket_front": "재킷 전체 앞면"
        case "jacket_interior": "재킷 내부 전체"
        case "jacket_back": "재킷 전체 뒷면"
        case "jacket_neck_label_patch": "재킷 목 라벨·패치"
        case "jacket_red_tab": "재킷 레드탭"
        case "jacket_chest_pocket": "재킷 가슴 포켓"
        case "jacket_button_back": "재킷 버튼 뒷면 각인"
        case "jacket_waist_adjuster": "재킷 허리 조절기 (신치백·버튼)"
        case "jacket_care_tag": "재킷 케어라벨 앞뒤"

        // 레거시/일반 역할
        case "overall_front": "전체 앞면"
        case "overall_back": "전체 뒷면"
        case "red_tab": "레드탭"
        case "top_button_front": "상단 버튼 앞면"
        case "top_button_back": "상단 버튼 뒷면 각인"
        case "care_label": "케어라벨"
        case "patch": "패치"
        case "rivets": "리벳"
        case "zipper_or_fly": "지퍼·플라이"
        case "selvedge": "셀비지"
        case "stitching": "봉제·아큐에이트"

        default: ""
        }
    }
}
