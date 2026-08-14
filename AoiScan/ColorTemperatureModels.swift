//
//  ColorTemperatureModels.swift
//  AoiScan
//

import Foundation


enum DocumentLightSource:String,Codable {
    case neutral
    case warm
    case cool
    case uncertain

    var diagnosticName:String {
        switch self {
        case .neutral: return "中性光"
        case .warm: return "暖光"
        case .cool: return "冷光"
        case .uncertain: return "无法确定"
        }
    }
}


struct ColorTemperatureResult:Codable {
    let source:DocumentLightSource
    let confidence:Float
    let averageRed:Float
    let averageGreen:Float
    let averageBlue:Float
    let redBlueRatio:Float
    let labYellowBias:Float
    let backgroundSaturation:Float
    let validSampleRatio:Float
    let possiblePaperColor:Bool
    let correctionApplied:Bool
}
