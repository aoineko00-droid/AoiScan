//
//  SmartEnhancementEvaluator.swift
//  AoiScan
//

import Foundation


struct SmartEnhancementEvaluator {
    func evaluate(
        original:OCRQualityResult,
        enhanced:OCRQualityResult,
        originalDocument:DocumentQualityScore,
        enhancedDocument:DocumentQualityScore,
        route:DocumentQualityRoute,
        whiteBalanceEvaluation:WhiteBalanceEvaluationResult? = nil
    )->SmartEnhancementDecision {
        let characterRetention = retention(
            enhanced.recognizedCharacterCount,
            relativeTo:original.recognizedCharacterCount
        )
        let coverageRetention = retention(
            enhanced.textCoverage,
            relativeTo:original.textCoverage
        )
        let confidenceGain = enhanced.weightedConfidence
            - original.weightedConfidence
        let scoreGain = enhanced.qualityScore
            - original.qualityScore
        guard enhanced.qualityLevel != .insufficientText else {
            return rejected(
                reason:"增强版本没有取得足够文字",
                confidenceGain:confidenceGain,
                characterRetention:characterRetention,
                coverageRetention:coverageRetention,
                scoreGain:scoreGain
            )
        }

        guard characterRetention >= 0.92 else {
            return rejected(
                reason:"增强版本识别文字数量下降",
                confidenceGain:confidenceGain,
                characterRetention:characterRetention,
                coverageRetention:coverageRetention,
                scoreGain:scoreGain
            )
        }

        guard coverageRetention >= 0.86 else {
            return rejected(
                reason:"增强版本文字覆盖范围下降",
                confidenceGain:confidenceGain,
                characterRetention:characterRetention,
                coverageRetention:coverageRetention,
                scoreGain:scoreGain
            )
        }

        let lowConfidenceGain = original.lowConfidenceRatio
            - enhanced.lowConfidenceRatio
        let minimumConfidenceGain:Float =
            original.qualityLevel == .poor ? 0.012 : 0.022
        let confidenceClearlyImproved = confidenceGain
            >= minimumConfidenceGain
        let combinedScoreImproved = scoreGain >= 0.025
            && confidenceGain >= -0.005
        let weakRegionsImproved = lowConfidenceGain >= 0.12
            && confidenceGain >= 0.008
        let recognitionPreserved = characterRetention >= 0.97
            && coverageRetention >= 0.90
            && confidenceGain >= -0.012
            && enhanced.lowConfidenceRatio
                <= original.lowConfidenceRatio + 0.03
        let targetImproved = problemSpecificImprovement(
            route:route,
            original:originalDocument,
            enhanced:enhancedDocument,
            whiteBalanceEvaluation:whiteBalanceEvaluation
        )
        let visualSafetyPassed = problemNotWorse(
            route:route,
            original:originalDocument,
            enhanced:enhancedDocument,
            whiteBalanceEvaluation:whiteBalanceEvaluation
        )
            && enhancedDocument.visual.haloPenalty
                <= originalDocument.visual.haloPenalty + 0.025
            && enhancedDocument.visual.noisePenalty
                <= originalDocument.visual.noisePenalty + 0.025
            && enhancedDocument.visual.backgroundBrightness
                >= originalDocument.visual.backgroundBrightness - 0.015
            && confidenceGain >= -0.002

        guard visualSafetyPassed else {
            return rejected(
                reason:"定向恢复引入了亮度、阴影或文字结构副作用",
                confidenceGain:confidenceGain,
                characterRetention:characterRetention,
                coverageRetention:coverageRetention,
                scoreGain:scoreGain
            )
        }

        guard targetImproved,
              recognitionPreserved
                || confidenceClearlyImproved
                || combinedScoreImproved
                || weakRegionsImproved else {
            return rejected(
                reason:"增强版本没有达到替换门槛",
                confidenceGain:confidenceGain,
                characterRetention:characterRetention,
                coverageRetention:coverageRetention,
                scoreGain:scoreGain
            )
        }

        return SmartEnhancementDecision(
            selectedVariant:.textAware,
            shouldReplaceImage:true,
            reason:targetImproved
                && !confidenceClearlyImproved
                && !combinedScoreImproved
                && !weakRegionsImproved
                ? "识别保持稳定且文档视觉质量提高"
                : "内容感知增强提高了文字识别质量",
            confidenceGain:confidenceGain,
            characterRetention:characterRetention,
            coverageRetention:coverageRetention,
            scoreGain:scoreGain
        )
    }

    private func problemNotWorse(
        route:DocumentQualityRoute,
        original:DocumentQualityScore,
        enhanced:DocumentQualityScore,
        whiteBalanceEvaluation:WhiteBalanceEvaluationResult?
    )->Bool {
        switch route.primaryIssue {
        case .regionalSharpness:
            return clarity(route.affectedRegion, in:enhanced.visual)
                >= clarity(route.affectedRegion, in:original.visual) - 0.005
        case .lighting, .background:
            return enhanced.visual.illuminationGradient
                    <= original.visual.illuminationGradient + 0.005
                && enhanced.visual.shadowSeverity
                    <= original.visual.shadowSeverity + 0.015
                && enhanced.visual.textStructureScore
                    >= original.visual.textStructureScore - 0.010
        case .colorTemperature:
            return whiteBalanceEvaluation?.accepted == true
                && enhanced.visual.backgroundUniformity
                    >= original.visual.backgroundUniformity - 0.008
                && enhanced.visual.shadowSeverity
                    <= original.visual.shadowSeverity + 0.012
                && enhanced.visual.textStructureScore
                    >= original.visual.textStructureScore - 0.015
        case .none, .perspective:
            return false
        }
    }

    private func problemSpecificImprovement(
        route:DocumentQualityRoute,
        original:DocumentQualityScore,
        enhanced:DocumentQualityScore,
        whiteBalanceEvaluation:WhiteBalanceEvaluationResult?
    )->Bool {
        switch route.primaryIssue {
        case .regionalSharpness:
            let originalRegion = clarity(
                route.affectedRegion,
                in:original.visual
            )
            let enhancedRegion = clarity(
                route.affectedRegion,
                in:enhanced.visual
            )
            return enhancedRegion >= originalRegion + 0.018
                && enhanced.visual.regionalClarityBalance
                    >= original.visual.regionalClarityBalance + 0.015
        case .lighting, .background:
            let minimumShadowReduction = max(
                0.025,
                original.visual.shadowSeverity * 0.12
            )
            let shadowImproved = original.visual.shadowSeverity >= 0.080
                && enhanced.visual.shadowSeverity
                    <= original.visual.shadowSeverity
                        - minimumShadowReduction
            return shadowImproved
                || enhanced.visual.illuminationGradient
                    <= original.visual.illuminationGradient - 0.018
                || enhanced.backgroundUniformity
                    >= original.backgroundUniformity + 0.018
        case .colorTemperature:
            return whiteBalanceEvaluation?.accepted == true
        case .none, .perspective:
            return false
        }
    }

    private func clarity(
        _ region:DocumentRegion,
        in visual:DocumentVisualQualityResult
    )->Float {
        switch region {
        case .top: return visual.topClarity
        case .middle: return visual.middleClarity
        case .bottom: return visual.bottomClarity
        case .none: return visual.textEdgeClarity
        }
    }

    func keepOriginal(reason:String)->SmartEnhancementDecision {
        rejected(
            reason:reason,
            confidenceGain:0,
            characterRetention:1,
            coverageRetention:1,
            scoreGain:0
        )
    }

    private func rejected(
        reason:String,
        confidenceGain:Float,
        characterRetention:Float,
        coverageRetention:Float,
        scoreGain:Float
    )->SmartEnhancementDecision {
        SmartEnhancementDecision(
            selectedVariant:.originalSmart,
            shouldReplaceImage:false,
            reason:reason,
            confidenceGain:confidenceGain,
            characterRetention:characterRetention,
            coverageRetention:coverageRetention,
            scoreGain:scoreGain
        )
    }

    private func retention(
        _ value:Int,
        relativeTo original:Int
    )->Float {
        guard original > 0 else {
            return value > 0 ? 1 : 0
        }
        return Float(value) / Float(original)
    }

    private func retention(
        _ value:CGFloat,
        relativeTo original:CGFloat
    )->Float {
        guard original > 0.0001 else {
            return value > 0 ? 1 : 0
        }
        return Float(value / original)
    }
}
