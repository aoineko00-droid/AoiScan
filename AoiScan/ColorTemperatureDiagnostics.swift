//
//  ColorTemperatureDiagnostics.swift
//  AoiScan
//

import Foundation
import UIKit


enum ColorTemperatureDiagnostics {
    static func analyzeAndRecord(
        image:UIImage,
        blocks:[OCRBlock],
        pageNumber:Int
    ) {
        guard let result = ColorTemperatureAnalyzer.analyze(
            image:image,
            blocks:blocks
        ) else {
            record(
                message:"未取得足够纸张背景样本",
                details:L10n.format("页码 %@\n未修改扫描图片", String(pageNumber))
            )
            return
        }
        let details = [
            L10n.format("页码 %@", String(pageNumber)),
            L10n.format("判断 %@", L10n.text(result.source.diagnosticName)),
            String(format:"置信度 %.1f%%", result.confidence * 100),
            String(format:"平均 RGB %.3f / %.3f / %.3f", result.averageRed, result.averageGreen, result.averageBlue),
            String(format:"R/B %.3f", result.redBlueRatio),
            String(format:"Lab 黄色偏移 %.2f", result.labYellowBias),
            String(format:"背景饱和度 %.1f%%", result.backgroundSaturation * 100),
            String(format:"有效背景样本 %.1f%%", result.validSampleRatio * 100),
            L10n.format("可能为纸张本色 %@", result.possiblePaperColor ? "是" : "否"),
            "本次检测仅记录；是否修正由智能增强质量路由决定"
        ].joined(separator:"\n")
        record(
            message:"检测到\(L10n.text(result.source.diagnosticName))",
            details:details
        )
    }

    private static func record(message:String,details:String) {
        RecognitionLogStore.shared.add(
            category:"色温检测",
            message:message,
            details:details
        )
        DiagnosticsCollector.shared.recordEvent(
            category:L10n.text("色温检测"),
            message:L10n.text(message),
            details:details
        )
    }
}
