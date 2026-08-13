//
//  QualityRoutingModels.swift
//  AoiScan
//

import Foundation


enum DocumentQualityIssue:String,Codable {
    case none
    case lighting
    case regionalSharpness
    case perspective
    case background

    var diagnosticName:String {
        switch self {
        case .none: return "无需定向恢复"
        case .lighting: return "光照问题"
        case .regionalSharpness: return "区域清晰度问题"
        case .perspective: return "透视问题"
        case .background: return "背景不均问题"
        }
    }
}


enum DocumentRegion:String,Codable {
    case none
    case top
    case middle
    case bottom

    var diagnosticName:String {
        switch self {
        case .none: return "无"
        case .top: return "顶部"
        case .middle: return "中部"
        case .bottom: return "底部"
        }
    }
}


struct DocumentQualityRoute:Codable {
    let primaryIssue:DocumentQualityIssue
    let affectedRegion:DocumentRegion
    let severity:Float
    let reason:String

    static func none(_ reason:String)->DocumentQualityRoute {
        DocumentQualityRoute(
            primaryIssue:.none,
            affectedRegion:.none,
            severity:0,
            reason:reason
        )
    }
}
