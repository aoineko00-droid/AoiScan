//
//  LuminanceEnhancer.swift
//  AoiScan
//

import CoreImage


/// Builds a document-style luminance layer while leaving hue/chroma handling
/// to SmartColorEnhancer. Processing is intentionally Core Image only.
enum LuminanceEnhancer {
    static func apply(
        to image:CIImage,
        parameters:EnhancementParameters
    )->CIImage {
        let extent = image.extent
        let grayscale = image.applyingFilter(
            "CIColorControls",
            parameters:[kCIInputSaturationKey:0]
        )
        let flattened = BackgroundFlattenEnhancer.apply(
            to:grayscale,
            strength:parameters.localNormalization
        )
        return flattened.cropped(to:extent)
    }
}
