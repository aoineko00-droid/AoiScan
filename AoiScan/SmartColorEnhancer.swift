//
//  SmartColorEnhancer.swift
//  AoiScan
//

import UIKit
import CoreImage


/// Enhances document luminance while retaining source chroma. Text receives
/// the full safe correction, background receives only a small flattening
/// blend, and saturated colors are restored from the source image.
enum SmartColorEnhancer {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    private static let saturationCubeData:Data = {
        let dimension = 24
        var values = [Float]()
        values.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Float(blueIndex) / Float(dimension - 1)
            for greenIndex in 0..<dimension {
                let green = Float(greenIndex) / Float(dimension - 1)
                for redIndex in 0..<dimension {
                    let red = Float(redIndex) / Float(dimension - 1)
                    let maximum = max(red, green, blue)
                    let minimum = min(red, green, blue)
                    let saturation = maximum > 0.001
                        ? (maximum - minimum) / maximum : 0
                    let isRedOrBlue = (
                        red > green * 1.10 && red > blue * 1.08
                    ) || (
                        blue > red * 1.08 && blue > green * 1.06
                    )
                    let threshold:Float = isRedOrBlue ? 0.08 : 0.17
                    let mask = min(
                        max((saturation - threshold) / 0.10, 0),
                        1
                    )
                    values.append(contentsOf:[mask, mask, mask, 1])
                }
            }
        }
        return values.withUnsafeBufferPointer { buffer in
            Data(buffer:buffer)
        }
    }()

    static func enhance(
        image:UIImage,
        blocks:[OCRBlock],
        parameters:EnhancementParameters
    )->UIImage {
        enhanceIllumination(
            image:image,
            blocks:blocks,
            parameters:parameters
        )
    }

    static func enhanceIllumination(
        image:UIImage,
        blocks:[OCRBlock],
        parameters:EnhancementParameters
    )->UIImage {
        guard let source = CIImage(image:image),
              !blocks.isEmpty else {
            return image
        }
        let luminance = LuminanceEnhancer.apply(
            to:source,
            parameters:parameters
        )
        let colorized = source.applyingFilter(
            "CIColorBlendMode",
            parameters:[kCIInputBackgroundImageKey:luminance]
        )
        .cropped(to:source.extent)
        let saturatedColorMask = source.applyingFilter(
            "CIColorCube",
            parameters:[
                "inputCubeDimension":24,
                "inputCubeData":saturationCubeData
            ]
        )
        .cropped(to:source.extent)
        let colorSafeEnhanced = source.applyingFilter(
            "CIBlendWithMask",
            parameters:[
                kCIInputBackgroundImageKey:colorized,
                kCIInputMaskImageKey:saturatedColorMask
            ]
        )
        .cropped(to:source.extent)
        guard let cgImage = context.createCGImage(
            colorSafeEnhanced,
            from:source.extent
        ) else {
            return image
        }
        return UIImage(
            cgImage:cgImage,
            scale:image.scale,
            orientation:.up
        )
    }
}
