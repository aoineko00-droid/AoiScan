//
//  DenoiseEnhancer.swift
//  AoiScan
//

import CoreImage


enum DenoiseEnhancer {
    static func apply(
        to image:CIImage,
        noiseLevel:CGFloat,
        sharpness:CGFloat
    )->CIImage {
        guard noiseLevel > 0 else { return image }

        return image.applyingFilter(
            "CINoiseReduction",
            parameters:[
                "inputNoiseLevel":noiseLevel,
                "inputSharpness":sharpness
            ]
        )
        .cropped(to:image.extent)
    }
}
