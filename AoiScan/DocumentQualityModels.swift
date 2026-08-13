//
//  DocumentQualityModels.swift
//  AoiScan
//

import Foundation


struct DocumentVisualQualityResult:Codable {
    let textEdgeClarity:Float
    let backgroundUniformity:Float
    let backgroundBrightness:Float
    let topClarity:Float
    let middleClarity:Float
    let bottomClarity:Float
    let regionalClarityBalance:Float
    let topBrightness:Float
    let middleBrightness:Float
    let bottomBrightness:Float
    let illuminationGradient:Float
    let shadowSeverity:Float
    let needsIlluminationCorrection:Bool
    let haloPenalty:Float
    let noisePenalty:Float
    let textStructureScore:Float
}


struct DocumentQualityScore:Codable {
    let ocrConfidence:Float
    let characterStability:Float
    let textEdgeClarity:Float
    let backgroundUniformity:Float
    let colorRetention:Float
    let totalScore:Float
    let visual:DocumentVisualQualityResult
}
