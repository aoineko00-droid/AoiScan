//
//  RegionalSharpnessRecovery.swift
//  AoiScan
//

import UIKit
import CoreImage


enum RegionalSharpnessRecovery {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    static func apply(
        to baseline:UIImage,
        blocks:[OCRBlock],
        region:DocumentRegion,
        severity:Float
    )->UIImage {
        guard region != .none,
              let source = CIImage(image:baseline) else { return baseline }
        let regionalBlocks = blocks.filter {
            DocumentQualityRouter.region(for:$0.boundingBox.midY) == region
        }
        guard !regionalBlocks.isEmpty else { return baseline }

        let amount = min(max(CGFloat(severity) * 0.08 + 0.055, 0.055), 0.13)
        let adjusted = source.applyingFilter(
            "CISharpenLuminance",
            parameters:[kCIInputSharpnessKey:amount]
        ).cropped(to:source.extent)
        let mask = TextEnhancementMask.make(
            blocks:regionalBlocks,
            extent:source.extent,
            expansion:0.025
        )
        let output = TextEnhancementMask.blend(
            adjusted:adjusted,
            over:source,
            mask:mask
        )
        guard let cgImage = context.createCGImage(
            output,
            from:source.extent
        ) else { return baseline }
        return UIImage(
            cgImage:cgImage,
            scale:baseline.scale,
            orientation:.up
        )
    }
}
