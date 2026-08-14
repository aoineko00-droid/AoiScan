//
//  EnhancementPreflightAnalyzer.swift
//  AoiScan
//

import UIKit


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
}


enum EnhancementPreflightAnalyzer {
    static func analyze(
        candidate:UIImage,
        blocks:[OCRBlock],
        route:DocumentQualityRoute,
        baselineQuality:DocumentQualityScore,
        colorRetention:ColorRetentionResult,
        recognizedCharacterCount:Int
    )->EnhancementPreflightResult {
        let candidateIllumination = IlluminationQualityAnalyzer.analyze(
            image:candidate,
            blocks:blocks
        )
        let candidateStructure = TextStructureQualityAnalyzer.analyze(
            image:candidate,
            blocks:blocks
        )
        let original = baselineQuality.visual
        let candidateBrightness = (
            candidateIllumination.topBrightness
                + candidateIllumination.middleBrightness
                + candidateIllumination.bottomBrightness
        ) / 3
        let backgroundGain = candidateIllumination.backgroundUniformity
            - original.backgroundUniformity
        let shadowReduction = original.shadowSeverity
            - candidateIllumination.shadowSeverity
        let gradientReduction = original.illuminationGradient
            - candidateIllumination.gradient
        let regionalGain = affectedClarity(
            candidateStructure,
            region:route.affectedRegion
        ) - affectedClarity(original, region:route.affectedRegion)
        let textStructureChange = candidateStructure.structureScore
            - original.textStructureScore
        let haloChange = candidateStructure.haloPenalty
            - original.haloPenalty
        let noiseChange = candidateStructure.noisePenalty
            - original.noisePenalty
        let brightnessChange = candidateBrightness
            - original.backgroundBrightness
        let colorSafe = colorRetention.overallRetention >= 0.97
            && colorRetention.chromaSimilarity >= 0.97
            && colorRetention.redRetention >= 0.97
            && colorRetention.blueRetention >= 0.97
        let brightnessSafe = brightnessChange >= -0.015
            && brightnessChange <= 0.065
        let structureSafe = textStructureChange >= -0.010
            && regionalGain >= -0.020
            && haloChange <= 0.015
            && noiseChange <= 0.020

        let meaningfulGain:Bool
        switch route.primaryIssue {
        case .lighting:
            meaningfulGain = gradientReduction >= 0.010
                || shadowReduction >= max(
                    0.015,
                    original.shadowSeverity * 0.14
                )
        case .background:
            meaningfulGain = backgroundGain >= 0.020
                || shadowReduction >= max(
                    0.015,
                    original.shadowSeverity * 0.14
                )
        case .regionalSharpness:
            meaningfulGain = regionalGain >= 0.050
        case .none, .perspective:
            meaningfulGain = false
        }

        let shouldRunOCR = meaningfulGain
            && colorSafe
            && brightnessSafe
            && structureSafe
        let reason:String
        if !colorSafe {
            reason = "候选颜色保持率未达到97%，OCR前早停"
        }
        else if !brightnessSafe {
            reason = "候选整体亮度变化超过安全门槛，OCR前早停"
        }
        else if !structureSafe {
            reason = "候选引入文字结构、光晕或噪声副作用，OCR前早停"
        }
        else if !meaningfulGain {
            reason = "候选未达到对应问题的最低图像改善门槛，OCR前早停"
        }
        else {
            reason = "候选通过低成本图像预检，允许执行OCR安全验证"
        }

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
                )
        )
    }

    private static func affectedClarity(
        _ quality:DocumentVisualQualityResult,
        region:DocumentRegion
    )->Float {
        switch region {
        case .top: return quality.topClarity
        case .middle: return quality.middleClarity
        case .bottom: return quality.bottomClarity
        case .none: return quality.regionalClarityBalance
        }
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

    private static func estimatedOCRMilliseconds(
        recognizedCharacterCount:Int
    )->Int {
        min(max(900 + recognizedCharacterCount * 8, 1_200), 12_000)
    }
}
