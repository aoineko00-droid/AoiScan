//
//  EnhancementPreflightAnalyzer.swift
//  AoiScan
//

import UIKit


enum EnhancementPreflightStage:String,Codable {
    case directionalPreview
    case structuralPreview
    case fullResolution
}


struct EnhancementPreflightResult:Codable {
    let shouldRunOCR:Bool
    let reason:String
    let backgroundGain:Float
    let shadowReduction:Float
    let gradientReduction:Float
    let regionalClarityGain:Float
    let textStructureChange:Float
    let haloChange:Float
    let noiseChange:Float
    let brightnessChange:Float
    let colorRetention:ColorRetentionResult
    let estimatedMillisecondsSaved:Int
    let stage:EnhancementPreflightStage
    let candidateBuildMilliseconds:Int
    let visualAnalysisMilliseconds:Int
    let colorRetentionAnalysisMilliseconds:Int
    let colorTemperatureAnalysisMilliseconds:Int
    let paperNormalizationAnalysisMilliseconds:Int?
    let currentPaperNormalizationAnalysisMilliseconds:Int?
    let illuminationAnalysisMilliseconds:Int
    let illuminationAnalysisMode:String?
    let currentIlluminationAnalysisMilliseconds:Int?
    let analysisReuseMode:String?
    let reusedAnalysisMilliseconds:Int?
    let structureAnalysisMilliseconds:Int
    let currentStructureAnalysisMilliseconds:Int?
    let whiteBalanceStructureEvaluation:
        WhiteBalanceStructureSafetyResult?
    let pixelLongEdge:Int
    let evaluatedBlockCount:Int
    let budgetExceeded:Bool

    func stopping(
        reason:String,
        budgetExceeded:Bool = false
    )->EnhancementPreflightResult {
        EnhancementPreflightResult(
            shouldRunOCR:false,
            reason:reason,
            backgroundGain:backgroundGain,
            shadowReduction:shadowReduction,
            gradientReduction:gradientReduction,
            regionalClarityGain:regionalClarityGain,
            textStructureChange:textStructureChange,
            haloChange:haloChange,
            noiseChange:noiseChange,
            brightnessChange:brightnessChange,
            colorRetention:colorRetention,
            estimatedMillisecondsSaved:estimatedMillisecondsSaved,
            stage:stage,
            candidateBuildMilliseconds:candidateBuildMilliseconds,
            visualAnalysisMilliseconds:visualAnalysisMilliseconds,
            colorRetentionAnalysisMilliseconds:
                colorRetentionAnalysisMilliseconds,
            colorTemperatureAnalysisMilliseconds:
                colorTemperatureAnalysisMilliseconds,
            paperNormalizationAnalysisMilliseconds:
                paperNormalizationAnalysisMilliseconds,
            currentPaperNormalizationAnalysisMilliseconds:
                currentPaperNormalizationAnalysisMilliseconds,
            illuminationAnalysisMilliseconds:
                illuminationAnalysisMilliseconds,
            illuminationAnalysisMode:illuminationAnalysisMode,
            currentIlluminationAnalysisMilliseconds:
                currentIlluminationAnalysisMilliseconds,
            analysisReuseMode:analysisReuseMode,
            reusedAnalysisMilliseconds:reusedAnalysisMilliseconds,
            structureAnalysisMilliseconds:structureAnalysisMilliseconds,
            currentStructureAnalysisMilliseconds:
                currentStructureAnalysisMilliseconds,
            whiteBalanceStructureEvaluation:
                whiteBalanceStructureEvaluation,
            pixelLongEdge:pixelLongEdge,
            evaluatedBlockCount:evaluatedBlockCount,
            budgetExceeded:budgetExceeded
        )
    }
}


enum EnhancementPreflightAnalyzer {
    static func analyze(
        candidate:UIImage,
        baseline:UIImage,
        blocks:[OCRBlock],
        route:DocumentQualityRoute,
        colorRetention:ColorRetentionResult,
        recognizedCharacterCount:Int,
        whiteBalanceEvaluation:WhiteBalanceEvaluationResult? = nil,
        stage:EnhancementPreflightStage,
        candidateBuildMilliseconds:Int,
        colorRetentionAnalysisMilliseconds:Int,
        colorTemperatureAnalysisMilliseconds:Int,
        paperNormalizationAnalysisMilliseconds:Int = 0,
        analysisReuseMode:String? = nil,
        reusedAnalysisMilliseconds:Int = 0,
        previousPreflight:EnhancementPreflightResult? = nil
    )->EnhancementPreflightResult {
        let illuminationStartedAt = Date()
        let directionOnlyLighting = stage == .directionalPreview
            && (route.primaryIssue == .lighting
                || route.primaryIssue == .background)
        let lightweightWhiteBalance = route.primaryIssue == .colorTemperature
        let reusesWhiteBalancePreflight = lightweightWhiteBalance
            && stage == .fullResolution
            && analysisReuseMode != nil
            && previousPreflight != nil
        let illuminationBlocks = directionOnlyLighting
            || lightweightWhiteBalance ? [] : blocks
        let baselineIllumination:IlluminationQualityResult
        let candidateIllumination:IlluminationQualityResult
        let brightnessMeasurementSucceeded:Bool
        let illuminationAnalysisMode:String
        if reusesWhiteBalancePreflight {
            baselineIllumination = neutralIllumination(brightness:0)
            candidateIllumination = neutralIllumination(brightness:0)
            brightnessMeasurementSucceeded = true
            illuminationAnalysisMode = "reusedWhiteBalanceBrightness"
        }
        else if lightweightWhiteBalance {
            let baselineBrightness = lightweightBrightness(baseline)
            let candidateBrightness = lightweightBrightness(candidate)
            baselineIllumination = neutralIllumination(
                brightness:baselineBrightness ?? 0
            )
            candidateIllumination = neutralIllumination(
                brightness:candidateBrightness ?? 0
            )
            brightnessMeasurementSucceeded = baselineBrightness != nil
                && candidateBrightness != nil
            illuminationAnalysisMode = brightnessMeasurementSucceeded
                ? "lightweightBrightness" : "lightweightBrightnessFailed"
        }
        else {
            baselineIllumination = IlluminationQualityAnalyzer.analyze(
                image:baseline,
                blocks:illuminationBlocks,
                treatDarkPixelsAsPossibleInk:directionOnlyLighting
            )
            candidateIllumination = IlluminationQualityAnalyzer.analyze(
                image:candidate,
                blocks:illuminationBlocks,
                treatDarkPixelsAsPossibleInk:directionOnlyLighting
            )
            brightnessMeasurementSucceeded = true
            illuminationAnalysisMode = directionOnlyLighting
                ? "blocklessDirectional" : "fullIllumination"
        }
        let currentIlluminationMilliseconds = reusesWhiteBalancePreflight
            ? 0 : max(
                0,
                Int(Date().timeIntervalSince(illuminationStartedAt) * 1000)
            )
        let structureStartedAt = Date()
        let shouldAnalyzeStructure = stage != .directionalPreview
            || route.primaryIssue == .regionalSharpness
        let usesWhiteBalanceStructure = shouldAnalyzeStructure
            && route.primaryIssue == .colorTemperature
        let whiteBalanceStructureEvaluation = usesWhiteBalanceStructure
            ? (reusesWhiteBalancePreflight
                ? previousPreflight?.whiteBalanceStructureEvaluation
                : WhiteBalanceStructureSafetyAnalyzer.analyze(
                    baseline:baseline,
                    candidate:candidate,
                    blocks:blocks
                )) : nil
        let baselineStructure = shouldAnalyzeStructure
            && !usesWhiteBalanceStructure
            ? TextStructureQualityAnalyzer.analyze(
                image:baseline,
                blocks:blocks
            ) : nil
        let candidateStructure = shouldAnalyzeStructure
            && !usesWhiteBalanceStructure
            ? TextStructureQualityAnalyzer.analyze(
                image:candidate,
                blocks:blocks
            ) : nil
        let backgroundGain:Float
        let shadowReduction:Float
        let gradientReduction:Float
        let brightnessChange:Float
        if route.primaryIssue == .colorTemperature,
           let paper = whiteBalanceEvaluation?
                .paperNormalizationEvaluation,
           let paperGradientReduction = paper.gradientReduction,
           let paperUniformityGain = paper.uniformityGain,
           let paperShadowReduction = paper.shadowReduction {
            backgroundGain = paperUniformityGain
            shadowReduction = paperShadowReduction
            gradientReduction = paperGradientReduction
            brightnessChange = paper.brightnessGain
        }
        else if reusesWhiteBalancePreflight,
           let previousPreflight {
            backgroundGain = previousPreflight.backgroundGain
            shadowReduction = previousPreflight.shadowReduction
            gradientReduction = previousPreflight.gradientReduction
            brightnessChange = previousPreflight.brightnessChange
        }
        else {
            let baselineBrightness = averageBrightness(baselineIllumination)
            let candidateBrightness = (
                candidateIllumination.topBrightness
                    + candidateIllumination.middleBrightness
                    + candidateIllumination.bottomBrightness
            ) / 3
            backgroundGain = candidateIllumination.backgroundUniformity
                - baselineIllumination.backgroundUniformity
            shadowReduction = baselineIllumination.shadowSeverity
                - candidateIllumination.shadowSeverity
            gradientReduction = baselineIllumination.gradient
                - candidateIllumination.gradient
            brightnessChange = candidateBrightness - baselineBrightness
        }
        let regionalGain:Float
        let textStructureChange:Float
        let haloChange:Float
        let noiseChange:Float
        if let whiteBalanceStructureEvaluation {
            regionalGain = whiteBalanceStructureEvaluation
                .minimumRegionalEdgeRetention - 1
            textStructureChange = whiteBalanceStructureEvaluation
                .edgeRetention - 1
            haloChange = max(
                whiteBalanceStructureEvaluation.highFrequencyChange,
                0
            )
            noiseChange = 0
        }
        else if let baselineStructure,
           let candidateStructure {
            regionalGain = affectedClarity(
                candidateStructure,
                region:route.affectedRegion
            ) - affectedClarity(
                baselineStructure,
                region:route.affectedRegion
            )
            textStructureChange = candidateStructure.structureScore
                - baselineStructure.structureScore
            haloChange = candidateStructure.haloPenalty
                - baselineStructure.haloPenalty
            noiseChange = candidateStructure.noisePenalty
                - baselineStructure.noisePenalty
        }
        else {
            regionalGain = 0
            textStructureChange = 0
            haloChange = 0
            noiseChange = 0
        }
        let currentStructureMilliseconds = shouldAnalyzeStructure
            && !reusesWhiteBalancePreflight
            ? max(
                0,
                Int(Date().timeIntervalSince(structureStartedAt) * 1000)
            ) : 0
        let minimumColorRetention:Float = route.primaryIssue
            == .colorTemperature ? 0.98 : 0.97
        let colorSafe = colorRetention.overallRetention
                >= minimumColorRetention
            && colorRetention.chromaSimilarity >= minimumColorRetention
            && colorRetention.redRetention >= minimumColorRetention
            && colorRetention.blueRetention >= minimumColorRetention
        let maximumBrightnessGain:Float = route.primaryIssue
            == .colorTemperature ? 0.20 : 0.065
        let brightnessSafe = brightnessMeasurementSucceeded
            && brightnessChange >= -0.015
            && brightnessChange <= maximumBrightnessGain
        let structureSafe:Bool
        if !shouldAnalyzeStructure {
            structureSafe = true
        }
        else if route.primaryIssue == .colorTemperature {
            // White balance uses a bounded channel matrix and a color mask.
            // Its dedicated raster-mask comparison protects text edges
            // without the per-pixel OCR rectangle scan used by the general
            // structure analyzer.
            structureSafe = whiteBalanceStructureEvaluation?.accepted
                == true
        }
        else {
            structureSafe = textStructureChange >= -0.010
                && regionalGain >= -0.020
                && haloChange <= 0.015
                && noiseChange <= 0.020
        }
        let illuminationDirectionSafe:Bool
        switch route.primaryIssue {
        case .lighting, .background:
            illuminationDirectionSafe = shadowReduction >= -0.005
                && backgroundGain >= -0.010
                && gradientReduction >= -0.005
        case .none, .regionalSharpness, .perspective, .colorTemperature:
            illuminationDirectionSafe = true
        }

        let meaningfulGain:Bool
        switch route.primaryIssue {
        case .lighting:
            meaningfulGain = gradientReduction >= 0.018
                || shadowReduction >= max(
                    0.025,
                    baselineIllumination.shadowSeverity * 0.12
                )
        case .background:
            meaningfulGain = backgroundGain >= 0.018
                || shadowReduction >= max(
                    0.025,
                    baselineIllumination.shadowSeverity * 0.12
                )
        case .regionalSharpness:
            meaningfulGain = regionalGain >= 0.050
        case .colorTemperature:
            meaningfulGain = whiteBalanceEvaluation?.accepted == true
        case .none, .perspective:
            meaningfulGain = false
        }

        let shouldRunOCR = meaningfulGain
            && illuminationDirectionSafe
            && colorSafe
            && brightnessSafe
            && structureSafe
        let reason:String
        if route.primaryIssue == .colorTemperature,
           let whiteBalanceEvaluation,
           !whiteBalanceEvaluation.accepted {
            reason = whiteBalanceEvaluation.reason
        }
        else if !illuminationDirectionSafe {
            reason = "候选使阴影、背景或光照梯度反向恶化，OCR前早停"
        }
        else if route.primaryIssue == .colorTemperature,
                !brightnessMeasurementSucceeded {
            reason = "白平衡候选轻量亮度检查失败，OCR前早停"
        }
        else if !brightnessSafe {
            reason = brightnessChange < -0.015
                ? "候选整体亮度下降超过1.5%，OCR前早停"
                : "候选整体亮度变化超过安全门槛，OCR前早停"
        }
        else if !colorSafe {
            reason = route.primaryIssue == .colorTemperature
                ? "白平衡候选颜色保持率未达98%，OCR前早停"
                : "候选相对基础智能版本的颜色保持率未达97%，OCR前早停"
        }
        else if route.primaryIssue == .colorTemperature,
                let whiteBalanceStructureEvaluation,
                !whiteBalanceStructureEvaluation.accepted {
            reason = whiteBalanceStructureEvaluation.reason
        }
        else if !structureSafe {
            reason = "候选引入文字结构、光晕或噪声副作用，OCR前早停"
        }
        else if !meaningfulGain {
            reason = "候选未达到对应问题的最低图像改善门槛，OCR前早停"
        }
        else {
            switch stage {
            case .directionalPreview:
                reason = route.primaryIssue == .colorTemperature
                    ? "白平衡候选通过一级轻量亮度与保色预检"
                    : "候选通过一级光照方向预检"
            case .structuralPreview:
                reason = "候选通过同尺寸文字结构预检"
            case .fullResolution:
                reason = "候选通过全分辨率视觉复检"
            }
        }

        let pixelWidth = candidate.cgImage?.width
            ?? Int(candidate.size.width * candidate.scale)
        let pixelHeight = candidate.cgImage?.height
            ?? Int(candidate.size.height * candidate.scale)
        let cumulativeColorRetentionMilliseconds =
            (previousPreflight?.colorRetentionAnalysisMilliseconds ?? 0)
                + colorRetentionAnalysisMilliseconds
        let cumulativeColorTemperatureMilliseconds =
            (previousPreflight?.colorTemperatureAnalysisMilliseconds ?? 0)
                + colorTemperatureAnalysisMilliseconds
        let cumulativePaperNormalizationMilliseconds =
            (previousPreflight?.paperNormalizationAnalysisMilliseconds ?? 0)
                + paperNormalizationAnalysisMilliseconds
        let cumulativeIlluminationMilliseconds =
            (previousPreflight?.illuminationAnalysisMilliseconds ?? 0)
                + currentIlluminationMilliseconds
        let cumulativeStructureMilliseconds =
            (previousPreflight?.structureAnalysisMilliseconds ?? 0)
                + currentStructureMilliseconds
        let cumulativeReusedAnalysisMilliseconds =
            (previousPreflight?.reusedAnalysisMilliseconds ?? 0)
                + reusedAnalysisMilliseconds
        let analysisMilliseconds = cumulativeColorRetentionMilliseconds
            + cumulativeColorTemperatureMilliseconds
            + cumulativePaperNormalizationMilliseconds
            + cumulativeIlluminationMilliseconds
            + cumulativeStructureMilliseconds

        return EnhancementPreflightResult(
            shouldRunOCR:shouldRunOCR,
            reason:reason,
            backgroundGain:backgroundGain,
            shadowReduction:shadowReduction,
            gradientReduction:gradientReduction,
            regionalClarityGain:regionalGain,
            textStructureChange:textStructureChange,
            haloChange:haloChange,
            noiseChange:noiseChange,
            brightnessChange:brightnessChange,
            colorRetention:colorRetention,
            estimatedMillisecondsSaved:shouldRunOCR
                ? 0 : estimatedOCRMilliseconds(
                    recognizedCharacterCount:recognizedCharacterCount
                ),
            stage:stage,
            candidateBuildMilliseconds:candidateBuildMilliseconds,
            visualAnalysisMilliseconds:analysisMilliseconds,
            colorRetentionAnalysisMilliseconds:
                cumulativeColorRetentionMilliseconds,
            colorTemperatureAnalysisMilliseconds:
                cumulativeColorTemperatureMilliseconds,
            paperNormalizationAnalysisMilliseconds:
                cumulativePaperNormalizationMilliseconds > 0
                    ? cumulativePaperNormalizationMilliseconds : nil,
            currentPaperNormalizationAnalysisMilliseconds:
                paperNormalizationAnalysisMilliseconds > 0
                    ? paperNormalizationAnalysisMilliseconds : nil,
            illuminationAnalysisMilliseconds:
                cumulativeIlluminationMilliseconds,
            illuminationAnalysisMode:illuminationAnalysisMode,
            currentIlluminationAnalysisMilliseconds:
                currentIlluminationMilliseconds,
            analysisReuseMode:analysisReuseMode
                ?? previousPreflight?.analysisReuseMode,
            reusedAnalysisMilliseconds:
                cumulativeReusedAnalysisMilliseconds > 0
                    ? cumulativeReusedAnalysisMilliseconds : nil,
            structureAnalysisMilliseconds:cumulativeStructureMilliseconds,
            currentStructureAnalysisMilliseconds:
                currentStructureMilliseconds,
            whiteBalanceStructureEvaluation:
                whiteBalanceStructureEvaluation,
            pixelLongEdge:max(pixelWidth, pixelHeight),
            evaluatedBlockCount:illuminationBlocks.count,
            budgetExceeded:false
        )
    }

    private static func affectedClarity(
        _ quality:TextStructureQualityResult,
        region:DocumentRegion
    )->Float {
        switch region {
        case .top: return quality.topClarity
        case .middle: return quality.middleClarity
        case .bottom: return quality.bottomClarity
        case .none: return quality.regionalBalance
        }
    }

    private static func averageBrightness(
        _ result:IlluminationQualityResult
    )->Float {
        (
            result.topBrightness
                + result.middleBrightness
                + result.bottomBrightness
        ) / 3
    }

    private static func neutralIllumination(
        brightness:Float
    )->IlluminationQualityResult {
        IlluminationQualityResult(
            topBrightness:brightness,
            middleBrightness:brightness,
            bottomBrightness:brightness,
            backgroundUniformity:1,
            gradient:0,
            shadowSeverity:0,
            needsCorrection:false,
            localBrightnessGrid:[Float](repeating:brightness, count:9),
            darkestLocalBrightness:brightness,
            bottomDarkestLocalBrightness:brightness,
            localBrightnessSpread:0,
            localizedShadowFraction:0
        )
    }

    private static func lightweightBrightness(_ image:UIImage)->Float? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 64
        let ratio = CGFloat(cgImage.height)
            / CGFloat(max(cgImage.width, 1))
        let height = min(
            max(Int((CGFloat(width) * ratio).rounded()), 32),
            128
        )
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
        context.interpolationQuality = .low
        context.draw(
            cgImage,
            in:CGRect(x:0, y:0, width:width, height:height)
        )
        guard !bytes.isEmpty else { return nil }
        let total = bytes.reduce(UInt64.zero) {
            $0 + UInt64($1)
        }
        return Float(total) / Float(bytes.count * 255)
    }

    private static func estimatedOCRMilliseconds(
        recognizedCharacterCount:Int
    )->Int {
        min(max(900 + recognizedCharacterCount * 8, 1_200), 12_000)
    }
}
