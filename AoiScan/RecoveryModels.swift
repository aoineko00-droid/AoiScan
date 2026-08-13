//
//  RecoveryModels.swift
//  AoiScan
//

import Foundation
import UIKit


struct CaptureCornerStability:Codable {
    let recentFrameCount:Int
    let stableFrameCount:Int
    let averageCornerJitter:CGFloat
}


enum RecoveryCandidateType:String,Codable,CaseIterable {
    case current = "A"
    case safeMargin = "B"
    case stableCorners = "C"
    case fusedCorners = "D"

    var diagnosticName:String {
        switch self {
        case .current:
            return "当前标准版本"
        case .safeMargin:
            return "安全边缘版本"
        case .stableCorners:
            return "连续帧四角版本"
        case .fusedCorners:
            return "融合四角版本"
        }
    }
}


struct RecoveryGeometryMetrics:Codable {
    let documentCoverage:CGFloat
    let topBottomWidthRatio:CGFloat
    let leftRightHeightRatio:CGFloat
    let perspectiveSeverity:CGFloat
    let outputScale:CGFloat
    let outputAspectRatio:CGFloat
    let cropMargin:CGFloat
    let cornersAreConvex:Bool
    let cornersAreInsideImage:Bool
    let edgeSafety:CGFloat
    let geometryScore:CGFloat
}


struct RegionalSharpnessMetrics:Codable {
    let top:Double
    let middle:Double
    let bottom:Double
    let balance:Double
    let average:Double
}


struct RecoveryCandidate {
    let type:RecoveryCandidateType
    let image:UIImage
    let corners:ScanCorners
    let geometry:RecoveryGeometryMetrics
    let sharpness:RegionalSharpnessMetrics
    let quickScore:Double
}


struct RecoveryTrialSummary {
    let type:RecoveryCandidateType
    let geometry:RecoveryGeometryMetrics
    let sharpness:RegionalSharpnessMetrics
    let weightedConfidence:Float?
    let recognizedCharacterCount:Int
    let characterStability:Float?
    let evaluatorAccepted:Bool
    let rejectionReason:String?
    let selected:Bool
}


struct SmartDocumentRecoveryOutput {
    let image:UIImage
    let corners:ScanCorners?
    let selectedType:RecoveryCandidateType
    let trials:[RecoveryTrialSummary]
    let processingMilliseconds:Int
    let selectionReason:String
    let enhancementSeed:SmartEnhancementSeed?
}
