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

        // Turn the slow background deficit into a blend mask, then blend a
        // bounded exposure lift over the original luminance. Avoid treating a
        // correction field as an RGBA foreground image: compositor alpha
        // semantics can otherwise replace the page with the correction layer.
        let maskScale = 1 / max(maximumCorrection, 0.001)
        let correctionMask = background.applyingFilter(
            "CIColorMatrix",
            parameters:[
                "inputRVector":CIVector(x:-maskScale, y:0, z:0, w:0),
                "inputGVector":CIVector(x:0, y:-maskScale, z:0, w:0),
                "inputBVector":CIVector(x:0, y:0, z:-maskScale, w:0),
                "inputAVector":CIVector(x:0, y:0, z:0, w:0),
                "inputBiasVector":CIVector(
                    x:0.94 * maskScale,
                    y:0.94 * maskScale,
                    z:0.94 * maskScale,
                    w:1
                )
            ]
        ).applyingFilter(
            "CIColorClamp",
            parameters:[
                "inputMinComponents":CIVector(x:0, y:0, z:0, w:1),
                "inputMaxComponents":CIVector(x:1, y:1, z:1, w:1)
            ]
        )
        .cropped(to:extent)
        let lifted = luminance.applyingFilter(
            "CIExposureAdjust",
            parameters:[kCIInputEVKey:log2(1 + maximumCorrection)]
        )
        .cropped(to:extent)
        return lifted.applyingFilter(
            "CIBlendWithMask",
            parameters:[
                kCIInputBackgroundImageKey:luminance,
                kCIInputMaskImageKey:correctionMask
            ]
        )
        .cropped(to:extent)
    }
}
