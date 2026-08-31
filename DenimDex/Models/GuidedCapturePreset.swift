import Foundation

/// 가이드 촬영 프리셋 (리바이스 팬츠 / 재킷 / 자유 촬영).
enum GuidedCapturePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case pants
    case jacket

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pants: "리바이스 팬츠"
        case .jacket: "리바이스 재킷"
        }
    }

    var subtitle: String {
        switch self {
        case .pants: "바지 9단계 정밀 촬영"
        case .jacket: "재킷 9단계 정밀 촬영"
        }
    }

    var iconName: String {
        switch self {
        case .pants: "figure.walk"
        case .jacket: "tshirt"
        }
    }

    var shots: [GuidedShotDefinition] {
        switch self {
        case .pants:
            return [
                GuidedShotDefinition(
                    index: 1,
                    role: "pants_front",
                    title: "전체 앞면",
                    shortInstruction: "바지 앞모습 전체가 한눈에 다 들어오게 바닥에 펴고 찍어주세요.",
                    detailHint: "실루엣과 전체 색감, 앞주머니 모양이 잘 보이도록 정면에서 담아주세요.",
                    iconName: "square.dashed"
                ),
                GuidedShotDefinition(
                    index: 2,
                    role: "pants_inside_hem_selvedge",
                    title: "안쪽 밑단·아웃심 (셀비지)",
                    shortInstruction: "바지 밑단을 살짝 접어 올려 안쪽 재봉선과 셀비지 실선이 보이게 찍어주세요.",
                    detailHint: "체인 스티치 마감과 빨간 셀비지 라인 유무를 확인하는 중요한 단서입니다.",
                    iconName: "arrow.up.and.line.horizontal.and.arrow.down"
                ),
                GuidedShotDefinition(
                    index: 3,
                    role: "pants_back",
                    title: "전체 뒷면",
                    shortInstruction: "바지 뒷모습 전체와 뒷주머니가 잘 보이게 펴고 찍어주세요.",
                    detailHint: "뒷주머니 배치와 요크 스티치가 전체적으로 보이게 담아주세요.",
                    iconName: "square.split.2x1"
                ),
                GuidedShotDefinition(
                    index: 4,
                    role: "pants_patch",
                    title: "가죽·종이 패치",
                    shortInstruction: "허리 오른쪽 뒤에 붙은 패치의 글자와 숫자가 잘 보이게 찍어주세요.",
                    detailHint: "로트 번호(501 등), 사이즈 표기, 투호스 인쇄 선명도를 확인합니다.",
                    iconName: "doc.text.fill"
                ),
                GuidedShotDefinition(
                    index: 5,
                    role: "pants_red_tab",
                    title: "레드탭",
                    shortInstruction: "뒷주머니 옆에 달린 빨간색 탭의 글자가 또렷하게 보이게 가까이서 찍어주세요.",
                    detailHint: "대문자 E(빅E)인지 소문자 e(스몰e)인지, 양면 인쇄인지 확인합니다.",
                    iconName: "tag.fill"
                ),
                GuidedShotDefinition(
                    index: 6,
                    role: "pants_waist_button_back",
                    title: "허리 상단 버튼 뒷면 각인",
                    shortInstruction: "허리 제일 위 버튼을 뒤집어서 뒷면에 찍힌 숫자나 영문 각인을 찍어주세요.",
                    detailHint: "555, 524, 6, E 등 생산 공장을 나타내는 중요한 각인 번호입니다.",
                    iconName: "circle.circle.fill"
                ),
                GuidedShotDefinition(
                    index: 7,
                    role: "pants_care_tag",
                    title: "케어라벨 앞뒤",
                    shortInstruction: "바지 안쪽에 달린 세탁 라벨의 글자와 숫자가 선명하게 보이게 찍어주세요.",
                    detailHint: "생산 연월(주차), 공장 번호, 원산지 표기가 읽히도록 초점을 맞춰주세요.",
                    iconName: "list.bullet.rectangle.portrait"
                ),
                GuidedShotDefinition(
                    index: 8,
                    role: "pants_inside_back_pocket",
                    title: "뒷포켓 안쪽 (히든리벳·바택)",
                    shortInstruction: "뒷주머니 안쪽 윗부분을 벌려서 숨은 쇠 리벳이나 보강 박음질을 찍어주세요.",
                    detailHint: "히든 리벳(숨은 리벳)이나 검정/감색 바택 박음질은 연대 구분의 핵심입니다.",
                    iconName: "square.bottomhalf.filled"
                ),
                GuidedShotDefinition(
                    index: 9,
                    role: "pants_fly",
                    title: "플라이 전체 (V스티치·지퍼·버튼)",
                    shortInstruction: "앞 여밈 부분의 단추/지퍼와 허리 단추 옆 V자 박음질이 잘 보이게 찍어주세요.",
                    detailHint: "V스티치 마감 방식과 Talon/Scovill/Levi's 지퍼 또는 버튼 모양을 확인합니다.",
                    iconName: "arrow.down.right.and.arrow.up.left"
                )
            ]
        case .jacket:
            return [
                GuidedShotDefinition(
                    index: 1,
                    role: "jacket_front",
                    title: "전체 앞면",
                    shortInstruction: "재킷 앞모습 전체가 한눈에 다 들어오게 바닥에 펴고 찍어주세요.",
                    detailHint: "전체 실루엣, 가슴 포켓 위치, 앞여밈 플리츠가 잘 보이게 담아주세요.",
                    iconName: "square.dashed"
                ),
                GuidedShotDefinition(
                    index: 2,
                    role: "jacket_interior",
                    title: "내부 전체",
                    shortInstruction: "재킷 앞을 활짝 열고 안쪽 전체 모습과 안감 상태를 찍어주세요.",
                    detailHint: "원단 안쪽 결, 셀비지 라인, 안감 유무와 봉제 마감을 확인합니다.",
                    iconName: "square.inset.filled"
                ),
                GuidedShotDefinition(
                    index: 3,
                    role: "jacket_back",
                    title: "전체 뒷면",
                    shortInstruction: "재킷 뒷모습 전체가 잘 보이게 반듯하게 펴고 찍어주세요.",
                    detailHint: "뒤판 요크 라인과 허리 밴드 마감이 잘 보이게 담아주세요.",
                    iconName: "square.split.2x1"
                ),
                GuidedShotDefinition(
                    index: 4,
                    role: "jacket_neck_label_patch",
                    title: "목 라벨·패치",
                    shortInstruction: "목 안쪽에 붙은 라벨이나 가죽 패치의 글자가 잘 보이게 찍어주세요.",
                    detailHint: "506XX, 507XX, 557XX, 70505 등 모델 번호와 사이즈 글자를 확인합니다.",
                    iconName: "doc.text.fill"
                ),
                GuidedShotDefinition(
                    index: 5,
                    role: "jacket_red_tab",
                    title: "레드탭",
                    shortInstruction: "가슴 주머니 옆에 달린 빨간색 탭의 글자가 선명하게 보이게 찍어주세요.",
                    detailHint: "빅E/스몰e 여부와 탭의 재질, 폰트 디테일을 확인합니다.",
                    iconName: "tag.fill"
                ),
                GuidedShotDefinition(
                    index: 6,
                    role: "jacket_chest_pocket",
                    title: "가슴 포켓",
                    shortInstruction: "가슴 주머니 덮개 모양과 주머니 옆 주름(플리츠) 박음질을 찍어주세요.",
                    detailHint: "1세대(1포켓), 2세대(2포켓), 3세대(V심) 등 모델 구분의 기준입니다.",
                    iconName: "tray.full.fill"
                ),
                GuidedShotDefinition(
                    index: 7,
                    role: "jacket_button_back",
                    title: "버튼 뒷면 각인",
                    shortInstruction: "앞단추를 뒤집어서 뒷면에 새겨진 공장 번호나 각인을 찍어주세요.",
                    detailHint: "52, 524, 555 등 생산 공장 번호를 확인하는 중요한 단서입니다.",
                    iconName: "circle.circle.fill"
                ),
                GuidedShotDefinition(
                    index: 8,
                    role: "jacket_waist_adjuster",
                    title: "허리 조절기 (신치백·버튼)",
                    shortInstruction: "허리 양옆의 조절 버튼이나 뒤쪽 허리 버클(신치백)을 찍어주세요.",
                    detailHint: "신치백 버클 형태(바늘/솔리드) 또는 허리 탭 버튼을 확인합니다.",
                    iconName: "slider.horizontal.3"
                ),
                GuidedShotDefinition(
                    index: 9,
                    role: "jacket_care_tag",
                    title: "케어라벨 앞뒤",
                    shortInstruction: "재킷 안쪽에 달린 세탁 라벨의 글자와 숫자가 또렷하게 보이게 찍어주세요.",
                    detailHint: "생산 연월, 공장 번호, 원산지 표기를 확인합니다.",
                    iconName: "list.bullet.rectangle.portrait"
                )
            ]
        }
    }
}

/// 가이드 촬영의 각 샷 정의.
struct GuidedShotDefinition: Identifiable, Equatable, Sendable {
    let index: Int
    let role: String
    let title: String
    let shortInstruction: String
    let detailHint: String
    let iconName: String

    var referenceImageName: String? {
        switch role {
        case "pants_front": return "GuidedPantsFront"
        case "pants_inside_hem_selvedge": return "GuidedPantsHem"
        case "pants_back": return "GuidedPantsBack"
        case "pants_patch": return "GuidedPantsPatch"
        case "pants_red_tab": return "GuidedPantsRedTab"
        case "pants_waist_button_back": return "GuidedPantsButtonBack"
        case "pants_care_tag": return "GuidedPantsCareTag"
        case "pants_inside_back_pocket": return "GuidedPantsPocketInside"
        case "pants_fly": return "GuidedPantsFly"
        case "jacket_front": return "GuidedJacketFront"
        case "jacket_interior": return "GuidedJacketInterior"
        case "jacket_back": return "GuidedJacketBack"
        case "jacket_neck_label_patch": return "GuidedJacketNeckPatch"
        case "jacket_red_tab": return "GuidedJacketRedTab"
        case "jacket_chest_pocket": return "GuidedJacketChestPocket"
        case "jacket_button_back": return "GuidedJacketButtonBack"
        case "jacket_waist_adjuster": return "GuidedJacketWaistAdjuster"
        case "jacket_care_tag": return "GuidedJacketCareTag"
        default: return nil
        }
    }

    var id: String { role }
}

/// 가이드 촬영 세션에서 개별 샷의 상태(사진 데이터, 건너뜀 여부).
struct GuidedShotSlot: Identifiable, Equatable {
    let definition: GuidedShotDefinition
    var photoData: Data?
    var isSkipped: Bool

    var id: String { definition.role }

    var isCaptured: Bool { photoData != nil }

    var statusText: String {
        if isCaptured { return "촬영 완료" }
        if isSkipped { return "건너뜀" }
        return "미촬영"
    }
}

/// 상단 탭에서 선택 가능한 촬영 모드.
enum CaptureModeSelection: String, CaseIterable, Identifiable {
    case pants = "pants"
    case jacket = "jacket"
    case quick = "quick"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pants: "팬츠"
        case .jacket: "재킷"
        case .quick: "자유 촬영"
        }
    }

    var iconName: String {
        switch self {
        case .pants: "figure.walk"
        case .jacket: "tshirt"
        case .quick: "sparkles"
        }
    }

    var badgeText: String {
        switch self {
        case .pants: "9장 가이드"
        case .jacket: "9장 가이드"
        case .quick: "최대 30장"
        }
    }
}
