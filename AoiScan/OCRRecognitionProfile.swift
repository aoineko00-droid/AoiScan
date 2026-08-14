//
//  OCRRecognitionProfile.swift
//  AoiScan
//

import Vision


enum OCRRecognitionProfile:String {
    case userText
    case searchIndex
    case qualityEvaluation
    case recoveryComparison

    var recognitionLevel:VNRequestTextRecognitionLevel {
        .accurate
    }

    var usesLanguageCorrection:Bool {
        switch self {
        case .qualityEvaluation:
            // Quality routing only compares candidates. Language correction is
            // expensive on dense pages and is not needed for this comparison.
            return false
        case .userText, .searchIndex, .recoveryComparison:
            return true
        }
    }

    var diagnosticName:String {
        switch self {
        case .userText:
            return "用户文字识别"
        case .searchIndex:
            return "搜索索引高质量识别"
        case .qualityEvaluation:
            return "智能增强轻量质量评估"
        case .recoveryComparison:
            return "恢复候选质量比较"
        }
    }
}
