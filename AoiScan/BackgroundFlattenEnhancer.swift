//
//  BackgroundFlattenEnhancer.swift
//  AoiScan
//

import CoreImage


/// Estimates slow paper illumination and corrects only the L-like luminance
/// layer. It never applies global contrast, gamma or edge expansion.
enum BackgroundFlattenEnhancer {
    static func apply(
        to luminance:CIImage,
        strength:CGFloat
    )->CIImage {
        let extent = luminance.extent
        guard strength > 0.001 else {
            return luminance.cropped(to:extent)
        }

        let maximumCorrection = min(max(strength, 0), 0.055)
        let radius = min(
            max(min(extent.width, extent.height) * 0.050, 40),
            96
        )
        let background = luminance
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters:[kCIInputRadiusKey:radius]
            )
            .cropped(to:extent)

        // Only brighten slow dark illumination. Never subtract luminance, so
        // this stage cannot turn a bright page gray as the former correction
        // did. Per-pixel correction is hard limited to 5.5%.
        let correction = background.applyingFilter(
            "CIColorMatrix",
            parameters:[
                "inputRVector":CIVector(x:-1, y:0, z:0, w:0),
                "inputGVector":CIVector(x:0, y:-1, z:0, w:0),
                "inputBVector":CIVector(x:0, y:0, z:-1, w:0),
                "inputAVector":CIVector(x:0, y:0, z:0, w:0),
                "inputBiasVector":CIVector(x:0.94, y:0.94, z:0.94, w:0)
            ]
        ).applyingFilter(
            "CIColorClamp",
            parameters:[
                "inputMinComponents":CIVector(x:0, y:0, z:0, w:0),
                "inputMaxComponents":CIVector(
                    x:maximumCorrection,
                    y:maximumCorrection,
                    z:maximumCorrection,
                    w:0
                )
            ]
        )
        return correction.applyingFilter(
            "CIAdditionCompositing",
            parameters:[kCIInputBackgroundImageKey:luminance]
        )
        .cropped(to:extent)
    }
}
