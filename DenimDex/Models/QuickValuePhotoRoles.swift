import Foundation

/// Quick Value V2는 사진 역할을 자유 촬영 순서로 취급한다. 프롬프트와 검증 양쪽이
/// 동일한 결정론적 식별자(`photo_1` … `photo_20`)를 참조하도록 여기서 한 번만 정의한다.
enum QuickValuePhotoRoles {
    static let minCount = 1
    static let maxCount = 20

    static func identifiers(count: Int) -> [String] {
        guard count >= 1 else { return [] }
        return (1...min(count, maxCount)).map { "photo_\($0)" }
    }
}
