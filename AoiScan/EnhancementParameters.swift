//
//  EnhancementParameters.swift
//  AoiScan
//

import Foundation
import CoreGraphics


enum EnhancementExperimentVariant:String,Codable,CaseIterable {
    case baseline = "A"
    case smartColorMedium = "B"
    case smartColorStrong = "C"

    var diagnosticName:String {
        switch self {
        case .baseline:
            return "原始智能版本"
        case .smartColorMedium:
            return "问题定向恢复"
        case .smartColorStrong:
            return "光照均衡与文字保护"
        }
    }
}


struct EnhancementParameters:Codable,Equatable {
    let contrast:CGFloat
    let brightness:CGFloat
    let sharpen:CGFloat
    let unsharpRadius:CGFloat
    let unsharpIntensity:CGFloat
    let denoiseNoiseLevel:CGFloat
    let denoiseSharpness:CGFloat
    let threshold:CGFloat?
    let luminanceGamma:CGFloat
    let localNormalization:CGFloat
    let textInkStrength:CGFloat
    let colorProtection:CGFloat

    static let baseline = EnhancementParameters(
        contrast:1,
        brightness:0,
        sharpen:0,
        unsharpRadius:0,
        unsharpIntensity:0,
        denoiseNoiseLevel:0,
        denoiseSharpness:0,
        threshold:nil,
        luminanceGamma:1,
        localNormalization:0,
        textInkStrength:0,
        colorProtection:1
    )

    static let smartColorMedium = EnhancementParameters(
        contrast:1,
        brightness:0,
        sharpen:0,
        unsharpRadius:0,
        unsharpIntensity:0,
        denoiseNoiseLevel:0,
        denoiseSharpness:0,
        threshold:nil,
        luminanceGamma:1,
        localNormalization:0.045,
        textInkStrength:0,
        colorProtection:1
    )

    static let smartColorStrong = EnhancementParameters(
        contrast:1,
        brightness:0,
        sharpen:0,
        unsharpRadius:0,
        unsharpIntensity:0,
        denoiseNoiseLevel:0,
        denoiseSharpness:0,
        threshold:nil,
        luminanceGamma:1,
        localNormalization:0.12,
        textInkStrength:0.10,
        colorProtection:1
    )
}


struct EnhancementExperimentCandidate {
    let variant:EnhancementExperimentVariant
    let parameters:EnhancementParameters
}


struct EnhancementTrialSummary:Codable {
    let variant:EnhancementExperimentVariant
    let parameters:EnhancementParameters
    let weightedConfidence:Float?
    let recognizedCharacterCount:Int
    let characterStability:Float
    let textCoverage:CGFloat
    let processingMilliseconds:Int
    let evaluatorAccepted:Bool
    let colorRetention:ColorRetentionResult?
    let documentQuality:DocumentQualityScore?
    let reusedBaselineOCR:Bool
    let preflight:EnhancementPreflightResult?
    let secondOCRPerformed:Bool
    var selected:Bool
}
