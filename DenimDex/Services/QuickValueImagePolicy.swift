import Foundation

/// DenimDex의 사진 수에 맞춰 AIBI 전송 사본의 총량을 약 16MB 안으로 제한한다.
/// 가까이 찍은 탭·라벨·버튼 각인이 읽힐 수 있도록 20장에서도 긴 변 1,536px을 우선 유지한다.
enum QuickValueImagePolicy {
    /// 사용자가 한 세션에서 촬영·보관할 수 있는 원본 수. 한양으로 추린 뒤 AIBI에는 최대 20장만 보낸다.
    static let captureMaximumCount = 30
    static let totalBatchBudgetBytes = 16_000_000
    static let maximumBytesPerImage = 2_000_000

    static func normalizationPolicy(photoCount: Int) -> AIBIImageNormalizationPolicy {
        let count = min(max(photoCount, 1), QuickValuePhotoRoles.maxCount)
        let perImageBudget = min(maximumBytesPerImage, totalBatchBudgetBytes / count)

        let longEdge: CGFloat
        let initialQuality: CGFloat
        switch count {
        case 1...8:
            longEdge = 2_048
            initialQuality = 0.84
        case 9...12:
            longEdge = 1_792
            initialQuality = 0.82
        case 13...16:
            longEdge = 1_600
            initialQuality = 0.80
        default:
            longEdge = 1_536
            initialQuality = 0.78
        }

        return AIBIImageNormalizationPolicy(
            maximumImageCount: QuickValuePhotoRoles.maxCount,
            maximumLongEdgePixels: longEdge,
            maximumBytesPerImage: perImageBudget,
            initialJPEGQuality: initialQuality,
            minimumJPEGQuality: 0.52
        )
    }
}
