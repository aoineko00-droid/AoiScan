//
//  SmartEnhancementCandidateBuilder.swift
//  AoiScan
//

import UIKit
import CoreImage


enum SmartEnhancementCandidateBuilder {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    /// Full-resolution candidates are expensive because illumination recovery
    /// contains morphology and a large low-frequency blur. Every route first
    /// runs on this bounded image; the production-size candidate is generated
    /// only after the same safety analyzers accept the preview.
    static func previewImage(
        _ image:UIImage,
        maximumPixelSize:CGFloat
    )->UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longest = max(width, height)
        guard maximumPixelSize >= 320,
              longest > maximumPixelSize else { return image }

        let scale = maximumPixelSize / longest
        let outputWidth = max(Int((width * scale).rounded()), 1)
        let outputHeight = max(Int((height * scale).rounded()), 1)
        guard let bitmap = CGContext(
            data:nil,
            width:outputWidth,
            height:outputHeight,
            bitsPerComponent:8,
            bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        bitmap.interpolationQuality = .medium
        bitmap.draw(
            cgImage,
            in:CGRect(x:0, y:0, width:outputWidth, height:outputHeight)
        )
        guard let output = bitmap.makeImage() else { return image }
        return UIImage(cgImage:output, scale:image.scale, orientation:.up)
    }

    /// The visual analyzers test every sampled pixel against the supplied
    /// OCR rectangles. Hundreds of dense-page blocks therefore make a cheap
    /// preview unexpectedly expensive. For preview-only analysis, collapse
    /// them into a bounded 32-row x 3-column occupancy map. Full OCR data and
    /// persisted OCR results are never changed.
    static func preflightBlocks(
        _ blocks:[OCRBlock],
        maximumCount:Int = 96
    )->[OCRBlock] {
        guard blocks.count > maximumCount,
              maximumCount >= 12 else { return blocks }

        let columnCount = 3
        let rowCount = max(maximumCount / columnCount, 1)
        var unions = [CGRect?](
            repeating:nil,
            count:rowCount * columnCount
        )

        for block in blocks {
            let rect = block.boundingBox.intersection(
                CGRect(x:0, y:0, width:1, height:1)
            )
            guard !rect.isNull,
                  rect.width > 0,
                  rect.height > 0 else { continue }
            let row = min(
                max(Int(rect.midY * CGFloat(rowCount)), 0),
                rowCount - 1
            )
            let column = min(
                max(Int(rect.midX * CGFloat(columnCount)), 0),
                columnCount - 1
            )
            let index = row * columnCount + column
            unions[index] = unions[index].map { $0.union(rect) } ?? rect
        }

        return unions.compactMap { rect in
            guard let rect else { return nil }
            return OCRBlock(
                text:"",
                boundingBox:rect,
                confidence:1
            )
        }
    }

    static func build(
        rgbSource:UIImage,
        baselineImage:UIImage,
        blocks:[OCRBlock],
        parameters:EnhancementParameters,
        route:DocumentQualityRoute,
        colorTemperature:ColorTemperatureResult? = nil
    )->UIImage {
        switch route.primaryIssue {
        case .lighting, .background:
            return DocumentShadowEnhancer.enhance(
                image:baselineImage,
                blocks:blocks,
                severity:route.severity
            )
        case .regionalSharpness:
            return RegionalSharpnessRecovery.apply(
                to:baselineImage,
                blocks:blocks,
                region:route.affectedRegion,
                severity:route.severity
            )
        case .none, .perspective:
            return baselineImage
        case .colorTemperature:
            guard let colorTemperature else { return baselineImage }
            let whiteBalanced = DocumentWhiteBalanceEnhancer.enhance(
                image:baselineImage,
                analysis:colorTemperature
            )
            return DocumentPaperNormalizer.enhance(
                image:whiteBalanced,
                blocks:blocks,
                analysis:colorTemperature
            )
        }
    }
}
