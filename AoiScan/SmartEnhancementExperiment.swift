//
//  SmartEnhancementExperiment.swift
//  AoiScan
//

import Foundation


enum SmartEnhancementExperiment {
    static let candidates:[EnhancementExperimentCandidate] = [
        EnhancementExperimentCandidate(
            variant:.smartColorMedium,
            parameters:.smartColorMedium
        )
    ]
    private static let whiteBalanceCandidate =
        EnhancementExperimentCandidate(
            variant:.whiteBalance,
            parameters:.baseline
        )

    static func route(
        for quality:OCRQualityResult
    )->SmartEnhancementQualityRoute {
        guard quality.qualityLevel != .insufficientText else {
            return .insufficientText
        }
        if quality.weightedConfidence >= 0.90 {
            return .excellentDirect
        }
        if quality.weightedConfidence >= 0.82,
           quality.lowConfidenceRatio <= 0.24 {
            return .normalLightOnly
        }
        return .poorProgressive
    }

    static func candidates(
        for route:DocumentQualityRoute
    )->[EnhancementExperimentCandidate] {
        switch route.primaryIssue {
        case .none, .perspective:
            return []
        case .lighting, .regionalSharpness, .background:
            return candidates
        case .colorTemperature:
            return [whiteBalanceCandidate]
        }
    }

    static func canSelect(
        quality:OCRQualityResult,
        original:OCRQualityResult,
        stability:Float,
        colorRetention:ColorRetentionResult,
        evaluatorDecision:SmartEnhancementDecision
    )->Bool {
        guard evaluatorDecision.shouldReplaceImage,
              stability >= 0.97,
              colorRetention.overallRetention >= 0.95,
              colorRetention.chromaSimilarity >= 0.95,
              colorRetention.redRetention >= 0.95,
              colorRetention.blueRetention >= 0.95 else {
            return false
        }

        let characterRetention = Float(
            quality.recognizedCharacterCount
        ) / Float(max(original.recognizedCharacterCount, 1))

        return characterRetention >= 0.98
            && quality.weightedConfidence + 0.002
                >= original.weightedConfidence
    }

    static func rankingScore(
        quality:OCRQualityResult,
        stability:Float,
        colorRetention:Float = 1,
        documentQuality:DocumentQualityScore? = nil
    )->Float {
        documentQuality?.totalScore
            ?? (quality.weightedConfidence * 0.68
                + quality.qualityScore * 0.14
                + stability * 0.10
                + colorRetention * 0.08)
    }
}
