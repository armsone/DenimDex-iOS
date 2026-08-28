import CoreGraphics
import HanAI
import UIKit
import Vision

struct PhotoDeduplicationResult: Sendable {
    let images: [Data]
    let keptIndices: [Int]
    let removedCount: Int
}

/// Apple Vision이 사진의 특징 거리를 만들고, 어떤 사진을 남길지는 한양의
/// 플랫폼 공통 정책이 결정한다. 원본은 건드리지 않고 ChatGPT 전송 사본만 추린다.
enum HanAIPhotoDeduplicator {
    static func selectRepresentatives(from images: [Data]) -> PhotoDeduplicationResult {
        guard images.count > 1 else {
            return PhotoDeduplicationResult(images: images, keptIndices: Array(images.indices), removedCount: 0)
        }

        let features = images.enumerated().map { index, data in
            feature(for: data, index: index)
        }
        let candidates = features.map {
            ImageSimilarityCandidate(index: $0.index, sharpness: $0.sharpness, pixelCount: $0.pixelCount)
        }

        var distances: [ImagePairDistance] = []
        for first in features.indices {
            guard let firstObservation = features[first].observation else { continue }
            for second in features.index(after: first)..<features.endIndex {
                guard let secondObservation = features[second].observation,
                      hasComparableShape(features[first], features[second]) else { continue }
                var distance: Float = 0
                do {
                    try firstObservation.computeDistance(&distance, to: secondObservation)
                    distances.append(ImagePairDistance(
                        firstIndex: features[first].index,
                        secondIndex: features[second].index,
                        distance: Double(distance)
                    ))
                } catch {
                    // 비교가 불확실하면 제거하지 않는 것이 원칙이다.
                }
            }
        }

        let kept = ImageSimilaritySelector.representativeIndices(
            candidates: candidates,
            distances: distances
        )
        return PhotoDeduplicationResult(
            images: kept.map { images[$0] },
            keptIndices: kept,
            removedCount: images.count - kept.count
        )
    }

    private static func feature(for data: Data, index: Int) -> PhotoFeature {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            return PhotoFeature(index: index, observation: nil, sharpness: 0, pixelCount: 1, aspectRatio: 0)
        }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImageOrientation)
        try? handler.perform([request])
        return PhotoFeature(
            index: index,
            observation: request.results?.first as? VNFeaturePrintObservation,
            sharpness: laplacianSharpness(of: cgImage),
            pixelCount: cgImage.width * cgImage.height,
            aspectRatio: Double(cgImage.width) / Double(max(1, cgImage.height))
        )
    }

    /// 전체 사진과 세부 접사를 잘못 합치지 않도록 화면 비율이 가까운 사진끼리만 비교한다.
    private static func hasComparableShape(_ lhs: PhotoFeature, _ rhs: PhotoFeature) -> Bool {
        guard lhs.aspectRatio > 0, rhs.aspectRatio > 0 else { return false }
        return abs(lhs.aspectRatio - rhs.aspectRatio) / max(lhs.aspectRatio, rhs.aspectRatio) <= 0.05
    }

    /// 64px 회색 썸네일의 라플라시안 분산. 절대 화질 판정이 아니라 유사 사진 중
    /// 더 선명한 대표 한 장을 고르는 상대 점수로만 사용한다.
    private static func laplacianSharpness(of image: CGImage) -> Double {
        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum = 0.0
        var squareSum = 0.0
        var count = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Double(pixels[y * width + x])
                let laplacian = 4 * center
                    - Double(pixels[(y - 1) * width + x])
                    - Double(pixels[(y + 1) * width + x])
                    - Double(pixels[y * width + x - 1])
                    - Double(pixels[y * width + x + 1])
                sum += laplacian
                squareSum += laplacian * laplacian
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / count
        return max(0, (squareSum / count - mean * mean) / 10_000)
    }
}

private struct PhotoFeature {
    let index: Int
    let observation: VNFeaturePrintObservation?
    let sharpness: Double
    let pixelCount: Int
    let aspectRatio: Double
}

private extension UIImage {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
