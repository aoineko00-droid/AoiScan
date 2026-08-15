//
//  DocumentPaperNormalizer.swift
//  AoiScan
//

import UIKit
import CoreImage


struct PaperNormalizationEvaluationResult:Codable {
    let eligible:Bool
    let accepted:Bool
    let reason:String
    let originalBrightness:Float
    let candidateBrightness:Float?
    let brightnessGain:Float
    let neutralityGain:Float
    let highlightClippingIncrease:Float
    let processingMilliseconds:Int
    let originalTopBrightness:Float?
    let originalMiddleBrightness:Float?
    let originalBottomBrightness:Float?
    let candidateTopBrightness:Float?
    let candidateMiddleBrightness:Float?
    let candidateBottomBrightness:Float?
    let originalGradient:Float?
    let candidateGradient:Float?
    let gradientReduction:Float?
    let darkestRegionGain:Float?
    let uniformityGain:Float?
    let shadowReduction:Float?
    let originalWhiteCoverage:Float?
    let candidateWhiteCoverage:Float?
    let whiteCoverageGain:Float?
    let originalEdgeWhiteCoverage:Float?
    let candidateEdgeWhiteCoverage:Float?
    let edgeWhiteCoverageGain:Float?
    let nonPaperHighlightClippingIncrease:Float?
    let originalTopPaperSaturation:Float?
    let originalMiddlePaperSaturation:Float?
    let originalBottomPaperSaturation:Float?
    let candidateTopPaperSaturation:Float?
    let candidateMiddlePaperSaturation:Float?
    let candidateBottomPaperSaturation:Float?
    let originalRegionalColorDifference:Float?
    let candidateRegionalColorDifference:Float?
    let regionalColorDifferenceReduction:Float?
    let originalMinimumLocalWhiteCoverage:Float?
    let candidateMinimumLocalWhiteCoverage:Float?
    let minimumLocalWhiteCoverageGain:Float?
    let originalBottomMinimumWhiteCoverage:Float?
    let candidateBottomMinimumWhiteCoverage:Float?
    let bottomMinimumWhiteCoverageGain:Float?
    let candidateLocalizedShadowFraction:Float?
    let originalLocalWhiteCoverages:[Float?]?
    let candidateLocalWhiteCoverages:[Float?]?
    let paperEvaluationSampleRatio:Float?
    let protectedContentExclusionRatio:Float?
    let localPaperEvaluationSampleRatios:[Float?]?
    let surfaceMode:String?
    let renderProtectedContentRatio:Float?
    let protectionMaskReused:Bool?
    let neutralInkRatio:Float?
    let confirmedNeutralInkRatio:Float?
    let connectedWeakInkRatio:Float?
    let redBlueInkRatio:Float?
    let localizedColorRatio:Float?
    let colorContentRatio:Float?
    let rejectedFaintInterferenceRatio:Float?
}


enum PaperNormalizationSurfaceMode:String,Codable {
    case stableLowFrequency
    case contentAwareWhiteCanvas
}


struct PaperProtectionMask {
    let width:Int
    let height:Int
    let values:[UInt8]
    let neutralInkValues:[UInt8]
    let colorContentValues:[UInt8]
    let colorEvaluationValues:[UInt8]
    let neutralInkRatio:Float?
    let confirmedNeutralInkRatio:Float?
    let connectedWeakInkRatio:Float?
    let redBlueInkRatio:Float?
    let localizedColorRatio:Float?
    let colorContentRatio:Float?
    let colorEvaluationRatio:Float?
    let rejectedFaintInterferenceRatio:Float?
    let colorMasksAligned:Bool

    var protectedRatio:Float {
        guard !values.isEmpty else { return 0 }
        let count = values.reduce(0) { partial, value in
            partial + (value >= 8 ? 1 : 0)
        }
        return Float(count) / Float(values.count)
    }
}


struct PaperNormalizationCandidate {
    let image:UIImage
    let protectionMask:PaperProtectionMask?
    let processingMilliseconds:Int
    let textMaskRasterizationMilliseconds:Int
}


/// Gives light, low-saturation paper a scanner-style neutral background while
/// preserving dark ink and saturated colors. A low-frequency page field makes
/// the correction spatial: bright areas remain stable while darker thirds and
/// local falloff are lifted toward the same scanner-white target.
enum DocumentPaperNormalizer {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    /// Selects non-red/blue color that differs materially from the local page
    /// field. Absolute saturation alone is deliberately insufficient: warm
    /// ambient light can tint every paper pixel without making it content.
    private static let localizedColorCubeData:Data = {
        let dimension = 24
        var values = [Float]()
        values.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Float(blueIndex) / Float(dimension - 1)
            for greenIndex in 0..<dimension {
                let green = Float(greenIndex) / Float(dimension - 1)
                for redIndex in 0..<dimension {
                    let red = Float(redIndex) / Float(dimension - 1)
                    let maximum = max(red, green, blue)
                    let minimum = min(red, green, blue)
                    let saturation = maximum > 0.001
                        ? (maximum - minimum) / maximum : 0
                    let luminance = red * 0.2126
                        + green * 0.7152 + blue * 0.0722
                    let isRedOrBlue = (
                        red > green * 1.065 && red > blue * 1.045
                    ) || (
                        blue > red * 1.045 && blue > green * 1.035
                    )
                    let threshold:Float = luminance > 0.65
                        ? 0.065 : 0.080
                    let mask = isRedOrBlue
                        ? 0
                        : min(
                            max((saturation - threshold) / 0.11, 0),
                            1
                        )
                    values.append(contentsOf:[mask, mask, mask, 1])
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer:$0) }
    }()

    private static let redBlueInkCoreCubeData:Data = {
        let dimension = 32
        var values = [Float]()
        values.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Float(blueIndex) / Float(dimension - 1)
            for greenIndex in 0..<dimension {
                let green = Float(greenIndex) / Float(dimension - 1)
                for redIndex in 0..<dimension {
                    let red = Float(redIndex) / Float(dimension - 1)
                    let maximum = max(red, green, blue)
                    let minimum = min(red, green, blue)
                    let saturation = maximum > 0.001
                        ? (maximum - minimum) / maximum : 0
                    let luminance = red * 0.2126
                        + green * 0.7152 + blue * 0.0722
                    let isRedCore = red > green * 1.075
                        && red > blue * 1.055
                    let isBlueCore = blue > red * 1.055
                        && blue > green * 1.045
                    let threshold:Float = luminance > 0.65
                        ? 0.075 : 0.060
                    let mask = isRedCore || isBlueCore
                        ? min(max((saturation - threshold) / 0.10, 0), 1)
                        : 0
                    values.append(contentsOf:[mask, mask, mask, 1])
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer:$0) }
    }()

    static func isEligible(
        _ analysis:ColorTemperatureResult?
    )->Bool {
        guard let analysis else { return false }
        let brightness = paperBrightness(analysis)
        return analysis.validSampleRatio >= 0.12
            && brightness >= 0.68
            && analysis.backgroundSaturation <= 0.18
    }

    static func needsNormalization(
        _ analysis:ColorTemperatureResult?
    )->Bool {
        guard let analysis,
              isEligible(analysis) else { return false }
        return paperBrightness(analysis) < 0.982
            || abs(analysis.labYellowBias) >= 2.2
            || abs(log(max(analysis.redBlueRatio, 0.001))) >= 0.018
    }

    /// Strong white-paper mode is deliberately narrower than the ordinary
    /// paper candidate. It is used before quality OCR, so only pages with
    /// broad, bright and low-saturation paper evidence may enter it.
    static func shouldUseScannerWhiteBaseline(
        _ analysis:ColorTemperatureResult?,
        visual:BaselineVisualPreflightResult
    )->Bool {
        guard let analysis,
              analysis.validSampleRatio >= 0.20,
              analysis.backgroundSaturation <= 0.10,
              paperBrightness(analysis) >= 0.72,
              visual.backgroundBrightness >= 0.78,
              min(
                visual.topBrightness,
                visual.middleBrightness,
                visual.bottomBrightness
              ) >= 0.70,
              visual.shadowSeverity <= 0.30,
              visual.backgroundUniformity >= 0.58 else { return false }

        return needsNormalization(analysis)
            || visual.illuminationGradient >= 0.020
            || min(
                visual.topBrightness,
                visual.middleBrightness,
                visual.bottomBrightness
            ) < 0.985
    }

    static func enhance(
        image:UIImage,
        contentImage:UIImage? = nil,
        blocks:[OCRBlock],
        analysis:ColorTemperatureResult,
        mode:PaperNormalizationSurfaceMode = .stableLowFrequency
    )->UIImage {
        makeCandidate(
            image:image,
            contentImage:contentImage,
            blocks:blocks,
            analysis:analysis,
            mode:mode
        ).image
    }

    static func makeCandidate(
        image:UIImage,
        contentImage:UIImage? = nil,
        blocks:[OCRBlock],
        analysis:ColorTemperatureResult,
        mode:PaperNormalizationSurfaceMode = .stableLowFrequency
    )->PaperNormalizationCandidate {
        let startedAt = Date()
        guard isEligible(analysis),
              let source = CIImage(image:image) else {
            return PaperNormalizationCandidate(
                image:image,
                protectionMask:nil,
                processingMilliseconds:milliseconds(since:startedAt),
                textMaskRasterizationMilliseconds:0
            )
        }

        let extent = source.extent
        let foregroundSource:CIImage
        if let contentImage,
           let requestedForeground = CIImage(image:contentImage),
           abs(requestedForeground.extent.width - extent.width) < 0.5,
           abs(requestedForeground.extent.height - extent.height) < 0.5 {
            foregroundSource = requestedForeground.transformed(
                by:CGAffineTransform(
                    translationX:extent.minX
                        - requestedForeground.extent.minX,
                    y:extent.minY
                        - requestedForeground.extent.minY
                )
            )
            .cropped(to:extent)
        }
        else {
            foregroundSource = source
        }
        let hasDedicatedWhiteBalance = DocumentWhiteBalanceEnhancer
            .correction(for:analysis) != nil
        let neutralized:CIImage
        if hasDedicatedWhiteBalance {
            neutralized = source
        }
        else {
            let neutral = (
                analysis.averageRed
                    + analysis.averageGreen
                    + analysis.averageBlue
            ) / 3
            let strength:Float = 0.30
            func gain(
                _ channel:Float,
                lower:Float,
                upper:Float
            )->Float {
                let raw = neutral / max(channel, 0.001)
                return min(
                    max(1 + (raw - 1) * strength, lower),
                    upper
                )
            }
            let redGain = gain(
                analysis.averageRed,
                lower:0.972,
                upper:1.025
            )
            let greenGain = gain(
                analysis.averageGreen,
                lower:0.988,
                upper:1.012
            )
            let blueGain = gain(
                analysis.averageBlue,
                lower:0.972,
                upper:1.030
            )
            neutralized = source.applyingFilter(
                "CIColorMatrix",
                parameters:[
                    "inputRVector":CIVector(
                        x:CGFloat(redGain), y:0, z:0, w:0
                    ),
                    "inputGVector":CIVector(
                        x:0, y:CGFloat(greenGain), z:0, w:0
                    ),
                    "inputBVector":CIVector(
                        x:0, y:0, z:CGFloat(blueGain), w:0
                    ),
                    "inputAVector":CIVector(x:0, y:0, z:0, w:1)
                ]
            )
            .cropped(to:extent)
        }

        let grayscale = neutralized.applyingFilter(
            "CIColorControls",
            parameters:[kCIInputSaturationKey:0]
        )
        .cropped(to:extent)
        let shortSide = min(extent.width, extent.height)
        let morphologyRadius = min(max(shortSide * 0.007, 7), 20)
        let backgroundField = neutralized
            .clampedToExtent()
            .applyingFilter(
                "CIMorphologyMaximum",
                parameters:[kCIInputRadiusKey:morphologyRadius]
            )
            .applyingFilter(
                "CIGaussianBlur",
                parameters:[
                    kCIInputRadiusKey:min(max(shortSide * 0.045, 36), 112)
                ]
            )
            .cropped(to:extent)
        // Content restoration must react to stroke-scale contrast, not to the
        // broad low-frequency field. Using the page field here classified
        // warm folds and paper texture as ink and blended them back over the
        // white canvas.
        let strokeRadius = min(max(shortSide * 0.0012, 2), 6)
        let strokeBackground = grayscale
            .clampedToExtent()
            .applyingFilter(
                "CIMorphologyMaximum",
                parameters:[kCIInputRadiusKey:strokeRadius]
            )
            .cropped(to:extent)
        let localInkSupportMask = strokeBackground.applyingFilter(
            "CIDifferenceBlendMode",
            parameters:[kCIInputBackgroundImageKey:grayscale]
        )
        .applyingFilter(
            "CIColorMatrix",
            parameters:[
                "inputRVector":CIVector(x:16, y:0, z:0, w:0),
                "inputGVector":CIVector(x:0, y:16, z:0, w:0),
                "inputBVector":CIVector(x:0, y:0, z:16, w:0),
                "inputAVector":CIVector(x:0, y:0, z:0, w:1),
                "inputBiasVector":CIVector(
                    x:-0.40, y:-0.40, z:-0.40, w:0
                )
            ]
        )
        .applyingFilter(
            "CIColorClamp",
            parameters:[
                "inputMinComponents":CIVector(x:0, y:0, z:0, w:1),
                "inputMaxComponents":CIVector(x:1, y:1, z:1, w:1)
            ]
        )
        .cropped(to:extent)
        // Gray/black restoration uses a stricter stroke threshold than color
        // protection. Broad folds and paper grain often differ from their
        // neighborhood by 2-5%; printed strokes normally provide at least an
        // 8% stroke-scale separation.
        let strictInkSupportMask = strokeBackground.applyingFilter(
            "CIDifferenceBlendMode",
            parameters:[kCIInputBackgroundImageKey:grayscale]
        )
        .applyingFilter(
            "CIColorMatrix",
            parameters:[
                "inputRVector":CIVector(x:12.5, y:0, z:0, w:0),
                "inputGVector":CIVector(x:0, y:12.5, z:0, w:0),
                "inputBVector":CIVector(x:0, y:0, z:12.5, w:0),
                "inputAVector":CIVector(x:0, y:0, z:0, w:1),
                "inputBiasVector":CIVector(
                    x:-1, y:-1, z:-1, w:0
                )
            ]
        )
        .applyingFilter(
            "CIColorClamp",
            parameters:[
                "inputMinComponents":CIVector(x:0, y:0, z:0, w:1),
                "inputMaxComponents":CIVector(x:1, y:1, z:1, w:1)
            ]
        )
        .cropped(to:extent)

        // Color is content only when it differs from the page's own local
        // field. This prevents a uniform warm cast from protecting most of
        // the sheet, while still retaining coherent green graphics and other
        // genuinely printed color.
        let backgroundGrayscale = backgroundField.applyingFilter(
            "CIColorControls",
            parameters:[kCIInputSaturationKey:0]
        )
        .cropped(to:extent)
        // Divide RGB by its own luminance before comparing with the page
        // field. A darker region with the same warm chromaticity therefore
        // produces almost no color evidence; only an actual hue/chroma change
        // survives this comparison.
        let normalizedLocalColor = grayscale.applyingFilter(
            "CIDivideBlendMode",
            parameters:[kCIInputBackgroundImageKey:neutralized]
        )
        .cropped(to:extent)
        let normalizedPageColor = backgroundGrayscale.applyingFilter(
            "CIDivideBlendMode",
            parameters:[kCIInputBackgroundImageKey:backgroundField]
        )
        .cropped(to:extent)
        let relativeColorDifference = normalizedLocalColor.applyingFilter(
            "CIDifferenceBlendMode",
            parameters:[kCIInputBackgroundImageKey:normalizedPageColor]
        )
        .applyingFilter(
            "CIColorControls",
            parameters:[kCIInputSaturationKey:0]
        )
        .cropped(to:extent)
        let relativeColorSupportMask = relativeColorDifference.applyingFilter(
            "CIColorMatrix",
            parameters:[
                "inputRVector":CIVector(x:20, y:0, z:0, w:0),
                "inputGVector":CIVector(x:0, y:20, z:0, w:0),
                "inputBVector":CIVector(x:0, y:0, z:20, w:0),
                "inputAVector":CIVector(x:0, y:0, z:0, w:1),
                "inputBiasVector":CIVector(
                    x:-0.80, y:-0.80, z:-0.80, w:0
                )
            ]
        )
        .applyingFilter(
            "CIColorClamp",
            parameters:[
                "inputMinComponents":CIVector(x:0, y:0, z:0, w:1),
                "inputMaxComponents":CIVector(x:1, y:1, z:1, w:1)
            ]
        )
        .cropped(to:extent)
        // Red/blue ink must also have a clear stroke-scale transition. The
        // six-percent floor intentionally excludes most pale show-through.
        let colorStrokeSupportMask = strokeBackground.applyingFilter(
            "CIDifferenceBlendMode",
            parameters:[kCIInputBackgroundImageKey:grayscale]
        )
        .applyingFilter(
            "CIColorMatrix",
            parameters:[
                "inputRVector":CIVector(x:16.67, y:0, z:0, w:0),
                "inputGVector":CIVector(x:0, y:16.67, z:0, w:0),
                "inputBVector":CIVector(x:0, y:0, z:16.67, w:0),
                "inputAVector":CIVector(x:0, y:0, z:0, w:1),
                "inputBiasVector":CIVector(x:-1, y:-1, z:-1, w:0)
            ]
        )
        .applyingFilter(
            "CIColorClamp",
            parameters:[
                "inputMinComponents":CIVector(x:0, y:0, z:0, w:1),
                "inputMaxComponents":CIVector(x:1, y:1, z:1, w:1)
            ]
        )
        .cropped(to:extent)
        let localizedColorCoreMask = neutralized.applyingFilter(
            "CIColorCube",
            parameters:[
                "inputCubeDimension":24,
                "inputCubeData":localizedColorCubeData
            ]
        )
        .cropped(to:extent)
        let localizedColorEvaluationMask = localizedColorCoreMask
            .applyingFilter(
            "CIMultiplyCompositing",
            parameters:[kCIInputBackgroundImageKey:relativeColorSupportMask]
        )
        .cropped(to:extent)
        let localizedColorMask = localizedColorEvaluationMask
        .clampedToExtent()
        .applyingFilter(
            "CIMorphologyMaximum",
            parameters:[kCIInputRadiusKey:1.0]
        )
        .applyingFilter(
            "CIGaussianBlur",
            parameters:[kCIInputRadiusKey:0.35]
        )
        .cropped(to:extent)
        let redBlueInkCoreMask = neutralized.applyingFilter(
            "CIColorCube",
            parameters:[
                "inputCubeDimension":32,
                "inputCubeData":redBlueInkCoreCubeData
            ]
        )
        .cropped(to:extent)
        let localizedRedBlueInkMask = redBlueInkCoreMask.applyingFilter(
            "CIMultiplyCompositing",
            parameters:[kCIInputBackgroundImageKey:colorStrokeSupportMask]
        )
        .applyingFilter(
            "CIMultiplyCompositing",
            parameters:[kCIInputBackgroundImageKey:relativeColorSupportMask]
        )
        .cropped(to:extent)
        let colorProtectionRadius = min(
            max(shortSide * 0.0008, 1.5),
            4
        )
        let expandedRedBlueInkMask = localizedRedBlueInkMask
            .clampedToExtent()
            .applyingFilter(
                "CIMorphologyMaximum",
                parameters:[kCIInputRadiusKey:colorProtectionRadius]
            )
            .applyingFilter(
                "CIGaussianBlur",
                parameters:[kCIInputRadiusKey:0.5]
            )
            .cropped(to:extent)
        let colorProtectionMask = expandedRedBlueInkMask.applyingFilter(
            "CIMaximumCompositing",
            parameters:[kCIInputBackgroundImageKey:localizedColorMask]
        )
        .cropped(to:extent)

        let paperBase:CIImage
        let contentMask:CIImage
        var confirmedNeutralProtectionMask:CIImage?
        var connectedWeakProtectionMask:CIImage?
        var faintInterferenceCandidateMask:CIImage?
        var textMaskRasterizationMilliseconds = 0
        switch mode {
        case .stableLowFrequency:
            // This is the stable 23:43 behavior: normalize the page against a
            // continuous RGB low-frequency field instead of classifying every
            // pixel as paper or content. Dark ink remains a ratio to its local
            // paper and therefore does not need a broad protection mask.
            let divided = backgroundField.applyingFilter(
                "CIDivideBlendMode",
                parameters:[kCIInputBackgroundImageKey:neutralized]
            )
            .applyingFilter(
                "CIColorMatrix",
                parameters:[
                    "inputRVector":CIVector(x:0.995, y:0, z:0, w:0),
                    "inputGVector":CIVector(x:0, y:0.995, z:0, w:0),
                    "inputBVector":CIVector(x:0, y:0, z:0.995, w:0),
                    "inputAVector":CIVector(x:0, y:0, z:0, w:1)
                ]
            )
            .applyingFilter(
                "CIColorClamp",
                parameters:[
                    "inputMinComponents":CIVector(x:0, y:0, z:0, w:1),
                    "inputMaxComponents":CIVector(x:1, y:1, z:1, w:1)
                ]
            )
            .cropped(to:extent)
            paperBase = divided
            contentMask = colorProtectionMask

        case .contentAwareWhiteCanvas:
            let scannerWhite = CIImage(
                color:CIColor(
                    red:1,
                    green:1,
                    blue:1,
                    alpha:1
                )
            )
            .cropped(to:extent)
            let recognizedToneMask = grayscale.applyingFilter(
                "CIColorMatrix",
                parameters:[
                    "inputRVector":CIVector(x:-4, y:0, z:0, w:0),
                    "inputGVector":CIVector(x:0, y:-4, z:0, w:0),
                    "inputBVector":CIVector(x:0, y:0, z:-4, w:0),
                    "inputAVector":CIVector(x:0, y:0, z:0, w:1),
                    "inputBiasVector":CIVector(
                        x:3.1, y:3.1, z:3.1, w:0
                    )
                ]
            )
            .applyingFilter(
                "CIColorClamp",
                parameters:[
                    "inputMinComponents":CIVector(x:0, y:0, z:0, w:1),
                    "inputMaxComponents":CIVector(x:1, y:1, z:1, w:1)
                ]
            )
            .cropped(to:extent)
            let absoluteStrongInkMask = grayscale.applyingFilter(
                "CIColorMatrix",
                parameters:[
                    "inputRVector":CIVector(x:-7.14, y:0, z:0, w:0),
                    "inputGVector":CIVector(x:0, y:-7.14, z:0, w:0),
                    "inputBVector":CIVector(x:0, y:0, z:-7.14, w:0),
                    "inputAVector":CIVector(x:0, y:0, z:0, w:1),
                    "inputBiasVector":CIVector(x:3, y:3, z:3, w:0)
                ]
            )
            .applyingFilter(
                "CIColorClamp",
                parameters:[
                    "inputMinComponents":CIVector(x:0, y:0, z:0, w:1),
                    "inputMaxComponents":CIVector(x:1, y:1, z:1, w:1)
                ]
            )
            .cropped(to:extent)
            // A local-difference mask contains the boundary of a broad solid
            // stroke but not its centre. Expand that boundary before applying
            // the absolute dark-tone gate so large headings and QR modules do
            // not turn into outlines on the pure-white canvas.
            let definiteInkNeighborhood = localInkSupportMask
                .clampedToExtent()
                .applyingFilter(
                    "CIMorphologyMaximum",
                    parameters:[
                        kCIInputRadiusKey:min(
                            max(shortSide * 0.0030, 3),
                            8
                        )
                    ]
                )
                .cropped(to:extent)
            let strongInkMask = absoluteStrongInkMask.applyingFilter(
                "CIMultiplyCompositing",
                parameters:[
                    kCIInputBackgroundImageKey:definiteInkNeighborhood
                ]
            )
            .cropped(to:extent)
            let pixelWidth = max(Int(extent.width.rounded()), 1)
            let pixelHeight = max(Int(extent.height.rounded()), 1)
            let textRegionMask:CIImage
            let textMaskStartedAt = Date()
            if let mask = NormalizedRectangleRasterizer
                .grayscaleMaskImage(
                    width:pixelWidth,
                    height:pixelHeight,
                    rectangles:blocks.map(\.boundingBox),
                    expansion:0.06
                ) {
                textRegionMask = CIImage(cgImage:mask)
                    .transformed(
                        by:CGAffineTransform(
                            translationX:extent.minX,
                            y:extent.minY
                        )
                    )
                    .cropped(to:extent)
            }
            else {
                textRegionMask = CIImage(
                    color:CIColor(red:0, green:0, blue:0, alpha:1)
                ).cropped(to:extent)
            }
            textMaskRasterizationMilliseconds = milliseconds(
                since:textMaskStartedAt
            )
            let recognizedInkMask = recognizedToneMask.applyingFilter(
                "CIMultiplyCompositing",
                parameters:[kCIInputBackgroundImageKey:strictInkSupportMask]
            )
            .applyingFilter(
                "CIMultiplyCompositing",
                parameters:[kCIInputBackgroundImageKey:textRegionMask]
            )
            .cropped(to:extent)
            let confirmedNeutralInkMask = recognizedInkMask.applyingFilter(
                "CIMaximumCompositing",
                parameters:[kCIInputBackgroundImageKey:strongInkMask]
            )
            .cropped(to:extent)
            // Weak gray pixels are restored only next to a confirmed front
            // stroke. This retains antialiasing and fine glyph edges without
            // reviving isolated pale show-through or fold texture.
            let weakInkCandidateMask = recognizedToneMask.applyingFilter(
                "CIMultiplyCompositing",
                parameters:[kCIInputBackgroundImageKey:textRegionMask]
            )
            .cropped(to:extent)
            let confirmedInkNeighborhood = confirmedNeutralInkMask
                .clampedToExtent()
                .applyingFilter(
                    "CIMorphologyMaximum",
                    parameters:[
                        kCIInputRadiusKey:min(
                            max(shortSide * 0.0032, 4),
                            9
                        )
                    ]
                )
                .cropped(to:extent)
            let connectedWeakInkMask = weakInkCandidateMask.applyingFilter(
                "CIMultiplyCompositing",
                parameters:[
                    kCIInputBackgroundImageKey:confirmedInkNeighborhood
                ]
            )
            .cropped(to:extent)
            let inkMask = confirmedNeutralInkMask.applyingFilter(
                "CIMaximumCompositing",
                parameters:[kCIInputBackgroundImageKey:connectedWeakInkMask]
            )
            .clampedToExtent()
            .applyingFilter(
                "CIMorphologyMaximum",
                parameters:[
                    kCIInputRadiusKey:min(max(shortSide * 0.00045, 1), 2)
                ]
            )
            .applyingFilter(
                "CIGaussianBlur",
                parameters:[kCIInputRadiusKey:0.30]
            )
            .cropped(to:extent)
            contentMask = inkMask.applyingFilter(
                "CIMaximumCompositing",
                parameters:[kCIInputBackgroundImageKey:colorProtectionMask]
            )
            .cropped(to:extent)
            confirmedNeutralProtectionMask = confirmedNeutralInkMask
            connectedWeakProtectionMask = connectedWeakInkMask
            faintInterferenceCandidateMask = weakInkCandidateMask
            paperBase = scannerWhite
        }

        let colorSafe = foregroundSource.applyingFilter(
            "CIBlendWithMask",
            parameters:[
                kCIInputBackgroundImageKey:paperBase,
                kCIInputMaskImageKey:contentMask
            ]
        )
        .cropped(to:extent)

        guard let output = context.createCGImage(colorSafe, from:extent) else {
            return PaperNormalizationCandidate(
                image:image,
                protectionMask:nil,
                processingMilliseconds:milliseconds(since:startedAt),
                textMaskRasterizationMilliseconds:
                    textMaskRasterizationMilliseconds
            )
        }
        return PaperNormalizationCandidate(
            image:UIImage(
                cgImage:output,
                scale:image.scale,
                orientation:.up
            ),
            protectionMask:sampledProtectionMask(
                contentMask,
                extent:extent,
                confirmedNeutralMask:confirmedNeutralProtectionMask,
                connectedWeakMask:connectedWeakProtectionMask,
                redBlueMask:expandedRedBlueInkMask,
                localizedColorMask:localizedColorMask,
                colorEvaluationRedBlueMask:localizedRedBlueInkMask,
                colorEvaluationLocalizedColorMask:
                    localizedColorEvaluationMask,
                faintCandidateMask:faintInterferenceCandidateMask
            ),
            processingMilliseconds:milliseconds(since:startedAt),
            textMaskRasterizationMilliseconds:
                textMaskRasterizationMilliseconds
        )
    }

    static func evaluate(
        baseline:UIImage,
        candidate:UIImage,
        blocks:[OCRBlock],
        originalAnalysis:ColorTemperatureResult?,
        candidateAnalysis:ColorTemperatureResult?,
        protectionMask:PaperProtectionMask? = nil,
        mode:PaperNormalizationSurfaceMode = .stableLowFrequency
    )->PaperNormalizationEvaluationResult? {
        let startedAt = Date()
        guard let originalAnalysis,
              isEligible(originalAnalysis) else { return nil }
        let originalBrightness = paperBrightness(originalAnalysis)
        guard let candidateAnalysis else {
            return PaperNormalizationEvaluationResult(
                eligible:true,
                accepted:false,
                reason:"纸张标准化候选没有取得足够背景样本",
                originalBrightness:originalBrightness,
                candidateBrightness:nil,
                brightnessGain:0,
                neutralityGain:0,
                highlightClippingIncrease:0,
                processingMilliseconds:milliseconds(since:startedAt),
                originalTopBrightness:nil,
                originalMiddleBrightness:nil,
                originalBottomBrightness:nil,
                candidateTopBrightness:nil,
                candidateMiddleBrightness:nil,
                candidateBottomBrightness:nil,
                originalGradient:nil,
                candidateGradient:nil,
                gradientReduction:nil,
                darkestRegionGain:nil,
                uniformityGain:nil,
                shadowReduction:nil,
                originalWhiteCoverage:nil,
                candidateWhiteCoverage:nil,
                whiteCoverageGain:nil,
                originalEdgeWhiteCoverage:nil,
                candidateEdgeWhiteCoverage:nil,
                edgeWhiteCoverageGain:nil,
                nonPaperHighlightClippingIncrease:nil,
                originalTopPaperSaturation:nil,
                originalMiddlePaperSaturation:nil,
                originalBottomPaperSaturation:nil,
                candidateTopPaperSaturation:nil,
                candidateMiddlePaperSaturation:nil,
                candidateBottomPaperSaturation:nil,
                originalRegionalColorDifference:nil,
                candidateRegionalColorDifference:nil,
                regionalColorDifferenceReduction:nil,
                originalMinimumLocalWhiteCoverage:nil,
                candidateMinimumLocalWhiteCoverage:nil,
                minimumLocalWhiteCoverageGain:nil,
                originalBottomMinimumWhiteCoverage:nil,
                candidateBottomMinimumWhiteCoverage:nil,
                bottomMinimumWhiteCoverageGain:nil,
                candidateLocalizedShadowFraction:nil,
                originalLocalWhiteCoverages:nil,
                candidateLocalWhiteCoverages:nil,
                paperEvaluationSampleRatio:nil,
                protectedContentExclusionRatio:nil,
                localPaperEvaluationSampleRatios:nil,
                surfaceMode:mode.rawValue,
                renderProtectedContentRatio:
                    protectionMask?.protectedRatio,
                protectionMaskReused:protectionMask != nil,
                neutralInkRatio:protectionMask?.neutralInkRatio,
                confirmedNeutralInkRatio:
                    protectionMask?.confirmedNeutralInkRatio,
                connectedWeakInkRatio:
                    protectionMask?.connectedWeakInkRatio,
                redBlueInkRatio:protectionMask?.redBlueInkRatio,
                localizedColorRatio:
                    protectionMask?.localizedColorRatio,
                colorContentRatio:
                    protectionMask?.colorContentRatio,
                rejectedFaintInterferenceRatio:
                    protectionMask?.rejectedFaintInterferenceRatio
            )
        }

        let originalSurface = IlluminationQualityAnalyzer.analyze(
            image:baseline,
            blocks:blocks
        )
        let candidateSurface = IlluminationQualityAnalyzer.analyze(
            image:candidate,
            blocks:blocks
        )
        let neutralityGain = neutralityDistance(originalAnalysis)
            - neutralityDistance(candidateAnalysis)
        let legacyClippingIncrease = max(
            highlightFraction(candidate)
                - highlightFraction(baseline),
            0
        )
        let coverage = paperCoverage(
            baseline:baseline,
            candidate:candidate,
            protectionMask:protectionMask
        )
        let usesWhiteCanvas = mode == .contentAwareWhiteCanvas
        let sharedMaskSurfaceAvailable = !usesWhiteCanvas
            || (
                coverage.protectionMaskReused
                    && coverage.originalMaskedPaperSurface != nil
                    && coverage.candidateMaskedPaperSurface != nil
            )
        let originalSpatialBrightness:Float
        let candidateBrightness:Float
        let originalGradient:Float
        let candidateGradient:Float
        let originalDarkest:Float
        let candidateDarkest:Float
        let originalUniformity:Float
        let candidateUniformity:Float
        let originalLocalizedShadow:Float
        let candidateLocalizedShadow:Float
        let originalTopBrightness:Float
        let originalMiddleBrightness:Float
        let originalBottomBrightness:Float
        let candidateTopBrightness:Float
        let candidateMiddleBrightness:Float
        let candidateBottomBrightness:Float
        if usesWhiteCanvas,
           let originalMasked = coverage.originalMaskedPaperSurface,
           let candidateMasked = coverage.candidateMaskedPaperSurface {
            originalSpatialBrightness = originalMasked.averageBrightness
            candidateBrightness = candidateMasked.averageBrightness
            originalGradient = originalMasked.gradient
            candidateGradient = candidateMasked.gradient
            originalDarkest = originalMasked.darkestLocalBrightness
            candidateDarkest = candidateMasked.darkestLocalBrightness
            originalUniformity = originalMasked.backgroundUniformity
            candidateUniformity = candidateMasked.backgroundUniformity
            originalLocalizedShadow = originalMasked.localizedShadowFraction
            candidateLocalizedShadow = candidateMasked.localizedShadowFraction
            originalTopBrightness = originalMasked.topBrightness
            originalMiddleBrightness = originalMasked.middleBrightness
            originalBottomBrightness = originalMasked.bottomBrightness
            candidateTopBrightness = candidateMasked.topBrightness
            candidateMiddleBrightness = candidateMasked.middleBrightness
            candidateBottomBrightness = candidateMasked.bottomBrightness
        }
        else {
            originalSpatialBrightness = averageBrightness(originalSurface)
            candidateBrightness = averageBrightness(candidateSurface)
            originalGradient = originalSurface.gradient
            candidateGradient = candidateSurface.gradient
            originalDarkest = darkestBrightness(originalSurface)
            candidateDarkest = darkestBrightness(candidateSurface)
            originalUniformity = originalSurface.backgroundUniformity
            candidateUniformity = candidateSurface.backgroundUniformity
            originalLocalizedShadow = originalSurface.localizedShadowFraction
            candidateLocalizedShadow = candidateSurface.localizedShadowFraction
            originalTopBrightness = originalSurface.topBrightness
            originalMiddleBrightness = originalSurface.middleBrightness
            originalBottomBrightness = originalSurface.bottomBrightness
            candidateTopBrightness = candidateSurface.topBrightness
            candidateMiddleBrightness = candidateSurface.middleBrightness
            candidateBottomBrightness = candidateSurface.bottomBrightness
        }
        let brightnessGain = candidateBrightness - originalSpatialBrightness
        let gradientReduction = originalGradient - candidateGradient
        let darkestRegionGain = candidateDarkest - originalDarkest
        let uniformityGain = candidateUniformity - originalUniformity
        let shadowReduction = usesWhiteCanvas
            ? originalLocalizedShadow - candidateLocalizedShadow
            : originalSurface.shadowSeverity - candidateSurface.shadowSeverity
        let meaningfulGain = brightnessGain >= 0.006
            || darkestRegionGain >= 0.010
            || gradientReduction >= 0.010
            || neutralityGain >= 0.008
            || coverage.whiteCoverageGain >= 0.20
        let brightnessSafe = brightnessGain >= -0.005
            && brightnessGain <= 0.20
        let saturationSafe = candidateAnalysis.backgroundSaturation
            <= originalAnalysis.backgroundSaturation + 0.010
        // Turning classified paper pure white is the intended result, not a
        // clipping defect. Only newly clipped non-paper content is unsafe.
        let clippingSafe = coverage.nonPaperClippingIncrease <= 0.005
        let surfaceDirectionSafe = gradientReduction >= -0.004
            && darkestRegionGain >= -0.004
            && shadowReduction >= -0.010
        let requiresGradientCorrection = originalGradient >= 0.030
        let gradientGainRequired = min(
            max(originalGradient * 0.28, 0.010),
            0.030
        )
        let surfaceGainSafe = !requiresGradientCorrection
            || gradientReduction >= gradientGainRequired
            || candidateGradient <= 0.015
        // The 128px binary grid is retained for diagnostics, but it must not
        // reject text-dense pages merely because protected antialias pixels
        // fall just below 98.5%. The white-canvas route is deterministic and
        // instead relies on continuous surface brightness, gradient, color,
        // clipping and the independent content-retention gate.
        let protectionScopeSafe = !usesWhiteCanvas
            || coverage.protectedContentExclusionRatio <= 0.38
        let whiteCoverageSafe = !usesWhiteCanvas
            || coverage.candidateWhiteCoverage >= 0.90
        let edgeWhiteCoverageGain:Float?
        if let originalEdgeCoverage = coverage.originalEdgeWhiteCoverage,
           let candidateEdgeCoverage = coverage.candidateEdgeWhiteCoverage {
            edgeWhiteCoverageGain = max(
                candidateEdgeCoverage - originalEdgeCoverage,
                0
            )
        }
        else {
            edgeWhiteCoverageGain = nil
        }
        // Edge samples include crop-border interpolation and occasional
        // content. Use the final coverage as the safety signal; relative gain
        // is no longer meaningful after direct paper replacement.
        let edgeWhiteCoverageSafe:Bool
        if usesWhiteCanvas {
            edgeWhiteCoverageSafe = coverage.candidateEdgeWhiteCoverage
                .map { $0 >= 0.85 } == true
        }
        else if let original = coverage.originalEdgeWhiteCoverage,
                let candidate = coverage.candidateEdgeWhiteCoverage {
            edgeWhiteCoverageSafe = candidate >= original - 0.01
        }
        else {
            edgeWhiteCoverageSafe = true
        }
        let localWhiteCoverageSafe = !usesWhiteCanvas
            || (
                coverage.candidateMinimumLocalWhiteCoverage
                    .map { $0 >= 0.85 } == true
                && coverage.candidateBottomMinimumWhiteCoverage
                    .map { $0 >= 0.85 } == true
            )
        let regionalColorSafe:Bool
        if usesWhiteCanvas {
            regionalColorSafe = coverage.candidateMaximumSaturation
                    .map { $0 <= 0.012 } == true
                && coverage.candidateRegionalColorDifference
                    .map { $0 <= 0.008 } == true
        }
        else if let originalDifference = coverage
                    .originalRegionalColorDifference,
                let candidateDifference = coverage
                    .candidateRegionalColorDifference {
            regionalColorSafe = candidateDifference
                <= originalDifference + 0.003
        }
        else {
            regionalColorSafe = true
        }
        let scannerSurfaceReached = !usesWhiteCanvas
            || (
                candidateDarkest >= 0.985
                    && candidateGradient <= 0.015
                    && candidateLocalizedShadow <= 0.06
            )
        let accepted = meaningfulGain
            && brightnessSafe
            && saturationSafe
            && clippingSafe
            && sharedMaskSurfaceAvailable
            && surfaceDirectionSafe
            && surfaceGainSafe
            && protectionScopeSafe
            && whiteCoverageSafe
            && edgeWhiteCoverageSafe
            && localWhiteCoverageSafe
            && regionalColorSafe
            && scannerSurfaceReached
        let reason:String
        if !brightnessSafe {
            reason = "纸张标准化的背景亮度变化超出安全范围"
        }
        else if !saturationSafe {
            reason = "纸张标准化提高了背景饱和度"
        }
        else if !clippingSafe {
            reason = "纸张标准化导致非纸面细节溢出增加超过0.5%"
        }
        else if !sharedMaskSurfaceAvailable {
            reason = "白画布无法复用实际保护mask或未保护纸面样本不足"
        }
        else if !surfaceDirectionSafe {
            reason = "纸张标准化使最暗区域、光照梯度或阴影反向恶化"
        }
        else if !surfaceGainSafe {
            reason = "纸张标准化未明显缩小整页上下亮度差"
        }
        else if !protectionScopeSafe {
            reason = "白画布前景保护范围超过38%，疑似恢复了纸纹或阴影"
        }
        else if !whiteCoverageSafe {
            reason = "扫描白整页覆盖率低于90%"
        }
        else if !edgeWhiteCoverageSafe {
            reason = usesWhiteCanvas
                ? "纸张四边的扫描白覆盖率低于85%"
                : "稳定去阴影使纸张四边亮度覆盖退化"
        }
        else if !localWhiteCoverageSafe {
            reason = "白画布的最差局部或下半页纯白覆盖率低于85%"
        }
        else if !regionalColorSafe {
            reason = usesWhiteCanvas
                ? "扫描白底仍存在上中下区域色差"
                : "稳定去阴影增加了上中下区域色差"
        }
        else if !scannerSurfaceReached {
            reason = "扫描白底的最暗区域或上下梯度未达标"
        }
        else if !meaningfulGain {
            reason = "候选未达到最低纸张提白或中性化收益"
        }
        else if usesWhiteCanvas
            && (
                coverage.candidateWhiteCoverage < 0.93
            || (coverage.candidateEdgeWhiteCoverage ?? 0) < 0.70
                || (coverage.candidateMinimumLocalWhiteCoverage ?? 0) < 0.93
            ) {
            reason = "候选通过扫描白近边界容错和非纸面细节保护检查"
        }
        else if !usesWhiteCanvas {
            reason = "稳定去阴影候选通过亮度、色差和非纸面细节保护检查"
        }
        else {
            reason = "候选通过整页扫描白底、中性化和非纸面细节保护检查"
        }
        let regionalColorDifferenceReduction:Float?
        if let originalDifference = coverage.originalRegionalColorDifference,
           let candidateDifference = coverage.candidateRegionalColorDifference {
            regionalColorDifferenceReduction = max(
                originalDifference - candidateDifference,
                0
            )
        }
        else {
            regionalColorDifferenceReduction = nil
        }
        let minimumLocalWhiteCoverageGain = coverage
            .candidateMinimumLocalWhiteCoverage.flatMap { candidate in
                coverage.originalMinimumLocalWhiteCoverage.map {
                    max(candidate - $0, 0)
                }
            }
        let bottomMinimumWhiteCoverageGain = coverage
            .candidateBottomMinimumWhiteCoverage.flatMap { candidate in
                coverage.originalBottomMinimumWhiteCoverage.map {
                    max(candidate - $0, 0)
                }
            }
        return PaperNormalizationEvaluationResult(
            eligible:true,
            accepted:accepted,
            reason:reason,
            originalBrightness:originalSpatialBrightness,
            candidateBrightness:candidateBrightness,
            brightnessGain:brightnessGain,
            neutralityGain:neutralityGain,
            highlightClippingIncrease:legacyClippingIncrease,
            processingMilliseconds:milliseconds(since:startedAt),
            originalTopBrightness:originalTopBrightness,
            originalMiddleBrightness:originalMiddleBrightness,
            originalBottomBrightness:originalBottomBrightness,
            candidateTopBrightness:candidateTopBrightness,
            candidateMiddleBrightness:candidateMiddleBrightness,
            candidateBottomBrightness:candidateBottomBrightness,
            originalGradient:originalGradient,
            candidateGradient:candidateGradient,
            gradientReduction:gradientReduction,
            darkestRegionGain:darkestRegionGain,
            uniformityGain:uniformityGain,
            shadowReduction:shadowReduction,
            originalWhiteCoverage:coverage.originalWhiteCoverage,
            candidateWhiteCoverage:coverage.candidateWhiteCoverage,
            whiteCoverageGain:coverage.whiteCoverageGain,
            originalEdgeWhiteCoverage:
                coverage.originalEdgeWhiteCoverage,
            candidateEdgeWhiteCoverage:
                coverage.candidateEdgeWhiteCoverage,
            edgeWhiteCoverageGain:edgeWhiteCoverageGain,
            nonPaperHighlightClippingIncrease:
                coverage.nonPaperClippingIncrease,
            originalTopPaperSaturation:
                coverage.originalRegionSaturations[0],
            originalMiddlePaperSaturation:
                coverage.originalRegionSaturations[1],
            originalBottomPaperSaturation:
                coverage.originalRegionSaturations[2],
            candidateTopPaperSaturation:
                coverage.candidateRegionSaturations[0],
            candidateMiddlePaperSaturation:
                coverage.candidateRegionSaturations[1],
            candidateBottomPaperSaturation:
                coverage.candidateRegionSaturations[2],
            originalRegionalColorDifference:
                coverage.originalRegionalColorDifference,
            candidateRegionalColorDifference:
                coverage.candidateRegionalColorDifference,
            regionalColorDifferenceReduction:
                regionalColorDifferenceReduction,
            originalMinimumLocalWhiteCoverage:
                coverage.originalMinimumLocalWhiteCoverage,
            candidateMinimumLocalWhiteCoverage:
                coverage.candidateMinimumLocalWhiteCoverage,
            minimumLocalWhiteCoverageGain:
                minimumLocalWhiteCoverageGain,
            originalBottomMinimumWhiteCoverage:
                coverage.originalBottomMinimumWhiteCoverage,
            candidateBottomMinimumWhiteCoverage:
                coverage.candidateBottomMinimumWhiteCoverage,
            bottomMinimumWhiteCoverageGain:
                bottomMinimumWhiteCoverageGain,
            candidateLocalizedShadowFraction:candidateLocalizedShadow,
            originalLocalWhiteCoverages:
                coverage.originalLocalWhiteCoverages,
            candidateLocalWhiteCoverages:
                coverage.candidateLocalWhiteCoverages,
            paperEvaluationSampleRatio:
                coverage.paperEvaluationSampleRatio,
            protectedContentExclusionRatio:
                coverage.protectedContentExclusionRatio,
            localPaperEvaluationSampleRatios:
                coverage.localPaperEvaluationSampleRatios,
            surfaceMode:mode.rawValue,
            renderProtectedContentRatio:
                coverage.renderProtectedContentRatio,
            protectionMaskReused:coverage.protectionMaskReused,
            neutralInkRatio:protectionMask?.neutralInkRatio,
            confirmedNeutralInkRatio:
                protectionMask?.confirmedNeutralInkRatio,
            connectedWeakInkRatio:
                protectionMask?.connectedWeakInkRatio,
            redBlueInkRatio:protectionMask?.redBlueInkRatio,
            localizedColorRatio:protectionMask?.localizedColorRatio,
            colorContentRatio:protectionMask?.colorContentRatio,
            rejectedFaintInterferenceRatio:
                protectionMask?.rejectedFaintInterferenceRatio
        )
    }

    private static func averageBrightness(
        _ result:IlluminationQualityResult
    )->Float {
        (
            result.topBrightness
                + result.middleBrightness
                + result.bottomBrightness
        ) / 3
    }

    private static func darkestBrightness(
        _ result:IlluminationQualityResult
    )->Float {
        min(
            result.topBrightness,
            result.middleBrightness,
            result.bottomBrightness
        )
    }

    private static func paperBrightness(
        _ analysis:ColorTemperatureResult
    )->Float {
        analysis.averageRed * 0.2126
            + analysis.averageGreen * 0.7152
            + analysis.averageBlue * 0.0722
    }

    private static func neutralityDistance(
        _ analysis:ColorTemperatureResult
    )->Float {
        let ratio = min(
            abs(log(max(analysis.redBlueRatio, 0.001))),
            0.30
        ) / 0.30
        let yellow = min(abs(analysis.labYellowBias), 30) / 30
        return ratio * 0.62 + yellow * 0.38
    }

    private static func highlightFraction(_ image:UIImage)->Float {
        guard let cgImage = image.cgImage else { return 0 }
        let width = 128
        let ratio = CGFloat(cgImage.height)
            / CGFloat(max(cgImage.width, 1))
        let height = max(Int((CGFloat(width) * ratio).rounded()), 1)
        var bytes = [UInt8](repeating:0, count:width * height * 4)
        guard let bitmap = CGContext(
            data:&bytes,
            width:width,
            height:height,
            bitsPerComponent:8,
            bytesPerRow:width * 4,
            space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        bitmap.interpolationQuality = .low
        bitmap.draw(
            cgImage,
            in:CGRect(x:0, y:0, width:width, height:height)
        )

        var eligibleCount = 0
        var clippedCount = 0
        for index in stride(from:0, to:bytes.count, by:4) {
            let red = Float(bytes[index]) / 255
            let green = Float(bytes[index + 1]) / 255
            let blue = Float(bytes[index + 2]) / 255
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum > 0.001
                ? (maximum - minimum) / maximum : 0
            let luminance = red * 0.2126 + green * 0.7152
                + blue * 0.0722
            guard luminance >= 0.55,
                  saturation <= 0.20 else { continue }
            eligibleCount += 1
            if maximum >= 0.992 { clippedCount += 1 }
        }
        guard eligibleCount > 0 else { return 0 }
        return Float(clippedCount) / Float(eligibleCount)
    }

    private struct PaperCoverage {
        let originalWhiteCoverage:Float
        let candidateWhiteCoverage:Float
        let whiteCoverageGain:Float
        let originalEdgeWhiteCoverage:Float?
        let candidateEdgeWhiteCoverage:Float?
        let nonPaperClippingIncrease:Float
        let originalRegionSaturations:[Float?]
        let candidateRegionSaturations:[Float?]
        let originalRegionalColorDifference:Float?
        let candidateRegionalColorDifference:Float?
        let originalLocalWhiteCoverages:[Float?]
        let candidateLocalWhiteCoverages:[Float?]
        let paperEvaluationSampleRatio:Float
        let protectedContentExclusionRatio:Float
        let localPaperEvaluationSampleRatios:[Float?]
        let renderProtectedContentRatio:Float?
        let protectionMaskReused:Bool
        let originalMaskedPaperSurface:MaskedPaperSurface?
        let candidateMaskedPaperSurface:MaskedPaperSurface?

        var candidateMaximumSaturation:Float? {
            candidateRegionSaturations.compactMap { $0 }.max()
        }

        var originalMinimumLocalWhiteCoverage:Float? {
            guard originalLocalWhiteCoverages.count == 9,
                  originalLocalWhiteCoverages.allSatisfy({ $0 != nil })
            else { return nil }
            return originalLocalWhiteCoverages.compactMap { $0 }.min()
        }

        var candidateMinimumLocalWhiteCoverage:Float? {
            guard candidateLocalWhiteCoverages.count == 9,
                  candidateLocalWhiteCoverages.allSatisfy({ $0 != nil })
            else { return nil }
            return candidateLocalWhiteCoverages.compactMap { $0 }.min()
        }

        var originalBottomMinimumWhiteCoverage:Float? {
            guard originalLocalWhiteCoverages.count >= 9 else { return nil }
            let values = originalLocalWhiteCoverages[6...8]
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            return values.compactMap { $0 }.min()
        }

        var candidateBottomMinimumWhiteCoverage:Float? {
            guard candidateLocalWhiteCoverages.count >= 9 else { return nil }
            let values = candidateLocalWhiteCoverages[6...8]
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            return values.compactMap { $0 }.min()
        }
    }

    /// Surface statistics measured only from pixels that the renderer treated
    /// as paper. The content-aware white canvas must not let protected green
    /// bars, ink, or glyph antialiasing re-enter the generic shadow metric.
    private struct MaskedPaperSurface {
        let topBrightness:Float
        let middleBrightness:Float
        let bottomBrightness:Float
        let darkestLocalBrightness:Float
        let gradient:Float
        let backgroundUniformity:Float
        let localizedShadowFraction:Float

        var averageBrightness:Float {
            (topBrightness + middleBrightness + bottomBrightness) / 3
        }
    }

    private static func paperCoverage(
        baseline:UIImage,
        candidate:UIImage,
        protectionMask:PaperProtectionMask?
    )->PaperCoverage {
        guard let first = sampledRGBA(baseline),
              let second = sampledRGBA(candidate),
              first.width == second.width,
              first.height == second.height,
              first.pixels.count == second.pixels.count else {
            return PaperCoverage(
                originalWhiteCoverage:0,
                candidateWhiteCoverage:0,
                whiteCoverageGain:0,
                originalEdgeWhiteCoverage:nil,
                candidateEdgeWhiteCoverage:nil,
                nonPaperClippingIncrease:1,
                originalRegionSaturations:[nil, nil, nil],
                candidateRegionSaturations:[nil, nil, nil],
                originalRegionalColorDifference:nil,
                candidateRegionalColorDifference:nil,
                originalLocalWhiteCoverages:[Float?](
                    repeating:nil,
                    count:9
                ),
                candidateLocalWhiteCoverages:[Float?](
                    repeating:nil,
                    count:9
                ),
                paperEvaluationSampleRatio:0,
                protectedContentExclusionRatio:0,
                localPaperEvaluationSampleRatios:[Float?](
                    repeating:nil,
                    count:9
                ),
                renderProtectedContentRatio:
                    protectionMask?.protectedRatio,
                protectionMaskReused:false,
                originalMaskedPaperSurface:nil,
                candidateMaskedPaperSurface:nil
            )
        }
        let originalLuminances = first.pixels.map { pixel in
            pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
        }
        let originalSaturations = first.pixels.map { pixel in
            let maximum = max(pixel.r, pixel.g, pixel.b)
            let minimum = min(pixel.r, pixel.g, pixel.b)
            return maximum > 0.001
                ? (maximum - minimum) / maximum : 0
        }
        // Evaluation must exclude the same kind of content that rendering
        // deliberately preserves. A brightness-only denominator classifies
        // antialiased glyph edges as blank paper, so text-dense lower cells
        // appear to have poor white coverage even when the actual sheet is
        // already scanner white.
        let canReuseProtectionMask = protectionMask?.width == first.width
            && protectionMask?.height == first.height
            && protectionMask?.values.count == first.pixels.count
        let protectedContent:[Bool]
        if canReuseProtectionMask,
           let protectionMask {
            protectedContent = protectionMask.values.map { $0 >= 8 }
        }
        else {
            protectedContent = evaluationProtectedContentMask(
                luminances:originalLuminances,
                saturations:originalSaturations,
                width:first.width,
                height:first.height
            )
        }
        let protectedContentCount = protectedContent.reduce(0) {
            $0 + ($1 ? 1 : 0)
        }
        var paperCount = 0
        var originalWhiteCount = 0
        var candidateWhiteCount = 0
        var edgePaperCount = 0
        var originalEdgeWhiteCount = 0
        var candidateEdgeWhiteCount = 0
        var nonPaperCount = 0
        var newlyClippedNonPaperCount = 0
        var originalRegions = [RegionColorAccumulator](
            repeating:RegionColorAccumulator(),
            count:3
        )
        var candidateRegions = [RegionColorAccumulator](
            repeating:RegionColorAccumulator(),
            count:3
        )
        var localPaperCounts = [Int](repeating:0, count:9)
        var localPixelCounts = [Int](repeating:0, count:9)
        var originalLocalWhiteCounts = [Int](repeating:0, count:9)
        var candidateLocalWhiteCounts = [Int](repeating:0, count:9)
        var originalSurfaceRegions = [DocumentLuminanceHistogram](
            repeating:DocumentLuminanceHistogram(),
            count:3
        )
        var candidateSurfaceRegions = [DocumentLuminanceHistogram](
            repeating:DocumentLuminanceHistogram(),
            count:3
        )
        var originalLocalSurfaceRegions = [DocumentLuminanceHistogram](
            repeating:DocumentLuminanceHistogram(),
            count:9
        )
        var candidateLocalSurfaceRegions = [DocumentLuminanceHistogram](
            repeating:DocumentLuminanceHistogram(),
            count:9
        )
        for index in first.pixels.indices {
            let original = first.pixels[index]
            let adjusted = second.pixels[index]
            let originalMinimum = min(original.r, original.g, original.b)
            let originalSaturation = originalSaturations[index]
            let originalLuminance = originalLuminances[index]
            let candidateMaximum = max(adjusted.r, adjusted.g, adjusted.b)
            let candidateMinimum = min(adjusted.r, adjusted.g, adjusted.b)
            let candidateSaturation = candidateMaximum > 0.001
                ? (candidateMaximum - candidateMinimum) / candidateMaximum : 0
            let candidateLuminance = adjusted.r * 0.2126
                + adjusted.g * 0.7152 + adjusted.b * 0.0722
            // Include warm folds and low-frequency shadow in the surface that
            // must become white, but exclude protected ink/color plus a small
            // halo around it. This keeps the 90% target strict for real paper
            // without penalizing intentionally preserved glyph edges.
            let isPaper = originalLuminance >= 0.65
                && originalSaturation <= 0.30
                && !protectedContent[index]
            // A deeper warm/pink fold is still page surface in scanner-white
            // mode. Keep the strict set for coverage and regional color
            // measurement, but do not count this broader light-pastel set as
            // protected foreground when checking newly clipped detail.
            let isLightPaperSurface = originalLuminance >= 0.65
                && originalSaturation <= 0.30
            let row = index / first.width
            let column = index % first.width
            let region = min(
                max(row * 3 / max(first.height, 1), 0),
                2
            )
            let localColumn = min(
                max(column * 3 / max(first.width, 1), 0),
                2
            )
            let localRegion = region * 3 + localColumn
            localPixelCounts[localRegion] += 1
            let edgeWidth = max(
                Int(
                    (Float(min(first.width, first.height)) * 0.035)
                        .rounded()
                ),
                2
            )
            let isInEdgeBand = row < edgeWidth
                || row >= first.height - edgeWidth
                || column < edgeWidth
                || column >= first.width - edgeWidth
            let isEdgePaperSurface = isInEdgeBand
                && originalLuminance >= 0.65
                && originalSaturation <= 0.30
                && !protectedContent[index]
            if isEdgePaperSurface {
                edgePaperCount += 1
                if originalLuminance >= 0.985,
                   originalSaturation <= 0.03 {
                    originalEdgeWhiteCount += 1
                }
                if candidateLuminance >= 0.985,
                   candidateSaturation <= 0.03 {
                    candidateEdgeWhiteCount += 1
                }
            }
            if isPaper {
                paperCount += 1
                localPaperCounts[localRegion] += 1
                originalRegions[region].add(original)
                candidateRegions[region].add(adjusted)
                let originalByte = luminanceByte(originalLuminance)
                let candidateByte = luminanceByte(candidateLuminance)
                originalSurfaceRegions[region].add(originalByte)
                candidateSurfaceRegions[region].add(candidateByte)
                originalLocalSurfaceRegions[localRegion].add(originalByte)
                candidateLocalSurfaceRegions[localRegion].add(candidateByte)
                // Use the same 98.5% scanner-white definition as the
                // regional surface target. The former 99.2% pixel threshold
                // rejected pages whose three regions had already reached
                // 98.7-100%, so the generated white result was never shown.
                if originalLuminance >= 0.985,
                   originalSaturation <= 0.03 {
                    originalWhiteCount += 1
                    originalLocalWhiteCounts[localRegion] += 1
                }
                if candidateLuminance >= 0.985,
                   candidateSaturation <= 0.03 {
                    candidateWhiteCount += 1
                    candidateLocalWhiteCounts[localRegion] += 1
                }
            }
            if !isLightPaperSurface {
                nonPaperCount += 1
                let originalClipped = originalMinimum >= 0.992
                let candidateClipped = candidateMinimum >= 0.992
                if candidateClipped && !originalClipped {
                    newlyClippedNonPaperCount += 1
                }
            }
        }
        let originalCoverage = paperCount > 0
            ? Float(originalWhiteCount) / Float(paperCount) : 0
        let candidateCoverage = paperCount > 0
            ? Float(candidateWhiteCount) / Float(paperCount) : 0
        let nonPaperIncrease = nonPaperCount > 0
            ? Float(newlyClippedNonPaperCount) / Float(nonPaperCount) : 0
        let originalEdgeCoverage = edgePaperCount >= 24
            ? Float(originalEdgeWhiteCount) / Float(edgePaperCount) : nil
        let candidateEdgeCoverage = edgePaperCount >= 24
            ? Float(candidateEdgeWhiteCount) / Float(edgePaperCount) : nil
        let originalColors = originalRegions.map { $0.result }
        let candidateColors = candidateRegions.map { $0.result }
        let originalLocalCoverages = localPaperCounts.indices.map { index in
            localPaperCounts[index] >= 24
                ? Float(originalLocalWhiteCounts[index])
                    / Float(localPaperCounts[index])
                : nil
        }
        let candidateLocalCoverages = localPaperCounts.indices.map { index in
            localPaperCounts[index] >= 24
                ? Float(candidateLocalWhiteCounts[index])
                    / Float(localPaperCounts[index])
                : nil
        }
        let localSampleRatios = localPaperCounts.indices.map { index in
            localPixelCounts[index] > 0
                ? Float(localPaperCounts[index])
                    / Float(localPixelCounts[index])
                : nil
        }
        let totalPixelCount = max(first.pixels.count, 1)
        return PaperCoverage(
            originalWhiteCoverage:originalCoverage,
            candidateWhiteCoverage:candidateCoverage,
            whiteCoverageGain:max(candidateCoverage - originalCoverage, 0),
            originalEdgeWhiteCoverage:originalEdgeCoverage,
            candidateEdgeWhiteCoverage:candidateEdgeCoverage,
            nonPaperClippingIncrease:nonPaperIncrease,
            originalRegionSaturations:originalColors.map { $0?.saturation },
            candidateRegionSaturations:candidateColors.map { $0?.saturation },
            originalRegionalColorDifference:regionalColorDifference(
                originalColors
            ),
            candidateRegionalColorDifference:regionalColorDifference(
                candidateColors
            ),
            originalLocalWhiteCoverages:originalLocalCoverages,
            candidateLocalWhiteCoverages:candidateLocalCoverages,
            paperEvaluationSampleRatio:
                Float(paperCount) / Float(totalPixelCount),
            protectedContentExclusionRatio:
                Float(protectedContentCount) / Float(totalPixelCount),
            localPaperEvaluationSampleRatios:localSampleRatios,
            renderProtectedContentRatio:
                protectionMask?.protectedRatio,
            protectionMaskReused:canReuseProtectionMask,
            originalMaskedPaperSurface:maskedPaperSurface(
                regions:originalSurfaceRegions,
                localRegions:originalLocalSurfaceRegions
            ),
            candidateMaskedPaperSurface:maskedPaperSurface(
                regions:candidateSurfaceRegions,
                localRegions:candidateLocalSurfaceRegions
            )
        )
    }

    private static func luminanceByte(_ value:Float)->UInt8 {
        UInt8(min(max(Int((value * 255).rounded()), 0), 255))
    }

    private static func maskedPaperSurface(
        regions:[DocumentLuminanceHistogram],
        localRegions:[DocumentLuminanceHistogram]
    )->MaskedPaperSurface? {
        guard regions.count == 3,
              localRegions.count == 9,
              regions.allSatisfy({ $0.count >= 24 }),
              localRegions.allSatisfy({ $0.count >= 24 }) else {
            return nil
        }
        func paperBrightness(
            _ histogram:DocumentLuminanceHistogram
        )->Float {
            histogram.mean(lowerQuantile:0.08, upperQuantile:0.96)
        }
        let regionBrightness = regions.map(paperBrightness)
        let localBrightness = localRegions.map(paperBrightness)
        let darkest = localBrightness.min()
            ?? regionBrightness.min() ?? 0
        let brightest = localBrightness.max()
            ?? regionBrightness.max() ?? 0
        let localizedShadowFractions:[Float] = localRegions.indices.map {
            index in
            let reference = localBrightness[index]
            let upper = min(max(reference - 0.075, 0.70), 0.91)
            let midToneFraction = localRegions[index].fraction(
                from:0.56,
                to:upper
            )
            let possiblePaperFraction = max(
                1 - localRegions[index].fraction(below:0.56),
                0.01
            )
            return min(midToneFraction / possiblePaperFraction, Float(1))
        }
        let localizedShadow = localizedShadowFractions.max() ?? 0
        return MaskedPaperSurface(
            topBrightness:regionBrightness[0],
            middleBrightness:regionBrightness[1],
            bottomBrightness:regionBrightness[2],
            darkestLocalBrightness:darkest,
            gradient:(regionBrightness.max() ?? 0)
                - (regionBrightness.min() ?? 0),
            backgroundUniformity:max(
                0,
                min(1, 1 - (brightest - darkest) * 3.4)
            ),
            localizedShadowFraction:localizedShadow
        )
    }

    private static func evaluationProtectedContentMask(
        luminances:[Float],
        saturations:[Float],
        width:Int,
        height:Int
    )->[Bool] {
        guard width > 0,
              height > 0,
              luminances.count == width * height,
              saturations.count == luminances.count else {
            return [Bool](repeating:false, count:luminances.count)
        }
        var seeds = [Bool](repeating:false, count:luminances.count)
        for index in luminances.indices {
            let luminance = luminances[index]
            let saturation = saturations[index]
            if saturation > 0.10 || luminance <= 0.58 {
                seeds[index] = true
                continue
            }
            // Gray antialiasing can still be quite bright. Require local
            // contrast so a broad warm shadow or gentle fold remains paper
            // and must pass the white-surface test.
            guard luminance < 0.82 else { continue }
            let row = index / width
            let column = index % width
            var localMaximum = luminance
            for rowOffset in -1...1 {
                let neighborRow = row + rowOffset
                guard neighborRow >= 0,
                      neighborRow < height else { continue }
                for columnOffset in -1...1 {
                    let neighborColumn = column + columnOffset
                    guard neighborColumn >= 0,
                          neighborColumn < width else { continue }
                    let neighborIndex = neighborRow * width + neighborColumn
                    localMaximum = max(
                        localMaximum,
                        luminances[neighborIndex]
                    )
                }
            }
            seeds[index] = localMaximum - luminance >= 0.10
        }

        // One evaluation pixel represents roughly 10-20 source pixels. This
        // single-cell expansion covers the protected stroke antialiasing and
        // the render mask's small blur without hiding broad page shadows.
        var expanded = seeds
        for index in seeds.indices where seeds[index] {
            let row = index / width
            let column = index % width
            for rowOffset in -1...1 {
                let neighborRow = row + rowOffset
                guard neighborRow >= 0,
                      neighborRow < height else { continue }
                for columnOffset in -1...1 {
                    let neighborColumn = column + columnOffset
                    guard neighborColumn >= 0,
                          neighborColumn < width else { continue }
                    expanded[neighborRow * width + neighborColumn] = true
                }
            }
        }
        return expanded
    }

    private struct RegionColor {
        let red:Float
        let green:Float
        let blue:Float

        var saturation:Float {
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            return maximum > 0.001
                ? (maximum - minimum) / maximum : 0
        }

        var chroma:(u:Float,v:Float) {
            let luminance = red * 0.2126
                + green * 0.7152 + blue * 0.0722
            return (blue - luminance, red - luminance)
        }
    }

    private struct RegionColorAccumulator {
        var red:Float = 0
        var green:Float = 0
        var blue:Float = 0
        var count:Int = 0

        mutating func add(_ pixel:RGBPixel) {
            red += pixel.r
            green += pixel.g
            blue += pixel.b
            count += 1
        }

        var result:RegionColor? {
            guard count >= 24 else { return nil }
            let divisor = Float(count)
            return RegionColor(
                red:red / divisor,
                green:green / divisor,
                blue:blue / divisor
            )
        }
    }

    private static func regionalColorDifference(
        _ colors:[RegionColor?]
    )->Float? {
        let valid = colors.compactMap { $0 }
        guard valid.count == 3 else { return nil }
        var maximumDifference:Float = 0
        for firstIndex in valid.indices {
            for secondIndex in valid.indices
                where secondIndex > firstIndex {
                let first = valid[firstIndex].chroma
                let second = valid[secondIndex].chroma
                maximumDifference = max(
                    maximumDifference,
                    hypot(first.u - second.u, first.v - second.v)
                )
            }
        }
        return maximumDifference
    }

    private struct RGBPixel {
        let r:Float
        let g:Float
        let b:Float
    }

    private struct SampledRGB {
        let width:Int
        let height:Int
        let pixels:[RGBPixel]
    }

    private static func sampledRGBA(_ image:UIImage)->SampledRGB? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 128
        let ratio = CGFloat(cgImage.height)
            / CGFloat(max(cgImage.width, 1))
        let height = max(Int((CGFloat(width) * ratio).rounded()), 1)
        var bytes = [UInt8](repeating:0, count:width * height * 4)
        guard let bitmap = CGContext(
            data:&bytes,
            width:width,
            height:height,
            bitsPerComponent:8,
            bytesPerRow:width * 4,
            space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        bitmap.interpolationQuality = .low
        bitmap.draw(cgImage, in:CGRect(x:0, y:0, width:width, height:height))
        let pixels = stride(from:0, to:bytes.count, by:4).map {
            RGBPixel(
                r:Float(bytes[$0]) / 255,
                g:Float(bytes[$0 + 1]) / 255,
                b:Float(bytes[$0 + 2]) / 255
            )
        }
        return SampledRGB(width:width, height:height, pixels:pixels)
    }

    private struct SampledMask {
        let width:Int
        let height:Int
        let values:[UInt8]
    }

    private static func sampledMask(
        _ mask:CIImage,
        extent:CGRect
    )->SampledMask? {
        let width = 128
        let ratio = extent.height / max(extent.width, 1)
        let height = max(Int((CGFloat(width) * ratio).rounded()), 1)
        let scale = CGFloat(width) / max(extent.width, 1)
        let scaledMask = mask.transformed(
            by:CGAffineTransform(scaleX:scale, y:scale)
        )
        let scaledExtent = CGRect(
            x:extent.minX * scale,
            y:extent.minY * scale,
            width:CGFloat(width),
            height:CGFloat(height)
        )
        guard let cgImage = context.createCGImage(
            scaledMask,
            from:scaledExtent
        ) else { return nil }
        var bytes = [UInt8](repeating:0, count:width * height)
        guard let bitmap = CGContext(
            data:&bytes,
            width:width,
            height:height,
            bitsPerComponent:8,
            bytesPerRow:width,
            space:CGColorSpaceCreateDeviceGray(),
            bitmapInfo:CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        bitmap.interpolationQuality = .low
        bitmap.draw(
            cgImage,
            in:CGRect(x:0, y:0, width:width, height:height)
        )
        return SampledMask(width:width, height:height, values:bytes)
    }

    private static func sampledProtectionMask(
        _ mask:CIImage,
        extent:CGRect,
        confirmedNeutralMask:CIImage?,
        connectedWeakMask:CIImage?,
        redBlueMask:CIImage?,
        localizedColorMask:CIImage?,
        colorEvaluationRedBlueMask:CIImage?,
        colorEvaluationLocalizedColorMask:CIImage?,
        faintCandidateMask:CIImage?
    )->PaperProtectionMask? {
        guard let final = sampledMask(mask, extent:extent) else {
            return nil
        }
        let confirmedNeutral = confirmedNeutralMask.flatMap {
            sampledMask($0, extent:extent)
        }
        let connectedWeak = connectedWeakMask.flatMap {
            sampledMask($0, extent:extent)
        }
        let redBlue = redBlueMask.flatMap {
            sampledMask($0, extent:extent)
        }
        let localizedColor = localizedColorMask.flatMap {
            sampledMask($0, extent:extent)
        }
        let colorEvaluationRedBlue = colorEvaluationRedBlueMask.flatMap {
            sampledMask($0, extent:extent)
        }
        let colorEvaluationLocalizedColor = colorEvaluationLocalizedColorMask.flatMap {
            sampledMask($0, extent:extent)
        }
        let faintCandidate = faintCandidateMask.flatMap {
            sampledMask($0, extent:extent)
        }
        // Rendering and evaluation color masks are required scanner-white
        // safety inputs. A failed sample must not silently become an empty
        // color domain, because empty color is accepted by design.
        guard let redBlue,
              let localizedColor,
              let colorEvaluationRedBlue,
              let colorEvaluationLocalizedColor else {
            return nil
        }
        let hasAlignedSubmasks = (
            isAligned(final, confirmedNeutral)
            && isAligned(final, connectedWeak)
            && isAligned(final, redBlue)
            && isAligned(final, localizedColor)
            && isAligned(final, colorEvaluationRedBlue)
            && isAligned(final, colorEvaluationLocalizedColor)
            && isAligned(final, faintCandidate)
        )
        guard hasAlignedSubmasks else { return nil }
        let neutralInkValues = combineMaskUnion(
            confirmedNeutral,
            connectedWeak,
            fallback:final
        )
        let colorContentValues = combineMaskUnion(
            redBlue,
            localizedColor,
            fallback:final
        )
        let colorEvaluationValues = combineMaskUnion(
            colorEvaluationRedBlue,
            colorEvaluationLocalizedColor,
            fallback:final
        )
        let colorEvaluationSampleCount = colorEvaluationValues.reduce(
            0
        ) { partial, value in
            partial + (value >= 8 ? 1 : 0)
        }
        let colorContentEvaluationRatio = Float(colorEvaluationSampleCount)
            / Float(max(final.values.count, 1))
        let rejectedFaintRatio:Float?
        if let faintCandidate,
           hasAlignedSubmasks,
           faintCandidate.width == final.width {
            let rejectedCount = faintCandidate.values.indices.reduce(0) {
                partial, index in
                partial + (
                    faintCandidate.values[index] >= 8
                        && final.values[index] < 8 ? 1 : 0
                )
            }
            rejectedFaintRatio = Float(rejectedCount)
                / Float(max(final.values.count, 1))
        }
        else {
            rejectedFaintRatio = nil
        }
        // Color and neutral-ink evidence are classifications, not mutually
        // exclusive ownership. A dark red/blue/green stroke normally has both
        // strong luminance contrast and real chroma. Removing the overlap
        // would erase exactly those colored glyph cores from the retention
        // denominator and could turn a true color loss into "no samples".
        let colorContentRatio = maskRatio(
            expectedWidth:final.width,
            expectedHeight:final.height,
            values:colorContentValues
        )
        return PaperProtectionMask(
            width:final.width,
            height:final.height,
            values:final.values,
            neutralInkValues:neutralInkValues,
            colorContentValues:colorContentValues,
            colorEvaluationValues:colorEvaluationValues,
            neutralInkRatio:maskRatio(
                expectedWidth:final.width,
                expectedHeight:final.height,
                values:neutralInkValues
            ),
            confirmedNeutralInkRatio:maskRatio(confirmedNeutral),
            connectedWeakInkRatio:exclusiveMaskRatio(
                connectedWeak,
                excluding:confirmedNeutral
            ),
            redBlueInkRatio:maskRatio(redBlue),
            localizedColorRatio:maskRatio(localizedColor),
            colorContentRatio:colorContentRatio,
            colorEvaluationRatio:colorContentEvaluationRatio,
            rejectedFaintInterferenceRatio:rejectedFaintRatio,
            colorMasksAligned:hasAlignedSubmasks
        )
    }

    private static func maskRatio(_ mask:SampledMask?)->Float? {
        guard let mask,
              !mask.values.isEmpty else { return nil }
        let protectedCount = mask.values.reduce(0) { partial, value in
            partial + (value >= 8 ? 1 : 0)
        }
        return Float(protectedCount) / Float(mask.values.count)
    }

    private static func maskRatio(
        expectedWidth:Int,
        expectedHeight:Int,
        values:[UInt8]?
    )->Float? {
        guard let values,
              !values.isEmpty,
              values.count == expectedWidth * expectedHeight else { return nil }
        let protectedCount = values.reduce(0) { partial, value in
            partial + (value >= 8 ? 1 : 0)
        }
        return Float(protectedCount)
            / Float(max(expectedWidth * expectedHeight, 1))
    }

    private static func exclusiveMaskRatio(
        _ mask:SampledMask?,
        excluding excluded:SampledMask?
    )->Float? {
        guard let mask,
              let excluded,
              mask.width == excluded.width,
              mask.height == excluded.height,
              mask.values.count == excluded.values.count,
              !mask.values.isEmpty else { return maskRatio(mask) }
        let exclusiveCount = mask.values.indices.reduce(0) {
            partial, index in
            partial + (
                mask.values[index] >= 8
                    && excluded.values[index] < 8 ? 1 : 0
            )
        }
        return Float(exclusiveCount) / Float(mask.values.count)
    }

    private static func isAligned(
        _ source:SampledMask,
        _ candidate:SampledMask?
    )->Bool {
        guard let candidate else { return true }
        return candidate.width == source.width
            && candidate.height == source.height
            && candidate.values.count == source.values.count
    }

    private static func combineMaskUnion(
        _ left:SampledMask?,
        _ right:SampledMask?,
        fallback:SampledMask
    )->[UInt8] {
        if let left,
           !isAligned(fallback, left)
           || left.values.count != left.width * left.height {
            return [UInt8](repeating:0, count:fallback.values.count)
        }
        if let right,
           !isAligned(fallback, right)
           || right.values.count != right.width * right.height {
            return [UInt8](repeating:0, count:fallback.values.count)
        }
        let leftValues = left?.values ?? fallback.values.map { _ in UInt8(0) }
        let rightValues = right?.values ?? fallback.values.map { _ in UInt8(0) }
        return (0..<leftValues.count).map {
            let merged = max(leftValues[$0], rightValues[$0])
            return merged
        }
    }

    private static func milliseconds(since date:Date)->Int {
        max(0, Int(Date().timeIntervalSince(date) * 1000))
    }
}
