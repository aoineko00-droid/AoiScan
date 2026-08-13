//
//  ContrastEnhancer.swift
//  AoiScan
//

import CoreImage


enum ContrastEnhancer {
    static func apply(
        to image:CIImage,
        blocks:[OCRBlock],
        contrast:CGFloat,
        brightness:CGFloat
    )->CIImage {
        guard abs(contrast - 1) > 0.0001
                || abs(brightness) > 0.0001 else {
            return image
        }

        let adjusted = image.applyingFilter(
            "CIColorControls",
            parameters:[
                kCIInputBrightnessKey:brightness,
                kCIInputContrastKey:contrast
            ]
        )
        .cropped(to:image.extent)

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
