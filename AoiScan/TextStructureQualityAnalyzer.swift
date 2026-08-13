//
//  TextStructureQualityAnalyzer.swift
//  AoiScan
//

import UIKit
import CoreGraphics


struct TextStructureQualityResult:Codable {
    let edgeClarity:Float
    let haloPenalty:Float
    let noisePenalty:Float
    let structureScore:Float
    let topClarity:Float
    let middleClarity:Float
    let bottomClarity:Float
    let regionalBalance:Float
}


enum TextStructureQualityAnalyzer {
    private static let width = 320

    static func analyze(
        image:UIImage,
        blocks:[OCRBlock]
    )->TextStructureQualityResult {
        guard let sample = sample(image), !blocks.isEmpty else {
            return TextStructureQualityResult(
                edgeClarity:0,
                haloPenalty:0,
                noisePenalty:0,
                structureScore:0,
                topClarity:0,
                middleClarity:0,
                bottomClarity:0,
                regionalBalance:0
            )
        }
        var edges = [Float]()
        var regions = [[Float](), [Float](), [Float]()]
        var veryStrong = 0
        var signChanges = 0
        var textPixels = 0

        for y in 1..<(sample.height - 1) {
            let normalizedY = 1 - (CGFloat(y) + 0.5)
                / CGFloat(sample.height)
            let region = min(max(Int((1 - normalizedY) * 3), 0), 2)
            for x in 2..<(sample.width - 2) {
                let point = CGPoint(
                    x:(CGFloat(x) + 0.5) / CGFloat(sample.width),
                    y:normalizedY
                )
                guard contains(point, blocks:blocks, expansion:0.08) else {
                    continue
                }
                textPixels += 1
                let index = y * sample.width + x
                let horizontal = abs(
                    sample.values[index + 1] - sample.values[index - 1]
                )
                let vertical = abs(
                    sample.values[index + sample.width]
                        - sample.values[index - sample.width]
                )
                let edge = min((horizontal + vertical) * 1.35, 1)
                if edge > 0.045 {
                    edges.append(edge)
                    regions[region].append(edge)
                }
                if edge > 0.72 { veryStrong += 1 }
                let left = sample.values[index] - sample.values[index - 1]
                let right = sample.values[index + 1] - sample.values[index]
                if abs(left) > 0.12,
                   abs(right) > 0.12,
                   left * right < 0 {
                    signChanges += 1
                }
            }
        }

        let clarity = percentileMean(edges, lower:0.45, upper:0.82)
        let top = percentileMean(regions[0], lower:0.45, upper:0.82)
        let middle = percentileMean(regions[1], lower:0.45, upper:0.82)
        let bottom = percentileMean(regions[2], lower:0.45, upper:0.82)
        let nonzero = [top, middle, bottom].filter { $0 > 0.001 }
        let balance = (nonzero.min() ?? 0) / max(nonzero.max() ?? 1, 0.001)
        let edgeCount = max(edges.count, 1)
        let strongFraction = Float(veryStrong) / Float(edgeCount)
        let oscillationFraction = Float(signChanges) / Float(max(textPixels, 1))
        let halo = min(max((strongFraction - 0.28) / 0.52, 0), 1)
        let noise = min(max((oscillationFraction - 0.025) / 0.16, 0), 1)
        let structure = max(0, min(1, clarity * 1.30
            + balance * 0.30 - halo * 0.12 - noise * 0.10))
        return TextStructureQualityResult(
            edgeClarity:clarity,
            haloPenalty:halo,
            noisePenalty:noise,
            structureScore:structure,
            topClarity:top,
            middleClarity:middle,
            bottomClarity:bottom,
            regionalBalance:balance
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
                dx:-max(rect.width * expansion, 0.003),
                dy:-max(rect.height * expansion, 0.002)
            ).contains(point)
        }
    }

    private static func percentileMean(
        _ values:[Float],
        lower:Float,
        upper:Float
    )->Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let start = min(Int(Float(sorted.count) * lower), sorted.count - 1)
        let end = max(min(Int(Float(sorted.count) * upper), sorted.count), start + 1)
        let slice = sorted[start..<end]
        return slice.reduce(0, +) / Float(slice.count)
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
