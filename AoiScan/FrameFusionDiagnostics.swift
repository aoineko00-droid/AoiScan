//
//  FrameFusionDiagnostics.swift
//  AoiScan
//

import Foundation


enum FrameFusionDiagnostics {
    static func record(
        result:FrameFusionFeasibilityResult,
        pageNumber:Int
    ) {
        let details = [
            L10n.format("页码 %@", String(pageNumber)),
            L10n.format("缓存帧 %@ 个", String(result.frameCount)),
            L10n.format("稳定帧 %@ 个", String(result.stableFrameCount)),
            "最大四角偏差 \(decimal(result.maximumCornerJitter))",
            "亮度差异 \(percent(result.brightnessSpread))",
            "曝光差异 \(percent(result.exposureSpread))",
            "顶部最大清晰度提升 \(percent(result.topSharpnessGain))",
            "中部最大清晰度提升 \(percent(result.middleSharpnessGain))",
            "底部最大清晰度提升 \(percent(result.bottomSharpnessGain))",
            L10n.format(
                "互补区域 %@ 个，最佳帧 %@ 个",
                String(result.complementaryRegionCount),
                String(result.distinctWinningFrameCount)
            ),
            L10n.format(
                "存在互补区域 %@",
                L10n.text(result.hasComplementaryRegions ? "是" : "否")
            ),
            L10n.format(
                "当前分辨率满足融合 %@",
                L10n.text(result.currentResolutionEligible ? "是" : "否")
            ),
            "缓存用途 仅诊断，不参与正式照片替换或融合",
            "缓存内存 \(storageMegabytes(result)) MB",
            "降级帧 \(fallbackFrameCount(result)) 个",
            L10n.format(
                "分析耗时 %@ms",
                String(result.analysisMilliseconds)
            ),
            L10n.format(
                "结论 %@",
                L10n.text(result.recommendation.diagnosticName)
            ),
            L10n.format("原因 %@", L10n.text(result.reason))
        ].joined(separator:"\n")

        RecognitionLogStore.shared.add(
            category:"多帧融合评估",
            message:result.recommendation.diagnosticName,
            details:details
        )
        DiagnosticsCollector.shared.recordEvent(
            category:L10n.text("多帧融合评估"),
            message:L10n.text(result.recommendation.diagnosticName),
            details:details
        )
    }

    private static func percent(_ value:Double)->String {
        String(format:"%.1f%%", value * 100)
    }

    private static func decimal(_ value:Double?)->String {
        guard let value else { return "--" }
        return String(format:"%.4f", value)
    }

    private static func storageMegabytes(
        _ result:FrameFusionFeasibilityResult
    )->String {
        String(format:"%.1f", result.storageMegabytes)
    }

    private static func fallbackFrameCount(
        _ result:FrameFusionFeasibilityResult
    )->String {
        String(result.fallbackFrameCount)
    }
}
