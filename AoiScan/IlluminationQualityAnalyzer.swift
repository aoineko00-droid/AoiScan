//
//  IlluminationQualityAnalyzer.swift
//  AoiScan
//

import UIKit
import CoreGraphics


/// Fixed 8-bit luminance statistics without allocating and sorting a pixel
/// array for every region. The source sampler is already 8-bit, so histogram
/// quantiles preserve its effective precision while making analysis linear.
struct DocumentLuminanceHistogram {
    private var bins = [Int](repeating:0, count:256)
    private(set) var count = 0

    mutating func add(_ value:UInt8) {
        bins[Int(value)] += 1
        count += 1
    }

    func mean(
        lowerQuantile:Float = 0,
        upperQuantile:Float = 1
    )->Float {
        let lower = min(max(lowerQuantile, 0), 1)
        let upper = min(max(upperQuantile, lower), 1)
        guard count > 0 else { return 0 }
        let start = min(Int(Float(count) * lower), count - 1)
        let end = min(
            max(Int(Float(count) * upper), start + 1),
            count
        )
        let values = moments(startRank:start, endRank:end)
        guard values.count > 0 else { return 0 }
        return Float(values.sum / Double(values.count * 255))
    }

    func statistics(
        discardingLowerFraction:Float = 0
    )->(mean:Float,standardDeviation:Float) {
        guard count > 0 else { return (0, 1) }
        let fraction = min(max(discardingLowerFraction, 0), 0.99)
        let start = min(Int(Float(count) * fraction), count - 1)
        let values = moments(startRank:start, endRank:count)
        guard values.count > 0 else { return (0, 1) }
        let byteMean = values.sum / Double(values.count)
        let variance = max(
            values.sumOfSquares / Double(values.count)
                - byteMean * byteMean,
            0
        )
        return (
            Float(byteMean / 255),
            Float(sqrt(variance) / 255)
        )
    }

    func fraction(below normalizedThreshold:Float)->Float {
        guard count > 0 else { return 0 }
        let threshold = min(max(normalizedThreshold, 0), 1)
        var matching = 0
        for value in bins.indices
        where Float(value) / 255 < threshold {
            matching += bins[value]
        }
        return Float(matching) / Float(count)
    }

    func fraction(
        from lowerThreshold:Float,
        to upperThreshold:Float
    )->Float {
        guard count > 0 else { return 0 }
        let lower = min(max(lowerThreshold, 0), 1)
        let upper = min(max(upperThreshold, lower), 1)
        return max(fraction(below:upper) - fraction(below:lower), 0)
    }

    private func moments(
        startRank:Int,
        endRank:Int
    )->(count:Int,sum:Double,sumOfSquares:Double) {
        guard startRank < endRank else { return (0, 0, 0) }
        var cursor = 0
        var includedCount = 0
        var sum:Double = 0
        var sumOfSquares:Double = 0

        for value in bins.indices {
            let binCount = bins[value]
            guard binCount > 0 else { continue }
            let binStart = cursor
            let binEnd = cursor + binCount
            cursor = binEnd
            let overlap = max(
                min(binEnd, endRank) - max(binStart, startRank),
                0
            )
            guard overlap > 0 else { continue }
            let numericValue = Double(value)
            includedCount += overlap
            sum += numericValue * Double(overlap)
            sumOfSquares += numericValue * numericValue * Double(overlap)
            if cursor >= endRank { break }
        }
        return (includedCount, sum, sumOfSquares)
    }
}


struct IlluminationQualityResult:Codable {
    let topBrightness:Float
    let middleBrightness:Float
    let bottomBrightness:Float
    let backgroundUniformity:Float
    let gradient:Float
    let shadowSeverity:Float
    let needsCorrection:Bool
    /// Row-major 3x3 robust paper brightness. Keeping the grid makes a dark
    /// lower corner visible even when the rest of the bottom third is white.
    let localBrightnessGrid:[Float]
    let darkestLocalBrightness:Float
    let bottomDarkestLocalBrightness:Float
    let localBrightnessSpread:Float
    /// Largest share of mid-tone paper-shadow pixels in any grid cell. Very
    /// dark pixels are excluded so dense black text does not dominate it.
    let localizedShadowFraction:Float
}


enum IlluminationQualityAnalyzer {
    private static let width = 256

    static func analyze(
        image:UIImage,
        blocks:[OCRBlock],
        treatDarkPixelsAsPossibleInk:Bool = false
    )->IlluminationQualityResult {
        guard let sample = sample(image) else {
            return IlluminationQualityResult(
                topBrightness:0,
                middleBrightness:0,
                bottomBrightness:0,
                backgroundUniformity:0,
                gradient:0,
                shadowSeverity:0,
                needsCorrection:false,
                localBrightnessGrid:[Float](repeating:0, count:9),
                darkestLocalBrightness:0,
                bottomDarkestLocalBrightness:0,
                localBrightnessSpread:0,
                localizedShadowFraction:0
            )
        }

        var regions = [
            DocumentLuminanceHistogram(),
            DocumentLuminanceHistogram(),
            DocumentLuminanceHistogram()
        ]
        var fallbackRegions = [
            DocumentLuminanceHistogram(),
            DocumentLuminanceHistogram(),
            DocumentLuminanceHistogram()
        ]
        var localRegions = [DocumentLuminanceHistogram](
            repeating:DocumentLuminanceHistogram(),
            count:9
        )
        var fallbackLocalRegions = [DocumentLuminanceHistogram](
            repeating:DocumentLuminanceHistogram(),
            count:9
        )
        var background = DocumentLuminanceHistogram()
        let exclusionMask = NormalizedRectangleRasterizer.exclusionMask(
            width:sample.width,
            height:sample.height,
            rectangles:blocks.map(\.boundingBox),
            expansion:0.22
        )
        for y in 0..<sample.height {
            let normalizedY = 1 - (CGFloat(y) + 0.5)
                / CGFloat(sample.height)
            let region = min(max(Int((1 - normalizedY) * 3), 0), 2)
            for x in 0..<sample.width {
                let index = y * sample.width + x
                let value = sample.values[index]
                let gridColumn = min(x * 3 / max(sample.width, 1), 2)
                let gridIndex = region * 3 + gridColumn
                fallbackRegions[region].add(value)
                fallbackLocalRegions[gridIndex].add(value)
                guard exclusionMask[index] == 0 else {
                    continue
                }
                regions[region].add(value)
                localRegions[gridIndex].add(value)
                background.add(value)
            }
        }

        // A dense page can cover nearly an entire third with OCR rectangles.
        // Keep the spatial measurement usable by falling back to the bright
        // tail of that region instead of reporting a false zero brightness.
        let minimumRegionSamples = max(
            sample.width * sample.height / 120,
            64
        )
        var usedFallback = [Bool](repeating:false, count:regions.count)
        for index in regions.indices
        where regions[index].count < minimumRegionSamples {
            regions[index] = fallbackRegions[index]
            usedFallback[index] = true
        }
        let minimumLocalSamples = max(
            sample.width * sample.height / 420,
            32
        )
        var usedLocalFallback = [Bool](
            repeating:false,
            count:localRegions.count
        )
        for index in localRegions.indices
        where localRegions[index].count < minimumLocalSamples {
            localRegions[index] = fallbackLocalRegions[index]
            usedLocalFallback[index] = true
        }

        func paperBrightness(
            _ histogram:DocumentLuminanceHistogram,
            fallback:Bool
        )->Float {
            histogram.mean(
                lowerQuantile:fallback ? 0.62 : 0.45,
                upperQuantile:fallback ? 0.95 : 0.92
            )
        }
        let top = paperBrightness(
            regions[0],
            fallback:usedFallback[0]
        )
        let middle = paperBrightness(
            regions[1],
            fallback:usedFallback[1]
        )
        let bottom = paperBrightness(
            regions[2],
            fallback:usedFallback[2]
        )
        let localBrightness = localRegions.indices.map { index in
            paperBrightness(
                localRegions[index],
                fallback:usedLocalFallback[index]
            )
        }
        let darkestLocal = localBrightness.min() ?? min(top, middle, bottom)
        let brightestLocal = localBrightness.max() ?? max(top, middle, bottom)
        let bottomDarkestLocal = localBrightness.count >= 9
            ? localBrightness[6...8].min() ?? bottom
            : bottom
        let localizedShadowFractions:[Float] = localRegions.indices.map {
            index in
            let reference = localBrightness[index]
            let upper = min(max(reference - 0.075, 0.70), 0.91)
            let midToneFraction = localRegions[index].fraction(
                from:0.56,
                to:upper
            )
            let possiblePaperFraction = max(
                1 - localRegions[index].fraction(below:0.56),
                0.01
            )
            return min(midToneFraction / possiblePaperFraction, Float(1))
        }
        let localizedShadowFraction = localizedShadowFractions.max() ?? 0
        let gradient = max(top, middle, bottom) - min(top, middle, bottom)
        // Before OCR there is no text mask. Discard the darkest portion for
        // background statistics so dense ink is not treated as paper shadow.
        let statistics = background.statistics(
            discardingLowerFraction:treatDarkPixelsAsPossibleInk ? 0.22 : 0
        )
        let globalMean = statistics.mean
        let deviation = statistics.standardDeviation
        let uniformity = max(0, min(1, 1 - deviation * 3.4))
        let rawDarkFraction = background.fraction(
            below:globalMean - 0.10
        )
        let darkFraction = treatDarkPixelsAsPossibleInk
            ? max(rawDarkFraction - 0.16, 0) / 0.84
            : rawDarkFraction
        let shadow = min(1, darkFraction * 1.55 + gradient * 1.35)
        let localizedShadow = shadow >= 0.095
            && uniformity <= 0.88
        // Dense text and textured paper can lower `uniformity`; that signal
        // alone must never route a page into illumination correction. A
        // localized shadow may have very little top-to-bottom gradient, so it
        // is allowed through only when dark-area and uniformity evidence agree.
        let needs = gradient >= 0.080
            || (gradient >= 0.050 && shadow >= 0.12)
            || localizedShadow
            || (uniformity < 0.72 && shadow >= 0.16)

        return IlluminationQualityResult(
            topBrightness:top,
            middleBrightness:middle,
            bottomBrightness:bottom,
            backgroundUniformity:uniformity,
            gradient:gradient,
            shadowSeverity:shadow,
            needsCorrection:needs,
            localBrightnessGrid:localBrightness,
            darkestLocalBrightness:darkestLocal,
            bottomDarkestLocalBrightness:bottomDarkestLocal,
            localBrightnessSpread:brightestLocal - darkestLocal,
            localizedShadowFraction:localizedShadowFraction
        )
    }

    private struct Sample {
        let width:Int
        let height:Int
        let values:[UInt8]
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
            values:bytes
        )
    }
}
