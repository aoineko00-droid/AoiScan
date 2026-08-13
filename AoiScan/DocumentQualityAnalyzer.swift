//
//  DocumentQualityAnalyzer.swift
//  AoiScan
//

import UIKit


enum DocumentQualityAnalyzer {
    static func analyze(
        image:UIImage,
        blocks:[OCRBlock],
        ocrQuality:OCRQualityResult,
        characterStability:Float,
        colorRetention:ColorRetentionResult = .identity
    )->DocumentQualityScore {
        let illumination = IlluminationQualityAnalyzer.analyze(
            image:image,
            blocks:blocks
        )
        let structure = TextStructureQualityAnalyzer.analyze(
            image:image,
            blocks:blocks
        )
        let total = ocrQuality.weightedConfidence * 0.45
            + characterStability * 0.20
            + structure.structureScore * 0.15
            + illumination.backgroundUniformity * 0.10
            + colorRetention.overallRetention * 0.10
        let visual = DocumentVisualQualityResult(
            textEdgeClarity:structure.edgeClarity,
            backgroundUniformity:illumination.backgroundUniformity,
            backgroundBrightness:(illumination.topBrightness
                + illumination.middleBrightness
                + illumination.bottomBrightness) / 3,
            topClarity:structure.topClarity,
            middleClarity:structure.middleClarity,
            bottomClarity:structure.bottomClarity,
            regionalClarityBalance:structure.regionalBalance,
            topBrightness:illumination.topBrightness,
            middleBrightness:illumination.middleBrightness,
            bottomBrightness:illumination.bottomBrightness,
            illuminationGradient:illumination.gradient,
            shadowSeverity:illumination.shadowSeverity,
            needsIlluminationCorrection:illumination.needsCorrection,
            haloPenalty:structure.haloPenalty,
            noisePenalty:structure.noisePenalty,
            textStructureScore:structure.structureScore
        )
        return DocumentQualityScore(
            ocrConfidence:ocrQuality.weightedConfidence,
            characterStability:characterStability,
            textEdgeClarity:structure.structureScore,
            backgroundUniformity:illumination.backgroundUniformity,
            colorRetention:colorRetention.overallRetention,
            totalScore:total,
            visual:visual
        )
    }
}
