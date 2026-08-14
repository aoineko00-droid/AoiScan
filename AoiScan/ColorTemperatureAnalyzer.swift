//
//  ColorTemperatureAnalyzer.swift
//  AoiScan
//

import UIKit
import CoreGraphics


/// Low-cost paper-background sampling. This module records the likely light
/// source only; it deliberately does not alter the scan image.
enum ColorTemperatureAnalyzer {
    private static let sampleWidth = 160

    static func analyze(
        image:UIImage,
        blocks:[OCRBlock] = []
    )->ColorTemperatureResult? {
        guard let sampled = sampledPixels(image) else { return nil }
        let exclusionRects = blocks.map {
            $0.boundingBox.insetBy(dx:-0.012, dy:-0.008)
        }
        var paperPixels:[Pixel] = []
        paperPixels.reserveCapacity(sampled.pixels.count / 3)

        for (index,pixel) in sampled.pixels.enumerated() {
            let x = Float(index % sampled.width)
                / Float(max(sampled.width - 1, 1))
            let row = index / sampled.width
            let topY = Float(row) / Float(max(sampled.height - 1, 1))
            let visionPoint = CGPoint(x:CGFloat(x), y:CGFloat(1 - topY))
            guard x >= 0.05, x <= 0.95,
                  topY >= 0.05, topY <= 0.95,
                  !exclusionRects.contains(where:{ $0.contains(visionPoint) })
            else { continue }

            let maximum = max(pixel.r, pixel.g, pixel.b)
            let minimum = min(pixel.r, pixel.g, pixel.b)
            let saturation = maximum > 0.001
                ? (maximum - minimum) / maximum : 0
            let luminance = 0.2126 * pixel.r
                + 0.7152 * pixel.g + 0.0722 * pixel.b
            guard luminance >= 0.48,
                  luminance <= 0.995,
                  saturation <= 0.30 else { continue }
            paperPixels.append(pixel)
        }

        guard paperPixels.count >= max(sampled.pixels.count / 50, 20) else {
            return nil
        }

        // Keep the brighter part of the low-saturation background population,
        // which is less likely to contain dark text or illustrations.
        paperPixels.sort { luminance($0) > luminance($1) }
        let retainedCount = max(Int(Float(paperPixels.count) * 0.55), 20)
        let retained = paperPixels.prefix(retainedCount)
        let count = Float(max(retained.count, 1))
        let red = retained.reduce(Float.zero) { $0 + $1.r } / count
        let green = retained.reduce(Float.zero) { $0 + $1.g } / count
        let blue = retained.reduce(Float.zero) { $0 + $1.b } / count
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let saturation = maximum > 0.001
            ? (maximum - minimum) / maximum : 0
        let ratio = red / max(blue, 0.001)
        let yellowBias = labYellowBias(r:red, g:green, b:blue)
        let sampleRatio = Float(retained.count)
            / Float(max(sampled.pixels.count, 1))
        let possiblePaperColor = saturation >= 0.12
            || sampleRatio < 0.08

        let warmEvidence = max(
            (ratio - 1.06) / 0.16,
            (yellowBias - 5) / 16
        )
        let coolEvidence = max(
            (0.96 - ratio) / 0.14,
            (-yellowBias - 3) / 14
        )
        let source:DocumentLightSource
        let rawConfidence:Float
        if warmEvidence >= 0.35,
           ratio >= 1.07,
           yellowBias >= 4 {
            source = .warm
            rawConfidence = warmEvidence
        }
        else if coolEvidence >= 0.35,
                ratio <= 0.96,
                yellowBias <= -2 {
            source = .cool
            rawConfidence = coolEvidence
        }
        else if abs(ratio - 1) <= 0.07,
                abs(yellowBias) <= 7 {
            source = .neutral
            rawConfidence = 0.70
        }
        else {
            source = .uncertain
            rawConfidence = 0.35
        }
        let sampleConfidence = min(sampleRatio / 0.18, 1)
        let paperPenalty:Float = possiblePaperColor ? 0.62 : 1

        return ColorTemperatureResult(
            source:source,
            confidence:min(max(rawConfidence, 0), 1)
                * sampleConfidence * paperPenalty,
            averageRed:red,
            averageGreen:green,
            averageBlue:blue,
            redBlueRatio:ratio,
            labYellowBias:yellowBias,
            backgroundSaturation:saturation,
            validSampleRatio:sampleRatio,
            possiblePaperColor:possiblePaperColor,
            correctionApplied:false
        )
    }

    private struct Pixel {
        let r:Float
        let g:Float
        let b:Float
    }

    private struct SampledImage {
        let width:Int
        let height:Int
        let pixels:[Pixel]
    }

    private static func sampledPixels(_ image:UIImage)->SampledImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = sampleWidth
        let ratio = CGFloat(cgImage.height) / CGFloat(max(cgImage.width, 1))
        let height = max(Int((CGFloat(width) * ratio).rounded()), 1)
        var bytes = [UInt8](repeating:0, count:width * height * 4)
        guard let context = CGContext(
            data:&bytes,
            width:width,
            height:height,
            bitsPerComponent:8,
            bytesPerRow:width * 4,
            space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(cgImage, in:CGRect(x:0, y:0, width:width, height:height))
        let pixels = stride(from:0, to:bytes.count, by:4).map {
            Pixel(
                r:Float(bytes[$0]) / 255,
                g:Float(bytes[$0 + 1]) / 255,
                b:Float(bytes[$0 + 2]) / 255
            )
        }
        return SampledImage(width:width, height:height, pixels:pixels)
    }

    private static func luminance(_ pixel:Pixel)->Float {
        0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b
    }

    private static func labYellowBias(r:Float,g:Float,b:Float)->Float {
        func linear(_ value:Float)->Float {
            value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        let red = linear(r)
        let green = linear(g)
        let blue = linear(b)
        let y = red * 0.2126 + green * 0.7152 + blue * 0.0722
        let z = (red * 0.0193 + green * 0.1192 + blue * 0.9505) / 1.08883
        func lab(_ value:Float)->Float {
            value > 0.008856
                ? pow(value, 1.0 / 3.0)
                : 7.787 * value + 16.0 / 116.0
        }
        return 200 * (lab(y) - lab(z))
    }
}
