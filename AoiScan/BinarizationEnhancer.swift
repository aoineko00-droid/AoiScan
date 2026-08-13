//
//  BinarizationEnhancer.swift
//  AoiScan
//

import CoreImage


enum BinarizationEnhancer {
    static func apply(
        to image:CIImage,
        blocks:[OCRBlock],
        threshold:CGFloat?
    )->CIImage {
        guard let threshold else { return image }

        let adjusted = image
            .applyingFilter(
                "CIColorControls",
                parameters:[kCIInputSaturationKey:0]
            )
            .applyingFilter(
                "CIColorThreshold",
                parameters:["inputThreshold":threshold]
            )
            .cropped(to:image.extent)

        return TextEnhancementMask.blend(
            adjusted:adjusted,
            over:image,
            mask:TextEnhancementMask.make(
                blocks:blocks,
                extent:image.extent,
                expansion:0.10
            )
        )
    }
}
