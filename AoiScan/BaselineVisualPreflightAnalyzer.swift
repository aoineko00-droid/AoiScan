//
//  BaselineVisualPreflightAnalyzer.swift
//  AoiScan
//

import UIKit


enum BaselineVisualPreflightDecision:String,Codable {
    case skipOCR
    case continueOCR
    case inconclusive

    var diagnosticName:String {
        switch self {
        case .skipOCR:
            return "视觉质量明确正常，跳过基准OCR"
        case .continueOCR:
            return "检测到明确视觉问题，继续基准OCR"
        case .inconclusive:
            return "视觉判断接近边界，保守继续基准OCR"
        }
    }
}


struct BaselineVisualPreflightResult:Codable {
    let decision:BaselineVisualPreflightDecision
    let reason:String
    let processingMilliseconds:Int
    let estimatedMillisecondsSaved:Int
    let pixelWidth:Int
    let pixelHeight:Int
    let topSharpness:Double
    let middleSharpness:Double
    let bottomSharpness:Double
    let averageSharpness:Double
    let sharpnessBalance:Double
    let topBrightness:Float
    let middleBrightness:Float
    let bottomBrightness:Float
    let backgroundBrightness:Float
    let backgroundUniformity:Float
    let illuminationGradient:Float
    let shadowSeverity:Float
    let smallTextRisk:SmallTextRiskResult

    var shouldSkipOCR:Bool {
        decision == .skipOCR
    }
}


enum BaselineVisualPreflightAnalyzer {
    static func analyze(
        image:UIImage,
        captureCorners:ScanCorners? = nil
    )->BaselineVisualPreflightResult {
        let startedAt = Date()
        let frame = CaptureFrameQualityAnalyzer.analyze(
            image:image,
            corners:nil
        )
        let illumination = IlluminationQualityAnalyzer.analyze(
            image:image,
            blocks:[],
            treatDarkPixelsAsPossibleInk:true
        )
        let backgroundBrightness = (
            illumination.topBrightness
                + illumination.middleBrightness
                + illumination.bottomBrightness
        ) / 3
        let smallTextRisk = SmallTextRiskAnalyzer.analyze(
            image:image,
            corners:captureCorners,
            visualQuality:frame
        )

        let dimensionsUsable = frame.pixelWidth >= 600
            && frame.pixelHeight >= 600
        let measurementsUsable = frame.averageSharpness > 0.006
            && backgroundBrightness > 0.05
            && illumination.backgroundUniformity > 0.05

        let clearProblem = illumination.gradient >= 0.075
            || illumination.shadowSeverity >= 0.18
            || illumination.backgroundUniformity < 0.66
            || backgroundBrightness < 0.76
            || frame.averageSharpness < 0.014
            || frame.sharpnessBalance < 0.24

        // These thresholds are intentionally conservative. Only a page with
        // strong agreement across light, background and regional sharpness is
        // allowed to skip OCR. Borderline samples keep the previous pipeline.
        let clearlySafe = dimensionsUsable
            && measurementsUsable
            && illumination.gradient <= 0.040
            && illumination.shadowSeverity <= 0.12
            && illumination.backgroundUniformity >= 0.74
            && backgroundBrightness >= 0.82
            && backgroundBrightness <= 0.995
            && frame.averageSharpness >= 0.018
            && frame.sharpnessBalance >= 0.35
            && !smallTextRisk.preventsVisualEarlyStop

        let decision:BaselineVisualPreflightDecision
        let reason:String
        if !dimensionsUsable || !measurementsUsable {
            decision = .inconclusive
            reason = "视觉采样不足，保守保留原有OCR质量判断"
        }
        else if smallTextRisk.preventsVisualEarlyStop {
            decision = .continueOCR
            reason = "检测到顶部小字风险，保守继续OCR质量判断"
        }
        else if clearProblem {
            decision = .continueOCR
            reason = problemReason(
                frame:frame,
                illumination:illumination,
                backgroundBrightness:backgroundBrightness
            )
        }
        else if clearlySafe {
            decision = .skipOCR
            reason = "光照、背景、曝光和区域清晰度均处于安全范围"
        }
        else {
            decision = .inconclusive
            reason = "至少一项视觉指标接近安全门槛，保守继续OCR"
        }

        let elapsed = max(
            0,
            Int(Date().timeIntervalSince(startedAt) * 1000)
        )
        return BaselineVisualPreflightResult(
            decision:decision,
            reason:reason,
            processingMilliseconds:elapsed,
            estimatedMillisecondsSaved:decision == .skipOCR
                ? estimateSavedMilliseconds(
                    pixelWidth:frame.pixelWidth,
                    pixelHeight:frame.pixelHeight
                ) : 0,
            pixelWidth:frame.pixelWidth,
            pixelHeight:frame.pixelHeight,
            topSharpness:frame.topSharpness,
            middleSharpness:frame.middleSharpness,
            bottomSharpness:frame.bottomSharpness,
            averageSharpness:frame.averageSharpness,
            sharpnessBalance:frame.sharpnessBalance,
            topBrightness:illumination.topBrightness,
            middleBrightness:illumination.middleBrightness,
            bottomBrightness:illumination.bottomBrightness,
            backgroundBrightness:backgroundBrightness,
            backgroundUniformity:illumination.backgroundUniformity,
            illuminationGradient:illumination.gradient,
            shadowSeverity:illumination.shadowSeverity,
            smallTextRisk:smallTextRisk
        )
    }

    private static func problemReason(
        frame:CaptureFrameQuality,
        illumination:IlluminationQualityResult,
        backgroundBrightness:Float
    )->String {
        if illumination.gradient >= 0.075 {
            return "检测到明显上下光照梯度，继续OCR验证恢复收益"
        }
        if illumination.shadowSeverity >= 0.18 {
            return "检测到明显阴影，继续OCR验证恢复收益"
        }
        if illumination.backgroundUniformity < 0.66 {
            return "背景均匀度明显不足，继续OCR验证恢复收益"
        }
        if backgroundBrightness < 0.76 {
            return "纸张背景明显偏暗，继续OCR验证恢复收益"
        }
        if frame.averageSharpness < 0.014 {
            return "整体清晰度明显偏低，继续OCR验证恢复收益"
        }
        return "区域清晰度差异明显，继续OCR验证恢复收益"
    }

    private static func estimateSavedMilliseconds(
        pixelWidth:Int,
        pixelHeight:Int
    )->Int {
        let megapixels = Double(pixelWidth * pixelHeight) / 1_000_000
        return min(max(Int(900 + megapixels * 420), 1_200), 9_000)
    }
}
