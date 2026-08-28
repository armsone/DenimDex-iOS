import Foundation

/// 기술서 7.1절의 사진 역할 정의. 정밀 조사 등 이후 기능에서 사용하며,
/// Quick Value V2는 자유 촬영 순서(`photo_1` … `photo_20`)를 대신 사용한다.
enum EvidencePhotoRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case overallFront = "overall_front"
    case overallBack = "overall_back"
    case redTab = "red_tab"
    case topButtonFront = "top_button_front"
    case topButtonBack = "top_button_back"
    case careLabel = "care_label"
    case patch
    case rivets
    case zipperOrFly = "zipper_or_fly"
    case selvedge
    case stitching
    case damage
    case scaleReference = "scale_reference"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overallFront: "전체 앞면"
        case .overallBack: "전체 뒷면"
        case .redTab: "레드탭"
        case .topButtonFront: "상단 버튼 앞면"
        case .topButtonBack: "상단 버튼 뒷면 각인"
        case .careLabel: "케어라벨"
        case .patch: "가죽·종이 패치"
        case .rivets: "리벳"
        case .zipperOrFly: "지퍼·버튼 플라이"
        case .selvedge: "셀비지"
        case .stitching: "봉제·아큐에이트"
        case .damage: "오염·수선·마모"
        case .scaleReference: "크기 비교 기준"
        }
    }

    var shortInstruction: String {
        switch self {
        case .overallFront: "전체 모습이 잘 보이게 정면에서 찍어주세요."
        case .redTab: "레드탭이나 브랜드 탭이 선명하게 보이도록 가까이서 찍어주세요."
        case .patch: "가죽 또는 종이 패치가 잘 보이게 찍어주세요."
        case .topButtonBack: "상단 버튼 뒷면 각인이 보이게 버튼을 뒤집어 찍어주세요."
        case .careLabel: "케어라벨 글자가 잘 보이게 가까이서 찍어주세요."
        default: "\(displayName) 부위를 가까이서 선명하게 찍어주세요."
        }
    }
}
