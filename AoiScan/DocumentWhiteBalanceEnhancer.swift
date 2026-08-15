//
//  DocumentWhiteBalanceEnhancer.swift
//  AoiScan
//

import UIKit
import CoreImage


struct DocumentWhiteBalanceCorrection:Codable {
    let redGain:Float
    let greenGain:Float
    let blueGain:Float
}


/// Applies a small, measured channel correction derived from the sampled
/// paper background. Saturated colors are restored from the baseline image.
enum DocumentWhiteBalanceEnhancer {
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
                        red > green * 1.08 && red > blue * 1.06
                    ) || (
                        blue > red * 1.06 && blue > green * 1.05
                    )
                    let threshold:Float = isRedOrBlue ? 0.07 : 0.15
                    let mask = min(
                        max((saturation - threshold) / 0.10, 0),
                        1
                    )
                    values.append(contentsOf:[mask, mask, mask, 1])
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer:$0) }
    }()

    static func correction(
        for analysis:ColorTemperatureResult
    )->DocumentWhiteBalanceCorrection? {
        guard analysis.source == .warm || analysis.source == .cool,
              analysis.confidence >= 0.68,
              analysis.validSampleRatio >= 0.18,
              !analysis.possiblePaperColor else {
            return nil
        }

        let neutral = (
            analysis.averageRed
                + analysis.averageGreen
                + analysis.averageBlue
        ) / 3
        let confidenceProgress = min(
            max((analysis.confidence - 0.68) / 0.27, 0),
            1
        )
        let strength:Float = 0.34 + confidenceProgress * 0.20
        func gain(channel:Float,lower:Float,upper:Float)->Float {
            let raw = neutral / max(channel, 0.001)
            return min(max(1 + (raw - 1) * strength, lower), upper)
        }

        return DocumentWhiteBalanceCorrection(
            redGain:gain(channel:analysis.averageRed, lower:0.965, upper:1.035),
            greenGain:gain(channel:analysis.averageGreen, lower:0.985, upper:1.015),
            blueGain:gain(channel:analysis.averageBlue, lower:0.965, upper:1.035)
        )
    }

    static func enhance(
        image:UIImage,
        analysis:ColorTemperatureResult
    )->UIImage {
        guard let source = CIImage(image:image),
              let correction = correction(for:analysis) else {
            return image
        }
        let extent = source.extent
        let adjusted = source.applyingFilter(
            "CIColorMatrix",
            parameters:[
                "inputRVector":CIVector(
                    x:CGFloat(correction.redGain), y:0, z:0, w:0
                ),
                "inputGVector":CIVector(
                    x:0, y:CGFloat(correction.greenGain), z:0, w:0
                ),
                "inputBVector":CIVector(
                    x:0, y:0, z:CGFloat(correction.blueGain), w:0
                ),
                "inputAVector":CIVector(x:0, y:0, z:0, w:1)
            ]
        )
        .cropped(to:extent)
        let saturatedColorMask = source.applyingFilter(
            "CIColorCube",
            parameters:[
                "inputCubeDimension":24,
                "inputCubeData":saturationCubeData
            ]
        )
        .cropped(to:extent)
        let colorSafe = source.applyingFilter(
            "CIBlendWithMask",
            parameters:[
                kCIInputBackgroundImageKey:adjusted,
                kCIInputMaskImageKey:saturatedColorMask
            ]
        )
        .cropped(to:extent)

        guard let cgImage = context.createCGImage(colorSafe, from:extent) else {
            return image
        }
        return UIImage(cgImage:cgImage, scale:image.scale, orientation:.up)
    }
}
