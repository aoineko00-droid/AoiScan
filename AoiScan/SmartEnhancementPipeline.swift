//
//  SmartEnhancementPipeline.swift
//  AoiScan
//

import UIKit
import CoreGraphics


enum SmartEnhancementPipeline {
    private static let evaluationMaximumPixelSize:CGFloat = 1800
    private static let directionalPreviewPixelSize:CGFloat = 640
    private static let structuralPreviewPixelSize:CGFloat = 960
    private static let denseCharacterThreshold = 700
    private static let maximumBaselineMillisecondsBeforeCandidate = 3_000
    private static let maximumPreviewMilliseconds = 850
    private static let maximumElapsedMillisecondsBeforeSecondOCR = 3_500
    private static let maximumElapsedMillisecondsBeforeFullWhiteBalance =
        2_700
    private static let maximumElapsedMillisecondsBeforeWhiteBalanceFallback =
        2_600

    private struct SelectedCandidate {
        let variant:EnhancementExperimentVariant
        let image:UIImage
        let ocrResult:OCRPageResult
        let quality:OCRQualityResult
        let documentQuality:DocumentQualityScore
        let decision:SmartEnhancementDecision
        let rankingScore:Float
    }

    private struct PreparedSmartBaseline {
        let image:UIImage
        let scannerWhiteAttempted:Bool
        let scannerWhiteApplied:Bool
        let selectedSurfaceMode:PaperNormalizationSurfaceMode?
        let colorRetention:ColorRetentionResult?
        let colorTemperature:ColorTemperatureResult?
        let whiteBalanceEvaluation:WhiteBalanceEvaluationResult?
        let scannerWhiteDiagnostics:ScannerWhiteAttemptDiagnostics?
    }

    /// Transient attempt data retained until the privacy-safe diagnostic line
    /// is written. It deliberately contains no image or recognized text.
    struct ScannerWhiteAttemptDiagnostics {
        let primaryMode:PaperNormalizationSurfaceMode
        let primaryCandidateBuildProcessingMilliseconds:Int
        let primaryTextMaskRasterizationMilliseconds:Int
        let primaryColorRetention:ColorRetentionResult
        let primaryColorRetentionProcessingMilliseconds:Int
        let primaryPaperEvaluation:PaperNormalizationEvaluationResult?
        let primaryPaperNormalizationProcessingMilliseconds:Int
        let primaryWhiteBalanceEvaluation:WhiteBalanceEvaluationResult
        let primaryStructureEvaluation:WhiteBalanceStructureSafetyResult?
        let primaryStructureProcessingMilliseconds:Int?
        let fallbackMode:PaperNormalizationSurfaceMode?
        let fallbackCandidateBuildProcessingMilliseconds:Int?
        let fallbackTextMaskRasterizationMilliseconds:Int?
        let fallbackColorRetention:ColorRetentionResult?
        let fallbackColorRetentionProcessingMilliseconds:Int?
        let fallbackPaperEvaluation:PaperNormalizationEvaluationResult?
        let fallbackPaperNormalizationProcessingMilliseconds:Int?
        let fallbackWhiteBalanceEvaluation:WhiteBalanceEvaluationResult?
        let fallbackStructureEvaluation:WhiteBalanceStructureSafetyResult?
        let fallbackStructureProcessingMilliseconds:Int?
        let selectedMode:PaperNormalizationSurfaceMode?
    }

    static func process(
        rgbImage:UIImage,
        pageNumber:Int,
        baselineSeed:SmartEnhancementSeed? = nil,
        captureCorners:ScanCorners? = nil,
        allowsSemanticRotation:Bool = true,
        completion:@escaping (SmartEnhancementOutput)->Void
    ) {
        let startedAt = Date()
        let reusableContentPreflight = allowsSemanticRotation
            ? baselineSeed.flatMap { seed in
                seed.isCompatible(with:rgbImage)
                    ? seed.contentPreflight : nil
            }
            : nil
        let contentOutput = reusableContentPreflight.map {
            DocumentContentPreflightOutput(
                image:rgbImage,
                result:$0,
                rotationQuarterTurns:0
            )
        } ?? DocumentContentPreflightAnalyzer.analyzeAndOrient(
            image:rgbImage,
            pageNumber:pageNumber,
            allowsRotation:allowsSemanticRotation
        )
        let sourceImage = contentOutput.image
        let contentPreflight = contentOutput.result
        let effectiveCaptureCorners = captureCorners.map {
            DocumentContentPreflightAnalyzer.rotated(
                $0,
                clockwiseQuarterTurns:contentOutput.rotationQuarterTurns
            )
        }
        let naturalSmart = DocumentImageFilter.apply(
            .smart,
            to:sourceImage
        )
        let preliminaryColorTemperature = ColorTemperatureAnalyzer.analyze(
            image:naturalSmart
        )
        let baselineStartedAt = Date()
        let baselineVisualPreflight = BaselineVisualPreflightAnalyzer
            .analyze(
                image:naturalSmart,
                captureCorners:effectiveCaptureCorners,
                precomputedTextRectangles:
                    contentPreflight.blocks.map(\.boundingBox)
            )
        let preparedBaseline = prepareSmartBaseline(
            naturalSmart:naturalSmart,
            colorTemperature:preliminaryColorTemperature,
            visual:baselineVisualPreflight,
            contentPreflight:contentPreflight
        )
        let originalSmart = preparedBaseline.image

        // Scanner-white is now the final production path for eligible paper.
        // Its paper, edge, color and non-paper safety gates already decide
        // whether the normalized image or the natural Smart image is kept.
        // The former quality OCR never compared those two images and could not
        // reverse that decision; it only reopened legacy candidates afterward.
        if preparedBaseline.scannerWhiteAttempted {
            finishScannerWhiteFastPath(
                preparedBaseline:preparedBaseline,
                naturalSmart:naturalSmart,
                preliminaryColorTemperature:preliminaryColorTemperature,
                visual:baselineVisualPreflight,
                baselineStartedAt:baselineStartedAt,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        // A seed produced from the natural Smart image cannot describe the
        // scanner-white pixels. Reuse it only when the baseline stayed natural.
        if !preparedBaseline.scannerWhiteApplied,
           let baselineSeed,
           baselineSeed.isCompatible(with:sourceImage),
           let seededOCR = baselineSeed.ocrResult,
           let seededQuality = baselineSeed.quality {
            beginExperiment(
                rawOriginalOCR:seededOCR,
                originalQuality:seededQuality,
                originalSmart:originalSmart,
                rgbSource:sourceImage,
                pageNumber:pageNumber,
                baselineStartedAt:baselineStartedAt,
                reusedBaselineOCR:true,
                baselineVisualPreflight:baselineVisualPreflight,
                scannerWhiteApplied:false,
                baselineColorRetention:
                    preparedBaseline.colorRetention,
                baselineWhiteBalanceEvaluation:
                    preparedBaseline.whiteBalanceEvaluation,
                startedAt:startedAt,
                completion:completion
            )
            return
        }
        let visuallyNeedsPaperNormalization = preliminaryColorTemperature
            .map { temperature in
                DocumentPaperNormalizer.isEligible(temperature)
                    && (
                        DocumentPaperNormalizer.needsNormalization(temperature)
                            || baselineVisualPreflight
                                .illuminationGradient >= 0.025
                            || min(
                                baselineVisualPreflight.topBrightness,
                                baselineVisualPreflight.middleBrightness,
                                baselineVisualPreflight.bottomBrightness
                            ) < 0.965
                    )
            } ?? false
        if baselineVisualPreflight.shouldSkipOCR,
           !hasStrictColorTemperatureEvidence(
                preliminaryColorTemperature
           ),
           !visuallyNeedsPaperNormalization {
            deliver(
                image:originalSmart,
                ocrResult:nil,
                originalQuality:nil,
                enhancedQuality:nil,
                decision:SmartEnhancementEvaluator().keepOriginal(
                    reason:"OCR前视觉质量明确正常，直接保留基础智能版本"
                ),
                selectedVariant:.baseline,
                trialSummaries:[],
                qualityRoute:.excellentDirect,
                documentQualityRoute:.none(
                    "OCR前视觉质量明确正常，无需运行质量评估OCR"
                ),
                earlyStopReason:baselineVisualPreflight.reason,
                executedCandidateCount:0,
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:false,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        LocalTextRecognizer.recognize(
            image:downscaledForEvaluation(originalSmart),
            pageNumber:pageNumber,
            background:true,
            profile:.qualityEvaluation
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
                    baselineVisualPreflight:baselineVisualPreflight,
                    baselineOCRPerformed:true,
                    startedAt:startedAt,
                    pageNumber:pageNumber,
                    completion:completion
                )

            case .success(let rawOriginalOCR):
                beginExperiment(
                    rawOriginalOCR:rawOriginalOCR,
                    originalQuality:nil,
                    originalSmart:originalSmart,
                    rgbSource:sourceImage,
                    pageNumber:pageNumber,
                    baselineStartedAt:baselineStartedAt,
                    reusedBaselineOCR:false,
                    baselineVisualPreflight:baselineVisualPreflight,
                    scannerWhiteApplied:
                        preparedBaseline.scannerWhiteApplied,
                    baselineColorRetention:
                        preparedBaseline.colorRetention,
                    baselineWhiteBalanceEvaluation:
                        preparedBaseline.whiteBalanceEvaluation,
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
        baselineVisualPreflight:BaselineVisualPreflightResult? = nil,
        scannerWhiteApplied:Bool = false,
        baselineColorRetention:ColorRetentionResult? = nil,
        baselineWhiteBalanceEvaluation:WhiteBalanceEvaluationResult? = nil,
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
        let baselineColorTemperature = ColorTemperatureAnalyzer.analyze(
            image:originalSmart,
            blocks:originalOCR.blocks
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
            colorRetention:baselineColorRetention ?? .identity,
            documentQuality:originalDocumentQuality,
            colorTemperature:baselineColorTemperature,
            whiteBalanceEvaluation:baselineWhiteBalanceEvaluation,
            reusedBaselineOCR:reusedBaselineOCR,
            preflight:nil,
            secondOCRPerformed:false,
            selected:false
        )
        let baselineDecision = SmartEnhancementEvaluator()
            .keepOriginal(
                reason:scannerWhiteApplied
                    ? "智能模式采用高置信度扫描白底基线"
                    : "A/B测试保留原始智能版本"
            )
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
        let routedDocumentQuality = DocumentQualityRouter.route(
            quality:originalDocumentQuality,
            ocrQuality:originalQuality,
            blocks:originalOCR.blocks,
            colorTemperature:baselineColorTemperature
        )
        let documentRoute = scannerWhiteApplied
            && routedDocumentQuality.primaryIssue == .colorTemperature
            ? .none("智能模式已应用高置信度扫描白底基线")
            : routedDocumentQuality
        let candidates = SmartEnhancementExperiment.candidates(
            for:documentRoute
        )
        let baselineProcessingMilliseconds = baselineSummary
            .processingMilliseconds

        // Once the baseline quality OCR has already consumed the page budget,
        // another image candidate cannot improve perceived latency. Preserve
        // the safe baseline and, crucially, never start a duplicate OCR pass.
        if !reusedBaselineOCR,
           baselineProcessingMilliseconds
                >= maximumBaselineMillisecondsBeforeCandidate,
           !candidates.isEmpty {
            finishExperiment(
                selected:baselineSelection,
                originalQuality:originalQuality,
                summaries:[baselineSummary],
                qualityRoute:route,
                documentQualityRoute:documentRoute,
                earlyStopReason:
                    "基准OCR已达单帧时间预算，跳过候选生成和重复OCR",
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:true,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        // Dense pages still avoid a second Vision OCR pass. When a concrete
        // lighting route exists, however, allow one cheap candidate through
        // visual, structure and color safety gates instead of skipping the
        // shadow correction completely.
        if originalQuality.recognizedCharacterCount
                >= denseCharacterThreshold,
           candidates.isEmpty {
            finishExperiment(
                selected:baselineSelection,
                originalQuality:originalQuality,
                summaries:[baselineSummary],
                qualityRoute:route,
                documentQualityRoute:documentRoute,
                earlyStopReason:"密集文字页面启用快速生产路径，跳过重复OCR",
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:!reusedBaselineOCR,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        guard !candidates.isEmpty else {
            let reason = documentRoute.reason
            finishExperiment(
                selected:baselineSelection,
                originalQuality:originalQuality,
                summaries:[baselineSummary],
                qualityRoute:route,
                documentQualityRoute:documentRoute,
                earlyStopReason:reason,
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:!reusedBaselineOCR,
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
            baselineColorTemperature:baselineColorTemperature,
            pageNumber:pageNumber,
            summaries:[baselineSummary],
            selected:baselineSelection,
            baselineVisualPreflight:baselineVisualPreflight,
            baselineOCRPerformed:!reusedBaselineOCR,
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
        baselineColorTemperature:ColorTemperatureResult?,
        pageNumber:Int,
        summaries:[EnhancementTrialSummary],
        selected:SelectedCandidate,
        baselineVisualPreflight:BaselineVisualPreflightResult?,
        baselineOCRPerformed:Bool,
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
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:baselineOCRPerformed,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        let candidate = candidates[index]
        let candidateStartedAt = Date()
        let previewBlocks = SmartEnhancementCandidateBuilder.preflightBlocks(
            originalOCR.blocks
        )
        let directionalBaseline = SmartEnhancementCandidateBuilder.previewImage(
            baselineImage,
            maximumPixelSize:directionalPreviewPixelSize
        )
        let directionalBuildStartedAt = Date()
        let directionalCandidate = buildCandidate(
            candidate,
            rgbSource:directionalBaseline,
            baselineImage:directionalBaseline,
            blocks:previewBlocks,
            route:documentQualityRoute,
            colorTemperature:baselineColorTemperature
        )
        let directionalBuildMilliseconds = milliseconds(
            since:directionalBuildStartedAt
        )
        var directionalEvaluation = evaluateCandidateVisuals(
            candidate:directionalCandidate,
            baselineReference:directionalBaseline,
            blocks:previewBlocks,
            route:documentQualityRoute,
            baselineColorTemperature:baselineColorTemperature,
            recognizedCharacterCount:originalQuality.recognizedCharacterCount,
            stage:.directionalPreview,
            candidateBuildMilliseconds:directionalBuildMilliseconds
        )
        if milliseconds(since:candidateStartedAt)
            > maximumPreviewMilliseconds {
            directionalEvaluation = CandidateVisualEvaluation(
                colorRetention:directionalEvaluation.colorRetention,
                colorTemperature:directionalEvaluation.colorTemperature,
                whiteBalanceEvaluation:
                    directionalEvaluation.whiteBalanceEvaluation,
                paperNormalizationEvaluation:
                    directionalEvaluation.paperNormalizationEvaluation,
                currentColorRetentionMilliseconds:
                    directionalEvaluation.currentColorRetentionMilliseconds,
                currentColorTemperatureMilliseconds:
                    directionalEvaluation.currentColorTemperatureMilliseconds,
                currentPaperNormalizationMilliseconds:
                    directionalEvaluation
                        .currentPaperNormalizationMilliseconds,
                preflight:directionalEvaluation.preflight.stopping(
                    reason:"一级预检超过候选时间预算，停止后续处理",
                    budgetExceeded:true
                )
            )
        }

        guard directionalEvaluation.preflight.shouldRunOCR else {
            var updatedSummaries = summaries
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
                    colorRetention:directionalColorRetentionForDiagnostics(
                        directionalEvaluation,
                        route:documentQualityRoute
                    ),
                    documentQuality:nil,
                    colorTemperature:directionalEvaluation.colorTemperature,
                    whiteBalanceEvaluation:
                        directionalEvaluation.whiteBalanceEvaluation,
                    reusedBaselineOCR:false,
                    preflight:directionalEvaluation.preflight,
                    secondOCRPerformed:false,
                    selected:false
                )
            )
            if let fallbackRoute = whiteBalanceFallbackRoute(
                after:directionalEvaluation.preflight,
                route:documentQualityRoute,
                originalDocumentQuality:originalDocumentQuality,
                baselineColorTemperature:baselineColorTemperature,
                recognizedCharacterCount:
                    originalQuality.recognizedCharacterCount,
                startedAt:startedAt
            ) {
                testCandidate(
                    at:0,
                    candidates:[
                        EnhancementExperimentCandidate(
                            variant:.whiteBalance,
                            parameters:.baseline
                        )
                    ],
                    qualityRoute:qualityRoute,
                    documentQualityRoute:fallbackRoute,
                    rgbSource:rgbSource,
                    baselineImage:baselineImage,
                    originalOCR:originalOCR,
                    originalQuality:originalQuality,
                    originalDocumentQuality:originalDocumentQuality,
                    baselineColorTemperature:baselineColorTemperature,
                    pageNumber:pageNumber,
                    summaries:updatedSummaries,
                    selected:selected,
                    baselineVisualPreflight:baselineVisualPreflight,
                    baselineOCRPerformed:baselineOCRPerformed,
                    startedAt:startedAt,
                    completion:completion
                )
                return
            }
            finishExperiment(
                selected:selected,
                originalQuality:originalQuality,
                summaries:updatedSummaries,
                qualityRoute:qualityRoute,
                documentQualityRoute:documentQualityRoute,
                earlyStopReason:
                    "一级方向预检：\(directionalEvaluation.preflight.reason)",
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:baselineOCRPerformed,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        let structuralBaseline = SmartEnhancementCandidateBuilder.previewImage(
            baselineImage,
            maximumPixelSize:structuralPreviewPixelSize
        )
        let structuralBuildStartedAt = Date()
        let structuralCandidate = buildCandidate(
            candidate,
            rgbSource:structuralBaseline,
            baselineImage:structuralBaseline,
            blocks:previewBlocks,
            route:documentQualityRoute,
            colorTemperature:baselineColorTemperature
        )
        let accumulatedBuildMilliseconds = directionalBuildMilliseconds
            + milliseconds(since:structuralBuildStartedAt)
        var structuralEvaluation = evaluateCandidateVisuals(
            candidate:structuralCandidate,
            baselineReference:structuralBaseline,
            blocks:previewBlocks,
            route:documentQualityRoute,
            baselineColorTemperature:baselineColorTemperature,
            recognizedCharacterCount:originalQuality.recognizedCharacterCount,
            stage:.structuralPreview,
            candidateBuildMilliseconds:accumulatedBuildMilliseconds,
            previousPreflight:directionalEvaluation.preflight
        )
        if milliseconds(since:candidateStartedAt)
            > maximumPreviewMilliseconds {
            structuralEvaluation = CandidateVisualEvaluation(
                colorRetention:structuralEvaluation.colorRetention,
                colorTemperature:structuralEvaluation.colorTemperature,
                whiteBalanceEvaluation:
                    structuralEvaluation.whiteBalanceEvaluation,
                paperNormalizationEvaluation:
                    structuralEvaluation.paperNormalizationEvaluation,
                currentColorRetentionMilliseconds:
                    structuralEvaluation.currentColorRetentionMilliseconds,
                currentColorTemperatureMilliseconds:
                    structuralEvaluation.currentColorTemperatureMilliseconds,
                currentPaperNormalizationMilliseconds:
                    structuralEvaluation
                        .currentPaperNormalizationMilliseconds,
                preflight:structuralEvaluation.preflight.stopping(
                    reason:"结构预检超过候选时间预算，停止全分辨率处理",
                    budgetExceeded:true
                )
            )
        }
        guard structuralEvaluation.preflight.shouldRunOCR else {
            var updatedSummaries = summaries
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
                    colorRetention:structuralEvaluation.colorRetention,
                    documentQuality:nil,
                    colorTemperature:structuralEvaluation.colorTemperature,
                    whiteBalanceEvaluation:
                        structuralEvaluation.whiteBalanceEvaluation,
                    reusedBaselineOCR:false,
                    preflight:structuralEvaluation.preflight,
                    secondOCRPerformed:false,
                    selected:false
                )
            )
            finishExperiment(
                selected:selected,
                originalQuality:originalQuality,
                summaries:updatedSummaries,
                qualityRoute:qualityRoute,
                documentQualityRoute:documentQualityRoute,
                earlyStopReason:
                    "二级结构预检：\(structuralEvaluation.preflight.reason)",
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:baselineOCRPerformed,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        let fullResolutionDeadline = documentQualityRoute.primaryIssue
            == .colorTemperature
            ? maximumElapsedMillisecondsBeforeFullWhiteBalance
            : maximumElapsedMillisecondsBeforeSecondOCR
        if milliseconds(since:startedAt) >= fullResolutionDeadline {
            var updatedSummaries = summaries
            let budgetPreflight = structuralEvaluation.preflight.stopping(
                reason:documentQualityRoute.primaryIssue == .colorTemperature
                    ? "白平衡收尾剩余时间不足800ms，停止全分辨率候选"
                    : "单帧总时间已达预算，停止全分辨率候选",
                budgetExceeded:true
            )
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
                    colorRetention:structuralEvaluation.colorRetention,
                    documentQuality:nil,
                    colorTemperature:structuralEvaluation.colorTemperature,
                    whiteBalanceEvaluation:
                        structuralEvaluation.whiteBalanceEvaluation,
                    reusedBaselineOCR:false,
                    preflight:budgetPreflight,
                    secondOCRPerformed:false,
                    selected:false
                )
            )
            finishExperiment(
                selected:selected,
                originalQuality:originalQuality,
                summaries:updatedSummaries,
                qualityRoute:qualityRoute,
                documentQualityRoute:documentQualityRoute,
                earlyStopReason:budgetPreflight.reason,
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:baselineOCRPerformed,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        let candidateImage:UIImage
        let visualEvaluation:CandidateVisualEvaluation
        if samePixelSize(structuralBaseline, baselineImage) {
            candidateImage = structuralCandidate
            visualEvaluation = structuralEvaluation
        }
        else {
            let fullBuildStartedAt = Date()
            candidateImage = buildCandidate(
                candidate,
                rgbSource:rgbSource,
                baselineImage:baselineImage,
                blocks:previewBlocks,
                route:documentQualityRoute,
                colorTemperature:baselineColorTemperature
            )
            let fullBuildMilliseconds = milliseconds(
                since:fullBuildStartedAt
            )
            visualEvaluation = evaluateCandidateVisuals(
                candidate:candidateImage,
                baselineReference:baselineImage,
                blocks:previewBlocks,
                route:documentQualityRoute,
                baselineColorTemperature:baselineColorTemperature,
                recognizedCharacterCount:
                    originalQuality.recognizedCharacterCount,
                stage:.fullResolution,
                candidateBuildMilliseconds:
                    accumulatedBuildMilliseconds + fullBuildMilliseconds,
                reusingWhiteBalanceSafety:structuralEvaluation,
                previousPreflight:structuralEvaluation.preflight
            )
        }
        let colorRetention = visualEvaluation.colorRetention
        let candidateColorTemperature = visualEvaluation.colorTemperature
        let whiteBalanceEvaluation = visualEvaluation.whiteBalanceEvaluation
        var preflight = visualEvaluation.preflight
        if documentQualityRoute.primaryIssue == .colorTemperature,
           milliseconds(since:startedAt)
            >= maximumElapsedMillisecondsBeforeSecondOCR {
            preflight = preflight.stopping(
                reason:"白平衡与纸张标准化已达3500ms硬性预算，保留基础版本",
                budgetExceeded:true
            )
        }

        guard preflight.shouldRunOCR else {
            var updatedSummaries = summaries
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
                    colorTemperature:candidateColorTemperature,
                    whiteBalanceEvaluation:whiteBalanceEvaluation,
                    reusedBaselineOCR:false,
                    preflight:preflight,
                    secondOCRPerformed:false,
                    selected:false
                )
            )
            finishExperiment(
                selected:selected,
                originalQuality:originalQuality,
                summaries:updatedSummaries,
                qualityRoute:qualityRoute,
                documentQualityRoute:documentQualityRoute,
                earlyStopReason:"全分辨率复检：\(preflight.reason)",
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:baselineOCRPerformed,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        let shouldRunSecondOCR = shouldPerformSecondOCR(
            originalQuality:originalQuality,
            preflight:preflight,
            route:documentQualityRoute,
            startedAt:startedAt
        )
        if !shouldRunSecondOCR {
            // White balance and paper normalization already passed the 960px
            // brightness, color and structure gates, which are reused at full
            // resolution. Re-running the generic document analyzer here cost
            // 0.6-1.5 seconds in real logs without changing the decision.
            let reusesBaselineDocumentQuality = documentQualityRoute
                .primaryIssue == .colorTemperature
            let candidateDocumentQuality = reusesBaselineDocumentQuality
                ? originalDocumentQuality
                : DocumentQualityAnalyzer.analyze(
                    image:candidateImage,
                    blocks:previewBlocks,
                    ocrQuality:originalQuality,
                    characterStability:1,
                    colorRetention:colorRetention
                )
            let canSelect:Bool
            switch documentQualityRoute.primaryIssue {
            case .lighting, .background:
                canSelect = canSelectVisualLightingCandidate(
                    preflight:preflight,
                    route:documentQualityRoute,
                    baseline:originalDocumentQuality,
                    colorRetention:colorRetention
                )
            case .colorTemperature:
                canSelect = canSelectVisualWhiteBalanceCandidate(
                    preflight:preflight,
                    evaluation:whiteBalanceEvaluation,
                    colorRetention:colorRetention
                )
            case .none, .regionalSharpness, .perspective:
                canSelect = false
            }
            let isDense = originalQuality.recognizedCharacterCount
                >= denseCharacterThreshold
            let acceptedReason:String
            if documentQualityRoute.primaryIssue == .colorTemperature {
                acceptedReason = "白平衡与纸张标准化候选通过提白、结构与保色门槛"
            }
            else if isDense {
                acceptedReason = "密集文字页通过去阴影、文字结构与保色门槛"
            }
            else {
                acceptedReason = "候选通过严格视觉安全门槛，跳过重复OCR"
            }
            let decision = canSelect
                ? SmartEnhancementDecision(
                    selectedVariant:.textAware,
                    shouldReplaceImage:true,
                    reason:acceptedReason,
                    confidenceGain:0,
                    characterRetention:1,
                    coverageRetention:1,
                    scoreGain:candidateDocumentQuality.totalScore
                        - originalDocumentQuality.totalScore
                )
                : SmartEnhancementEvaluator().keepOriginal(
                    reason:"候选未达到无重复OCR的严格视觉门槛"
                )
            let visualSelection = canSelect
                ? SelectedCandidate(
                    variant:candidate.variant,
                    image:candidateImage,
                    ocrResult:originalOCR,
                    quality:originalQuality,
                    documentQuality:candidateDocumentQuality,
                    decision:decision,
                    rankingScore:SmartEnhancementExperiment.rankingScore(
                        quality:originalQuality,
                        stability:1,
                        colorRetention:colorRetention.overallRetention,
                        documentQuality:candidateDocumentQuality
                    )
                )
                : selected
            var updatedSummaries = summaries
            updatedSummaries.append(
                EnhancementTrialSummary(
                    variant:candidate.variant,
                    parameters:candidate.parameters,
                    weightedConfidence:originalQuality.weightedConfidence,
                    recognizedCharacterCount:
                        originalQuality.recognizedCharacterCount,
                    characterStability:1,
                    textCoverage:originalQuality.textCoverage,
                    processingMilliseconds:milliseconds(
                        since:candidateStartedAt
                    ),
                    evaluatorAccepted:canSelect,
                    colorRetention:colorRetention,
                    documentQuality:candidateDocumentQuality,
                    colorTemperature:candidateColorTemperature,
                    whiteBalanceEvaluation:whiteBalanceEvaluation,
                    reusedBaselineOCR:true,
                    preflight:preflight,
                    secondOCRPerformed:false,
                    selected:false
                )
            )
            finishExperiment(
                selected:visualSelection,
                originalQuality:originalQuality,
                summaries:updatedSummaries,
                qualityRoute:qualityRoute,
                documentQualityRoute:documentQualityRoute,
                earlyStopReason:canSelect
                    ? "候选采用严格视觉验证，跳过重复OCR"
                    : "候选视觉收益不足，跳过重复OCR",
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:baselineOCRPerformed,
                startedAt:startedAt,
                pageNumber:pageNumber,
                completion:completion
            )
            return
        }

        LocalTextRecognizer.recognize(
            image:downscaledForEvaluation(candidateImage),
            pageNumber:pageNumber,
            background:true,
            profile:.qualityEvaluation
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
                        colorTemperature:candidateColorTemperature,
                        whiteBalanceEvaluation:whiteBalanceEvaluation,
                        reusedBaselineOCR:false,
                        preflight:preflight,
                        secondOCRPerformed:true,
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
                        route:documentQualityRoute,
                        whiteBalanceEvaluation:whiteBalanceEvaluation
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

                let rankingAllowsSelection = documentQualityRoute.primaryIssue
                    == .colorTemperature
                    ? score >= selected.rankingScore - 0.002
                    : score > selected.rankingScore + 0.0005
                if canSelect,
                   rankingAllowsSelection {
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
                        colorTemperature:candidateColorTemperature,
                        whiteBalanceEvaluation:whiteBalanceEvaluation,
                        reusedBaselineOCR:false,
                        preflight:preflight,
                        secondOCRPerformed:true,
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
                baselineVisualPreflight:baselineVisualPreflight,
                baselineOCRPerformed:baselineOCRPerformed,
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
        baselineVisualPreflight:BaselineVisualPreflightResult?,
        baselineOCRPerformed:Bool,
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
            decision = selected.decision
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
            baselineVisualPreflight:baselineVisualPreflight,
            baselineOCRPerformed:baselineOCRPerformed,
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
        baselineVisualPreflight:BaselineVisualPreflightResult? = nil,
        baselineOCRPerformed:Bool = true,
        scannerWhiteDiagnostics:ScannerWhiteAttemptDiagnostics? = nil,
        additionalEstimatedMillisecondsSaved:Int = 0,
        startedAt:Date,
        pageNumber:Int,
        completion:@escaping (SmartEnhancementOutput)->Void
    ) {
        let densePageEstimatedSavings:Int
        if earlyStopReason?.contains("密集文字页") == true,
           let recognizedCharacterCount = originalQuality?
                .recognizedCharacterCount {
            densePageEstimatedSavings = min(
                max(900 + recognizedCharacterCount * 8, 1_200),
                12_000
            )
        }
        else {
            densePageEstimatedSavings = 0
        }
        let candidateEstimatedSavings = trialSummaries.compactMap {
            $0.preflight?.estimatedMillisecondsSaved
        }.reduce(0, +)
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
                SmartEnhancementExperiment.candidates(
                    for:documentQualityRoute
                ).count
                    - executedCandidateCount,
                0
            ),
            documentQualityRoute:documentQualityRoute,
            preflightSkippedOCRCount:trialSummaries.filter {
                $0.preflight != nil && !$0.secondOCRPerformed
            }.count,
            estimatedMillisecondsSaved:max(
                candidateEstimatedSavings,
                densePageEstimatedSavings
            )
                + (baselineVisualPreflight?.estimatedMillisecondsSaved ?? 0)
                + additionalEstimatedMillisecondsSaved,
            baselineVisualPreflight:baselineVisualPreflight,
            baselineOCRPerformed:baselineOCRPerformed
        )

        DispatchQueue.main.async {
            SmartEnhancementDiagnostics.record(
                output:output,
                pageNumber:pageNumber,
                scannerWhiteDiagnostics:scannerWhiteDiagnostics
            )
            completion(output)
        }
    }

    private static func supportsVisualLightingValidation(
        _ route:DocumentQualityRoute
    )->Bool {
        route.primaryIssue == .lighting
            || route.primaryIssue == .background
    }

    private struct CandidateVisualEvaluation {
        let colorRetention:ColorRetentionResult
        let colorTemperature:ColorTemperatureResult?
        let whiteBalanceEvaluation:WhiteBalanceEvaluationResult?
        let paperNormalizationEvaluation:
            PaperNormalizationEvaluationResult?
        let currentColorRetentionMilliseconds:Int
        let currentColorTemperatureMilliseconds:Int
        let currentPaperNormalizationMilliseconds:Int
        let preflight:EnhancementPreflightResult
    }

    private static func buildCandidate(
        _ candidate:EnhancementExperimentCandidate,
        rgbSource:UIImage,
        baselineImage:UIImage,
        blocks:[OCRBlock],
        route:DocumentQualityRoute,
        colorTemperature:ColorTemperatureResult?
    )->UIImage {
        switch candidate.variant {
        case .baseline:
            return baselineImage
        case .smartColorMedium, .smartColorStrong, .whiteBalance:
            return SmartEnhancementCandidateBuilder.build(
                rgbSource:rgbSource,
                baselineImage:baselineImage,
                blocks:blocks,
                parameters:candidate.parameters,
                route:route,
                colorTemperature:colorTemperature
            )
        }
    }

    private static func evaluateCandidateVisuals(
        candidate:UIImage,
        baselineReference:UIImage,
        blocks:[OCRBlock],
        route:DocumentQualityRoute,
        baselineColorTemperature:ColorTemperatureResult?,
        recognizedCharacterCount:Int,
        stage:EnhancementPreflightStage,
        candidateBuildMilliseconds:Int,
        reusingWhiteBalanceSafety:CandidateVisualEvaluation? = nil,
        previousPreflight:EnhancementPreflightResult? = nil
    )->CandidateVisualEvaluation {
        // Measure only changes introduced by this candidate. The accepted
        // smart image, at the same resolution, is the color reference.
        let directionOnlyLighting = stage == .directionalPreview
            && (route.primaryIssue == .lighting
                || route.primaryIssue == .background)
        let canReuseWhiteBalanceSafety = stage == .fullResolution
            && route.primaryIssue == .colorTemperature
            && reusingWhiteBalanceSafety != nil
        let colorStartedAt = Date()
        let colorRetention:ColorRetentionResult
        if canReuseWhiteBalanceSafety,
           let reused = reusingWhiteBalanceSafety?.colorRetention {
            colorRetention = reused
        }
        else if directionOnlyLighting {
            colorRetention = .identity
        }
        else {
            colorRetention = ColorRetentionAnalyzer.analyze(
                original:baselineReference,
                candidate:candidate,
                ignoringLightLowSaturationPaper:
                    route.primaryIssue == .colorTemperature
            )
        }
        let colorRetentionMilliseconds = directionOnlyLighting
            || canReuseWhiteBalanceSafety
            ? 0 : milliseconds(since:colorStartedAt)
        let temperatureStartedAt = Date()
        let candidateColorTemperature:ColorTemperatureResult?
        if canReuseWhiteBalanceSafety {
            candidateColorTemperature = reusingWhiteBalanceSafety?
                .colorTemperature
        }
        else if route.primaryIssue == .colorTemperature {
            candidateColorTemperature = ColorTemperatureAnalyzer.analyze(
                image:candidate,
                blocks:blocks
            )
        }
        else {
            candidateColorTemperature = nil
        }
        let colorTemperatureMilliseconds = route.primaryIssue
            == .colorTemperature && !canReuseWhiteBalanceSafety
            ? milliseconds(since:temperatureStartedAt) : 0
        let whiteBalanceEvaluation:WhiteBalanceEvaluationResult?
        let paperNormalizationEvaluation:
            PaperNormalizationEvaluationResult?
        if canReuseWhiteBalanceSafety {
            paperNormalizationEvaluation = reusingWhiteBalanceSafety?
                .paperNormalizationEvaluation
            whiteBalanceEvaluation = reusingWhiteBalanceSafety?
                .whiteBalanceEvaluation
        }
        else if route.primaryIssue == .colorTemperature,
           let baselineColorTemperature {
            paperNormalizationEvaluation = DocumentPaperNormalizer.evaluate(
                baseline:baselineReference,
                candidate:candidate,
                blocks:blocks,
                originalAnalysis:baselineColorTemperature,
                candidateAnalysis:candidateColorTemperature
            )
            whiteBalanceEvaluation = WhiteBalanceCandidateEvaluator.evaluate(
                candidateTemperature:candidateColorTemperature,
                originalTemperature:baselineColorTemperature,
                colorRetention:colorRetention,
                paperNormalizationEvaluation:
                    paperNormalizationEvaluation,
                paperSurfaceMode:
                    PaperNormalizationSurfaceMode(
                        rawValue:paperNormalizationEvaluation?.surfaceMode
                            ?? ""
                    )
            )
        }
        else {
            paperNormalizationEvaluation = nil
            whiteBalanceEvaluation = nil
        }
        let paperNormalizationMilliseconds = canReuseWhiteBalanceSafety
            ? 0 : (paperNormalizationEvaluation?
                .processingMilliseconds ?? 0)
        let reusedAnalysisMilliseconds = canReuseWhiteBalanceSafety
            ? (reusingWhiteBalanceSafety?
                .currentColorRetentionMilliseconds ?? 0)
                + (reusingWhiteBalanceSafety?
                    .currentColorTemperatureMilliseconds ?? 0)
                + (reusingWhiteBalanceSafety?.preflight
                    .currentIlluminationAnalysisMilliseconds ?? 0)
                + (reusingWhiteBalanceSafety?.preflight
                    .currentStructureAnalysisMilliseconds ?? 0)
                + (reusingWhiteBalanceSafety?
                    .currentPaperNormalizationMilliseconds ?? 0)
            : 0
        let preflight = EnhancementPreflightAnalyzer.analyze(
            candidate:candidate,
            baseline:baselineReference,
            blocks:blocks,
            route:route,
            colorRetention:colorRetention,
            recognizedCharacterCount:recognizedCharacterCount,
            whiteBalanceEvaluation:whiteBalanceEvaluation,
            stage:stage,
            candidateBuildMilliseconds:candidateBuildMilliseconds,
            colorRetentionAnalysisMilliseconds:
                colorRetentionMilliseconds,
            colorTemperatureAnalysisMilliseconds:
                colorTemperatureMilliseconds,
            paperNormalizationAnalysisMilliseconds:
                paperNormalizationMilliseconds,
            analysisReuseMode:canReuseWhiteBalanceSafety
                ? "whiteBalancePaperBrightnessColorTemperatureAndStructure"
                : nil,
            reusedAnalysisMilliseconds:reusedAnalysisMilliseconds,
            previousPreflight:previousPreflight
        )
        return CandidateVisualEvaluation(
            colorRetention:colorRetention,
            colorTemperature:candidateColorTemperature,
            whiteBalanceEvaluation:whiteBalanceEvaluation,
            paperNormalizationEvaluation:
                paperNormalizationEvaluation,
            currentColorRetentionMilliseconds:colorRetentionMilliseconds,
            currentColorTemperatureMilliseconds:
                colorTemperatureMilliseconds,
            currentPaperNormalizationMilliseconds:
                paperNormalizationMilliseconds,
            preflight:preflight
        )
    }

    private static func directionalColorRetentionForDiagnostics(
        _ evaluation:CandidateVisualEvaluation,
        route:DocumentQualityRoute
    )->ColorRetentionResult? {
        route.primaryIssue == .lighting
            || route.primaryIssue == .background
            ? nil : evaluation.colorRetention
    }

    private static func samePixelSize(
        _ first:UIImage,
        _ second:UIImage
    )->Bool {
        let firstWidth = first.cgImage?.width
            ?? Int(first.size.width * first.scale)
        let firstHeight = first.cgImage?.height
            ?? Int(first.size.height * first.scale)
        let secondWidth = second.cgImage?.width
            ?? Int(second.size.width * second.scale)
        let secondHeight = second.cgImage?.height
            ?? Int(second.size.height * second.scale)
        return firstWidth == secondWidth && firstHeight == secondHeight
    }

    private static func prepareSmartBaseline(
        naturalSmart:UIImage,
        colorTemperature:ColorTemperatureResult?,
        visual:BaselineVisualPreflightResult,
        contentPreflight:DocumentContentPreflightResult
    )->PreparedSmartBaseline {
        guard let colorTemperature,
              DocumentPaperNormalizer.shouldUseScannerWhiteBaseline(
                colorTemperature,
                visual:visual
              ) else {
            return PreparedSmartBaseline(
                image:naturalSmart,
                scannerWhiteAttempted:false,
                scannerWhiteApplied:false,
                selectedSurfaceMode:nil,
                colorRetention:nil,
                colorTemperature:colorTemperature,
                whiteBalanceEvaluation:nil,
                scannerWhiteDiagnostics:nil
            )
        }

        let whiteBalanced = DocumentWhiteBalanceEnhancer.enhance(
            image:naturalSmart,
            analysis:colorTemperature
        )
        let primaryMode:PaperNormalizationSurfaceMode =
            contentPreflight.whiteCanvasEligible
                ? .contentAwareWhiteCanvas : .stableLowFrequency
        let scannerWhiteCandidate = DocumentPaperNormalizer.makeCandidate(
            image:whiteBalanced,
            contentImage:primaryMode == .contentAwareWhiteCanvas
                ? naturalSmart : nil,
            blocks:contentPreflight.blocks,
            analysis:colorTemperature,
            mode:primaryMode
        )
        let scannerWhite = scannerWhiteCandidate.image
        let candidateTemperature = ColorTemperatureAnalyzer.analyze(
            image:scannerWhite
        )
        let colorRetentionStartedAt = Date()
        let colorRetention = ColorRetentionAnalyzer.analyze(
            original:naturalSmart,
            candidate:scannerWhite,
            ignoringLightLowSaturationPaper:true,
            protectionMask:primaryMode == .contentAwareWhiteCanvas
                ? scannerWhiteCandidate.protectionMask : nil,
            mode:primaryMode == .contentAwareWhiteCanvas
                ? .scannerWhiteCanvas
                : .ordinary
        )
        let primaryColorRetentionMilliseconds = milliseconds(
            since:colorRetentionStartedAt
        )
        let paperEvaluationStartedAt = Date()
        let paperEvaluation = DocumentPaperNormalizer.evaluate(
            baseline:naturalSmart,
            candidate:scannerWhite,
            blocks:contentPreflight.blocks,
            originalAnalysis:colorTemperature,
            candidateAnalysis:candidateTemperature,
            protectionMask:scannerWhiteCandidate.protectionMask,
            mode:primaryMode
        )
        let primaryPaperNormalizationMilliseconds = milliseconds(
            since:paperEvaluationStartedAt
        )
        let whiteBalanceEvaluation = WhiteBalanceCandidateEvaluator.evaluate(
            candidateTemperature:candidateTemperature,
            originalTemperature:colorTemperature,
            colorRetention:colorRetention,
            paperNormalizationEvaluation:paperEvaluation
            ,
            paperSurfaceMode:
                PaperNormalizationSurfaceMode(
                    rawValue:paperEvaluation?.surfaceMode
                        ?? ""
                )
        )
        let requiresStructureEvaluation = primaryMode
                == .contentAwareWhiteCanvas
            && !contentPreflight.blocks.isEmpty
            && paperEvaluation?.accepted == true
            && whiteBalanceEvaluation.accepted
        let structureEvaluation:WhiteBalanceStructureSafetyResult? =
            requiresStructureEvaluation
            ? WhiteBalanceStructureSafetyAnalyzer.analyze(
                baseline:naturalSmart,
                candidate:scannerWhite,
                blocks:contentPreflight.blocks,
                mode:.scannerWhiteCanvas
            ) : nil
        let structureAccepted = !requiresStructureEvaluation
            || structureEvaluation?.accepted == true
        let accepted = paperEvaluation?.accepted == true
            && whiteBalanceEvaluation.accepted
            && structureAccepted

        if accepted {
            return PreparedSmartBaseline(
                image:scannerWhite,
                scannerWhiteAttempted:true,
                scannerWhiteApplied:
                    primaryMode == .contentAwareWhiteCanvas,
                selectedSurfaceMode:primaryMode,
                colorRetention:colorRetention,
                colorTemperature:candidateTemperature,
                whiteBalanceEvaluation:whiteBalanceEvaluation,
                scannerWhiteDiagnostics:ScannerWhiteAttemptDiagnostics(
                    primaryMode:primaryMode,
                    primaryCandidateBuildProcessingMilliseconds:
                        scannerWhiteCandidate.processingMilliseconds,
                    primaryTextMaskRasterizationMilliseconds:
                        scannerWhiteCandidate
                            .textMaskRasterizationMilliseconds,
                    primaryColorRetention:colorRetention,
                    primaryColorRetentionProcessingMilliseconds:
                        primaryColorRetentionMilliseconds,
                    primaryPaperEvaluation:paperEvaluation,
                    primaryPaperNormalizationProcessingMilliseconds:
                        primaryPaperNormalizationMilliseconds,
                    primaryWhiteBalanceEvaluation:whiteBalanceEvaluation,
                    primaryStructureEvaluation:structureEvaluation,
                    primaryStructureProcessingMilliseconds:
                        structureEvaluation?.processingMilliseconds,
                    fallbackMode:nil,
                    fallbackCandidateBuildProcessingMilliseconds:nil,
                    fallbackTextMaskRasterizationMilliseconds:nil,
                    fallbackColorRetention:nil,
                    fallbackColorRetentionProcessingMilliseconds:nil,
                    fallbackPaperEvaluation:nil,
                    fallbackPaperNormalizationProcessingMilliseconds:nil,
                    fallbackWhiteBalanceEvaluation:nil,
                    fallbackStructureEvaluation:nil,
                    fallbackStructureProcessingMilliseconds:nil,
                    selectedMode:primaryMode
                )
            )
        }

        if primaryMode == .contentAwareWhiteCanvas {
            let stableCandidate = DocumentPaperNormalizer.makeCandidate(
                image:whiteBalanced,
                blocks:contentPreflight.blocks,
                analysis:colorTemperature,
                mode:.stableLowFrequency
            )
            let stableWhite = stableCandidate.image
            let stableTemperature = ColorTemperatureAnalyzer.analyze(
                image:stableWhite
            )
            let stableColorRetentionStartedAt = Date()
            let stableColorRetention = ColorRetentionAnalyzer.analyze(
                original:naturalSmart,
                candidate:stableWhite,
                ignoringLightLowSaturationPaper:true,
                mode:.ordinary
            )
            let stableColorRetentionMilliseconds = milliseconds(
                since:stableColorRetentionStartedAt
            )
            let stablePaperEvaluationStartedAt = Date()
            let stablePaperEvaluation = DocumentPaperNormalizer.evaluate(
                baseline:naturalSmart,
                candidate:stableWhite,
                blocks:contentPreflight.blocks,
                originalAnalysis:colorTemperature,
                candidateAnalysis:stableTemperature,
                protectionMask:stableCandidate.protectionMask,
                mode:.stableLowFrequency
            )
            let stablePaperNormalizationMilliseconds = milliseconds(
                since:stablePaperEvaluationStartedAt
            )
            let stableWhiteBalanceEvaluation =
                WhiteBalanceCandidateEvaluator.evaluate(
                    candidateTemperature:stableTemperature,
                    originalTemperature:colorTemperature,
                    colorRetention:stableColorRetention,
                    paperNormalizationEvaluation:stablePaperEvaluation,
                    paperSurfaceMode:
                        PaperNormalizationSurfaceMode(
                            rawValue:stablePaperEvaluation?.surfaceMode
                                ?? ""
                        )
                )
            let stableAccepted = stablePaperEvaluation?.accepted == true
                && stableWhiteBalanceEvaluation.accepted
            let selectedMode:PaperNormalizationSurfaceMode? = stableAccepted
                ? .stableLowFrequency : nil
            return PreparedSmartBaseline(
                image:stableAccepted ? stableWhite : naturalSmart,
                scannerWhiteAttempted:true,
                scannerWhiteApplied:false,
                selectedSurfaceMode:selectedMode,
                colorRetention:stableAccepted
                    ? stableColorRetention : colorRetention,
                colorTemperature:stableAccepted
                    ? stableTemperature : colorTemperature,
                whiteBalanceEvaluation:stableAccepted
                    ? stableWhiteBalanceEvaluation : whiteBalanceEvaluation,
                scannerWhiteDiagnostics:ScannerWhiteAttemptDiagnostics(
                    primaryMode:primaryMode,
                    primaryCandidateBuildProcessingMilliseconds:
                        scannerWhiteCandidate.processingMilliseconds,
                    primaryTextMaskRasterizationMilliseconds:
                        scannerWhiteCandidate
                            .textMaskRasterizationMilliseconds,
                    primaryColorRetention:colorRetention,
                    primaryColorRetentionProcessingMilliseconds:
                        primaryColorRetentionMilliseconds,
                    primaryPaperEvaluation:paperEvaluation,
                    primaryPaperNormalizationProcessingMilliseconds:
                        primaryPaperNormalizationMilliseconds,
                    primaryWhiteBalanceEvaluation:whiteBalanceEvaluation,
                    primaryStructureEvaluation:structureEvaluation,
                    primaryStructureProcessingMilliseconds:
                        structureEvaluation?.processingMilliseconds,
                    fallbackMode:.stableLowFrequency,
                    fallbackCandidateBuildProcessingMilliseconds:
                        stableCandidate.processingMilliseconds,
                    fallbackTextMaskRasterizationMilliseconds:
                        stableCandidate.textMaskRasterizationMilliseconds,
                    fallbackColorRetention:stableColorRetention,
                    fallbackColorRetentionProcessingMilliseconds:
                        stableColorRetentionMilliseconds,
                    fallbackPaperEvaluation:stablePaperEvaluation,
                    fallbackPaperNormalizationProcessingMilliseconds:
                        stablePaperNormalizationMilliseconds,
                    fallbackWhiteBalanceEvaluation:
                        stableWhiteBalanceEvaluation,
                    fallbackStructureEvaluation:nil,
                    fallbackStructureProcessingMilliseconds:nil,
                    selectedMode:selectedMode
                )
            )
        }

        return PreparedSmartBaseline(
            image:naturalSmart,
            scannerWhiteAttempted:true,
            scannerWhiteApplied:false,
            selectedSurfaceMode:nil,
            colorRetention:colorRetention,
            colorTemperature:colorTemperature,
            whiteBalanceEvaluation:whiteBalanceEvaluation,
            scannerWhiteDiagnostics:ScannerWhiteAttemptDiagnostics(
                primaryMode:primaryMode,
                primaryCandidateBuildProcessingMilliseconds:
                    scannerWhiteCandidate.processingMilliseconds,
                primaryTextMaskRasterizationMilliseconds:
                    scannerWhiteCandidate.textMaskRasterizationMilliseconds,
                primaryColorRetention:colorRetention,
                primaryColorRetentionProcessingMilliseconds:
                    primaryColorRetentionMilliseconds,
                primaryPaperEvaluation:paperEvaluation,
                primaryPaperNormalizationProcessingMilliseconds:
                    primaryPaperNormalizationMilliseconds,
                primaryWhiteBalanceEvaluation:whiteBalanceEvaluation,
                primaryStructureEvaluation:structureEvaluation,
                primaryStructureProcessingMilliseconds:
                    structureEvaluation?.processingMilliseconds,
                fallbackMode:nil,
                fallbackCandidateBuildProcessingMilliseconds:nil,
                fallbackTextMaskRasterizationMilliseconds:nil,
                fallbackColorRetention:nil,
                fallbackColorRetentionProcessingMilliseconds:nil,
                fallbackPaperEvaluation:nil,
                fallbackPaperNormalizationProcessingMilliseconds:nil,
                fallbackWhiteBalanceEvaluation:nil,
                fallbackStructureEvaluation:nil,
                fallbackStructureProcessingMilliseconds:nil,
                selectedMode:nil
            )
        )
    }

    private static func finishScannerWhiteFastPath(
        preparedBaseline:PreparedSmartBaseline,
        naturalSmart:UIImage,
        preliminaryColorTemperature:ColorTemperatureResult?,
        visual:BaselineVisualPreflightResult,
        baselineStartedAt:Date,
        startedAt:Date,
        pageNumber:Int,
        completion:@escaping (SmartEnhancementOutput)->Void
    ) {
        let selectedMode = preparedBaseline.selectedSurfaceMode
        let applied = selectedMode != nil
        let reason:String
        let routeReason:String
        switch selectedMode {
        case .contentAwareWhiteCanvas:
            reason = "主白画布通过纸面、四边、保色和非纸面保护，快速路径直接输出"
            routeReason = "内容感知白画布已应用，不再打开备选方案"
        case .stableLowFrequency:
            if preparedBaseline.scannerWhiteDiagnostics?.fallbackMode
                == .stableLowFrequency {
                reason = "主白画布未通过安全门槛，已应用稳定低频纸面回退"
                routeReason = "稳定低频纸面回退已应用，不再打开备选方案"
            }
            else {
                reason = "页面未进入主白画布，稳定低频纸面基线通过安全检查"
                routeReason = "稳定低频纸面基线已应用，不再打开备选方案"
            }
        case nil:
            reason = "纸面标准化候选未通过安全门槛，快速回退自然智能版本"
            routeReason = "纸面标准化安全回退后保留自然智能版本"
        }
        let decision = SmartEnhancementEvaluator().keepOriginal(
            reason:reason
        )
        let summary = EnhancementTrialSummary(
            variant:.baseline,
            parameters:.baseline,
            weightedConfidence:nil,
            recognizedCharacterCount:0,
            characterStability:1,
            textCoverage:0,
            processingMilliseconds:milliseconds(since:baselineStartedAt),
            evaluatorAccepted:true,
            colorRetention:preparedBaseline.colorRetention,
            documentQuality:nil,
            colorTemperature:preparedBaseline.colorTemperature
                ?? preliminaryColorTemperature,
            whiteBalanceEvaluation:
                preparedBaseline.whiteBalanceEvaluation,
            reusedBaselineOCR:false,
            preflight:nil,
            secondOCRPerformed:false,
            selected:true
        )
        deliver(
            image:applied ? preparedBaseline.image : naturalSmart,
            ocrResult:nil,
            originalQuality:nil,
            enhancedQuality:nil,
            decision:decision,
            selectedVariant:.baseline,
            trialSummaries:[summary],
            qualityRoute:.excellentDirect,
            documentQualityRoute:.none(routeReason),
            earlyStopReason:reason,
            executedCandidateCount:0,
            baselineVisualPreflight:visual,
            baselineOCRPerformed:false,
            scannerWhiteDiagnostics:
                preparedBaseline.scannerWhiteDiagnostics,
            additionalEstimatedMillisecondsSaved:
                estimatedScannerWhiteOCRSavings(visual),
            startedAt:startedAt,
            pageNumber:pageNumber,
            completion:completion
        )
    }

    private static func estimatedScannerWhiteOCRSavings(
        _ visual:BaselineVisualPreflightResult
    )->Int {
        let megapixels = Double(visual.pixelWidth * visual.pixelHeight)
            / 1_000_000
        return min(max(Int(900 + megapixels * 420), 1_200), 9_000)
    }

    private static func hasStrictColorTemperatureEvidence(
        _ result:ColorTemperatureResult?
    )->Bool {
        guard let result else { return false }
        return (result.source == .warm || result.source == .cool)
            && result.confidence >= 0.68
            && result.validSampleRatio >= 0.18
            && !result.possiblePaperColor
    }

    private static func whiteBalanceFallbackRoute(
        after preflight:EnhancementPreflightResult,
        route:DocumentQualityRoute,
        originalDocumentQuality:DocumentQualityScore,
        baselineColorTemperature:ColorTemperatureResult?,
        recognizedCharacterCount:Int,
        startedAt:Date
    )->DocumentQualityRoute? {
        guard route.primaryIssue == .lighting
                || route.primaryIssue == .background,
              !preflight.budgetExceeded,
              recognizedCharacterCount < denseCharacterThreshold,
              milliseconds(since:startedAt)
                < maximumElapsedMillisecondsBeforeWhiteBalanceFallback,
              let baselineColorTemperature,
              hasStrictColorTemperatureEvidence(baselineColorTemperature)
                || (
                    DocumentPaperNormalizer.isEligible(
                        baselineColorTemperature
                    )
                    && DocumentPaperNormalizer.needsNormalization(
                        baselineColorTemperature
                    )
                ) else {
            return nil
        }

        let directionSafe = preflight.shadowReduction >= -0.005
            && preflight.backgroundGain >= -0.010
            && preflight.gradientReduction >= -0.005
            && preflight.brightnessChange >= -0.015
            && preflight.brightnessChange <= 0.065
        let minimumShadowReduction = max(
            0.025,
            originalDocumentQuality.visual.shadowSeverity * 0.12
        )
        let meaningfulGain:Bool
        if route.primaryIssue == .lighting {
            meaningfulGain = preflight.gradientReduction >= 0.018
                || preflight.shadowReduction >= minimumShadowReduction
        }
        else {
            meaningfulGain = preflight.backgroundGain >= 0.018
                || preflight.shadowReduction >= minimumShadowReduction
        }
        guard directionSafe, !meaningfulGain else { return nil }

        return DocumentQualityRoute(
            primaryIssue:.colorTemperature,
            affectedRegion:.none,
            severity:baselineColorTemperature.confidence,
            reason:"去阴影方向安全但收益不足，在严格总时间预算内补测一次白平衡与纸张标准化"
        )
    }

    private static func shouldPerformSecondOCR(
        originalQuality:OCRQualityResult,
        preflight:EnhancementPreflightResult,
        route:DocumentQualityRoute,
        startedAt:Date
    )->Bool {
        guard originalQuality.recognizedCharacterCount
                < denseCharacterThreshold,
              milliseconds(since:startedAt)
                < maximumElapsedMillisecondsBeforeSecondOCR else {
            return false
        }

        switch route.primaryIssue {
        case .lighting, .background:
            // Lighting recovery now has same-size structure, illumination and
            // color safety gates. A second Vision pass cost up to 7.5 seconds
            // in real logs without changing selection, so never duplicate it.
            return false
        case .regionalSharpness:
            return preflight.regionalClarityGain >= 0.060
                && originalQuality.weightedConfidence < 0.72
        case .colorTemperature, .none, .perspective:
            return false
        }
    }

    private static func canSelectVisualLightingCandidate(
        preflight:EnhancementPreflightResult,
        route:DocumentQualityRoute,
        baseline:DocumentQualityScore,
        colorRetention:ColorRetentionResult
    )->Bool {
        guard supportsVisualLightingValidation(route) else { return false }
        let minimumShadowReduction = max(
            0.025,
            baseline.visual.shadowSeverity * 0.12
        )
        let targetClearlyImproved = preflight.shadowReduction
                >= minimumShadowReduction
            || preflight.gradientReduction >= 0.018
            || preflight.backgroundGain >= 0.018
        return preflight.shouldRunOCR
            && targetClearlyImproved
            && preflight.backgroundGain >= -0.004
            && preflight.gradientReduction >= -0.003
            && preflight.textStructureChange >= -0.005
            && preflight.regionalClarityGain >= -0.010
            && preflight.haloChange <= 0.008
            && preflight.noiseChange <= 0.012
            && preflight.brightnessChange <= 0.055
            && colorRetention.overallRetention >= 0.985
            && colorRetention.chromaSimilarity >= 0.985
            && colorRetention.redRetention >= 0.985
            && colorRetention.blueRetention >= 0.985
    }

    private static func canSelectVisualWhiteBalanceCandidate(
        preflight:EnhancementPreflightResult,
        evaluation:WhiteBalanceEvaluationResult?,
        colorRetention:ColorRetentionResult
    )->Bool {
        let scannerWhiteAccepted = evaluation?
            .paperNormalizationEvaluation?.accepted == true
        let maximumBrightnessChange:Float = scannerWhiteAccepted
            ? 0.20 : 0.020
        return preflight.shouldRunOCR
            && evaluation?.accepted == true
            && preflight.brightnessChange >= -0.015
            && preflight.brightnessChange <= maximumBrightnessChange
            && preflight.textStructureChange >= -0.012
            && preflight.regionalClarityGain >= -0.020
            && preflight.haloChange <= 0.015
            && colorRetention.overallRetention >= 0.985
            && colorRetention.chromaSimilarity >= 0.985
            && colorRetention.redRetention >= 0.985
            && colorRetention.blueRetention >= 0.985
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
