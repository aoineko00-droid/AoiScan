//
//  WhiteBalanceStructureSafetyAnalyzer.swift
//  AoiScan
//

import UIKit
import CoreGraphics

enum WhiteBalanceStructureSafetyMode:String,Codable {
    case ordinaryWhiteBalance
    case scannerWhiteCanvas
}

enum WhiteBalanceStructureSafetyProfile:String,Codable {
    case ordinary = "ordinaryWhiteBalance"
    case scannerCanvas = "scannerWhiteCanvas"
}


struct WhiteBalanceStructureSafetyResult:Codable {
    let accepted:Bool
    let reason:String
    let structureProfile:WhiteBalanceStructureSafetyProfile
    let edgeRetention:Float
    let minimumRegionalEdgeRetention:Float
    let highFrequencyChange:Float
    let meanLuminanceDelta:Float
    let firstRejectedMetric:String?
    let firstRejectedValue:Float?
    let firstRejectedThreshold:Float?
    let sampledEdgeCount:Int
    let processingMilliseconds:Int
}


enum WhiteBalanceStructureSafetyAnalyzer {
    private static let sampleWidth = 160
    private static let minimumEdgeCount = 48
    private static let ordinaryMaxEdgeGain:Float = 1.12
    private static let ordinaryMaxHighFrequencyGain:Float = 0.05
    private static let scannerWhiteMaxEdgeGainDiagnostic:Float = 1.30
    private static let scannerWhiteMaxHighFrequencyChangeDiagnostic:Float = 0.30

    static func analyze(
        baseline:UIImage,
        candidate:UIImage,
        blocks:[OCRBlock],
        mode:WhiteBalanceStructureSafetyMode = .ordinaryWhiteBalance
    )->WhiteBalanceStructureSafetyResult {
        let startedAt = Date()
        guard let baselineSample = sample(baseline),
              let candidateSample = sample(
                candidate,
                width:baselineSample.width,
                height:baselineSample.height
              ),
              !blocks.isEmpty else {
            return result(
                accepted:false,
                reason:"白平衡文字结构轻量采样失败",
                structureProfile:mode == .scannerWhiteCanvas
                    ? .scannerCanvas : .ordinary,
                edgeRetention:0,
                minimumRegionalEdgeRetention:0,
                highFrequencyChange:0,
                meanLuminanceDelta:0,
                firstRejectedMetric:"采样失败",
                firstRejectedValue:nil,
                firstRejectedThreshold:nil,
                sampledEdgeCount:0,
                startedAt:startedAt
            )
        }

        let mask = textMask(
            blocks:blocks,
            width:baselineSample.width,
            height:baselineSample.height
        )
        var baselineEdgeTotal:Float = 0
        var candidateEdgeTotal:Float = 0
        var regionBaseline = [Float](repeating:0, count:3)
        var regionCandidate = [Float](repeating:0, count:3)
        var regionCounts = [Int](repeating:0, count:3)
        var baselineStrong = 0
        var candidateStrong = 0
        var edgeCount = 0
        var luminanceDeltaTotal:Float = 0
        var detailPixelCount = 0

        for y in 1..<(baselineSample.height - 1) {
            let region = min(
                max(y * 3 / max(baselineSample.height, 1), 0),
                2
            )
            for x in 1..<(baselineSample.width - 1) {
                let index = y * baselineSample.width + x
                guard mask[index] else { continue }
                let baselineEdge = edgeMagnitude(
                    baselineSample,
                    x:x,
                    y:y
                )
                let candidateEdge = edgeMagnitude(
                    candidateSample,
                    x:x,
                    y:y
                )
                // White gaps inside an OCR rectangle are paper, not text.
                // Scanner-white intentionally changes them strongly; measure
                // luminance safety only on dark or edge-bearing detail.
                if baselineSample.values[index] < 0.82
                    || baselineEdge >= 0.035 {
                    detailPixelCount += 1
                    luminanceDeltaTotal += abs(
                        candidateSample.values[index]
                            - baselineSample.values[index]
                    )
                }
                guard baselineEdge >= 0.035 else { continue }

                edgeCount += 1
                baselineEdgeTotal += baselineEdge
                candidateEdgeTotal += candidateEdge
                regionBaseline[region] += baselineEdge
                regionCandidate[region] += candidateEdge
                regionCounts[region] += 1
                if baselineEdge >= 0.25 { baselineStrong += 1 }
                if candidateEdge >= 0.25 { candidateStrong += 1 }
            }
        }

        guard edgeCount >= minimumEdgeCount,
              baselineEdgeTotal > 0.001,
              detailPixelCount > 0 else {
            let profile:WhiteBalanceStructureSafetyProfile = mode
                == .scannerWhiteCanvas ? .scannerCanvas : .ordinary
            return result(
                accepted:false,
                reason:"白平衡文字结构有效边缘样本不足",
                structureProfile:profile,
                edgeRetention:0,
                minimumRegionalEdgeRetention:0,
                highFrequencyChange:0,
                meanLuminanceDelta:0,
                firstRejectedMetric:"有效边缘样本不足",
                firstRejectedValue:nil,
                firstRejectedThreshold:nil,
                sampledEdgeCount:edgeCount,
                startedAt:startedAt
            )
        }

        let edgeRetention = candidateEdgeTotal / baselineEdgeTotal
        let regionalRetentions: [Float] = regionCounts.indices.compactMap { index -> Float? in
            guard regionCounts[index] >= 16,
                  regionBaseline[index] > 0.001 else { return nil }
            return regionCandidate[index] / regionBaseline[index]
        }
        let minimumRegionalRetention = regionalRetentions.min()
            ?? edgeRetention
        let baselineStrongFraction = Float(baselineStrong)
            / Float(edgeCount)
        let candidateStrongFraction = Float(candidateStrong)
            / Float(edgeCount)
        let highFrequencyChange = candidateStrongFraction
            - baselineStrongFraction
        let meanLuminanceDelta = luminanceDeltaTotal
            / Float(detailPixelCount)

        let profile:WhiteBalanceStructureSafetyProfile = mode
            == .scannerWhiteCanvas
                ? .scannerCanvas : .ordinary
        let allowedEdgeRetentionLoss:Float = 0.98
        let allowedRegionalRetention:Float = 0.96
        let allowedLuminanceChange:Float = 0.06
        let disallowEdgeGain = mode == .ordinaryWhiteBalance
        let disallowHighFrequencyGrowth = mode == .ordinaryWhiteBalance
        let allowedEdgeGain = mode == .ordinaryWhiteBalance
            ? ordinaryMaxEdgeGain
            : scannerWhiteMaxEdgeGainDiagnostic
        let allowedHighFrequencyGain = mode == .ordinaryWhiteBalance
            ? ordinaryMaxHighFrequencyGain
            : scannerWhiteMaxHighFrequencyChangeDiagnostic

        let accepted:Bool
        let reason:String
        var firstRejectedMetric:String?
        var firstRejectedValue:Float?
        var firstRejectedThreshold:Float?

        if edgeRetention < allowedEdgeRetentionLoss {
            accepted = false
            reason = "白平衡候选总体文字边缘保留低于98%"
            firstRejectedMetric = "edgeRetention"
            firstRejectedValue = edgeRetention
            firstRejectedThreshold = allowedEdgeRetentionLoss
        }
        else if disallowEdgeGain
                && edgeRetention > allowedEdgeGain {
            accepted = false
            reason = "白平衡候选文字边缘异常增强"
            firstRejectedMetric = "edgeRetention"
            firstRejectedValue = edgeRetention
            firstRejectedThreshold = allowedEdgeGain
        }
        else if minimumRegionalRetention < allowedRegionalRetention {
            accepted = false
            reason = "白平衡候选存在局部文字边缘退化"
            firstRejectedMetric = "minimumRegionalEdgeRetention"
            firstRejectedValue = minimumRegionalRetention
            firstRejectedThreshold = allowedRegionalRetention
        }
        else if disallowHighFrequencyGrowth
            && highFrequencyChange > allowedHighFrequencyGain {
            accepted = false
            reason = mode == .ordinaryWhiteBalance
                ? "白平衡候选引入异常高频边缘"
                : "扫描白候选出现明显异常高频边缘"
            firstRejectedMetric = "highFrequencyChange"
            firstRejectedValue = highFrequencyChange
            firstRejectedThreshold = allowedHighFrequencyGain
        }
        else if meanLuminanceDelta > allowedLuminanceChange {
            accepted = false
            reason = "白平衡候选文字区域亮度改变过大"
            firstRejectedMetric = "meanLuminanceDelta"
            firstRejectedValue = meanLuminanceDelta
            firstRejectedThreshold = allowedLuminanceChange
        }
        else {
            accepted = true
            reason = "白平衡候选通过轻量文字结构安全检查"
        }

        return result(
            accepted:accepted,
            reason:reason,
            structureProfile:profile,
            edgeRetention:edgeRetention,
            minimumRegionalEdgeRetention:minimumRegionalRetention,
            highFrequencyChange:highFrequencyChange,
            meanLuminanceDelta:meanLuminanceDelta,
            firstRejectedMetric:firstRejectedMetric,
            firstRejectedValue:firstRejectedValue,
            firstRejectedThreshold:firstRejectedThreshold,
            sampledEdgeCount:edgeCount,
            startedAt:startedAt
        )
    }

    private static func edgeMagnitude(
        _ sample:Sample,
        x:Int,
        y:Int
    )->Float {
        let index = y * sample.width + x
        let horizontal = abs(
            sample.values[index + 1] - sample.values[index - 1]
        )
        let vertical = abs(
            sample.values[index + sample.width]
                - sample.values[index - sample.width]
        )
        return min((horizontal + vertical) * 0.5, 1)
    }

    private static func textMask(
        blocks:[OCRBlock],
        width:Int,
        height:Int
    )->[Bool] {
        var mask = [Bool](repeating:false, count:width * height)
        for block in blocks {
            let expanded = block.boundingBox.insetBy(
                dx:-max(block.boundingBox.width * 0.08, 0.003),
                dy:-max(block.boundingBox.height * 0.08, 0.002)
            ).intersection(CGRect(x:0, y:0, width:1, height:1))
            guard !expanded.isNull,
                  expanded.width > 0,
                  expanded.height > 0 else { continue }
            let minimumX = min(
                max(Int(floor(expanded.minX * CGFloat(width))), 0),
                width - 1
            )
            let maximumX = min(
                max(Int(ceil(expanded.maxX * CGFloat(width))), minimumX + 1),
                width
            )
            // OCRBlock uses Vision normalized bottom-left coordinates while
            // the sampled byte buffer is traversed from its top row.
            let minimumY = min(
                max(Int(floor((1 - expanded.maxY) * CGFloat(height))), 0),
                height - 1
            )
            let maximumY = min(
                max(
                    Int(ceil((1 - expanded.minY) * CGFloat(height))),
                    minimumY + 1
                ),
                height
            )
            for y in minimumY..<maximumY {
                let offset = y * width
                for x in minimumX..<maximumX {
                    mask[offset + x] = true
                }
            }
        }
        return mask
    }

    private struct Sample {
        let width:Int
        let height:Int
        let values:[Float]
    }

    private static func sample(_ image:UIImage)->Sample? {
        guard let cgImage = image.cgImage else { return nil }
        let ratio = CGFloat(cgImage.height)
            / CGFloat(max(cgImage.width, 1))
        let height = min(
            max(Int((CGFloat(sampleWidth) * ratio).rounded()), 48),
            320
        )
        return sample(image, width:sampleWidth, height:height)
    }

    private static func sample(
        _ image:UIImage,
        width:Int,
        height:Int
    )->Sample? {
        guard let cgImage = image.cgImage else { return nil }
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
        context.draw(
            cgImage,
            in:CGRect(x:0, y:0, width:width, height:height)
        )
        return Sample(
            width:width,
            height:height,
            values:bytes.map { Float($0) / 255 }
        )
    }

    private static func result(
        accepted:Bool,
        reason:String,
        structureProfile:WhiteBalanceStructureSafetyProfile,
        edgeRetention:Float,
        minimumRegionalEdgeRetention:Float,
        highFrequencyChange:Float,
        meanLuminanceDelta:Float,
        firstRejectedMetric:String?,
        firstRejectedValue:Float?,
        firstRejectedThreshold:Float?,
        sampledEdgeCount:Int,
        startedAt:Date
    )->WhiteBalanceStructureSafetyResult {
        WhiteBalanceStructureSafetyResult(
            accepted:accepted,
            reason:reason,
            structureProfile:structureProfile,
            edgeRetention:edgeRetention,
            minimumRegionalEdgeRetention:minimumRegionalEdgeRetention,
            highFrequencyChange:highFrequencyChange,
            meanLuminanceDelta:meanLuminanceDelta,
            firstRejectedMetric:firstRejectedMetric,
            firstRejectedValue:firstRejectedValue,
            firstRejectedThreshold:firstRejectedThreshold,
            sampledEdgeCount:sampledEdgeCount,
            processingMilliseconds:max(
                0,
                Int(Date().timeIntervalSince(startedAt) * 1000)
            )
        )
    }
}
