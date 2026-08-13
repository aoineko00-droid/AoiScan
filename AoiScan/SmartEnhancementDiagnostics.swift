//
//  SmartEnhancementDiagnostics.swift
//  AoiScan
//

import Foundation


enum SmartEnhancementDiagnostics {
    static func record(
        output:SmartEnhancementOutput,
        pageNumber:Int
    ) {
        let selectedCode = output.selectedExperimentVariant.rawValue
        let message = output.selectedExperimentVariant == .baseline
            ? "A/B测试保留原始智能版本"
            : "A/B测试选择了增强版本"
        var lines = [
            L10n.format("页码 %@", String(pageNumber)),
            L10n.format("选中版本 %@", selectedCode),
            L10n.format(
                "总耗时 %@ms",
                String(output.processingMilliseconds)
            ),
            L10n.format(
                "原因 %@",
                L10n.text(output.decision.reason)
            ),
            L10n.format(
                "质量路线 %@",
                L10n.text(output.qualityRoute.diagnosticName)
            ),
            L10n.format(
                "问题类型 %@",
                L10n.text(
                    output.documentQualityRoute.primaryIssue.diagnosticName
                )
            ),
            L10n.format(
                "影响区域 %@",
                L10n.text(
                    output.documentQualityRoute.affectedRegion.diagnosticName
                )
            ),
            L10n.format(
                "问题程度 %@",
                percent(output.documentQualityRoute.severity)
            ),
            L10n.format(
                "路由原因 %@",
                L10n.text(output.documentQualityRoute.reason)
            ),
            L10n.format(
                "实际测试 %@ 个，跳过 %@ 个",
                String(output.executedCandidateCount),
                String(output.skippedCandidateCount)
            )
        ]

        if let earlyStopReason = output.earlyStopReason {
            lines.append(
                L10n.format(
                    "早停原因 %@",
                    L10n.text(earlyStopReason)
                )
            )
        }

        for trial in output.trialSummaries {
            lines.append(trialLine(trial))
        }
        let details = lines.joined(separator:"\n")

        RecognitionLogStore.shared.add(
            level:"信息",
            category:"智能增强 A/B",
            message:message,
            details:details
        )

        DiagnosticsCollector.shared.recordEvent(
            category:L10n.text("智能增强 A/B"),
            message:L10n.text(message),
            details:details
        )
    }

    private static func trialLine(
        _ trial:EnhancementTrialSummary
    )->String {
        let parameters = trial.parameters
        let threshold = parameters.threshold.map {
            decimal($0)
        } ?? L10n.text("关闭")
        let selected = trial.selected
            ? L10n.text("已选中")
            : L10n.text("未选中")
        let accepted = trial.evaluatorAccepted
            ? L10n.text("通过")
            : L10n.text("未通过")
        let reusedOCR = trial.reusedBaselineOCR
            ? L10n.text("是")
            : L10n.text("否")

        return [
            "[\(trial.variant.rawValue)]",
            L10n.text(trial.variant.diagnosticName),
            "confidence=\(percent(trial.weightedConfidence))",
            "characters=\(trial.recognizedCharacterCount)",
            "stability=\(percent(trial.characterStability))",
            "contrast=\(decimal(parameters.contrast))",
            "gamma=\(decimal(parameters.luminanceGamma))",
            "local=\(decimal(parameters.localNormalization))",
            "ink=\(decimal(parameters.textInkStrength))",
            "colorProtect=\(decimal(parameters.colorProtection))",
            "sharpen=\(decimal(parameters.sharpen))",
            "unsharp=\(decimal(parameters.unsharpIntensity))",
            "threshold=\(threshold)",
            "denoise=\(decimal(parameters.denoiseNoiseLevel))",
            "color=\(percent(trial.colorRetention?.overallRetention))",
            "red=\(percent(trial.colorRetention?.redRetention))",
            "blue=\(percent(trial.colorRetention?.blueRetention))",
            "document=\(percent(trial.documentQuality?.totalScore))",
            "edge=\(percent(trial.documentQuality?.textEdgeClarity))",
            "background=\(percent(trial.documentQuality?.backgroundUniformity))",
            "brightness=\(percent(trial.documentQuality?.visual.backgroundBrightness))",
            "top=\(percent(trial.documentQuality?.visual.topClarity))",
            "middle=\(percent(trial.documentQuality?.visual.middleClarity))",
            "bottom=\(percent(trial.documentQuality?.visual.bottomClarity))",
            "regionBalance=\(percent(trial.documentQuality?.visual.regionalClarityBalance))",
            "topLight=\(percent(trial.documentQuality?.visual.topBrightness))",
            "middleLight=\(percent(trial.documentQuality?.visual.middleBrightness))",
            "bottomLight=\(percent(trial.documentQuality?.visual.bottomBrightness))",
            "lightGradient=\(percent(trial.documentQuality?.visual.illuminationGradient))",
            "shadow=\(percent(trial.documentQuality?.visual.shadowSeverity))",
            "needsLight=\(boolean(trial.documentQuality?.visual.needsIlluminationCorrection))",
            "halo=\(percent(trial.documentQuality?.visual.haloPenalty))",
            "noise=\(percent(trial.documentQuality?.visual.noisePenalty))",
            "structure=\(percent(trial.documentQuality?.visual.textStructureScore))",
            "reusedOCR=\(reusedOCR)",
            "time=\(trial.processingMilliseconds)ms",
            "evaluator=\(accepted)",
            "selected=\(selected)"
        ]
        .joined(separator:"，")
    }

    private static func percent(_ value:Float?)->String {
        guard let value else { return "--" }
        return String(format:"%.1f%%", value * 100)
    }

    private static func decimal(_ value:CGFloat)->String {
        String(format:"%.3f", value)
    }

    private static func boolean(_ value:Bool?)->String {
        guard let value else { return "--" }
        return L10n.text(value ? "是" : "否")
    }
}
