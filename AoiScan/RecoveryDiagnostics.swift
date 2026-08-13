//
//  RecoveryDiagnostics.swift
//  AoiScan
//

import Foundation


enum RecoveryDiagnostics {
    static func record(
        output:SmartDocumentRecoveryOutput,
        pageNumber:Int,
        stability:CaptureCornerStability?
    ) {
        var lines = [
            L10n.format("页码 %@", String(pageNumber)),
            L10n.format("选中版本 %@", output.selectedType.rawValue),
            L10n.format(
                "总耗时 %@ms",
                String(output.processingMilliseconds)
            ),
            L10n.format(
                "原因 %@",
                L10n.text(output.selectionReason)
            )
        ]

        if let stability {
            lines.append(
                String(
                    format:
                        "previewFrames=%d，stableFrames=%d，cornerJitter=%.4f",
                    stability.recentFrameCount,
                    stability.stableFrameCount,
                    stability.averageCornerJitter
                )
            )
        }

        for trial in output.trials {
            lines.append(trialLine(trial))
        }
        let details = lines.joined(separator:"\n")
        let message = output.selectedType == .current
            ? "智能恢复保留当前版本"
            : "智能恢复采用恢复版本"

        RecognitionLogStore.shared.add(
            category:"智能文档恢复",
            message:message,
            details:details
        )
        DiagnosticsCollector.shared.recordEvent(
            category:L10n.text("智能文档恢复"),
            message:L10n.text(message),
            details:details
        )
    }

    private static func trialLine(
        _ trial:RecoveryTrialSummary
    )->String {
        let geometry = trial.geometry
        let sharpness = trial.sharpness
        let rejectionReason = trial.rejectionReason.map {
            L10n.text($0)
        } ?? "--"
        return [
            "[\(trial.type.rawValue)]",
            L10n.text(trial.type.diagnosticName),
            "coverage=\(percent(Double(geometry.documentCoverage)))",
            "perspective=\(decimal(Double(geometry.perspectiveSeverity)))",
            "topBottom=\(decimal(Double(geometry.topBottomWidthRatio)))",
            "leftRight=\(decimal(Double(geometry.leftRightHeightRatio)))",
            "outputScale=\(decimal(Double(geometry.outputScale)))",
            "cropMargin=\(percent(Double(geometry.cropMargin)))",
            "topSharpness=\(decimal(sharpness.top))",
            "middleSharpness=\(decimal(sharpness.middle))",
            "bottomSharpness=\(decimal(sharpness.bottom))",
            "sharpnessBalance=\(percent(sharpness.balance))",
            "confidence=\(percent(trial.weightedConfidence.map(Double.init)))",
            "characters=\(trial.recognizedCharacterCount)",
            "stability=\(percent(trial.characterStability.map(Double.init)))",
            "accepted=\(trial.evaluatorAccepted ? L10n.text("通过") : L10n.text("未通过"))",
            "selected=\(trial.selected ? L10n.text("已选中") : L10n.text("未选中"))",
            "reason=\(rejectionReason)"
        ]
        .joined(separator:"，")
    }

    private static func percent(_ value:Double?)->String {
        guard let value else { return "--" }
        return String(format:"%.1f%%", value * 100)
    }

    private static func decimal(_ value:Double)->String {
        String(format:"%.3f", value)
    }
}
