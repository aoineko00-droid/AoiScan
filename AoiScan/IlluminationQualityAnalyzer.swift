//
//  IlluminationQualityAnalyzer.swift
//  AoiScan
//

import UIKit
import CoreGraphics


struct IlluminationQualityResult:Codable {
    let topBrightness:Float
    let middleBrightness:Float
    let bottomBrightness:Float
    let backgroundUniformity:Float
    let gradient:Float
    let shadowSeverity:Float
    let needsCorrection:Bool
}


enum IlluminationQualityAnalyzer {
    private static let width = 256

    static func analyze(
        image:UIImage,
        blocks:[OCRBlock]
    )->IlluminationQualityResult {
        guard let sample = sample(image) else {
            return IlluminationQualityResult(
                topBrightness:0,
                middleBrightness:0,
                bottomBrightness:0,
                backgroundUniformity:0,
                gradient:0,
                shadowSeverity:0,
                needsCorrection:false
            )
        }

        var regions = [[Float](), [Float](), [Float]()]
        var background = [Float]()
        for y in 0..<sample.height {
            let normalizedY = 1 - (CGFloat(y) + 0.5)
                / CGFloat(sample.height)
            let region = min(max(Int((1 - normalizedY) * 3), 0), 2)
            for x in 0..<sample.width {
                let point = CGPoint(
                    x:(CGFloat(x) + 0.5) / CGFloat(sample.width),
                    y:normalizedY
                )
                guard !contains(point, blocks:blocks, expansion:0.22) else {
                    continue
                }
                let value = sample.values[y * sample.width + x]
                regions[region].append(value)
                background.append(value)
            }
        }

        let top = robustBrightMean(regions[0])
        let middle = robustBrightMean(regions[1])
        let bottom = robustBrightMean(regions[2])
        let gradient = max(top, middle, bottom) - min(top, middle, bottom)
        let globalMean = mean(background)
        let deviation = standardDeviation(background, mean:globalMean)
        let uniformity = max(0, min(1, 1 - deviation * 3.4))
        let darkFraction = background.isEmpty ? 0 : Float(
            background.filter { $0 < globalMean - 0.10 }.count
        ) / Float(background.count)
        let shadow = min(1, darkFraction * 1.55 + gradient * 1.35)
        // Dense text and textured paper can lower `uniformity`; that signal
        // alone must never route a page into illumination correction.
        let needs = gradient >= 0.080
            || (gradient >= 0.055 && shadow >= 0.16)
            || (uniformity < 0.72 && shadow >= 0.20)

        return IlluminationQualityResult(
            topBrightness:top,
            middleBrightness:middle,
            bottomBrightness:bottom,
            backgroundUniformity:uniformity,
            gradient:gradient,
            shadowSeverity:shadow,
            needsCorrection:needs
        )
    }

    private static func contains(
        _ point:CGPoint,
        blocks:[OCRBlock],
        expansion:CGFloat
    )->Bool {
        blocks.contains { block in
            let rect = block.boundingBox
            return rect.insetBy(
                dx:-max(rect.width * expansion, 0.004),
                dy:-max(rect.height * expansion, 0.003)
            ).contains(point)
        }
    }

    private static func robustBrightMean(_ values:[Float])->Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let start = Int(Float(sorted.count) * 0.45)
        let end = max(Int(Float(sorted.count) * 0.92), start + 1)
        return mean(Array(sorted[start..<min(end, sorted.count)]))
    }

    private static func mean(_ values:[Float])->Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    private static func standardDeviation(
        _ values:[Float],
        mean:Float
    )->Float {
        guard !values.isEmpty else { return 1 }
        return sqrt(values.reduce(Float(0)) {
            $0 + ($1 - mean) * ($1 - mean)
        } / Float(values.count))
    }

    private struct Sample {
        let width:Int
        let height:Int
        let values:[Float]
    }

    private static func sample(_ image:UIImage)->Sample? {
        guard let cgImage = image.cgImage else { return nil }
        let ratio = CGFloat(cgImage.height) / CGFloat(max(cgImage.width, 1))
        let height = max(Int((CGFloat(width) * ratio).rounded()), 3)
        var bytes = [UInt8](repeating:0, count:width * height)
        guard let context = CGContext(
            data:&bytes,
            width:width,
            height:height,
            bitsPerComponent:8,
            bytesPerRow:width,
            space:CGColorSpaceCreateDeviceGray(),
            bitmapInfo:CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in:CGRect(x:0, y:0, width:width, height:height))
        return Sample(
            width:width,
            height:height,
            values:bytes.map { Float($0) / 255 }
        )
    }
}
