//
//  ColorRetentionAnalyzer.swift
//  AoiScan
//

import UIKit
import CoreGraphics


/// Shared scanner-white acceptance and sample-domain thresholds. Keeping
/// these beside the analyzer avoids turning the transient OCR diagnostic
/// model into an algorithm configuration surface.
enum ScannerWhiteColorThresholds {
    static let overallMinimum:Float = 0.975
    static let chromaMinimum:Float = 0.970
    static let saturatedColorMinimum:Float = 0.960
    static let redMinimum:Float = 0.980
    static let blueMinimum:Float = 0.985

    static let colorEvaluationMinimumSaturation:Float = 0.045
    static let colorEvaluationMinimumChromaMagnitude:Float = 0.028
}


/// Fast 192px sampling used only as a color safety gate. No OCR or full-size
/// per-pixel comparison is performed here.
enum ColorRetentionAnalyzer {
    private static let sampleSize = 192

    enum Mode:String {
        case ordinary
        case scannerWhiteCanvas
    }

    static func analyze(
        original:UIImage,
        candidate:UIImage,
        ignoringLightLowSaturationPaper:Bool = false,
        protectionMask:PaperProtectionMask? = nil,
        mode:Mode = .ordinary
    )->ColorRetentionResult {
        let samplingWidth = protectionMask?.width ?? sampleSize
        let samplingHeight = protectionMask?.height ?? {
            let ratio = candidate.cgImage
                .map { CGFloat($0.height) / CGFloat(max($0.width, 1)) }
                ?? CGFloat(candidate.size.height / max(candidate.size.width, 1))
            return max(Int((CGFloat(samplingWidth) * ratio).rounded()), 1)
        }()
        guard samplingWidth > 0,
              samplingHeight > 0,
              let first = pixels(
                  original,
                width:samplingWidth,
                height:samplingHeight
              ),
              let second = pixels(
                candidate,
                width:samplingWidth,
                height:samplingHeight
              ),
                  first.count == second.count else {
            return mode == .scannerWhiteCanvas
                ? .scanWhiteFailure
                : .identity
        }

        let scannerWhite = mode == .scannerWhiteCanvas
        // Rendering needs the expanded/feathered colorContentValues, but
        // scanner-white acceptance must use the unexpanded color core. Using
        // the render mask here reintroduces paper transitions and antialiasing
        // into the chroma denominator.
        let colorEvaluationMask = scannerWhite
            ? protectionMask?.colorEvaluationValues : nil
        let colorEvaluationSampleCount = scannerWhite
            ? (colorEvaluationMask?.reduce(0) { $0 + ($1 >= 8 ? 1 : 0 ) } ?? 0)
            : 0
        var validatedColorEvaluationMask:[UInt8] = []
        if scannerWhite {
            guard let protectionMask else {
                return scannerWhiteFailure(metric:"missingProtectionMask")
            }
            guard protectionMask.width == samplingWidth,
                  protectionMask.height == samplingHeight,
                  protectionMask.values.count == first.count,
                  protectionMask.colorMasksAligned,
                  let colorEvaluationMask,
                  colorEvaluationMask.count == first.count else {
                // Scanner-white mask mismatch must fail closed and cannot
                // fall back to an unrelated absolute denominator.
                return scannerWhiteFailure(metric:"maskMismatch")
            }
            validatedColorEvaluationMask = colorEvaluationMask
            if colorEvaluationSampleCount == 0 {
                return ColorRetentionResult(
                    overallRetention:1,
                    chromaSimilarity:1,
                    saturatedColorRetention:1,
                    redRetention:1,
                    blueRetention:1,
                    redSampleCount:0,
                    blueSampleCount:0,
                    actualChromaSampleCount:0,
                    actualColorContentSampleCount:0,
                    excludedNonColorSampleCount:0,
                    colorContentSampleRatio:0,
                    hasRealColorSamples:false,
                    severeColorLossFraction:nil,
                    severeRedLossFraction:nil,
                    severeBlueLossFraction:nil,
                    minimumRegionalColorRetention:nil,
                    nearBoundaryToleranceApplied:false,
                    firstRejectedColorMetric:nil,
                    firstRejectedColorValue:nil,
                    firstRejectedColorThreshold:nil
                )
            }
        }
        else if let protectionMask,
                protectionMask.width != samplingWidth
                    || protectionMask.height * samplingWidth != first.count
                    || protectionMask.values.count != first.count {
            // Preserve ordinary-mode behavior for all non-scanner use cases.
            return scannerWhiteFailure(metric:"maskMismatch")
        }

        var chromaScore:Float = 0
        var chromaCount = 0
        var saturatedScore:Float = 0
        var saturatedCount = 0
        var redScore:Float = 0
        var redCount = 0
        var blueScore:Float = 0
        var blueCount = 0
        var excludedNonColorSampleCount = 0
        var severeColorLossCount = 0
        var severeRedLossCount = 0
        var severeBlueLossCount = 0
        var regionalScores = [Float](repeating:0, count:9)
        var regionalCounts = [Int](repeating:0, count:9)

        for index in first.indices {
            if scannerWhite {
                guard validatedColorEvaluationMask[index] >= 8 else { continue }
            }
            else if let protectionMask,
                    protectionMask.values[index] < 8 {
                continue
            }

            let a = chroma(first[index])
            let b = chroma(second[index])
            let difference = hypot(a.u - b.u, a.v - b.v)
            let similarity = max(0, 1 - difference / 0.42)

            let saturation = max(a.r, a.g, a.b) - min(a.r, a.g, a.b)
            let luminance = 0.299 * a.r + 0.587 * a.g + 0.114 * a.b
            let isOrdinaryPaperAllowed = protectionMask == nil
                && ignoringLightLowSaturationPaper
                && luminance >= 0.55
                && saturation <= 0.13
            let isHighConfidenceColor = isHighConfidenceColorPixel(
                channelDiff:a,
                saturation:saturation,
                luminance:luminance
            )

            if !isOrdinaryPaperAllowed || scannerWhite {
                if scannerWhite && !isHighConfidenceColor {
                    excludedNonColorSampleCount += 1
                    continue
                }
                chromaCount += 1
                chromaScore += similarity
                if similarity < 0.90 { severeColorLossCount += 1 }
                let x = index % samplingWidth
                let y = index / samplingWidth
                let column = min(x * 3 / max(samplingWidth, 1), 2)
                let row = min(y * 3 / max(samplingHeight, 1), 2)
                let region = row * 3 + column
                regionalScores[region] += similarity
                regionalCounts[region] += 1
            }

            if saturation >= 0.16 {
                saturatedCount += 1
                saturatedScore += similarity
            }
            if a.r >= a.g * 1.16 && a.r >= a.b * 1.12
                && saturation >= 0.12 {
                redCount += 1
                redScore += similarity
                if similarity < 0.90 { severeRedLossCount += 1 }
            }
            if a.b >= a.r * 1.10 && a.b >= a.g * 1.08
                && saturation >= 0.10 {
                blueCount += 1
                blueScore += similarity
                if similarity < 0.90 { severeBlueLossCount += 1 }
            }
        }

        let chromaSimilarity = chromaCount > 0
            ? chromaScore / Float(chromaCount) : 1
        let saturatedRetention = saturatedCount > 0
            ? saturatedScore / Float(saturatedCount) : 1
        let redRetention = redCount > 0 ? redScore / Float(redCount) : 1
        let blueRetention = blueCount > 0 ? blueScore / Float(blueCount) : 1

        let overall = chromaSimilarity * 0.42
            + saturatedRetention * 0.28
            + redRetention * 0.18
            + blueRetention * 0.12

        let hasRealColorSamples = chromaCount > 0
        let severeColorLossFraction = chromaCount > 0
            ? Float(severeColorLossCount) / Float(chromaCount) : nil
        let severeRedLossFraction = redCount > 0
            ? Float(severeRedLossCount) / Float(redCount) : nil
        let severeBlueLossFraction = blueCount > 0
            ? Float(severeBlueLossCount) / Float(blueCount) : nil
        let regionalRetentions = regionalCounts.indices.compactMap { index in
            regionalCounts[index] >= 8
                ? regionalScores[index] / Float(regionalCounts[index])
                : nil
        }
        let minimumRegionalColorRetention = regionalRetentions.min()
        let commonScannerWhiteMetricsSafe = overall
                >= ScannerWhiteColorThresholds.overallMinimum
            && chromaSimilarity >= ScannerWhiteColorThresholds.chromaMinimum
            && saturatedRetention
                >= ScannerWhiteColorThresholds.saturatedColorMinimum
        let regionalSafety = minimumRegionalColorRetention.map { $0 >= 0.96 }
            ?? true
        let redNearBoundarySafe = scannerWhite
            && commonScannerWhiteMetricsSafe
            && blueRetention >= ScannerWhiteColorThresholds.blueMinimum
            && redCount >= 128
            && redRetention < ScannerWhiteColorThresholds.redMinimum
            && redRetention >= ScannerWhiteColorThresholds.redMinimum - 0.003
            && (severeRedLossFraction ?? 1) <= 0.005
            && regionalSafety
        let blueNearBoundarySafe = scannerWhite
            && commonScannerWhiteMetricsSafe
            && redRetention >= ScannerWhiteColorThresholds.redMinimum
            && blueCount >= 128
            && blueRetention < ScannerWhiteColorThresholds.blueMinimum
            && blueRetention >= ScannerWhiteColorThresholds.blueMinimum - 0.003
            && (severeBlueLossFraction ?? 1) <= 0.005
            && regionalSafety
        let nearBoundaryToleranceApplied = redNearBoundarySafe
            || blueNearBoundarySafe
        let firstRejectedColorMetric:String?
        let firstRejectedColorValue:Float?
        let firstRejectedColorThreshold:Float?
        if scannerWhite && overall < ScannerWhiteColorThresholds
            .overallMinimum {
            firstRejectedColorMetric = "overall"
            firstRejectedColorValue = overall
            firstRejectedColorThreshold = ScannerWhiteColorThresholds
                .overallMinimum
        }
        else if scannerWhite && chromaSimilarity
            < ScannerWhiteColorThresholds.chromaMinimum {
            firstRejectedColorMetric = "chroma"
            firstRejectedColorValue = chromaSimilarity
            firstRejectedColorThreshold = ScannerWhiteColorThresholds
                .chromaMinimum
        }
        else if scannerWhite && saturatedCount > 0
            && saturatedRetention < ScannerWhiteColorThresholds
                .saturatedColorMinimum {
            firstRejectedColorMetric = "saturatedColor"
            firstRejectedColorValue = saturatedRetention
            firstRejectedColorThreshold = ScannerWhiteColorThresholds
                .saturatedColorMinimum
        }
        else if scannerWhite && redCount > 0
            && !redNearBoundarySafe
            && redRetention < ScannerWhiteColorThresholds.redMinimum {
            firstRejectedColorMetric = "red"
            firstRejectedColorValue = redRetention
            firstRejectedColorThreshold = ScannerWhiteColorThresholds
                .redMinimum
        }
        else if scannerWhite && blueCount > 0
            && !blueNearBoundarySafe
            && blueRetention < ScannerWhiteColorThresholds.blueMinimum {
            firstRejectedColorMetric = "blue"
            firstRejectedColorValue = blueRetention
            firstRejectedColorThreshold = ScannerWhiteColorThresholds
                .blueMinimum
        }
        else {
            firstRejectedColorMetric = nil
            firstRejectedColorValue = nil
            firstRejectedColorThreshold = nil
        }

        return ColorRetentionResult(
            overallRetention:overall,
            chromaSimilarity:chromaSimilarity,
            saturatedColorRetention:saturatedRetention,
            redRetention:redRetention,
            blueRetention:blueRetention,
            redSampleCount:redCount,
            blueSampleCount:blueCount,
            actualChromaSampleCount:chromaCount,
            actualColorContentSampleCount:scannerWhite
                ? colorEvaluationSampleCount
                : 0,
            excludedNonColorSampleCount:excludedNonColorSampleCount,
            colorContentSampleRatio:scannerWhite
                ? Float(colorEvaluationSampleCount)
                    / Float(max(first.count, 1))
                : nil,
            hasRealColorSamples:hasRealColorSamples,
            severeColorLossFraction:severeColorLossFraction,
            severeRedLossFraction:severeRedLossFraction,
            severeBlueLossFraction:severeBlueLossFraction,
            minimumRegionalColorRetention:minimumRegionalColorRetention,
            nearBoundaryToleranceApplied:nearBoundaryToleranceApplied,
            firstRejectedColorMetric:firstRejectedColorMetric,
            firstRejectedColorValue:firstRejectedColorValue,
            firstRejectedColorThreshold:firstRejectedColorThreshold
        )
    }

    private struct Pixel {
        let r:Float
        let g:Float
        let b:Float
    }

    private static func pixels(
        _ image:UIImage,
        width:Int = sampleSize,
        height requestedHeight:Int? = nil
    )->[Pixel]? {
        guard let cgImage = image.cgImage else { return nil }
        let ratio = CGFloat(cgImage.height) / CGFloat(max(cgImage.width, 1))
        let height = requestedHeight
            ?? max(Int((CGFloat(width) * ratio).rounded()), 1)
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

    private static func isHighConfidenceColorPixel(
        channelDiff pixel:(r:Float,g:Float,b:Float,u:Float,v:Float),
        saturation:Float,
        luminance:Float
    )->Bool {
        let chromaMagnitude = hypot(pixel.u, pixel.v)
        guard chromaMagnitude >= ScannerWhiteColorThresholds
            .colorEvaluationMinimumChromaMagnitude,
              saturation >= ScannerWhiteColorThresholds
            .colorEvaluationMinimumSaturation else {
            return false
        }
        // Keep a small warm-paper margin so very bright neutral transitions from
        // feathering and anti-aliased glyph edges are excluded.
        if luminance > 0.87 && saturation < 0.065 {
            return false
        }
        return true
    }

    private static func scannerWhiteFailure(
        metric:String
    )->ColorRetentionResult {
        ColorRetentionResult(
            overallRetention:0,
            chromaSimilarity:0,
            saturatedColorRetention:0,
            redRetention:0,
            blueRetention:0,
            redSampleCount:0,
            blueSampleCount:0,
            actualChromaSampleCount:0,
            actualColorContentSampleCount:0,
            excludedNonColorSampleCount:0,
            colorContentSampleRatio:nil,
            hasRealColorSamples:false,
            severeColorLossFraction:nil,
            severeRedLossFraction:nil,
            severeBlueLossFraction:nil,
            minimumRegionalColorRetention:nil,
            nearBoundaryToleranceApplied:false,
            firstRejectedColorMetric:metric,
            firstRejectedColorValue:nil,
            firstRejectedColorThreshold:nil
        )
    }
}
