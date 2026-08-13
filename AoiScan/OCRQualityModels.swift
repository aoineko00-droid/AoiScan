//
//  OCRQualityModels.swift
//  AoiScan
//

import Foundation
import CoreGraphics
import UIKit


enum OCRQualityLevel:String,Codable {
    case excellent
    case normal
    case poor
    case insufficientText
}


struct OCRQualityResult:Codable {
    let averageConfidence:Float
    let weightedConfidence:Float
    let lowConfidenceBlocks:[OCRBlock]
    let lowConfidenceRatio:Float
    let recognizedBlockCount:Int
    let recognizedCharacterCount:Int
    let textCoverage:CGFloat
    let qualityScore:Float
    let qualityLevel:OCRQualityLevel
}


enum SmartEnhancementVariant:String,Codable {
    case originalSmart
    case textAware
}


enum SmartEnhancementQualityRoute:String,Codable {
    case excellentDirect
    case normalLightOnly
    case poorProgressive
    case insufficientText

    var diagnosticName:String {
        switch self {
        case .excellentDirect:
            return "优秀质量直接输出"
        case .normalLightOnly:
            return "正常质量按需测试光照均衡"
        case .poorProgressive:
            return "较低质量按需光照与文字测试"
        case .insufficientText:
            return "文字不足保留基础版本"
        }
    }
}


struct SmartEnhancementDecision:Codable {
    let selectedVariant:SmartEnhancementVariant
    let shouldReplaceImage:Bool
    let reason:String
    let confidenceGain:Float
    let characterRetention:Float
    let coverageRetention:Float
    let scoreGain:Float
}


struct SmartEnhancementOutput {
    let image:UIImage
    let ocrResult:OCRPageResult?
    let originalQuality:OCRQualityResult?
    let enhancedQuality:OCRQualityResult?
    let decision:SmartEnhancementDecision
    let selectedExperimentVariant:EnhancementExperimentVariant
    let trialSummaries:[EnhancementTrialSummary]
    let processingMilliseconds:Int
    let qualityRoute:SmartEnhancementQualityRoute
    let earlyStopReason:String?
    let executedCandidateCount:Int
    let skippedCandidateCount:Int
    let documentQualityRoute:DocumentQualityRoute
}


/// Transient OCR produced for the exact adjusted page used by smart mode.
/// It is never persisted and must be discarded after crop/rotation changes.
struct SmartEnhancementSeed {
    let ocrResult:OCRPageResult
    let quality:OCRQualityResult
    let sourcePixelWidth:Int
    let sourcePixelHeight:Int

    func isCompatible(with image:UIImage)->Bool {
        let width = image.cgImage?.width
            ?? Int(image.size.width * image.scale)
        let height = image.cgImage?.height
            ?? Int(image.size.height * image.scale)
        return width == sourcePixelWidth && height == sourcePixelHeight
    }
}


struct ColorRetentionResult:Codable {
    let overallRetention:Float
    let chromaSimilarity:Float
    let saturatedColorRetention:Float
    let redRetention:Float
    let blueRetention:Float
    let redSampleCount:Int
    let blueSampleCount:Int

    static let identity = ColorRetentionResult(
        overallRetention:1,
        chromaSimilarity:1,
        saturatedColorRetention:1,
        redRetention:1,
        blueRetention:1,
        redSampleCount:0,
        blueSampleCount:0
    )
}
