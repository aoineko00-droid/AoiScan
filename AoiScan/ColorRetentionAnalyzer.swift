//
//  ColorRetentionAnalyzer.swift
//  AoiScan
//

import UIKit
import CoreGraphics


/// Fast 192px sampling used only as a color safety gate. No OCR or full-size
/// per-pixel comparison is performed here.
enum ColorRetentionAnalyzer {
    private static let sampleSize = 192

    static func analyze(
        original:UIImage,
        candidate:UIImage
    )->ColorRetentionResult {
        guard let first = pixels(original),
              let second = pixels(candidate),
              first.count == second.count else {
            return .identity
        }
        var chromaScore:Float = 0
        var saturatedScore:Float = 0
        var saturatedCount = 0
        var redScore:Float = 0
        var redCount = 0
        var blueScore:Float = 0
        var blueCount = 0

        for index in first.indices {
            let a = chroma(first[index])
            let b = chroma(second[index])
            let difference = hypot(a.u - b.u, a.v - b.v)
            let similarity = max(0, 1 - difference / 0.42)
            chromaScore += similarity

            let saturation = max(a.r, a.g, a.b) - min(a.r, a.g, a.b)
            if saturation >= 0.16 {
                saturatedCount += 1
                saturatedScore += similarity
            }
            if a.r >= a.g * 1.16 && a.r >= a.b * 1.12
                && saturation >= 0.12 {
                redCount += 1
                redScore += similarity
            }
            if a.b >= a.r * 1.10 && a.b >= a.g * 1.08
                && saturation >= 0.10 {
                blueCount += 1
                blueScore += similarity
            }
        }

        let chromaSimilarity = chromaScore / Float(max(first.count, 1))
        let saturatedRetention = saturatedCount > 0
            ? saturatedScore / Float(saturatedCount) : 1
        let redRetention = redCount > 0 ? redScore / Float(redCount) : 1
        let blueRetention = blueCount > 0 ? blueScore / Float(blueCount) : 1
        let overall = chromaSimilarity * 0.42
            + saturatedRetention * 0.28
            + redRetention * 0.18
            + blueRetention * 0.12
        return ColorRetentionResult(
            overallRetention:overall,
            chromaSimilarity:chromaSimilarity,
            saturatedColorRetention:saturatedRetention,
            redRetention:redRetention,
            blueRetention:blueRetention,
            redSampleCount:redCount,
            blueSampleCount:blueCount
        )
    }

    private struct Pixel {
        let r:Float
        let g:Float
        let b:Float
    }

    private static func pixels(_ image:UIImage)->[Pixel]? {
        guard let cgImage = image.cgImage else { return nil }
        let width = sampleSize
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
        context.interpolationQuality = .medium
        context.draw(cgImage, in:CGRect(x:0, y:0, width:width, height:height))
        return stride(from:0, to:bytes.count, by:4).map {
            Pixel(
                r:Float(bytes[$0]) / 255,
                g:Float(bytes[$0 + 1]) / 255,
                b:Float(bytes[$0 + 2]) / 255
            )
        }
    }

    private static func chroma(_ pixel:Pixel)->(
        r:Float,g:Float,b:Float,u:Float,v:Float
    ) {
        let y = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b
        return (
            pixel.r,
            pixel.g,
            pixel.b,
            pixel.b - y,
            pixel.r - y
        )
    }
}
