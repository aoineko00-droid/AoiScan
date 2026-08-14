//
//  SmallTextRiskAnalyzer.swift
//  AoiScan
//

import UIKit
import Vision
import ImageIO
import CoreImage


enum SmallTextRiskLevel:String,Codable {
    case none
    case low
    case elevated
    case high
}


struct SmallTextRiskResult:Codable {
    let level:SmallTextRiskLevel
    let preventsVisualEarlyStop:Bool
    let reason:String
    let processingMilliseconds:Int
    let detectedTextRegionCount:Int
    let smallTextRegionCount:Int
    let topTextRegionCount:Int
    let topSmallTextRegionCount:Int
    let medianTextHeight:CGFloat
    let smallTextRatio:CGFloat
    let topConcentration:CGFloat
    let topSmallTextRatio:CGFloat
    let topSharpnessRetention:Double
    let topBottomWidthRatio:CGFloat?
}


enum SmallTextRiskAnalyzer {
    private static let maximumAnalysisEdge:CGFloat = 1_200
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    static func analyze(
        image:UIImage,
        corners:ScanCorners?,
        visualQuality:CaptureFrameQuality
    )->SmallTextRiskResult {
        let startedAt = Date()
        let observations = detectTextRegions(in:image)
        let heights = observations.map { $0.boundingBox.height }
        let medianHeight = median(heights)
        let smallHeightLimit = min(max(medianHeight * 1.12, 0.014), 0.032)
        let small = observations.filter {
            $0.boundingBox.height <= smallHeightLimit
        }
        let top = observations.filter {
            $0.boundingBox.midY >= 0.52
        }
        let topSmall = top.filter {
            $0.boundingBox.height <= smallHeightLimit
        }
        let count = observations.count
        let smallRatio = ratio(small.count, count)
        let topConcentration = ratio(top.count, count)
        let topSmallRatio = ratio(topSmall.count, max(top.count, 1))
        let lowerReference = max(
            visualQuality.middleSharpness,
            visualQuality.bottomSharpness,
            0.0001
        )
        let topRetention = visualQuality.topSharpness / lowerReference
        let widthRatio = corners.map(topBottomWidthRatio)

        let hasEnoughText = count >= 7
        let isSmallTextPage = medianHeight > 0
            && medianHeight <= 0.031
            && smallRatio >= 0.48
        let isTopConcentrated = top.count >= 4
            && topConcentration >= 0.38
            && topSmallRatio >= 0.55
        let hasTopSharpnessDeficit = topRetention < 0.84
        let hasPerspectiveRisk = (widthRatio ?? 1) < 0.86
        let highRisk = hasEnoughText
            && isSmallTextPage
            && isTopConcentrated
            && hasTopSharpnessDeficit
            && hasPerspectiveRisk
        let elevatedRisk = hasEnoughText
            && isSmallTextPage
            && isTopConcentrated
            && (hasTopSharpnessDeficit || hasPerspectiveRisk)
        let lowRisk = hasEnoughText
            && isSmallTextPage
            && (hasTopSharpnessDeficit || hasPerspectiveRisk)

        let level:SmallTextRiskLevel
        let reason:String
        if highRisk {
            level = .high
            reason = "顶部小字集中，同时存在清晰度下降和透视缩小"
        }
        else if elevatedRisk {
            level = .elevated
            reason = hasTopSharpnessDeficit
                ? "顶部小字集中且顶部清晰度低于中下部"
                : "顶部小字集中且纸张上边存在明显透视缩小"
        }
        else if lowRisk {
            level = .low
            reason = "检测到小字与局部风险，但尚未形成顶部集中风险"
        }
        else {
            level = .none
            reason = count < 7
                ? "快速检测到的文字区域不足，不据此改变早停"
                : "未检测到顶部小字集中风险"
        }

        return SmallTextRiskResult(
            level:level,
            preventsVisualEarlyStop:level == .elevated || level == .high,
            reason:reason,
            processingMilliseconds:max(
                0,
                Int(Date().timeIntervalSince(startedAt) * 1_000)
            ),
            detectedTextRegionCount:count,
            smallTextRegionCount:small.count,
            topTextRegionCount:top.count,
            topSmallTextRegionCount:topSmall.count,
            medianTextHeight:medianHeight,
            smallTextRatio:smallRatio,
            topConcentration:topConcentration,
            topSmallTextRatio:topSmallRatio,
            topSharpnessRetention:topRetention,
            topBottomWidthRatio:widthRatio
        )
    }

    private static func detectTextRegions(
        in image:UIImage
    )->[VNTextObservation] {
        guard let cgImage = analysisCGImage(image) else { return [] }
        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = false
        let handler = VNImageRequestHandler(
            cgImage:cgImage,
            orientation:.up,
            options:[:]
        )
        do {
            try handler.perform([request])
            return request.results ?? []
        }
        catch {
            return []
        }
    }

    private static func analysisCGImage(_ image:UIImage)->CGImage? {
        guard let source = CIImage(image:image) else { return image.cgImage }
        let extent = source.extent
        let longest = max(extent.width, extent.height)
        let scale = min(1, maximumAnalysisEdge / max(longest, 1))
        let normalized = source.transformed(
            by:CGAffineTransform(
                translationX:-extent.minX,
                y:-extent.minY
            )
        ).transformed(
            by:CGAffineTransform(scaleX:scale, y:scale)
        )
        return context.createCGImage(
            normalized,
            from:normalized.extent
        )
    }

    nonisolated private static func topBottomWidthRatio(
        _ corners:ScanCorners
    )->CGFloat {
        let top = hypot(
            corners.topRight.x - corners.topLeft.x,
            corners.topRight.y - corners.topLeft.y
        )
        let bottom = hypot(
            corners.bottomRight.x - corners.bottomLeft.x,
            corners.bottomRight.y - corners.bottomLeft.y
        )
        return min(top, bottom) / max(max(top, bottom), 0.0001)
    }

    private static func median(_ values:[CGFloat])->CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of:2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func ratio(_ value:Int,_ total:Int)->CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(value) / CGFloat(total)
    }

}
