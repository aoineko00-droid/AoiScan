//
//  SmartEnhancementPipeline.swift
//  AoiScan
//

import UIKit
import CoreGraphics


enum SmartEnhancementPipeline {
    private static let evaluationMaximumPixelSize:CGFloat = 2000

    private struct SelectedCandidate {
        let variant:EnhancementExperimentVariant
        let image:UIImage
        let ocrResult:OCRPageResult
        let quality:OCRQualityResult
        let documentQuality:DocumentQualityScore
        let decision:SmartEnhancementDecision
        let rankingScore:Float
    }

    static func process(
        rgbImage:UIImage,
        pageNumber:Int,
        baselineSeed:SmartEnhancementSeed? = nil,
        completion:@escaping (SmartEnhancementOutput)->Void
    ) {
        let startedAt = Date()
        let originalSmart = DocumentImageFilter.apply(
            .smart,
            to:rgbImage
        )
        let baselineStartedAt = Date()

        if let baselineSeed,
           baselineSeed.isCompatible(with:rgbImage) {
            beginExperiment(
                rawOriginalOCR:baselineSeed.ocrResult,
                originalQuality:baselineSeed.quality,
                originalSmart:originalSmart,
                rgbSource:rgbImage,
                pageNumber:pageNumber,
                baselineStartedAt:baselineStartedAt,
                reusedBaselineOCR:true,
                startedAt:startedAt,
                completion:completion
            )
            return
        }

        LocalTextRecognizer.recognize(
            image:downscaledForEvaluation(originalSmart),
            pageNumber:pageNumber,
            background:true
        ) { originalResult in
            switch originalResult {
            case .failure:
                deliver(
                    image:originalSmart,
                    ocrResult:nil,
                    originalQuality:nil,
                    enhancedQuality:nil,
                    decision:SmartEnhancementEvaluator()
                        .keepOriginal(
                            reason:"基础版本没有取得足够文字"
                        ),
                    selectedVariant:.baseline,
                    trialSummaries:[],
                    qualityRoute:.insufficientText,
                    documentQualityRoute:.none("基础版本没有取得足够文字"),
                    earlyStopReason:"基础版本没有取得足够文字",
                    executedCandidateCount:0,
                    startedAt:startedAt,
                    pageNumber:pageNumber,
                    completion:completion
                )

            case .success(let rawOriginalOCR):
                beginExperiment(
                    rawOriginalOCR:rawOriginalOCR,
                    originalQuality:nil,
                    originalSmart:originalSmart,
                    rgbSource:rgbImage,
                    pageNumber:pageNumber,
                    baselineStartedAt:baselineStartedAt,
                    reusedBaselineOCR:false,
                    startedAt:startedAt,
                    completion:completion
                )
            }
        }
    }

    private static func beginExperiment(
        rawOriginalOCR:OCRPageResult,
        originalQuality seededQuality:OCRQualityResult?,
        originalSmart:UIImage,
        rgbSource:UIImage,
        pageNumber:Int,
        baselineStartedAt:Date,
        reusedBaselineOCR:Bool,
        startedAt:Date,
        completion:@escaping (SmartEnhancementOutput)->Void
    ) {
        let originalOCR = normalizedResult(
            rawOriginalOCR,
            for:originalSmart,
            pageNumber:pageNumber
        )
        let originalQuality = seededQuality
            ?? OCRQualityAnalyzer().analyze(blocks:originalOCR.blocks)
        let originalDocumentQuality = DocumentQualityAnalyzer.analyze(
            image:originalSmart,
            blocks:originalOCR.blocks,
            ocrQuality:originalQuality,
            characterStability:1
        )
        let baselineSummary = EnhancementTrialSummary(
            variant:.baseline,
            parameters:.baseline,
            weightedConfidence:originalQuality.weightedConfidence,
            recognizedCharacterCount:originalQuality.recognizedCharacterCount,
            characterStability:1,
            textCoverage:originalQuality.textCoverage,
            processingMilliseconds:reusedBaselineOCR
                ? 0 : milliseconds(since:baselineStartedAt),
            evaluatorAccepted:true,
            colorRetention:.identity,
            documentQuality:originalDocumentQuality,
            reusedBaselineOCR:reusedBaselineOCR,
            selected:false
        )
        let baselineDecision = SmartEnhancementEvaluator()
            .keepOriginal(reason:"A/B测试保留原始智能版本")
        let baselineSelection = SelectedCandidate(
            variant:.baseline,
            image:originalSmart,
            ocrResult:originalOCR,
            quality:originalQuality,
            documentQuality:originalDocumentQuality,
            decision:baselineDecision,
            rankingScore:SmartEnhancementExperiment.rankingScore(
                quality:originalQuality,
                stability:1,
                documentQuality:originalDocumentQuality
            )
        )
        let route = SmartEnhancementExperiment.route(
            for:originalQuality
        )
        let documentRoute = DocumentQualityRouter.route(
            quality:originalDocumentQuality,
            ocrQuality:originalQuality,
            blocks:originalOCR.blocks
        )
        let candidates = SmartEnhancementExperiment.candidates(
            for:documentRoute
        )

        guard !candidates.isEmpty else {
            let reason = documentRoute.reason
            finishExperiment(
                selected:baselineSelection,
                originalQuality:originalQuality,
                summaries:[baselineSummary],
                qualityRoute:route,
                documentQualityRoute:documentRoute,
                earlyStopReason:reason,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        testCandidate(
            at:0,
            candidates:candidates,
            qualityRoute:route,
            documentQualityRoute:documentRoute,
            rgbSource:rgbSource,
            baselineImage:originalSmart,
            originalOCR:originalOCR,
            originalQuality:originalQuality,
            originalDocumentQuality:originalDocumentQuality,
            pageNumber:pageNumber,
            summaries:[baselineSummary],
            selected:baselineSelection,
            startedAt:startedAt,
            completion:completion
        )
    }

    private static func testCandidate(
        at index:Int,
        candidates:[EnhancementExperimentCandidate],
        qualityRoute:SmartEnhancementQualityRoute,
        documentQualityRoute:DocumentQualityRoute,
        rgbSource:UIImage,
        baselineImage:UIImage,
        originalOCR:OCRPageResult,
        originalQuality:OCRQualityResult,
        originalDocumentQuality:DocumentQualityScore,
        pageNumber:Int,
        summaries:[EnhancementTrialSummary],
        selected:SelectedCandidate,
        startedAt:Date,
        completion:@escaping (SmartEnhancementOutput)->Void
    ) {
        guard candidates.indices.contains(index) else {
            let routeStopReason = "按需光照与文字保护测试完成"
            finishExperiment(
                selected:selected,
                originalQuality:originalQuality,
                summaries:summaries,
                qualityRoute:qualityRoute,
                documentQualityRoute:documentQualityRoute,
                earlyStopReason:routeStopReason,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        let candidate = candidates[index]
        let candidateStartedAt = Date()
        let candidateImage:UIImage
        switch candidate.variant {
        case .baseline:
            candidateImage = baselineImage
        case .smartColorMedium, .smartColorStrong:
            candidateImage = SmartEnhancementCandidateBuilder.build(
                rgbSource:rgbSource,
                baselineImage:baselineImage,
                blocks:originalOCR.blocks,
                parameters:candidate.parameters,
                route:documentQualityRoute
            )
        }
        let colorRetention = ColorRetentionAnalyzer.analyze(
            original:rgbSource,
            candidate:candidateImage
        )

        LocalTextRecognizer.recognize(
            image:downscaledForEvaluation(candidateImage),
            pageNumber:pageNumber,
            background:true
        ) { result in
            var updatedSummaries = summaries
            var updatedSelection = selected
            let earlyStopReason = "已完成对应问题的单一 A/B 恢复测试"

            switch result {
            case .failure:
                updatedSummaries.append(
                    EnhancementTrialSummary(
                        variant:candidate.variant,
                        parameters:candidate.parameters,
                        weightedConfidence:nil,
                        recognizedCharacterCount:0,
                        characterStability:0,
                        textCoverage:0,
                        processingMilliseconds:milliseconds(
                            since:candidateStartedAt
                        ),
                        evaluatorAccepted:false,
                        colorRetention:colorRetention,
                        documentQuality:nil,
                        reusedBaselineOCR:false,
                        selected:false
                    )
                )

            case .success(let rawOCR):
                let candidateOCR = normalizedResult(
                    rawOCR,
                    for:candidateImage,
                    pageNumber:pageNumber
                )
                let candidateQuality = OCRQualityAnalyzer().analyze(
                    blocks:candidateOCR.blocks
                )
                let stability = TextStabilityAnalyzer().similarity(
                    baseline:originalOCR.plainText,
                    candidate:candidateOCR.plainText
                )
                let candidateDocumentQuality =
                    DocumentQualityAnalyzer.analyze(
                        image:candidateImage,
                        blocks:candidateOCR.blocks,
                        ocrQuality:candidateQuality,
                        characterStability:stability,
                        colorRetention:colorRetention
                    )
                let evaluatorDecision = SmartEnhancementEvaluator()
                    .evaluate(
                        original:originalQuality,
                        enhanced:candidateQuality,
                        originalDocument:originalDocumentQuality,
                        enhancedDocument:candidateDocumentQuality,
                        route:documentQualityRoute
                    )
                let canSelect = SmartEnhancementExperiment.canSelect(
                    quality:candidateQuality,
                    original:originalQuality,
                    stability:stability,
                    colorRetention:colorRetention,
                    evaluatorDecision:evaluatorDecision
                )
                let score = SmartEnhancementExperiment.rankingScore(
                    quality:candidateQuality,
                    stability:stability,
                    colorRetention:colorRetention.overallRetention,
                    documentQuality:candidateDocumentQuality
                )

                if canSelect,
                   score > selected.rankingScore + 0.0005 {
                    updatedSelection = SelectedCandidate(
                        variant:candidate.variant,
                        image:candidateImage,
                        ocrResult:candidateOCR,
                        quality:candidateQuality,
                        documentQuality:candidateDocumentQuality,
                        decision:evaluatorDecision,
                        rankingScore:score
                    )
                }

                updatedSummaries.append(
                    EnhancementTrialSummary(
                        variant:candidate.variant,
                        parameters:candidate.parameters,
                        weightedConfidence:
                            candidateQuality.weightedConfidence,
                        recognizedCharacterCount:
                            candidateQuality.recognizedCharacterCount,
                        characterStability:stability,
                        textCoverage:candidateQuality.textCoverage,
                        processingMilliseconds:milliseconds(
                            since:candidateStartedAt
                        ),
                        evaluatorAccepted:canSelect,
                        colorRetention:colorRetention,
                        documentQuality:candidateDocumentQuality,
                        reusedBaselineOCR:false,
                        selected:false
                    )
                )

            }
            finishExperiment(
                selected:updatedSelection,
                originalQuality:originalQuality,
                summaries:updatedSummaries,
                qualityRoute:qualityRoute,
                documentQualityRoute:documentQualityRoute,
                earlyStopReason:earlyStopReason,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
        }
    }

    private static func finishExperiment(
        selected:SelectedCandidate,
        originalQuality:OCRQualityResult,
        summaries:[EnhancementTrialSummary],
        qualityRoute:SmartEnhancementQualityRoute,
        documentQualityRoute:DocumentQualityRoute,
        earlyStopReason:String?,
        startedAt:Date,
        pageNumber:Int,
        completion:@escaping (SmartEnhancementOutput)->Void
    ) {
        let selectedSummaries = summaries.map { summary in
            var updated = summary
            updated.selected = summary.variant == selected.variant
            return updated
        }
        let didReplace = selected.variant != .baseline
        let decision:SmartEnhancementDecision

        if didReplace {
            decision = SmartEnhancementDecision(
                selectedVariant:.textAware,
                shouldReplaceImage:true,
                reason:"A/B测试选择了更优增强版本",
                confidenceGain:selected.quality.weightedConfidence
                    - originalQuality.weightedConfidence,
                characterRetention:Float(
                    selected.quality.recognizedCharacterCount
                ) / Float(max(originalQuality.recognizedCharacterCount, 1)),
                coverageRetention:Float(
                    selected.quality.textCoverage
                        / max(originalQuality.textCoverage, 0.0001)
                ),
                scoreGain:selected.quality.qualityScore
                    - originalQuality.qualityScore
            )
        }
        else {
            decision = SmartEnhancementEvaluator().keepOriginal(
                reason:earlyStopReason ?? "A/B测试未发现更优版本"
            )
        }

        deliver(
            image:selected.image,
            ocrResult:selected.ocrResult,
            originalQuality:originalQuality,
            enhancedQuality:didReplace ? selected.quality : nil,
            decision:decision,
            selectedVariant:selected.variant,
            trialSummaries:selectedSummaries,
            qualityRoute:qualityRoute,
            documentQualityRoute:documentQualityRoute,
            earlyStopReason:earlyStopReason,
            executedCandidateCount:max(selectedSummaries.count - 1, 0),
            startedAt:startedAt,
            pageNumber:pageNumber,
            completion:completion
        )
    }

    private static func deliver(
        image:UIImage,
        ocrResult:OCRPageResult?,
        originalQuality:OCRQualityResult?,
        enhancedQuality:OCRQualityResult?,
        decision:SmartEnhancementDecision,
        selectedVariant:EnhancementExperimentVariant,
        trialSummaries:[EnhancementTrialSummary],
        qualityRoute:SmartEnhancementQualityRoute,
        documentQualityRoute:DocumentQualityRoute,
        earlyStopReason:String?,
        executedCandidateCount:Int,
        startedAt:Date,
        pageNumber:Int,
        completion:@escaping (SmartEnhancementOutput)->Void
    ) {
        let output = SmartEnhancementOutput(
            image:image,
            ocrResult:ocrResult,
            originalQuality:originalQuality,
            enhancedQuality:enhancedQuality,
            decision:decision,
            selectedExperimentVariant:selectedVariant,
            trialSummaries:trialSummaries,
            processingMilliseconds:milliseconds(since:startedAt),
            qualityRoute:qualityRoute,
            earlyStopReason:earlyStopReason,
            executedCandidateCount:executedCandidateCount,
            skippedCandidateCount:max(
                SmartEnhancementExperiment.candidates.count
                    - executedCandidateCount,
                0
            ),
            documentQualityRoute:documentQualityRoute
        )

        DispatchQueue.main.async {
            SmartEnhancementDiagnostics.record(
                output:output,
                pageNumber:pageNumber
            )
            completion(output)
        }
    }

    private static func normalizedResult(
        _ result:OCRPageResult,
        for image:UIImage,
        pageNumber:Int
    )->OCRPageResult {
        OCRPageResult(
            pageNumber:pageNumber,
            imageWidth:image.cgImage?.width
                ?? Int(image.size.width * image.scale),
            imageHeight:image.cgImage?.height
                ?? Int(image.size.height * image.scale),
            blocks:result.blocks
        )
    }

    private static func downscaledForEvaluation(
        _ image:UIImage
    )->UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longestEdge = max(width, height)

        guard longestEdge > evaluationMaximumPixelSize else {
            return image
        }

        let scale = evaluationMaximumPixelSize / longestEdge
        let outputWidth = max(Int((width * scale).rounded()), 1)
        let outputHeight = max(Int((height * scale).rounded()), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data:nil,
            width:outputWidth,
            height:outputHeight,
            bitsPerComponent:8,
            bytesPerRow:0,
            space:colorSpace,
            bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(
            cgImage,
            in:CGRect(
                x:0,
                y:0,
                width:outputWidth,
                height:outputHeight
            )
        )

        guard let output = context.makeImage() else { return image }
        return UIImage(
            cgImage:output,
            scale:1,
            orientation:.up
        )
    }

    private static func milliseconds(since date:Date)->Int {
        max(0, Int(Date().timeIntervalSince(date) * 1000))
    }
}
