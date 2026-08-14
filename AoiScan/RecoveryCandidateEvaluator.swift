//
//  RecoveryCandidateEvaluator.swift
//  AoiScan
//

import Foundation
import UIKit


enum RecoveryCandidateEvaluator {
    private static let evaluationMaximumPixelSize:CGFloat = 1800

    static func evaluate(
        candidates:[RecoveryCandidate],
        pageNumber:Int,
        startedAt:Date,
        completion:@escaping(SmartDocumentRecoveryOutput)->Void
    ) {
        guard let baseline = candidates.first(where:{
            $0.type == .current
        }) else {
            return
        }
        let alternative = candidates
            .filter {
                $0.type != .current
                    && hasStrongQuickEvidence(
                        candidate:$0,
                        baseline:baseline
                    )
            }
            .max { $0.quickScore < $1.quickScore }

        guard let alternative else {
            deliver(
                selected:baseline,
                trials:quickTrials(candidates, selected:.current),
                reason:"没有明确几何或清晰度收益，恢复OCR前早停",
                startedAt:startedAt,
                completion:completion
            )
            return
        }

        recognizePair(
            baseline:baseline,
            alternative:alternative,
            pageNumber:pageNumber
        ) { baselineOCR, baselineQuality,
            alternativeOCR, alternativeQuality in
            guard let baselineOCR,
                  let baselineQuality else {
                deliver(
                    selected:baseline,
                    selectedOCR:nil,
                    selectedQuality:nil,
                    trials:quickTrials(candidates, selected:.current),
                    reason:"当前版本没有取得足够文字，安全保留当前版本",
                    startedAt:startedAt,
                    completion:completion
                )
                return
            }
                guard let alternativeOCR,
                      let alternativeQuality else {
                    deliver(
                        selected:baseline,
                        selectedOCR:baselineOCR,
                        selectedQuality:baselineQuality,
                        trials:trials(
                            candidates:candidates,
                            baseline:baseline,
                            baselineQuality:baselineQuality,
                            alternative:alternative,
                            alternativeQuality:nil,
                            stability:nil,
                            accepted:false,
                            selected:.current,
                            rejectionReason:"恢复候选没有取得足够文字"
                        ),
                        reason:"恢复候选没有取得足够文字",
                        startedAt:startedAt,
                        completion:completion
                    )
                    return
                }

                let stability = TextStabilityAnalyzer().similarity(
                    baseline:baselineOCR.plainText,
                    candidate:alternativeOCR.plainText
                )
                let characterRetention = Float(
                    alternativeQuality.recognizedCharacterCount
                ) / Float(max(
                    baselineQuality.recognizedCharacterCount,
                    1
                ))
                let confidenceGain = alternativeQuality.weightedConfidence
                    - baselineQuality.weightedConfidence
                let topGain = relativeGain(
                    alternative.sharpness.top,
                    baseline.sharpness.top
                )
                let averageGain = relativeGain(
                    alternative.sharpness.average,
                    baseline.sharpness.average
                )
                let safe = stability >= 0.97
                    && characterRetention >= 0.98
                    && alternative.geometry.outputScale <= 1.35
                    && alternative.geometry.cornersAreConvex
                    && alternative.geometry.cornersAreInsideImage
                let improvesOCR = confidenceGain >= 0.010
                let improvesRegionalSharpness = confidenceGain >= -0.001
                    && topGain >= 0.08
                    && averageGain >= -0.02
                let addsStableText = confidenceGain >= -0.001
                    && characterRetention >= 1.01
                    && stability >= 0.98
                let accepted = safe && (
                    improvesOCR
                        || improvesRegionalSharpness
                        || addsStableText
                )
                let selected = accepted ? alternative : baseline
                let reason:String
                if accepted {
                    reason = "恢复候选综合质量优于当前版本"
                }
                else if !safe {
                    reason = "恢复候选未通过文字或几何安全门槛"
                }
                else {
                    reason = "恢复候选没有达到替换门槛"
                }

                deliver(
                    selected:selected,
                    selectedOCR:accepted ? alternativeOCR : baselineOCR,
                    selectedQuality:accepted
                        ? alternativeQuality : baselineQuality,
                    trials:trials(
                        candidates:candidates,
                        baseline:baseline,
                        baselineQuality:baselineQuality,
                        alternative:alternative,
                        alternativeQuality:alternativeQuality,
                        stability:stability,
                        accepted:accepted,
                        selected:selected.type,
                        rejectionReason:accepted ? nil : reason
                    ),
                    reason:reason,
                    startedAt:startedAt,
                    completion:completion
                )
        }
    }

    private static func recognizePair(
        baseline:RecoveryCandidate,
        alternative:RecoveryCandidate,
        pageNumber:Int,
        completion:@escaping(
            OCRPageResult?,OCRQualityResult?,
            OCRPageResult?,OCRQualityResult?
        )->Void
    ) {
        let group = DispatchGroup()
        let lock = NSLock()
        var baselineOCR:OCRPageResult?
        var baselineQuality:OCRQualityResult?
        var alternativeOCR:OCRPageResult?
        var alternativeQuality:OCRQualityResult?

        group.enter()
        recognize(image:baseline.image, pageNumber:pageNumber) { ocr, quality in
            lock.lock()
            baselineOCR = ocr
            baselineQuality = quality
            lock.unlock()
            group.leave()
        }
        group.enter()
        recognize(image:alternative.image, pageNumber:pageNumber) { ocr, quality in
            lock.lock()
            alternativeOCR = ocr
            alternativeQuality = quality
            lock.unlock()
            group.leave()
        }
        group.notify(queue:.main) {
            completion(
                baselineOCR,
                baselineQuality,
                alternativeOCR,
                alternativeQuality
            )
        }
    }

    private static func hasStrongQuickEvidence(
        candidate:RecoveryCandidate,
        baseline:RecoveryCandidate
    )->Bool {
        let geometryGain = candidate.geometry.geometryScore
            - baseline.geometry.geometryScore
        let perspectiveReduction = baseline.geometry.perspectiveSeverity
            - candidate.geometry.perspectiveSeverity
        let edgeSafetyGain = candidate.geometry.edgeSafety
            - baseline.geometry.edgeSafety
        let balanceGain = candidate.sharpness.balance
            - baseline.sharpness.balance
        let averageSharpnessGain = relativeGain(
            candidate.sharpness.average,
            baseline.sharpness.average
        )
        let quickScoreGain = candidate.quickScore - baseline.quickScore

        let fixesStrongPerspective =
            baseline.geometry.perspectiveSeverity >= 0.18
            && perspectiveReduction >= 0.025
        let fixesUnsafeEdge = baseline.geometry.edgeSafety < 0.35
            && edgeSafetyGain >= 0.12
        let improvesSharpness = balanceGain >= 0.10
            && averageSharpnessGain >= -0.02
        let broadQuickGain = quickScoreGain >= 0.025
            && geometryGain >= 0.012

        return fixesStrongPerspective
            || fixesUnsafeEdge
            || improvesSharpness
            || broadQuickGain
    }

    private static func recognize(
        image:UIImage,
        pageNumber:Int,
        completion:@escaping(OCRPageResult?,OCRQualityResult?)->Void
    ) {
        // Use the same baseline rendering that SmartEnhancementPipeline uses.
        // This makes the selected result reusable and removes one later OCR pass.
        let evaluationImage = DocumentImageFilter.apply(
            .smart,
            to:image
        )
        LocalTextRecognizer.recognize(
            image:downscaled(evaluationImage),
            pageNumber:pageNumber,
            background:true,
            recoveryComparison:true
        ) { result in
            switch result {
            case .failure:
                completion(nil, nil)
            case .success(let ocr):
                completion(
                    ocr,
                    OCRQualityAnalyzer().analyze(blocks:ocr.blocks)
                )
            }
        }
    }

    private static func trials(
        candidates:[RecoveryCandidate],
        baseline:RecoveryCandidate,
        baselineQuality:OCRQualityResult,
        alternative:RecoveryCandidate,
        alternativeQuality:OCRQualityResult?,
        stability:Float?,
        accepted:Bool,
        selected:RecoveryCandidateType,
        rejectionReason:String?
    )->[RecoveryTrialSummary] {
        candidates.map { candidate in
            let isBaseline = candidate.type == baseline.type
            let isAlternative = candidate.type == alternative.type
            return RecoveryTrialSummary(
                type:candidate.type,
                geometry:candidate.geometry,
                sharpness:candidate.sharpness,
                weightedConfidence:isBaseline
                    ? baselineQuality.weightedConfidence
                    : (isAlternative
                        ? alternativeQuality?.weightedConfidence
                        : nil),
                recognizedCharacterCount:isBaseline
                    ? baselineQuality.recognizedCharacterCount
                    : (isAlternative
                        ? alternativeQuality?.recognizedCharacterCount ?? 0
                        : 0),
                characterStability:isBaseline ? 1 : (isAlternative ? stability : nil),
                evaluatorAccepted:isBaseline || (isAlternative && accepted),
                rejectionReason:isBaseline
                    ? nil
                    : (isAlternative
                        ? rejectionReason
                        : "快速筛选未入选"),
                selected:candidate.type == selected
            )
        }
    }

    private static func quickTrials(
        _ candidates:[RecoveryCandidate],
        selected:RecoveryCandidateType
    )->[RecoveryTrialSummary] {
        candidates.map {
            RecoveryTrialSummary(
                type:$0.type,
                geometry:$0.geometry,
                sharpness:$0.sharpness,
                weightedConfidence:nil,
                recognizedCharacterCount:0,
                characterStability:nil,
                evaluatorAccepted:$0.type == .current,
                rejectionReason:$0.type == .current
                    ? nil
                    : "快速筛选未入选",
                selected:$0.type == selected
            )
        }
    }

    private static func deliver(
        selected:RecoveryCandidate,
        selectedOCR:OCRPageResult? = nil,
        selectedQuality:OCRQualityResult? = nil,
        trials:[RecoveryTrialSummary],
        reason:String,
        startedAt:Date,
        completion:@escaping(SmartDocumentRecoveryOutput)->Void
    ) {
        let width = selected.image.cgImage?.width
            ?? Int(selected.image.size.width * selected.image.scale)
        let height = selected.image.cgImage?.height
            ?? Int(selected.image.size.height * selected.image.scale)
        let output = SmartDocumentRecoveryOutput(
            image:selected.image,
            corners:selected.corners,
            selectedType:selected.type,
            trials:trials,
            processingMilliseconds:Int(
                Date().timeIntervalSince(startedAt) * 1000
            ),
            selectionReason:reason,
            enhancementSeed:selectedOCR.flatMap { ocr in
                selectedQuality.map { quality in
                    SmartEnhancementSeed(
                        ocrResult:ocr,
                        quality:quality,
                        sourcePixelWidth:width,
                        sourcePixelHeight:height
                    )
                }
            }
        )
        DispatchQueue.main.async {
            completion(output)
        }
    }

    private static func relativeGain(
        _ candidate:Double,
        _ baseline:Double
    )->Double {
        guard baseline > 0.0001 else { return 0 }
        return candidate / baseline - 1
    }

    private static func downscaled(_ image:UIImage)->UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longest = max(width, height)
        guard longest > evaluationMaximumPixelSize else { return image }
        let scale = evaluationMaximumPixelSize / longest
        let size = CGSize(width:width * scale, height:height * scale)
        let renderer = UIGraphicsImageRenderer(size:size)
        return renderer.image { _ in
            image.draw(in:CGRect(origin:.zero, size:size))
        }
    }
}
