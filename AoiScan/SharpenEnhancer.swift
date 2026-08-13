//
//  SharpenEnhancer.swift
//  AoiScan
//

import CoreImage


enum SharpenEnhancer {
    static func apply(
        to image:CIImage,
        blocks:[OCRBlock],
        sharpen:CGFloat,
        unsharpRadius:CGFloat,
        unsharpIntensity:CGFloat
    )->CIImage {
        guard sharpen > 0 || unsharpIntensity > 0 else {
            return image
        }

        var adjusted = image
        if sharpen > 0 {
            adjusted = adjusted.applyingFilter(
                "CISharpenLuminance",
                parameters:["inputSharpness":sharpen]
            )
        }

        if unsharpIntensity > 0 {
            adjusted = adjusted.applyingFilter(
                "CIUnsharpMask",
                parameters:[
                    kCIInputRadiusKey:unsharpRadius,
                    kCIInputIntensityKey:unsharpIntensity
                ]
            )
        }

        adjusted = adjusted.cropped(to:image.extent)
        return TextEnhancementMask.blend(
            adjusted:adjusted,
            over:image,
            mask:TextEnhancementMask.make(
                blocks:blocks,
                extent:image.extent
            )
        )
    }
}
