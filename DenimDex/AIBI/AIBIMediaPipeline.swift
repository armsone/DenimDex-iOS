//
//  AIBIMediaPipeline.swift
//  Ordered, privacy-preserving image preparation for AIBI tasks.
//  Portable — adapted from the canonical AIBI media contract
//  (/Users/armsone/.codex/skills/aibi/references/media-attachments.md).
//

import Foundation
import UIKit

struct AIBIMediaAttachment: Equatable, Sendable {
    let data: Data
    let mimeType: String
    let filename: String
    let sourceIndex: Int
    let role: String?

    init(data: Data, mimeType: String = "image/jpeg", filename: String, sourceIndex: Int, role: String? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.filename = filename
        self.sourceIndex = sourceIndex
        self.role = role
    }

    var dataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

struct AIBIImageNormalizationPolicy: Equatable, Sendable {
    var maximumImageCount: Int = 8
    var maximumLongEdgePixels: CGFloat = 2_048
    var maximumBytesPerImage: Int = 2_000_000
    var initialJPEGQuality: CGFloat = 0.84
    var minimumJPEGQuality: CGFloat = 0.50
}

enum AIBIMediaPreparationError: Error, Equatable {
    case invalidPolicy
    case attachmentLimitExceeded
    case unsupportedImage(index: Int)
    case sizeTargetUnreachable(index: Int)
}

enum AIBIImageNormalizer {
    /// 선택된 사진만 순서대로 처리한다. 원본은 바꾸지 않으며 다시 그리면서 방향을
    /// 고정하고 위치·EXIF 등 원본 메타데이터를 제거한다.
    static func normalizeOrdered(
        _ sourceImages: [Data],
        roles: [String?] = [],
        policy: AIBIImageNormalizationPolicy = .init()
    ) throws -> [AIBIMediaAttachment] {
        guard (1...20).contains(policy.maximumImageCount),
              policy.maximumLongEdgePixels >= 512,
              policy.maximumBytesPerImage >= 128_000,
              (0...1).contains(policy.initialJPEGQuality),
              (0...policy.initialJPEGQuality).contains(policy.minimumJPEGQuality) else {
            throw AIBIMediaPreparationError.invalidPolicy
        }
        guard sourceImages.count <= policy.maximumImageCount else {
            throw AIBIMediaPreparationError.attachmentLimitExceeded
        }

        var output: [AIBIMediaAttachment] = []
        output.reserveCapacity(sourceImages.count)
        for (index, source) in sourceImages.enumerated() {
            let data = try autoreleasepool {
                try normalizeOne(source, index: index, policy: policy)
            }
            let role = roles.indices.contains(index)
                ? roles[index]?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64).description
                : nil
            output.append(AIBIMediaAttachment(
                data: data,
                filename: String(format: "aibi-%02d.jpg", index + 1),
                sourceIndex: index,
                role: role?.isEmpty == false ? role : nil
            ))
        }
        return output
    }

    private static func normalizeOne(
        _ source: Data,
        index: Int,
        policy: AIBIImageNormalizationPolicy
    ) throws -> Data {
        guard let image = UIImage(data: source), image.size.width > 0, image.size.height > 0 else {
            throw AIBIMediaPreparationError.unsupportedImage(index: index)
        }

        var rendered = render(image, maximumLongEdge: policy.maximumLongEdgePixels)
        var quality = policy.initialJPEGQuality
        var encoded = rendered.jpegData(compressionQuality: quality) ?? Data()

        while encoded.count > policy.maximumBytesPerImage && quality > policy.minimumJPEGQuality {
            quality = max(policy.minimumJPEGQuality, quality - 0.07)
            encoded = rendered.jpegData(compressionQuality: quality) ?? Data()
        }
        while encoded.count > policy.maximumBytesPerImage && max(rendered.size.width, rendered.size.height) > 640 {
            rendered = render(rendered, maximumLongEdge: max(640, max(rendered.size.width, rendered.size.height) * 0.85))
            encoded = rendered.jpegData(compressionQuality: quality) ?? Data()
        }
        guard !encoded.isEmpty, encoded.count <= policy.maximumBytesPerImage else {
            throw AIBIMediaPreparationError.sizeTargetUnreachable(index: index)
        }
        return encoded
    }

    private static func render(_ image: UIImage, maximumLongEdge: CGFloat) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        let ratio = min(1, maximumLongEdge / longEdge)
        let target = CGSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
