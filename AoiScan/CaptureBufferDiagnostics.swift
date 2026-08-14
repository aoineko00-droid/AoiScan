//
//  CaptureBufferDiagnostics.swift
//  AoiScan
//

import Foundation


enum CaptureBufferDiagnostics {
    static func record(
        result:BestFrameSelectionResult,
        pageNumber:Int
    ) {
        var lines = [
            L10n.format("页码 %@", String(pageNumber)),
            L10n.format("缓存帧 %@ 个", String(result.candidates.count)),
            L10n.format("选中来源 %@", sourceName(result.source)),
            L10n.format("选择耗时 %@ms", String(result.processingMilliseconds)),
            L10n.format("比较状态 %@", stateName(result.comparisonState)),
            L10n.format("原因 %@", L10n.text(result.reason))
        ]
        if let formalQuality = result.formalQuality {
            lines.append(qualityLine("正式照片", formalQuality))
        }
        else {
            lines.append(
                "[\(L10n.text("正式照片"))]，size=\(result.formalPixelWidth)x\(result.formalPixelHeight)，quality=未执行（已安全早停）"
            )
        }
        for (index,frame) in result.candidates.enumerated() {
            lines.append(
                qualityLine("缓存帧\(index + 1)", frame.quality)
                    + "，memory=\(megabytes(frame.pixelFrame.storageBytes))MB"
                    + "，fallback=\(frame.pixelFrame.usedFallbackResolution ? "是" : "否")"
            )
        }
        let details = lines.joined(separator:"\n")
        let message = result.source == .formalPhoto
            ? "Best Frame 保留正式照片"
            : "Best Frame 采用缓存帧"
        RecognitionLogStore.shared.add(
            category:"Capture Buffer",
            message:message,
            details:details
        )
        DiagnosticsCollector.shared.recordEvent(
            category:"Capture Buffer",
            message:L10n.text(message),
            details:details
        )
    }

    private static func qualityLine(
        _ name:String,
        _ quality:CaptureFrameQuality
    )->String {
        [
            "[\(L10n.text(name))]",
            "size=\(quality.pixelWidth)x\(quality.pixelHeight)",
            "top=\(decimal(quality.topSharpness))",
            "middle=\(decimal(quality.middleSharpness))",
            "bottom=\(decimal(quality.bottomSharpness))",
            "average=\(decimal(quality.averageSharpness))",
            "balance=\(percent(quality.sharpnessBalance))",
            "brightness=\(percent(quality.brightness))",
            "exposure=\(percent(quality.exposureScore))",
            "coverage=\(percent(Double(quality.documentCoverage)))",
            "cornerJitter=\(quality.cornerJitter.map { decimal(Double($0)) } ?? "--")",
            "score=\(percent(quality.overallScore))"
        ].joined(separator:"，")
    }

    private static func sourceName(_ source:BestFrameSource)->String {
        switch source {
        case .formalPhoto: return L10n.text("正式照片")
        case .bufferedFrame: return L10n.text("缓存帧")
        }
    }

    private static func stateName(
        _ state:BestFrameComparisonState
    )->String {
        switch state {
        case .noBufferedFrames:
            return L10n.text("没有缓存帧")
        case .diagnosticsOnly:
            return L10n.text("高分辨率缓存仅用于诊断")
        case .skippedInsufficientResolution:
            return L10n.text("分辨率不足，质量分析前早停")
        case .skippedMissingStability:
            return L10n.text("缺少连续稳定度，质量分析前早停")
        case .skippedExposure:
            return L10n.text("曝光不合格，质量分析前早停")
        case .comparedNoImprovement:
            return L10n.text("已比较，没有安全收益")
        case .selectedBufferedFrame:
            return L10n.text("已比较并采用缓存帧")
        }
    }

    private static func percent(_ value:Double)->String {
        String(format:"%.1f%%", value * 100)
    }

    private static func decimal(_ value:Double)->String {
        String(format:"%.3f", value)
    }

    private static func megabytes(_ bytes:Int)->String {
        String(format:"%.1f", Double(bytes) / 1_048_576)
    }
}
