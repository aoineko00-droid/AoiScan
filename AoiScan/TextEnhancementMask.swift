//
//  TextEnhancementMask.swift
//  AoiScan
//

import CoreImage
import CoreGraphics


enum TextEnhancementMask {
    static func make(
        blocks:[OCRBlock],
        extent:CGRect,
        expansion:CGFloat = 0.08
    )->CIImage {
        var mask = CIImage(
            color:CIColor(red:0, green:0, blue:0, alpha:1)
        )
        .cropped(to:extent)

        for block in blocks {
            let dynamicExpansion = min(
                expansion,
                max(0.035, 0.004 / max(block.boundingBox.height, 0.01))
            )
            let normalized = expanded(
                block.boundingBox,
                by:dynamicExpansion
            )
            let rect = CGRect(
                x:extent.minX + normalized.minX * extent.width,
                y:extent.minY + normalized.minY * extent.height,
                width:normalized.width * extent.width,
                height:normalized.height * extent.height
            )
            .intersection(extent)

            guard !rect.isNull,
                  rect.width > 0,
                  rect.height > 0 else {
                continue
            }

            let white = CIImage(
                color:CIColor(red:1, green:1, blue:1, alpha:1)
            )
            .cropped(to:rect)
            mask = white.composited(over:mask)
        }

        let featherRadius = min(
            max(min(extent.width, extent.height) * 0.0010, 1.5),
            5
        )
        return mask
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters:[kCIInputRadiusKey:featherRadius]
            )
            .cropped(to:extent)
    }

    static func blend(
        adjusted:CIImage,
        over source:CIImage,
        mask:CIImage
    )->CIImage {
        adjusted.applyingFilter(
            "CIBlendWithMask",
            parameters:[
                kCIInputBackgroundImageKey:source,
                kCIInputMaskImageKey:mask
            ]
        )
        .cropped(to:source.extent)
    }

    private static func expanded(
        _ rawRect:CGRect,
        by fraction:CGFloat
    )->CGRect {
        let rect = rawRect.intersection(
            CGRect(x:0, y:0, width:1, height:1)
        )
        guard !rect.isNull else { return .zero }

        return rect.insetBy(
            dx:-max(rect.width * fraction, 0.005),
            dy:-max(rect.height * fraction, 0.003)
        )
        .intersection(
            CGRect(x:0, y:0, width:1, height:1)
        )
    }
}
