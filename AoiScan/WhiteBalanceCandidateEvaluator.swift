//
//  WhiteBalanceCandidateEvaluator.swift
//  AoiScan
//

import Foundation


struct WhiteBalanceEvaluationResult:Codable {
    let accepted:Bool
    let reason:String
    let redGain:Float
    let greenGain:Float
    let blueGain:Float
    let originalRedBlueRatio:Float
    let candidateRedBlueRatio:Float?
    let originalLabYellowBias:Float
    let candidateLabYellowBias:Float?
    let neutralityGain:Float
    let overcorrectionDetected:Bool
    let paperNormalizationEvaluation:
        PaperNormalizationEvaluationResult?
}


enum WhiteBalanceCandidateEvaluator {
    static func evaluate(
        candidateTemperature:ColorTemperatureResult?,
        originalTemperature:ColorTemperatureResult,
        colorRetention:ColorRetentionResult,
        paperNormalizationEvaluation:
            PaperNormalizationEvaluationResult? = nil,
        paperSurfaceMode:PaperNormalizationSurfaceMode? = nil
    )->WhiteBalanceEvaluationResult {
        let correction = DocumentWhiteBalanceEnhancer.correction(
            for:originalTemperature
        )
        let gains = correction ?? DocumentWhiteBalanceCorrection(
            redGain:1,
            greenGain:1,
            blueGain:1
        )

        let canNormalizePaper = paperNormalizationEvaluation?.eligible
            == true
        guard correction != nil || canNormalizePaper else {
            return result(
                accepted:false,
                reason:"色温与纸张背景证据均未达到标准化门槛",
                gains:gains,
                original:originalTemperature,
                candidate:candidateTemperature,
                neutralityGain:0,
                overcorrection:false,
                paperNormalizationEvaluation:
                    paperNormalizationEvaluation
            )
        }
        guard let candidateTemperature else {
            return result(
                accepted:false,
                reason:"白平衡候选没有取得足够背景样本",
                gains:gains,
                original:originalTemperature,
                candidate:nil,
                neutralityGain:0,
                overcorrection:false,
                paperNormalizationEvaluation:
                    paperNormalizationEvaluation
            )
        }

        let originalDistance = neutralityDistance(originalTemperature)
        let candidateDistance = neutralityDistance(candidateTemperature)
        let neutralityGain = originalDistance - candidateDistance
        let overcorrection:Bool
        switch originalTemperature.source {
        case .warm:
            overcorrection = candidateTemperature.redBlueRatio < 0.98
                || candidateTemperature.labYellowBias < -3
                || candidateTemperature.source == .cool
        case .cool:
            overcorrection = candidateTemperature.redBlueRatio > 1.02
                || candidateTemperature.labYellowBias > 3
                || candidateTemperature.source == .warm
        case .neutral, .uncertain:
            overcorrection = !canNormalizePaper
                || abs(candidateTemperature.labYellowBias)
                    > abs(originalTemperature.labYellowBias) + 1
        }
        let scannerWhitePaperAccepted =
            paperNormalizationEvaluation?.accepted == true
            && paperSurfaceMode
            == PaperNormalizationSurfaceMode.contentAwareWhiteCanvas
        let genericColorSafe = colorRetention.overallRetention >= 0.98
            && colorRetention.chromaSimilarity >= 0.985
            && colorRetention.redRetention >= 0.985
            && colorRetention.blueRetention >= 0.985
        // Generic chroma similarity is deliberately strict for ordinary
        // white balance, but scanner-white is expected to remove a broad beige
        // paper cast. Once the dedicated paper/non-paper safety evaluation has
        // passed, protect localized saturated content and red/blue ink while
        // allowing the low-saturation sheet itself to become neutral white.
        // The analyzer is the single source of truth for scanner-white color
        // safety, including its tightly bounded red/blue sampling tolerance.
        // Missing/misaligned masks also surface as a rejection metric here.
        let scannerWhiteColorSafe = colorRetention
            .firstRejectedColorMetric == nil
        let colorSafe = scannerWhitePaperAccepted
            ? scannerWhiteColorSafe : genericColorSafe
        let saturationSafe = candidateTemperature.backgroundSaturation
            <= originalTemperature.backgroundSaturation + 0.010
        // A scanner-white page may leave few non-clipped samples after OCR
        // rectangles are excluded. Its dedicated regional paper evaluation is
        // stronger evidence than the generic background sample ratio.
        let sampleSafe = scannerWhitePaperAccepted
            || candidateTemperature.validSampleRatio
                >= max(originalTemperature.validSampleRatio * 0.55, 0.12)
        let correctionBounded = gains.redGain >= 0.94
            && gains.redGain <= 1.06
            && gains.greenGain >= 0.96
            && gains.greenGain <= 1.04
            && gains.blueGain >= 0.94
            && gains.blueGain <= 1.06
        let minimumNeutralityGain = min(
            max(originalDistance * 0.16, 0.008),
            0.014
        )
        let meaningfulGain = neutralityGain >= minimumNeutralityGain
            || paperNormalizationEvaluation?.accepted == true
        let paperSafe = !canNormalizePaper
            || paperNormalizationEvaluation?.accepted == true

        let accepted = meaningfulGain
            && !overcorrection
            && colorSafe
            && saturationSafe
            && sampleSafe
            && correctionBounded
            && paperSafe
        let reason:String
        if overcorrection {
            reason = "白平衡候选出现反向偏色或过度校正"
        }
        else if !colorSafe {
            reason = "白平衡候选未通过彩色内容保持门槛"
        }
        else if !saturationSafe {
            reason = "白平衡候选提高了背景饱和度"
        }
        else if !sampleSafe {
            reason = "白平衡候选的有效背景样本不足"
        }
        else if !correctionBounded {
            reason = "白平衡候选的 RGB 增益超出安全范围"
        }
        else if !paperSafe {
            reason = paperNormalizationEvaluation?.reason
                ?? "纸张标准化未通过安全检查"
        }
        else if !meaningfulGain {
            reason = "候选未达到最低中性化或纸张提白收益"
        }
        else if scannerWhitePaperAccepted {
            let usesScannerWhiteTolerance = !genericColorSafe
                || colorRetention.nearBoundaryToleranceApplied
                || paperNormalizationEvaluation?.reason
                    .contains("近边界容错") == true
            reason = usesScannerWhiteTolerance
                ? "候选通过扫描白近边界容错、保色和非纸面细节检查"
                : "候选通过整页扫描白底、中性化、保色和非纸面细节检查"
        }
        else if paperNormalizationEvaluation?.accepted == true,
                paperSurfaceMode == .stableLowFrequency {
            reason = "稳定低频候选通过普通严格保色、有效样本和纸面检查"
        }
        else {
            reason = "白平衡候选通过中性化、保色和过校正检查"
        }

        return result(
            accepted:accepted,
            reason:reason,
            gains:gains,
            original:originalTemperature,
            candidate:candidateTemperature,
            neutralityGain:neutralityGain,
            overcorrection:overcorrection,
            paperNormalizationEvaluation:paperNormalizationEvaluation
        )
    }

    private static func neutralityDistance(
        _ result:ColorTemperatureResult
    )->Float {
        let ratioDistance = min(abs(log(max(result.redBlueRatio, 0.001))), 0.30)
            / 0.30
        let labDistance = min(abs(result.labYellowBias), 30) / 30
        return ratioDistance * 0.62 + labDistance * 0.38
    }

    private static func result(
        accepted:Bool,
        reason:String,
        gains:DocumentWhiteBalanceCorrection,
        original:ColorTemperatureResult,
        candidate:ColorTemperatureResult?,
        neutralityGain:Float,
        overcorrection:Bool,
        paperNormalizationEvaluation:
            PaperNormalizationEvaluationResult?
    )->WhiteBalanceEvaluationResult {
        WhiteBalanceEvaluationResult(
            accepted:accepted,
            reason:reason,
            redGain:gains.redGain,
            greenGain:gains.greenGain,
            blueGain:gains.blueGain,
            originalRedBlueRatio:original.redBlueRatio,
            candidateRedBlueRatio:candidate?.redBlueRatio,
            originalLabYellowBias:original.labYellowBias,
            candidateLabYellowBias:candidate?.labYellowBias,
            neutralityGain:neutralityGain,
            overcorrectionDetected:overcorrection,
            paperNormalizationEvaluation:
                paperNormalizationEvaluation
        )
    }
}
