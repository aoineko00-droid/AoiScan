//
//  DocumentContentPreflightAnalyzer.swift
//  AoiScan
//

import UIKit
import Vision
import CoreImage
import ImageIO


enum DocumentSemanticOrientation:String,Codable {
    case up
    case right
    case down
    case left
    case uncertain
}


struct DocumentContentPreflightResult {
    let orientation:DocumentSemanticOrientation
    let orientationConfidence:Float
    let blocks:[OCRBlock]
    let recognizedCharacterCount:Int
    let detectedTextRegionCount:Int
    let whiteCanvasEligible:Bool
    let analysisLongEdge:Int
    let processingMilliseconds:Int
    let reason:String
}


struct DocumentContentPreflightOutput {
    let image:UIImage
    let result:DocumentContentPreflightResult
    /// Clockwise physical rotation applied to `image`, expressed in 90° turns.
    let rotationQuarterTurns:Int
}


/// A small, non-persisted OCR pass used only for semantic orientation and
/// scanner-white content masks. Formal user OCR remains a separate later pass.
enum DocumentContentPreflightAnalyzer {
    private static let maximumAnalysisEdge:CGFloat = 960
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    private struct RecognitionPass {
        let blocks:[OCRBlock]
        let score:Float
        let averageConfidence:Float
        let characterCount:Int
        let processingMilliseconds:Int

        var hasReliableLayout:Bool {
            !blocks.isEmpty
                && characterCount >= 4
                && averageConfidence >= 0.36
        }

        /// Scanner-white needs approximate foreground locations, not a
        /// semantically trustworthy reading. A lower-confidence but repeated
        /// set of text rectangles is safe to offer to the paper pipeline,
        /// whose independent mask scope, color and structure gates still make
        /// the final decision.
        var hasScannerWhiteSpatialEvidence:Bool {
            hasReliableLayout
                || (
                    blocks.count >= 3
                        && characterCount >= 12
                        && averageConfidence >= 0.18
                )
        }
    }

    private struct OrientationCandidate {
        let semantic:DocumentSemanticOrientation
        let property:CGImagePropertyOrientation
        let clockwiseQuarterTurns:Int
        let pass:RecognitionPass
    }

    private struct OrientationSelection {
        let value:DocumentSemanticOrientation
        let confidence:Float
        let winner:OrientationCandidate
        let axis:String
        let axisConfidence:Float
        let layoutDelta:Float
        let languageDelta:Float
        let recognitionDelta:Float
        let evidenceReason:String
    }

    private enum OrientationAxis:String {
        case vertical
        case horizontal
    }

    private struct AxisSelection {
        let axis:OrientationAxis
        let confidence:Float
        let verticalScore:Float
        let horizontalScore:Float
    }

    static func analyzeAndOrient(
        image:UIImage,
        pageNumber:Int,
        allowsRotation:Bool = true
    )->DocumentContentPreflightOutput {
        let startedAt = Date()
        guard let analysisImage = analysisCGImage(image) else {
            let result = DocumentContentPreflightResult(
                orientation:.uncertain,
                orientationConfidence:0,
                blocks:[],
                recognizedCharacterCount:0,
                detectedTextRegionCount:0,
                whiteCanvasEligible:false,
                analysisLongEdge:0,
                processingMilliseconds:milliseconds(since:startedAt),
                reason:"无法生成轻量OCR图像"
            )
            return DocumentContentPreflightOutput(
                image:image,
                result:result,
                rotationQuarterTurns:0
            )
        }

        let definitions:[(
            DocumentSemanticOrientation,
            CGImagePropertyOrientation,
            Int
        )] = allowsRotation
            ? [
                (.up, .up, 0),
                (.right, .right, 1),
                (.down, .down, 2),
                (.left, .left, 3)
            ]
            : [(.up, .up, 0)]
        var candidates = definitions.map { definition in
            OrientationCandidate(
                semantic:definition.0,
                property:definition.1,
                clockwiseQuarterTurns:definition.2,
                pass:recognize(
                    in:analysisImage,
                    orientation:definition.1,
                    level:.fast
                )
            )
        }
        let fastCandidates = candidates
        var accurateConfirmationPerformed = false
        var accurateDirections = Set<DocumentSemanticOrientation>()
        var orientationFastExit = "none"
        let orientation:OrientationSelection
        if !allowsRotation {
            orientation = OrientationSelection(
                value:.up,
                confidence:1,
                winner:candidates[0],
                axis:OrientationAxis.vertical.rawValue,
                axisConfidence:1,
                layoutDelta:0,
                languageDelta:0,
                recognitionDelta:0,
                evidenceReason:"用户方向锁定"
            )
        }
        else {
            var axis = chooseAxis(candidates)
            let fastFinalists = candidates.filter {
                semantics(for:axis.axis).contains($0.semantic)
            }
            let fastOrientation = chooseUprightOrientation(
                fastFinalists,
                axis:axis
            )
            let fastUp = candidates.first { $0.semantic == .up }
            let denseCurrentPage = fastUp.map {
                $0.pass.blocks.count >= 80
                    || $0.pass.characterCount >= 1_800
            } ?? false
            let preserveDenseAmbiguousCurrent = axis.confidence >= 0.80
                && denseCurrentPage
                && fastOrientation.value == .uncertain
                && fastUp?.pass.hasScannerWhiteSpatialEvidence == true
            // Fast OCR first decides the text axis. When both axes are close,
            // confirm all four directions; otherwise accurate OCR is limited
            // to the opposite pair on the winning axis.
            if preserveDenseAmbiguousCurrent,
               let fastUp {
                orientationFastExit = "denseAmbiguousPreserveCurrent"
                orientation = OrientationSelection(
                    value:.uncertain,
                    confidence:fastOrientation.confidence,
                    winner:fastUp,
                    axis:axis.axis.rawValue,
                    axisConfidence:axis.confidence,
                    layoutDelta:fastOrientation.layoutDelta,
                    languageDelta:fastOrientation.languageDelta,
                    recognitionDelta:fastOrientation.recognitionDelta,
                    evidenceReason:"密集页快速证据无法安全区分正反面，保留当前方向"
                )
            }
            else {
                accurateDirections = axis.confidence < 0.22
                    ? Set(definitions.map { $0.0 })
                    : semantics(for:axis.axis)
                candidates = candidates.map { candidate in
                    guard accurateDirections.contains(candidate.semantic)
                    else { return candidate }
                    return OrientationCandidate(
                        semantic:candidate.semantic,
                        property:candidate.property,
                        clockwiseQuarterTurns:candidate.clockwiseQuarterTurns,
                        pass:recognize(
                            in:analysisImage,
                            orientation:candidate.property,
                            level:.accurate
                        )
                    )
                }
                accurateConfirmationPerformed = true
                if accurateDirections.count == 4 {
                    axis = chooseAxis(candidates)
                }
                let finalists = candidates.filter {
                    semantics(for:axis.axis).contains($0.semantic)
                }
                orientation = chooseUprightOrientation(
                    finalists,
                    axis:axis
                )
            }
        }
        let upPass = candidates.first { $0.semantic == .up }?.pass
            ?? orientation.winner.pass
        let selectedPass:RecognitionPass
        let rotationQuarterTurns:Int
        if orientation.value == .uncertain {
            // Spatial rectangles must remain in the unchanged image's
            // coordinates when semantic direction is uncertain.
            selectedPass = upPass
            rotationQuarterTurns = 0
        }
        else {
            selectedPass = orientation.winner.pass
            rotationQuarterTurns = orientation.winner.clockwiseQuarterTurns
        }
        let outputImage = rotate(
            image,
            clockwiseQuarterTurns:rotationQuarterTurns
        )

        let noRecognizableText = candidates.allSatisfy {
            $0.pass.blocks.isEmpty
        }
        // Scanner-white only needs trustworthy spatial text regions. It does
        // not require semantic reading direction, so an uncertain direction
        // must not disable paper replacement when the unchanged-coordinate
        // OCR pass still provides reliable regions.
        let whiteCanvasEligible = noRecognizableText
            || selectedPass.hasScannerWhiteSpatialEvidence
        let whiteCanvasReason:String
        if noRecognizableText {
            whiteCanvasReason = "无文字区域，使用深色墨迹安全网"
        }
        else if selectedPass.hasReliableLayout {
            whiteCanvasReason = "文字区域和平均置信度达到严格门槛"
        }
        else if selectedPass.hasScannerWhiteSpatialEvidence {
            whiteCanvasReason = "文字区域充足，低置信度只限制方向判断"
        }
        else {
            whiteCanvasReason = "文字区域或平均置信度不足"
        }
        let reason:String
        if !allowsRotation {
            reason = "用户已确认方向，保持当前像素方向"
        }
        else if orientation.value == .up {
            reason = "轻量OCR确认文字方向正常"
        }
        else if orientation.value != .uncertain {
            reason = "轻量OCR确认文字方向，已顺时针旋转\(rotationQuarterTurns * 90)度"
        }
        else if noRecognizableText {
            reason = "未取得可识别文字，保留相机方向并使用深色墨迹安全网"
        }
        else if whiteCanvasEligible {
            reason = "文字方向证据不足，保留当前方向但按可靠文字区域执行白纸处理"
        }
        else {
            reason = "文字方向证据不足，保留相机方向和稳定白纸基线"
        }

        let result = DocumentContentPreflightResult(
            orientation:orientation.value,
            orientationConfidence:orientation.confidence,
            blocks:selectedPass.blocks,
            recognizedCharacterCount:selectedPass.characterCount,
            detectedTextRegionCount:selectedPass.blocks.count,
            whiteCanvasEligible:whiteCanvasEligible,
            analysisLongEdge:max(analysisImage.width, analysisImage.height),
            processingMilliseconds:milliseconds(since:startedAt),
            reason:reason
        )
        let directionEvidence = candidates.map { candidate in
            "\(candidate.semantic.rawValue):"
                + String(format:"%.2f", candidate.pass.score)
                + "/\(candidate.pass.characterCount)"
        }.joined(separator:"|")
        let accurateEvidence = accurateDirections.map(\.rawValue)
            .sorted().joined(separator:"|")
        let fastPassTimes = fastCandidates.map { candidate in
            "\(candidate.semantic.rawValue):\(candidate.pass.processingMilliseconds)"
        }.joined(separator:"|")
        let accuratePassMilliseconds = candidates
            .filter { accurateDirections.contains($0.semantic) }
            .reduce(0) { $0 + $1.pass.processingMilliseconds }
        RecognitionLogStore.shared.add(
            category:"文字方向与纸面预检",
            message:reason,
            details:[
                "页码 \(pageNumber)",
                "orientation=\(result.orientation.rawValue)",
                "confidence=\(percent(result.orientationConfidence))",
                "characters=\(result.recognizedCharacterCount)",
                "blocks=\(result.blocks.count)",
                "textRegions=\(result.detectedTextRegionCount)",
                "whiteCanvas=\(result.whiteCanvasEligible ? "yes" : "no")",
                "whiteCanvasReason=\(whiteCanvasReason)",
                "layoutConfidence=\(percent(selectedPass.averageConfidence))",
                "quarterTurns=\(rotationQuarterTurns)",
                "directionEvidence=\(directionEvidence)",
                "axis=\(orientation.axis)",
                "axisConfidence=\(percent(orientation.axisConfidence))",
                "layoutDelta=\(signedPercent(orientation.layoutDelta))",
                "languageDelta=\(signedPercent(orientation.languageDelta))",
                "recognitionDelta=\(signedPercent(orientation.recognitionDelta))",
                "uprightnessReason=\(orientation.evidenceReason)",
                "rotationAllowed=\(allowsRotation ? "yes" : "no")",
                "accurateConfirmation=\(accurateConfirmationPerformed ? "yes" : "no")",
                "accurateDirections=\(accurateEvidence.isEmpty ? "none" : accurateEvidence)",
                "orientationFastExit=\(orientationFastExit)",
                "fastPassTimes=\(fastPassTimes)",
                "accuratePassTime=\(accuratePassMilliseconds)ms",
                "size=\(result.analysisLongEdge)px",
                "time=\(result.processingMilliseconds)ms"
            ].joined(separator:"，")
        )
        return DocumentContentPreflightOutput(
            image:outputImage,
            result:result,
            rotationQuarterTurns:rotationQuarterTurns
        )
    }

    private static func semantics(
        for axis:OrientationAxis
    )->Set<DocumentSemanticOrientation> {
        switch axis {
        case .vertical:
            return [.up, .down]
        case .horizontal:
            return [.right, .left]
        }
    }

    private static func chooseAxis(
        _ candidates:[OrientationCandidate]
    )->AxisSelection {
        func pairScore(
            _ semantics:Set<DocumentSemanticOrientation>
        )->Float {
            let scores = candidates.filter {
                semantics.contains($0.semantic)
            }.map(\.pass.score).sorted(by:>)
            guard let first = scores.first else { return 0 }
            return first + (scores.dropFirst().first ?? 0) * 0.35
        }
        let vertical = pairScore([.up, .down])
        let horizontal = pairScore([.right, .left])
        let best = max(vertical, horizontal)
        let confidence = best > 0
            ? abs(vertical - horizontal) / best : 0
        return AxisSelection(
            axis:vertical >= horizontal ? .vertical : .horizontal,
            confidence:min(max(confidence, 0), 1),
            verticalScore:vertical,
            horizontalScore:horizontal
        )
    }

    private static func chooseUprightOrientation(
        _ candidates:[OrientationCandidate],
        axis:AxisSelection
    )->OrientationSelection {
        precondition(!candidates.isEmpty)
        let maximumRecognition = max(
            candidates.map(\.pass.score).max() ?? 0,
            0.001
        )
        let scored = candidates.map { candidate in
            let recognition = candidate.pass.score / maximumRecognition
            let layout = layoutUprightness(candidate.pass.blocks)
            let language = languagePlausibility(candidate.pass.blocks)
            let composite = recognition * 0.26
                + layout * 0.54
                + language * 0.20
            return (
                candidate:candidate,
                recognition:recognition,
                layout:layout,
                language:language,
                composite:composite
            )
        }.sorted { $0.composite > $1.composite }
        let best = scored[0]
        let second = scored.count > 1 ? scored[1] : scored[0]
        let layoutDelta = best.layout - second.layout
        let languageDelta = best.language - second.language
        let recognitionDelta = best.recognition - second.recognition
        let compositeDelta = best.composite - second.composite
        let hasIndependentEvidence = layoutDelta >= 0.075
            || languageDelta >= 0.060
            || recognitionDelta >= 0.12
        let accepted = best.candidate.pass.hasReliableLayout
            && compositeDelta >= 0.030
            && hasIndependentEvidence
        let reason:String
        if layoutDelta >= 0.075 {
            reason = "页面标题、正文与页脚层级支持该方向"
        }
        else if languageDelta >= 0.060 {
            reason = "本地文字序列合理性支持该方向"
        }
        else if recognitionDelta >= 0.12 {
            reason = "相反方向识别质量存在明确差距"
        }
        else {
            reason = "相反方向的正反面证据仍接近"
        }
        return OrientationSelection(
            value:accepted ? best.candidate.semantic : .uncertain,
            confidence:min(max(compositeDelta, 0), 1),
            winner:best.candidate,
            axis:axis.axis.rawValue,
            axisConfidence:axis.confidence,
            layoutDelta:layoutDelta,
            languageDelta:languageDelta,
            recognitionDelta:recognitionDelta,
            evidenceReason:reason
        )
    }

    private static func layoutUprightness(
        _ blocks:[OCRBlock]
    )->Float {
        guard !blocks.isEmpty else { return 0.5 }
        let heights = blocks.map { Float($0.boundingBox.height) }.sorted()
        let medianHeight = max(heights[heights.count / 2], 0.001)
        var hierarchySignal:Float = 0
        var hierarchyWeight:Float = 0
        var footerSignal:Float = 0
        var footerWeight:Float = 0
        for block in blocks {
            let height = Float(block.boundingBox.height)
            let centerY = Float(block.boundingBox.midY)
            let prominence = min(max(height / medianHeight - 1.10, 0), 2.5)
            if prominence > 0,
               block.text.count >= 4 {
                let weight = prominence
                    * min(Float(block.text.count) / 8, 2)
                hierarchySignal += (centerY - 0.5) * 2 * weight
                hierarchyWeight += weight
            }
            if isLikelyFooterMarker(block.text) {
                footerSignal += (0.5 - centerY) * 2
                footerWeight += 1
            }
        }
        let hierarchy = hierarchyWeight > 0
            ? hierarchySignal / hierarchyWeight : 0
        let footer = footerWeight > 0
            ? footerSignal / footerWeight : 0
        return min(max(0.5 + hierarchy * 0.35 + footer * 0.22, 0), 1)
    }

    private static func isLikelyFooterMarker(_ text:String)->Bool {
        let scalars = text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        guard !scalars.isEmpty,
              scalars.count <= 12 else { return false }
        let digits = scalars.filter {
            CharacterSet.decimalDigits.contains($0)
        }.count
        let punctuation = scalars.filter {
            CharacterSet.punctuationCharacters.contains($0)
                || CharacterSet.symbols.contains($0)
        }.count
        return digits > 0
            && Float(digits + punctuation) / Float(scalars.count) >= 0.62
    }

    private static func languagePlausibility(
        _ blocks:[OCRBlock]
    )->Float {
        let common = Set("的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会可主发年动同工也能下过子说产种面而方后多定行学法所民得经十三之进着等部度家电力里如水化高自二理起小物现实加量都两体制机当使点从业本去把性好应开它合还因由其些然前外天政四日那社义事平形相全表间样与关各重新线内数正心反你明看原又么利比或但质气第向道命此变条只没结解问意建月公无系军很情者最立代想已通并提直题党程展五果料象员革位入常文总次品式活设及管特件长求老头基资边流路级少图山统接知较将组见计别她手角期根论运农指几九区强放决西被干做必战先回则任取据处理世车两")
        var validCount = 0
        var commonCount = 0
        var totalCount = 0
        var coherentBlocks = 0
        for block in blocks {
            var blockValid = 0
            for character in block.text {
                totalCount += 1
                if isNaturalDocumentCharacter(character) {
                    validCount += 1
                    blockValid += 1
                }
                if common.contains(character) {
                    commonCount += 1
                }
            }
            if block.text.count >= 2,
               Float(blockValid) / Float(max(block.text.count, 1)) >= 0.75 {
                coherentBlocks += 1
            }
        }
        guard totalCount > 0 else { return 0 }
        let validRatio = Float(validCount) / Float(totalCount)
        let commonRatio = min(
            Float(commonCount) / Float(max(totalCount, 1)) * 3,
            1
        )
        let coherentRatio = Float(coherentBlocks)
            / Float(max(blocks.count, 1))
        return min(
            max(validRatio * 0.52 + commonRatio * 0.23
                + coherentRatio * 0.25, 0),
            1
        )
    }

    private static func isNaturalDocumentCharacter(
        _ character:Character
    )->Bool {
        character.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            let isHan = (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0xF900...0xFAFF).contains(value)
            return isHan
                || CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }

    private static func recognize(
        in image:CGImage,
        orientation:CGImagePropertyOrientation,
        level:VNRequestTextRecognitionLevel
    )->RecognitionPass {
        let startedAt = Date()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = level == .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.minimumTextHeight = 0.006
        let handler = VNImageRequestHandler(
            cgImage:image,
            orientation:orientation,
            options:[:]
        )
        do {
            try handler.perform([request])
        }
        catch {
            return RecognitionPass(
                blocks:[],
                score:0,
                averageConfidence:0,
                characterCount:0,
                processingMilliseconds:milliseconds(since:startedAt)
            )
        }
        let blocks:[OCRBlock] = (request.results ?? []).compactMap {
            observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            let text = candidate.string.trimmingCharacters(
                in:.whitespacesAndNewlines
            )
            guard !text.isEmpty else { return nil }
            return OCRBlock(
                text:text,
                boundingBox:observation.boundingBox,
                confidence:candidate.confidence
            )
        }
        let characterCount = blocks.reduce(0) { $0 + $1.text.count }
        let confidenceTotal = blocks.reduce(Float.zero) {
            $0 + $1.confidence
        }
        let averageConfidence = blocks.isEmpty
            ? 0 : confidenceTotal / Float(blocks.count)
        let score = blocks.reduce(Float.zero) { partial, block in
            let usefulCharacters = min(max(block.text.count, 1), 16)
            return partial + block.confidence * Float(usefulCharacters)
        } + Float(blocks.count) * 0.20
        return RecognitionPass(
            blocks:blocks,
            score:score,
            averageConfidence:averageConfidence,
            characterCount:characterCount,
            processingMilliseconds:milliseconds(since:startedAt)
        )
    }

    private static func analysisCGImage(_ image:UIImage)->CGImage? {
        guard let source = CIImage(image:image) else { return image.cgImage }
        let extent = source.extent
        let longest = max(extent.width, extent.height)
        let scale = min(1, maximumAnalysisEdge / max(longest, 1))
        let normalized = source.transformed(
            by:CGAffineTransform(
                translationX:-extent.minX,
                y:-extent.minY
            )
        ).transformed(
            by:CGAffineTransform(scaleX:scale, y:scale)
        )
        return context.createCGImage(normalized, from:normalized.extent)
    }

    static func rotate(
        _ image:UIImage,
        clockwiseQuarterTurns:Int
    )->UIImage {
        let turns = ((clockwiseQuarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }
        guard let source = CIImage(image:image) else { return image }
        let property:CGImagePropertyOrientation
        switch turns {
        case 1:
            property = .right
        case 2:
            property = .down
        default:
            property = .left
        }
        let oriented = source.oriented(property)
        let normalized = oriented.transformed(
            by:CGAffineTransform(
                translationX:-oriented.extent.minX,
                y:-oriented.extent.minY
            )
        )
        guard let output = context.createCGImage(
            normalized,
            from:normalized.extent
        ) else { return image }
        return UIImage(cgImage:output, scale:image.scale, orientation:.up)
    }

    nonisolated static func rotated(
        _ corners:ScanCorners,
        clockwiseQuarterTurns:Int
    )->ScanCorners {
        let turns = ((clockwiseQuarterTurns % 4) + 4) % 4
        guard turns != 0 else { return corners }
        func rotate(_ point:CGPoint)->CGPoint {
            switch turns {
            case 1:
                return CGPoint(x:1 - point.y, y:point.x)
            case 2:
                return CGPoint(x:1 - point.x, y:1 - point.y)
            default:
                return CGPoint(x:point.y, y:1 - point.x)
            }
        }
        switch turns {
        case 1:
            return ScanCorners(
                topLeft:rotate(corners.bottomLeft),
                topRight:rotate(corners.topLeft),
                bottomRight:rotate(corners.topRight),
                bottomLeft:rotate(corners.bottomRight)
            )
        case 2:
            return ScanCorners(
                topLeft:rotate(corners.bottomRight),
                topRight:rotate(corners.bottomLeft),
                bottomRight:rotate(corners.topLeft),
                bottomLeft:rotate(corners.topRight)
            )
        default:
            return ScanCorners(
                topLeft:rotate(corners.topRight),
                topRight:rotate(corners.bottomRight),
                bottomRight:rotate(corners.bottomLeft),
                bottomLeft:rotate(corners.topLeft)
            )
        }
    }

    private static func milliseconds(since date:Date)->Int {
        max(0, Int(Date().timeIntervalSince(date) * 1_000))
    }

    private static func percent(_ value:Float)->String {
        String(format:"%.1f%%", value * 100)
    }

    private static func signedPercent(_ value:Float)->String {
        String(format:"%+.1f%%", value * 100)
    }
}
