//
//  SmartEnhancementDiagnostics.swift
//  AoiScan
//

import Foundation


enum SmartEnhancementDiagnostics {
    static func record(
        output:SmartEnhancementOutput,
        pageNumber:Int,
        scannerWhiteDiagnostics:
            SmartEnhancementPipeline.ScannerWhiteAttemptDiagnostics? = nil
    ) {
        let selectedCode = output.selectedExperimentVariant.rawValue
        let selectedPaperMode = scannerWhiteDiagnostics?.selectedMode
        let scannerWhiteBaseline = selectedPaperMode
            == .contentAwareWhiteCanvas
        let stableLowFrequencySelected = selectedPaperMode
            == .stableLowFrequency
        let scannerWhiteFastPath = scannerWhiteDiagnostics != nil
        let message:String
        if output.selectedExperimentVariant == .baseline,
           scannerWhiteBaseline {
            message = "智能模式采用高置信度扫描白底基线"
        }
        else if output.selectedExperimentVariant == .baseline,
                stableLowFrequencySelected {
            message = scannerWhiteDiagnostics?.fallbackMode != nil
                ? "智能模式采用稳定低频纸面回退"
                : "智能模式采用稳定低频纸面基线"
        }
        else if output.selectedExperimentVariant == .baseline {
            message = "A/B测试保留原始智能版本"
        }
        else {
            message = "A/B测试选择了增强版本"
        }
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
            ),
            L10n.format(
                "OCR前预检跳过 %@ 次，预计节省 %@ms",
                String(output.preflightSkippedOCRCount),
                String(output.estimatedMillisecondsSaved)
            ),
            L10n.format(
                "单帧预算 基准候选门槛 %@ms，一二级预检 %@px / %@px，白平衡全分辨率启动门槛 2700ms，预留 800ms",
                "3000",
                "640",
                "960"
            ),
        ]

        if output.baselineOCRPerformed {
            lines.append(
                L10n.format(
                    "质量评估OCR %@，最长边 %@px，语言纠错 %@，基准OCR耗时 %@ms",
                    L10n.text(
                        OCRRecognitionProfile.qualityEvaluation
                            .diagnosticName
                    ),
                    "1800",
                    L10n.text("关闭"),
                    String(
                        output.trialSummaries.first?
                            .processingMilliseconds ?? 0
                    )
                )
            )
        }
        else {
            lines.append(
                L10n.text(
                    scannerWhiteFastPath
                        ? "质量评估OCR 已跳过，纸面快速路径不执行旧质量候选"
                        : "质量评估OCR 已由OCR前视觉预检跳过"
                )
            )
        }

        if scannerWhiteFastPath {
            let status:String
            switch selectedPaperMode {
            case .contentAwareWhiteCanvas:
                status = "主白画布已应用"
            case .stableLowFrequency:
                status = scannerWhiteDiagnostics?.fallbackMode != nil
                    ? "主白画布未通过，稳定低频回退已应用"
                    : "稳定低频基线已应用"
            case nil:
                status = "纸面候选均未通过，已安全回退自然智能"
            }
            lines.append(
                L10n.format(
                    "纸面快速路径 %@，旧质量候选已关闭",
                    L10n.text(status)
                )
            )
            if let scannerWhiteDiagnostics {
                lines.append(
                    scannerWhiteAttemptLine(
                        label:"paperPrimary",
                        mode:scannerWhiteDiagnostics.primaryMode,
                        candidateBuildProcessingMilliseconds:
                            scannerWhiteDiagnostics
                                .primaryCandidateBuildProcessingMilliseconds,
                        textMaskRasterizationMilliseconds:
                            scannerWhiteDiagnostics
                                .primaryTextMaskRasterizationMilliseconds,
                        colorRetention:
                            scannerWhiteDiagnostics.primaryColorRetention,
                        colorRetentionProcessingMilliseconds:
                            scannerWhiteDiagnostics
                                .primaryColorRetentionProcessingMilliseconds,
                        paperEvaluation:
                            scannerWhiteDiagnostics.primaryPaperEvaluation,
                        paperNormalizationProcessingMilliseconds:
                            scannerWhiteDiagnostics
                                .primaryPaperNormalizationProcessingMilliseconds,
                        whiteBalanceEvaluation:
                            scannerWhiteDiagnostics
                                .primaryWhiteBalanceEvaluation,
                        structureEvaluation:scannerWhiteDiagnostics
                            .primaryStructureEvaluation,
                        structureProcessingMilliseconds:
                            scannerWhiteDiagnostics
                                .primaryStructureProcessingMilliseconds
                    )
                )
            if let fallbackMode = scannerWhiteDiagnostics.fallbackMode,
               let fallbackColor = scannerWhiteDiagnostics
                    .fallbackColorRetention,
                   let fallbackWhiteBalance = scannerWhiteDiagnostics
                        .fallbackWhiteBalanceEvaluation {
                    lines.append(
                        scannerWhiteAttemptLine(
                            label:"paperFallback",
                            mode:fallbackMode,
                            candidateBuildProcessingMilliseconds:
                                scannerWhiteDiagnostics
                                    .fallbackCandidateBuildProcessingMilliseconds
                                ?? 0,
                            textMaskRasterizationMilliseconds:
                                scannerWhiteDiagnostics
                                    .fallbackTextMaskRasterizationMilliseconds
                                ?? 0,
                            colorRetention:fallbackColor,
                            colorRetentionProcessingMilliseconds:
                                scannerWhiteDiagnostics
                                    .fallbackColorRetentionProcessingMilliseconds
                                ?? 0,
                            paperEvaluation:scannerWhiteDiagnostics
                                .fallbackPaperEvaluation,
                            paperNormalizationProcessingMilliseconds:
                                scannerWhiteDiagnostics
                                    .fallbackPaperNormalizationProcessingMilliseconds,
                            whiteBalanceEvaluation:fallbackWhiteBalance,
                            structureEvaluation:scannerWhiteDiagnostics
                                .fallbackStructureEvaluation,
                            structureProcessingMilliseconds:
                                scannerWhiteDiagnostics
                                    .fallbackStructureProcessingMilliseconds
                        )
                    )
                }
                lines.append(
                    "paperSelectedMode=\(selectedPaperMode?.rawValue ?? "naturalSmart")"
                )
            }
        }

        if let earlyStopReason = output.earlyStopReason {
            lines.append(
                L10n.format(
                    "早停原因 %@",
                    L10n.text(earlyStopReason)
                )
            )
        }

        if output.documentQualityRoute.reason.contains("白平衡")
            && output.documentQualityRoute.reason.contains("补测") {
            lines.append(
                L10n.format(
                    "白平衡补位原因 %@",
                    L10n.text(output.documentQualityRoute.reason)
                )
            )
        }

        if let temperature = output.trialSummaries.first?.colorTemperature {
            lines.append(
                [
                    "[质量路由色温]",
                    "source=\(L10n.text(temperature.source.diagnosticName))",
                    "confidence=\(percent(temperature.confidence))",
                    "redBlue=\(decimal(temperature.redBlueRatio))",
                    "labYellow=\(decimal(temperature.labYellowBias))",
                    "backgroundSaturation=\(percent(temperature.backgroundSaturation))",
                    "validSamples=\(percent(temperature.validSampleRatio))",
                    "possiblePaperColor=\(L10n.text(temperature.possiblePaperColor ? "是" : "否"))"
                ].joined(separator:"，")
            )
        }

        if let visual = output.baselineVisualPreflight {
            lines.append(
                L10n.format(
                    "基准OCR %@，视觉预检 %@ms，预计节省 %@ms",
                    L10n.text(
                        output.baselineOCRPerformed ? "已执行" : "已跳过"
                    ),
                    String(visual.processingMilliseconds),
                    String(visual.estimatedMillisecondsSaved)
                )
            )
            lines.append(
                [
                    "[OCR前视觉预检]",
                    L10n.text(visual.decision.diagnosticName),
                    "size=\(visual.pixelWidth)x\(visual.pixelHeight)",
                    "top=\(decimal(visual.topSharpness))",
                    "middle=\(decimal(visual.middleSharpness))",
                    "bottom=\(decimal(visual.bottomSharpness))",
                    "average=\(decimal(visual.averageSharpness))",
                    "balance=\(percent(visual.sharpnessBalance))",
                    "brightness=\(percent(visual.backgroundBrightness))",
                    "background=\(percent(visual.backgroundUniformity))",
                    "topLight=\(percent(visual.topBrightness))",
                    "middleLight=\(percent(visual.middleBrightness))",
                    "bottomLight=\(percent(visual.bottomBrightness))",
                    "lightGradient=\(percent(visual.illuminationGradient))",
                    "shadow=\(percent(visual.shadowSeverity))",
                    "smallTextRisk=\(visual.smallTextRisk.level.rawValue)",
                    "textRegions=\(visual.smallTextRisk.detectedTextRegionCount)",
                    "smallRatio=\(percent(visual.smallTextRisk.smallTextRatio))",
                    "topConcentration=\(percent(visual.smallTextRisk.topConcentration))",
                    "topSmallRatio=\(percent(visual.smallTextRisk.topSmallTextRatio))",
                    "medianTextHeight=\(decimal(visual.smallTextRisk.medianTextHeight))",
                    "topRetention=\(boundedPercent(visual.smallTextRisk.topSharpnessRetention))",
                    "topBottom=\(percent(visual.smallTextRisk.topBottomWidthRatio))",
                    "smallTextTime=\(visual.smallTextRisk.processingMilliseconds)ms",
                    "smallTextReason=\(L10n.text(visual.smallTextRisk.reason))",
                    "reason=\(L10n.text(visual.reason))"
                ].joined(separator:"，")
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
        let secondOCR = trial.secondOCRPerformed
            ? L10n.text("是")
            : L10n.text("否")
        let preflight = trial.preflight
        let unclassifiedMilliseconds = max(
            trial.processingMilliseconds
                - (preflight?.candidateBuildMilliseconds ?? 0)
                - (preflight?.visualAnalysisMilliseconds ?? 0),
            0
        )
        let temperature = trial.colorTemperature
        let whiteBalance = trial.whiteBalanceEvaluation
        let paperNormalization = whiteBalance?
            .paperNormalizationEvaluation
        let whiteBalanceStructure = preflight?
            .whiteBalanceStructureEvaluation
        let preflightStatus:String
        let preflightStopType:String
        if let preflight {
            preflightStatus = preflight.shouldRunOCR
                ? L10n.text("通过") : L10n.text("早停")
            if preflight.budgetExceeded {
                preflightStopType = "budget"
            }
            else if preflight.shouldRunOCR {
                preflightStopType = "passed"
            }
            else {
                preflightStopType = "gainOrSafety"
            }
        }
        else {
            preflightStatus = "--"
            preflightStopType = "--"
        }

        return [
            "[\(trial.variant.rawValue)]",
            L10n.text(trial.variant.diagnosticName),
            "candidateType=\(candidateType(trial.variant))",
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
            "colorReference=\(trial.colorRetention == nil ? "--" : "baselineSmart")",
            "chroma=\(percent(trial.colorRetention?.chromaSimilarity))",
            "saturatedColor=\(percent(trial.colorRetention?.saturatedColorRetention))",
            "actualChromaSamples=\(trial.colorRetention?.actualChromaSampleCount ?? 0)",
            "actualColorContentSamples=\(trial.colorRetention?.actualColorContentSampleCount ?? 0)",
            "excludedNonColorSamples=\(trial.colorRetention?.excludedNonColorSampleCount ?? 0)",
            "red=\(percent(trial.colorRetention?.redRetention))",
            "blue=\(percent(trial.colorRetention?.blueRetention))",
            "paperColorProtection=\(paperNormalization == nil ? "--" : "redBlueInkLocalized")",
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
            "preflight=\(preflightStatus)",
            "preflightStopType=\(preflightStopType)",
            "preflightStage=\(preflight?.stage.rawValue ?? "--")",
            "preflightSize=\(preflight.map { "\($0.pixelLongEdge)px" } ?? "--")",
            "preflightBlocks=\(preflight.map { String($0.evaluatedBlockCount) } ?? "--")",
            "candidateBuildTime=\(preflight?.candidateBuildMilliseconds ?? 0)ms",
            "visualAnalysisTime=\(preflight?.visualAnalysisMilliseconds ?? 0)ms",
            "illuminationAnalysisMode=\(preflight?.illuminationAnalysisMode ?? "--")",
            "illuminationAnalysisTime=\(preflight?.illuminationAnalysisMilliseconds ?? 0)ms",
            "colorRetentionAnalysisTime=\(preflight?.colorRetentionAnalysisMilliseconds ?? 0)ms",
            "colorTemperatureAnalysisTime=\(preflight?.colorTemperatureAnalysisMilliseconds ?? 0)ms",
            "paperNormalizationAnalysisTime=\(preflight?.paperNormalizationAnalysisMilliseconds ?? 0)ms",
            "analysisReuseMode=\(preflight?.analysisReuseMode ?? "--")",
            "analysisReuseSaved=\(preflight?.reusedAnalysisMilliseconds ?? 0)ms",
            "structureAnalysisTime=\(preflight?.structureAnalysisMilliseconds ?? 0)ms",
            "whiteBalanceStructureAccepted=\(boolean(whiteBalanceStructure?.accepted))",
            "whiteBalanceStructureProfile=\(whiteBalanceStructure?.structureProfile.rawValue ?? "--")",
            "whiteBalanceEdgeRetention=\(percent(whiteBalanceStructure?.edgeRetention))",
            "whiteBalanceRegionalRetention=\(percent(whiteBalanceStructure?.minimumRegionalEdgeRetention))",
            "whiteBalanceHighFrequencyChange=\(percent(whiteBalanceStructure?.highFrequencyChange))",
            "whiteBalanceTextLuminanceDelta=\(percent(whiteBalanceStructure?.meanLuminanceDelta))",
            "whiteBalanceStructureRejectMetric=\(whiteBalanceStructure?.firstRejectedMetric ?? "--")",
            "whiteBalanceStructureRejectValue=\(percent(whiteBalanceStructure?.firstRejectedValue))",
            "whiteBalanceStructureRejectThreshold=\(percent(whiteBalanceStructure?.firstRejectedThreshold))",
            "whiteBalanceStructureSamples=\(whiteBalanceStructure.map { String($0.sampledEdgeCount) } ?? "--")",
            "whiteBalanceStructureTime=\(whiteBalanceStructure?.processingMilliseconds ?? 0)ms",
            "whiteBalanceStructureReason=\(whiteBalanceStructure.map { L10n.text($0.reason) } ?? "--")",
            "ocrAndDecisionTime=\(unclassifiedMilliseconds)ms",
            "backgroundGain=\(percent(preflight?.backgroundGain))",
            "shadowReduction=\(percent(preflight?.shadowReduction))",
            "gradientReduction=\(percent(preflight?.gradientReduction))",
            "regionalGain=\(percent(preflight?.regionalClarityGain))",
            "structureChange=\(percent(preflight?.textStructureChange))",
            "haloChange=\(percent(preflight?.haloChange))",
            "noiseChange=\(percent(preflight?.noiseChange))",
            "brightnessChange=\(percent(preflight?.brightnessChange))",
            "temperatureSource=\(temperature.map { L10n.text($0.source.diagnosticName) } ?? "--")",
            "temperatureConfidence=\(percent(temperature?.confidence))",
            "redBlue=\(decimal(temperature?.redBlueRatio))",
            "labYellow=\(decimal(temperature?.labYellowBias))",
            "whiteBalanceRedGain=\(decimal(whiteBalance?.redGain))",
            "whiteBalanceGreenGain=\(decimal(whiteBalance?.greenGain))",
            "whiteBalanceBlueGain=\(decimal(whiteBalance?.blueGain))",
            "whiteBalanceNeutralityGain=\(percent(whiteBalance?.neutralityGain))",
            "whiteBalanceOvercorrection=\(boolean(whiteBalance?.overcorrectionDetected))",
            "whiteBalanceReason=\(whiteBalanceDiagnosticReason(whiteBalance, paperEvaluation:paperNormalization))",
            "paperNormalizationEligible=\(boolean(paperNormalization?.eligible))",
            "paperNormalizationAccepted=\(boolean(paperNormalization?.accepted))",
            "paperSurfaceMode=\(paperNormalization?.surfaceMode ?? "--")",
            "paperOriginalBrightness=\(percent(paperNormalization?.originalBrightness))",
            "paperCandidateBrightness=\(percent(paperNormalization?.candidateBrightness))",
            "paperBrightnessGain=\(percent(paperNormalization?.brightnessGain))",
            "paperNeutralityGain=\(percent(paperNormalization?.neutralityGain))",
            "paperHighlightClippingIncrease=\(percent(paperNormalization?.highlightClippingIncrease))",
            "paperOriginalWhiteCoverage=\(percent(paperNormalization?.originalWhiteCoverage))",
            "paperCandidateWhiteCoverage=\(percent(paperNormalization?.candidateWhiteCoverage))",
            "paperWhiteCoverageGain=\(percent(paperNormalization?.whiteCoverageGain))",
            "paperOriginalEdgeWhiteCoverage=\(percent(paperNormalization?.originalEdgeWhiteCoverage))",
            "paperCandidateEdgeWhiteCoverage=\(percent(paperNormalization?.candidateEdgeWhiteCoverage))",
            "paperEdgeWhiteCoverageGain=\(percent(paperNormalization?.edgeWhiteCoverageGain))",
            "paperOriginalMinimumLocalWhiteCoverage=\(percent(paperNormalization?.originalMinimumLocalWhiteCoverage))",
            "paperCandidateMinimumLocalWhiteCoverage=\(percent(paperNormalization?.candidateMinimumLocalWhiteCoverage))",
            "paperMinimumLocalWhiteCoverageGain=\(percent(paperNormalization?.minimumLocalWhiteCoverageGain))",
            "paperOriginalBottomMinimumWhiteCoverage=\(percent(paperNormalization?.originalBottomMinimumWhiteCoverage))",
            "paperCandidateBottomMinimumWhiteCoverage=\(percent(paperNormalization?.candidateBottomMinimumWhiteCoverage))",
            "paperBottomMinimumWhiteCoverageGain=\(percent(paperNormalization?.bottomMinimumWhiteCoverageGain))",
            "paperCandidateLocalizedShadow=\(percent(paperNormalization?.candidateLocalizedShadowFraction))",
            "paperOriginalLocalWhiteGrid=\(percentGrid(paperNormalization?.originalLocalWhiteCoverages))",
            "paperCandidateLocalWhiteGrid=\(percentGrid(paperNormalization?.candidateLocalWhiteCoverages))",
            "paperEvaluationSampleRatio=\(percent(paperNormalization?.paperEvaluationSampleRatio))",
            "paperProtectedContentExclusion=\(percent(paperNormalization?.protectedContentExclusionRatio))",
            "paperRenderProtectedContent=\(percent(paperNormalization?.renderProtectedContentRatio))",
            "paperProtectionMaskReused=\(boolean(paperNormalization?.protectionMaskReused))",
            "paperConfirmedNeutralInk=\(percent(paperNormalization?.confirmedNeutralInkRatio))",
            "paperConnectedWeakInk=\(percent(paperNormalization?.connectedWeakInkRatio))",
            "paperRedBlueInk=\(percent(paperNormalization?.redBlueInkRatio))",
            "paperLocalizedColor=\(percent(paperNormalization?.localizedColorRatio))",
            "paperRejectedFaintInterference=\(percent(paperNormalization?.rejectedFaintInterferenceRatio))",
            "paperLocalEvaluationSampleGrid=\(percentGrid(paperNormalization?.localPaperEvaluationSampleRatios))",
            "paperNonPaperClippingIncrease=\(percent(paperNormalization?.nonPaperHighlightClippingIncrease))",
            "paperOriginalTopSaturation=\(percent(paperNormalization?.originalTopPaperSaturation))",
            "paperOriginalMiddleSaturation=\(percent(paperNormalization?.originalMiddlePaperSaturation))",
            "paperOriginalBottomSaturation=\(percent(paperNormalization?.originalBottomPaperSaturation))",
            "paperCandidateTopSaturation=\(percent(paperNormalization?.candidateTopPaperSaturation))",
            "paperCandidateMiddleSaturation=\(percent(paperNormalization?.candidateMiddlePaperSaturation))",
            "paperCandidateBottomSaturation=\(percent(paperNormalization?.candidateBottomPaperSaturation))",
            "paperOriginalRegionalColorDifference=\(percent(paperNormalization?.originalRegionalColorDifference))",
            "paperCandidateRegionalColorDifference=\(percent(paperNormalization?.candidateRegionalColorDifference))",
            "paperRegionalColorDifferenceReduction=\(percent(paperNormalization?.regionalColorDifferenceReduction))",
            "paperOriginalTop=\(percent(paperNormalization?.originalTopBrightness))",
            "paperOriginalMiddle=\(percent(paperNormalization?.originalMiddleBrightness))",
            "paperOriginalBottom=\(percent(paperNormalization?.originalBottomBrightness))",
            "paperCandidateTop=\(percent(paperNormalization?.candidateTopBrightness))",
            "paperCandidateMiddle=\(percent(paperNormalization?.candidateMiddleBrightness))",
            "paperCandidateBottom=\(percent(paperNormalization?.candidateBottomBrightness))",
            "paperOriginalGradient=\(percent(paperNormalization?.originalGradient))",
            "paperCandidateGradient=\(percent(paperNormalization?.candidateGradient))",
            "paperGradientReduction=\(percent(paperNormalization?.gradientReduction))",
            "paperDarkestRegionGain=\(percent(paperNormalization?.darkestRegionGain))",
            "paperUniformityGain=\(percent(paperNormalization?.uniformityGain))",
            "paperShadowReduction=\(percent(paperNormalization?.shadowReduction))",
            "paperNormalizationTime=\(paperNormalization?.processingMilliseconds ?? 0)ms",
            "paperNormalizationReason=\(paperNormalization.map { L10n.text($0.reason) } ?? "--")",
            "secondOCR=\(secondOCR)",
            "estimatedSaved=\(preflight?.estimatedMillisecondsSaved ?? 0)ms",
            "reusedOCR=\(reusedOCR)",
            "time=\(trial.processingMilliseconds)ms",
            "evaluator=\(accepted)",
            "selected=\(selected)",
            "preflightReason=\(preflight.map { L10n.text($0.reason) } ?? "--")"
        ]
        .joined(separator:"，")
    }

    private static func scannerWhiteAttemptLine(
        label:String,
        mode:PaperNormalizationSurfaceMode,
        candidateBuildProcessingMilliseconds:Int,
        textMaskRasterizationMilliseconds:Int,
        colorRetention:ColorRetentionResult,
        colorRetentionProcessingMilliseconds:Int,
        paperEvaluation:PaperNormalizationEvaluationResult?,
        paperNormalizationProcessingMilliseconds:Int?,
        whiteBalanceEvaluation:WhiteBalanceEvaluationResult,
        structureEvaluation:WhiteBalanceStructureSafetyResult?,
        structureProcessingMilliseconds:Int?
    )->String {
        let accepted = paperEvaluation?.accepted == true
            && whiteBalanceEvaluation.accepted
            && structureEvaluation?.accepted != false
        let paperAccepted = paperEvaluation?.accepted == true
        let colorAccepted = whiteBalanceEvaluation.accepted
        let structureAccepted = structureEvaluation?.accepted ?? true
        let rejectDomains = scannerWhiteRejectDomains(
            paperAccepted:paperAccepted,
            colorAccepted:colorAccepted,
            structureAccepted:structureAccepted
        )
        let finalReason = scannerWhiteFirstRejectReason(
            paperAccepted:paperAccepted,
            colorAccepted:colorAccepted,
            structureAccepted:structureAccepted,
            structureEvaluation:structureEvaluation,
            whiteBalanceEvaluation:whiteBalanceEvaluation,
            paperEvaluation:paperEvaluation,
            mode:mode
        )
        let colorSampleState = colorRetention.hasRealColorSamples
            ? "realColor" : "noRealColor"
        return [
            "[\(label)]",
            "mode=\(mode.rawValue)",
            "structureProfile=\(structureEvaluation?.structureProfile.rawValue ?? "--")",
            "accepted=\(boolean(accepted))",
            "rejectDomains=\(rejectDomains)",
            "paperAccepted=\(boolean(paperEvaluation?.accepted))",
            "finalReason=\(finalReason)",
            "paperReason=\(paperEvaluation.map { L10n.text($0.reason) } ?? "--")",
            "color=\(percent(colorRetention.overallRetention))",
            "chroma=\(percent(colorRetention.chromaSimilarity))",
            "saturatedColor=\(percent(colorRetention.saturatedColorRetention))",
            "red=\(percent(colorRetention.redRetention))",
            "blue=\(percent(colorRetention.blueRetention))",
            "actualChromaSamples=\(colorRetention.actualChromaSampleCount)",
            "colorEvaluationMaskSamples=\(colorRetention.actualColorContentSampleCount)",
            "excludedNonColorSamples=\(colorRetention.excludedNonColorSampleCount)",
            "colorSampleState=\(colorSampleState)",
            "severeColorLoss=\(percent4(colorRetention.severeColorLossFraction))",
            "severeRedLoss=\(percent4(colorRetention.severeRedLossFraction))",
            "severeBlueLoss=\(percent4(colorRetention.severeBlueLossFraction))",
            "minimumRegionalColorRetention=\(percent4(colorRetention.minimumRegionalColorRetention))",
            "nearBoundaryToleranceApplied=\(colorRetention.nearBoundaryToleranceApplied ? "yes" : "no")",
            "colorRejectMetric=\(colorRetention.firstRejectedColorMetric ?? "--")",
            "colorRejectValue=\(percent4(colorRetention.firstRejectedColorValue))",
            "colorRejectThreshold=\(percent4(colorRetention.firstRejectedColorThreshold))",
            "redSamples=\(colorRetention.redSampleCount)",
            "blueSamples=\(colorRetention.blueSampleCount)",
            "neutralInkMaskRatio=\(percent4(paperEvaluation?.neutralInkRatio))",
            "colorEvaluationMaskRatio=\(percent4(colorRetention.colorContentSampleRatio))",
            "paperColorContentRatio=\(percent4(paperEvaluation?.colorContentRatio))",
            "candidateBuildTime=\(candidateBuildProcessingMilliseconds)ms",
            "textMaskRasterTime=\(textMaskRasterizationMilliseconds)ms",
            "colorRetentionTime=\(colorRetentionProcessingMilliseconds)ms",
            "paperNormalizationTime=\(paperNormalizationProcessingMilliseconds ?? 0)ms",
            "whiteCoverage=\(percent(paperEvaluation?.candidateWhiteCoverage))",
            "edgeWhiteCoverage=\(percent(paperEvaluation?.candidateEdgeWhiteCoverage))",
            "minimumLocalWhiteCoverage=\(percent(paperEvaluation?.candidateMinimumLocalWhiteCoverage))",
            "bottomMinimumWhiteCoverage=\(percent(paperEvaluation?.candidateBottomMinimumWhiteCoverage))",
            "localizedShadow=\(percent(paperEvaluation?.candidateLocalizedShadowFraction))",
            "nonPaperClippingIncrease=\(percent(paperEvaluation?.nonPaperHighlightClippingIncrease))",
            "protectedContent=\(percent(paperEvaluation?.protectedContentExclusionRatio))",
            "renderProtectedContent=\(percent(paperEvaluation?.renderProtectedContentRatio))",
            "protectionMaskReused=\(boolean(paperEvaluation?.protectionMaskReused))",
            "confirmedNeutralInk=\(percent(paperEvaluation?.confirmedNeutralInkRatio))",
            "connectedWeakInk=\(percent(paperEvaluation?.connectedWeakInkRatio))",
            "redBlueInk=\(percent(paperEvaluation?.redBlueInkRatio))",
            "localizedColor=\(percent(paperEvaluation?.localizedColorRatio))",
            "colorContent=\(percent(paperEvaluation?.colorContentRatio))",
            "rejectedFaintInterference=\(percent(paperEvaluation?.rejectedFaintInterferenceRatio))",
            "neutralInk=\(percent(paperEvaluation?.neutralInkRatio))",
            "structureEdgeGainDiagnosticMode=\(mode == .contentAwareWhiteCanvas ? "true" : "false")",
            "structureAccepted=\(boolean(structureEvaluation?.accepted))",
            "structureRejectMetric=\(structureEvaluation?.firstRejectedMetric ?? "--")",
            "structureRejectValue=\(percent4(structureEvaluation?.firstRejectedValue))",
            "structureRejectThreshold=\(percent4(structureEvaluation?.firstRejectedThreshold))",
            "structureEdgeRetention=\(percent(structureEvaluation?.edgeRetention))",
            "structureRegionalRetention=\(percent(structureEvaluation?.minimumRegionalEdgeRetention))",
            "structureHighFrequencyChange=\(percent(structureEvaluation?.highFrequencyChange))",
            "structureTextLuminanceDelta=\(percent(structureEvaluation?.meanLuminanceDelta))",
            "structureSamples=\(structureEvaluation.map { String($0.sampledEdgeCount) } ?? "--")",
            "structureTime=\(structureProcessingMilliseconds ?? structureEvaluation?.processingMilliseconds ?? 0)ms",
            "structureReason=\(structureEvaluation.map { L10n.text($0.reason) } ?? "--")"
        ]
        .joined(separator:"，")
    }

    private static func scannerWhiteRejectDomains(
        paperAccepted:Bool,
        colorAccepted:Bool,
        structureAccepted:Bool
    )->String {
        var domains:[String] = []
        if !paperAccepted { domains.append("paper") }
        if !colorAccepted { domains.append("color") }
        if !structureAccepted { domains.append("structure") }
        return domains.isEmpty ? "none" : domains.joined(separator:"|")
    }

    private static func scannerWhiteFirstRejectReason(
        paperAccepted:Bool,
        colorAccepted:Bool,
        structureAccepted:Bool,
        structureEvaluation:WhiteBalanceStructureSafetyResult?,
        whiteBalanceEvaluation:WhiteBalanceEvaluationResult,
        paperEvaluation:PaperNormalizationEvaluationResult?,
        mode:PaperNormalizationSurfaceMode
    )->String {
        if !paperAccepted {
            return paperEvaluation.map {
                "paperFail: " + $0.reason
            } ?? "扫描白候选未通过纸面保护"
        }
        if !colorAccepted {
            return whiteBalanceDiagnosticReason(
                whiteBalanceEvaluation,
                paperEvaluation:paperEvaluation
            )
        }
        if !structureAccepted {
            return L10n.text(
                structureEvaluation?.reason
                    ?? "扫描白候选未通过文字结构安全检查"
            )
        }
        return whiteBalanceDiagnosticReason(
            whiteBalanceEvaluation,
            paperEvaluation:paperEvaluation
        )
    }

    private static func whiteBalanceDiagnosticReason(
        _ evaluation:WhiteBalanceEvaluationResult?,
        paperEvaluation:PaperNormalizationEvaluationResult?
    )->String {
        guard let evaluation else { return "--" }
        if evaluation.accepted,
           paperEvaluation?.surfaceMode
            == PaperNormalizationSurfaceMode.stableLowFrequency.rawValue {
            return L10n.text(
                "稳定低频候选通过亮度、色差、保色和非纸面保护检查"
            )
        }
        return L10n.text(evaluation.reason)
    }

    private static func percent(_ value:Float?)->String {
        guard let value else { return "--" }
        return String(format:"%.1f%%", value * 100)
    }

    private static func percentGrid(_ values:[Float?]?)->String {
        guard let values,
              values.count == 9 else { return "--" }
        return values.map { value in
            guard let value else { return "--" }
            return String(format:"%.0f", value * 100)
        }
        .joined(separator:"/")
    }

    private static func decimal(_ value:Float?)->String {
        guard let value else { return "--" }
        return String(format:"%.3f", value)
    }

    private static func decimal4(_ value:Float?)->String {
        guard let value else { return "--" }
        return String(format:"%.4f", value)
    }

    private static func percent4(_ value:Float?)->String {
        guard let value else { return "--" }
        return String(format:"%.4f%%", value * 100)
    }

    private static func candidateType(
        _ variant:EnhancementExperimentVariant
    )->String {
        switch variant {
        case .baseline:
            return "baseline"
        case .smartColorMedium, .smartColorStrong:
            return "shadowRecovery"
        case .whiteBalance:
            return "whiteBalanceAndPaperNormalization"
        }
    }

    private static func decimal(_ value:CGFloat)->String {
        String(format:"%.3f", value)
    }

    private static func decimal(_ value:Double)->String {
        String(format:"%.3f", value)
    }

    private static func percent(_ value:Double)->String {
        String(format:"%.1f%%", value * 100)
    }

    private static func boundedPercent(_ value:Double)->String {
        percent(min(max(value, 0), 1))
    }

    private static func percent(_ value:CGFloat)->String {
        String(format:"%.1f%%", Double(value) * 100)
    }

    private static func percent(_ value:CGFloat?)->String {
        guard let value else { return "--" }
        return percent(value)
    }

    private static func boolean(_ value:Bool?)->String {
        guard let value else { return "--" }
        return L10n.text(value ? "是" : "否")
    }
}
