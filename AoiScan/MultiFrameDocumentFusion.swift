//
//  MultiFrameDocumentFusion.swift
//  AoiScan
//

import Foundation
import UIKit
import CoreImage


struct DocumentFrameFusionInput {
    let id:UUID
    let image:UIImage
    let corners:ScanCorners

    init(
        id:UUID = UUID(),
        image:UIImage,
        corners:ScanCorners
    ) {
        self.id = id
        self.image = image
        self.corners = corners
    }
}


struct DocumentFrameFusionConfiguration {
    let maximumFrameCount:Int
    let maximumOutputLongEdge:CGFloat
    let minimumResolutionRatio:CGFloat
    let maximumAspectDifference:CGFloat
    let maximumBrightnessDifference:Float
    let maximumResidualDifference:Float
    let minimumRegionalSharpnessGain:Float
    let transitionFraction:CGFloat

    static let safeExperiment = DocumentFrameFusionConfiguration(
        maximumFrameCount:3,
        maximumOutputLongEdge:2_400,
        minimumResolutionRatio:0.84,
        maximumAspectDifference:0.035,
        maximumBrightnessDifference:0.055,
        maximumResidualDifference:0.075,
        minimumRegionalSharpnessGain:0.080,
        transitionFraction:0.055
    )
}


enum DocumentFrameFusionState:String,Codable {
    case fused
    case insufficientFrames
    case invalidReference
    case invalidGeometry
    case resolutionMismatch
    case exposureMismatch
    case alignmentFailed
    case noComplementaryDetail
    case renderingFailed
    case qualityRegression
}


struct DocumentFrameFusionMetrics:Codable {
    let outputPixelWidth:Int
    let outputPixelHeight:Int
    let maximumResidualDifference:Float
    let brightnessSpread:Float
    let topSharpnessGain:Float
    let middleSharpnessGain:Float
    let bottomSharpnessGain:Float
    let averageSharpnessGain:Float
    let colorRetention:Float
    let topFrameID:UUID
    let middleFrameID:UUID
    let bottomFrameID:UUID
    let distinctSourceFrameCount:Int
}


struct DocumentFrameFusionResult {
    /// Present only when every alignment and regression gate succeeds.
    let image:UIImage?
    let state:DocumentFrameFusionState
    let frameCount:Int
    let eligibleFrameCount:Int
    let processingMilliseconds:Int
    let metrics:DocumentFrameFusionMetrics?
    let reason:String
}


/// Experimental offline document fusion core.
///
/// Frames are first perspective-corrected into one document coordinate space.
/// The processor then permits regional fusion only when exposure, residual
/// alignment, regional sharpness and final color/quality regression checks all
/// pass. It is deliberately not connected to the camera production path.
enum MultiFrameDocumentFusion {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    static func fuse(
        reference:DocumentFrameFusionInput,
        candidates:[DocumentFrameFusionInput],
        configuration:DocumentFrameFusionConfiguration = .safeExperiment
    )->DocumentFrameFusionResult {
        let startedAt = Date()
        let uniqueCandidates = candidates.filter { $0.id != reference.id }
        let inputs = Array(
            ([reference] + uniqueCandidates)
                .prefix(max(configuration.maximumFrameCount, 1))
        )
        guard inputs.count >= 2 else {
            return result(
                state:.insufficientFrames,
                frameCount:inputs.count,
                eligibleFrameCount:0,
                startedAt:startedAt,
                reason:"至少需要2帧不同图像才能进行区域融合"
            )
        }

        guard valid(reference.corners),
              let naturalReference = rectify(reference) else {
            return result(
                state:.invalidReference,
                frameCount:inputs.count,
                eligibleFrameCount:0,
                startedAt:startedAt,
                reason:"基准帧纸张四角或透视拉正结果无效"
            )
        }

        let referenceLongEdge = max(
            naturalReference.extent.width,
            naturalReference.extent.height
        )
        guard referenceLongEdge >= 640 else {
            return result(
                state:.invalidReference,
                frameCount:inputs.count,
                eligibleFrameCount:0,
                startedAt:startedAt,
                reason:"基准文档拉正后分辨率不足"
            )
        }

        let outputScale = min(
            1,
            configuration.maximumOutputLongEdge / referenceLongEdge
        )
        let outputWidth = max(
            Int((naturalReference.extent.width * outputScale).rounded()),
            1
        )
        let outputHeight = max(
            Int((naturalReference.extent.height * outputScale).rounded()),
            1
        )
        let outputExtent = CGRect(
            x:0,
            y:0,
            width:outputWidth,
            height:outputHeight
        )

        guard let referenceFrame = commonFrame(
            input:reference,
            naturalImage:naturalReference,
            outputExtent:outputExtent
        ) else {
            return result(
                state:.renderingFailed,
                frameCount:inputs.count,
                eligibleFrameCount:0,
                startedAt:startedAt,
                reason:"无法生成基准帧的统一文档坐标"
            )
        }

        var geometryEligible = [referenceFrame]
        var rejectedForResolution = 0
        var rejectedForGeometry = 0
        for input in inputs.dropFirst() {
            guard valid(input.corners),
                  let natural = rectify(input) else {
                rejectedForGeometry += 1
                continue
            }
            let longEdge = max(natural.extent.width, natural.extent.height)
            let resolutionRatio = longEdge / max(referenceLongEdge, 1)
            let referenceAspect = naturalReference.extent.width
                / max(naturalReference.extent.height, 1)
            let candidateAspect = natural.extent.width
                / max(natural.extent.height, 1)
            let aspectDifference = abs(candidateAspect / referenceAspect - 1)
            guard resolutionRatio >= configuration.minimumResolutionRatio else {
                rejectedForResolution += 1
                continue
            }
            guard aspectDifference <= configuration.maximumAspectDifference,
                  let frame = commonFrame(
                    input:input,
                    naturalImage:natural,
                    outputExtent:outputExtent
                  ) else {
                rejectedForGeometry += 1
                continue
            }
            geometryEligible.append(frame)
        }

        guard geometryEligible.count >= 2 else {
            let state:DocumentFrameFusionState = rejectedForResolution > 0
                ? .resolutionMismatch : .invalidGeometry
            let reason = rejectedForResolution > 0
                ? "候选帧文档有效分辨率低于基准帧安全门槛"
                : "候选帧四角、长宽比或透视拉正结果不一致"
            return result(
                state:state,
                frameCount:inputs.count,
                eligibleFrameCount:geometryEligible.count,
                startedAt:startedAt,
                reason:reason
            )
        }

        var eligible = [referenceFrame]
        var rejectedForExposure = 0
        var rejectedForAlignment = 0
        var residuals = [Float]()
        for frame in geometryEligible.dropFirst() {
            let brightnessDifference = abs(
                frame.quality.brightness
                    - referenceFrame.quality.brightness
            )
            guard brightnessDifference
                    <= configuration.maximumBrightnessDifference else {
                rejectedForExposure += 1
                continue
            }
            let residual = residualDifference(
                referenceFrame.image,
                frame.image
            )
            guard residual <= configuration.maximumResidualDifference else {
                rejectedForAlignment += 1
                continue
            }
            residuals.append(residual)
            eligible.append(frame)
        }

        guard eligible.count >= 2 else {
            let state:DocumentFrameFusionState = rejectedForExposure > 0
                ? .exposureMismatch : .alignmentFailed
            let reason = rejectedForExposure > 0
                ? "帧间平均亮度差超过融合安全门槛"
                : "透视拉正后仍存在过大的帧间内容残差"
            return result(
                state:state,
                frameCount:inputs.count,
                eligibleFrameCount:eligible.count,
                startedAt:startedAt,
                reason:reason
            )
        }

        let top = winner(
            in:eligible,
            reference:referenceFrame,
            value:{ $0.quality.topSharpness },
            minimumGain:configuration.minimumRegionalSharpnessGain
        )
        let middle = winner(
            in:eligible,
            reference:referenceFrame,
            value:{ $0.quality.middleSharpness },
            minimumGain:configuration.minimumRegionalSharpnessGain
        )
        let bottom = winner(
            in:eligible,
            reference:referenceFrame,
            value:{ $0.quality.bottomSharpness },
            minimumGain:configuration.minimumRegionalSharpnessGain
        )
        let sourceIDs = Set([top.input.id, middle.input.id, bottom.input.id])
        guard sourceIDs.count >= 2 else {
            return result(
                state:.noComplementaryDetail,
                frameCount:inputs.count,
                eligibleFrameCount:eligible.count,
                startedAt:startedAt,
                reason:sourceIDs.first == reference.id
                    ? "没有候选帧在局部清晰度上明确优于基准帧"
                    : "同一候选帧在所有区域占优，应交由 Best Frame 整帧比较"
            )
        }

        guard let fusedCIImage = blend(
            bottom:bottom.image,
            middle:middle.image,
            top:top.image,
            extent:outputExtent,
            transitionFraction:configuration.transitionFraction
        ),
        let fusedImage = render(fusedCIImage, extent:outputExtent),
        let referenceImage = render(referenceFrame.image, extent:outputExtent)
        else {
            return result(
                state:.renderingFailed,
                frameCount:inputs.count,
                eligibleFrameCount:eligible.count,
                startedAt:startedAt,
                reason:"无法渲染多帧融合结果"
            )
        }

        let fusedQuality = analyze(fusedCIImage)
        let topGain = relativeGain(
            fusedQuality.topSharpness,
            referenceFrame.quality.topSharpness
        )
        let middleGain = relativeGain(
            fusedQuality.middleSharpness,
            referenceFrame.quality.middleSharpness
        )
        let bottomGain = relativeGain(
            fusedQuality.bottomSharpness,
            referenceFrame.quality.bottomSharpness
        )
        let averageGain = relativeGain(
            fusedQuality.averageSharpness,
            referenceFrame.quality.averageSharpness
        )
        let colorRetention = ColorRetentionAnalyzer.analyze(
            original:referenceImage,
            candidate:fusedImage
        ).overallRetention
        let brightnessSpread = spread(eligible.map { $0.quality.brightness })
        let metrics = DocumentFrameFusionMetrics(
            outputPixelWidth:outputWidth,
            outputPixelHeight:outputHeight,
            maximumResidualDifference:residuals.max() ?? 0,
            brightnessSpread:brightnessSpread,
            topSharpnessGain:topGain,
            middleSharpnessGain:middleGain,
            bottomSharpnessGain:bottomGain,
            averageSharpnessGain:averageGain,
            colorRetention:colorRetention,
            topFrameID:top.input.id,
            middleFrameID:middle.input.id,
            bottomFrameID:bottom.input.id,
            distinctSourceFrameCount:sourceIDs.count
        )
        let regionalRetentionSafe = min(topGain, middleGain, bottomGain)
            >= -0.015
        let hasMeasuredGain = max(topGain, middleGain, bottomGain) >= 0.035
            && averageGain >= 0.010
        let brightnessSafe = abs(
            fusedQuality.brightness - referenceFrame.quality.brightness
        ) <= 0.025
        let colorSafe = colorRetention >= 0.970
        guard regionalRetentionSafe,
              hasMeasuredGain,
              brightnessSafe,
              colorSafe else {
            return result(
                state:.qualityRegression,
                frameCount:inputs.count,
                eligibleFrameCount:eligible.count,
                startedAt:startedAt,
                metrics:metrics,
                reason:"融合后的区域清晰度、亮度或颜色保持未通过回归门槛"
            )
        }

        return result(
            image:fusedImage,
            state:.fused,
            frameCount:inputs.count,
            eligibleFrameCount:eligible.count,
            startedAt:startedAt,
            metrics:metrics,
            reason:"帧间对齐、区域互补、清晰度回归和保色检查全部通过"
        )
    }

    private struct FrameQuality {
        let topSharpness:Float
        let middleSharpness:Float
        let bottomSharpness:Float
        let averageSharpness:Float
        let brightness:Float
    }

    private struct CommonFrame {
        let input:DocumentFrameFusionInput
        let image:CIImage
        let quality:FrameQuality
    }

    private static func commonFrame(
        input:DocumentFrameFusionInput,
        naturalImage:CIImage,
        outputExtent:CGRect
    )->CommonFrame? {
        guard !naturalImage.extent.isEmpty else { return nil }
        let transform = CGAffineTransform(
            scaleX:outputExtent.width / naturalImage.extent.width,
            y:outputExtent.height / naturalImage.extent.height
        )
        let image = naturalImage
            .transformed(by:transform)
            .cropped(to:outputExtent)
        return CommonFrame(
            input:input,
            image:image,
            quality:analyze(image)
        )
    }

    private static func rectify(
        _ input:DocumentFrameFusionInput
    )->CIImage? {
        guard let source = CIImage(image:input.image) else { return nil }
        let extent = source.extent
        func point(_ value:CGPoint)->CIVector {
            CIVector(
                x:extent.minX + value.x * extent.width,
                y:extent.minY + (1 - value.y) * extent.height
            )
        }

        guard let filter = CIFilter(name:"CIPerspectiveCorrection") else {
            return nil
        }
        filter.setValue(source, forKey:kCIInputImageKey)
        filter.setValue(point(input.corners.topLeft), forKey:"inputTopLeft")
        filter.setValue(point(input.corners.topRight), forKey:"inputTopRight")
        filter.setValue(
            point(input.corners.bottomRight),
            forKey:"inputBottomRight"
        )
        filter.setValue(
            point(input.corners.bottomLeft),
            forKey:"inputBottomLeft"
        )
        guard let output = filter.outputImage,
              !output.extent.isEmpty,
              output.extent.width.isFinite,
              output.extent.height.isFinite else { return nil }
        let outputExtent = output.extent.integral
        return output.transformed(
            by:CGAffineTransform(
                translationX:-outputExtent.minX,
                y:-outputExtent.minY
            )
        )
        .cropped(to:CGRect(origin:.zero, size:outputExtent.size))
    }

    private static func valid(_ corners:ScanCorners)->Bool {
        let points = [
            corners.topLeft,
            corners.topRight,
            corners.bottomRight,
            corners.bottomLeft
        ]
        guard points.allSatisfy({
            $0.x.isFinite && $0.y.isFinite
                && $0.x >= 0 && $0.x <= 1
                && $0.y >= 0 && $0.y <= 1
        }) else { return false }

        var area:CGFloat = 0
        var crossProducts = [CGFloat]()
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            let after = points[(index + 2) % points.count]
            area += points[index].x * next.y - next.x * points[index].y
            let cross = (next.x - points[index].x)
                * (after.y - next.y)
                - (next.y - points[index].y)
                * (after.x - next.x)
            if abs(cross) > 0.00001 {
                crossProducts.append(cross)
            }
        }
        let convex = !crossProducts.isEmpty
            && (crossProducts.allSatisfy { $0 > 0 }
                || crossProducts.allSatisfy { $0 < 0 })
        return convex && abs(area) / 2 >= 0.15
    }

    private static func winner(
        in frames:[CommonFrame],
        reference:CommonFrame,
        value:(CommonFrame)->Float,
        minimumGain:Float
    )->CommonFrame {
        guard let best = frames.max(by:{ value($0) < value($1) }),
              best.input.id != reference.input.id,
              relativeGain(value(best), value(reference)) >= minimumGain else {
            return reference
        }
        return best
    }

    private static func blend(
        bottom:CIImage,
        middle:CIImage,
        top:CIImage,
        extent:CGRect,
        transitionFraction:CGFloat
    )->CIImage? {
        let feather = max(extent.height * transitionFraction, 2)
        guard let lowerMask = verticalMask(
            extent:extent,
            boundary:extent.minY + extent.height / 3,
            feather:feather
        ),
        let upperMask = verticalMask(
            extent:extent,
            boundary:extent.minY + extent.height * 2 / 3,
            feather:feather
        ) else { return nil }

        let lowerBlend = middle.applyingFilter(
            "CIBlendWithMask",
            parameters:[
                kCIInputBackgroundImageKey:bottom,
                kCIInputMaskImageKey:lowerMask
            ]
        )
        .cropped(to:extent)
        return top.applyingFilter(
            "CIBlendWithMask",
            parameters:[
                kCIInputBackgroundImageKey:lowerBlend,
                kCIInputMaskImageKey:upperMask
            ]
        )
        .cropped(to:extent)
    }

    private static func verticalMask(
        extent:CGRect,
        boundary:CGFloat,
        feather:CGFloat
    )->CIImage? {
        CIFilter(
            name:"CILinearGradient",
            parameters:[
                "inputPoint0":CIVector(
                    x:extent.midX,
                    y:boundary - feather / 2
                ),
                "inputPoint1":CIVector(
                    x:extent.midX,
                    y:boundary + feather / 2
                ),
                "inputColor0":CIColor(red:0, green:0, blue:0, alpha:1),
                "inputColor1":CIColor(red:1, green:1, blue:1, alpha:1)
            ]
        )?.outputImage?.cropped(to:extent)
    }

    private static func analyze(_ source:CIImage)->FrameQuality {
        let longest = max(source.extent.width, source.extent.height)
        let scale = min(1, 640 / max(longest, 1))
        let input = source.transformed(
            by:CGAffineTransform(scaleX:scale, y:scale)
        )
        let gray = input.applyingFilter(
            "CIColorControls",
            parameters:[kCIInputSaturationKey:0]
        )
        let edges = gray.applyingFilter(
            "CIEdges",
            parameters:[kCIInputIntensityKey:1.8]
        )
        let extent = edges.extent
        let third = extent.height / 3
        let bottom = averageLuminance(edges.cropped(to:CGRect(
            x:extent.minX,
            y:extent.minY,
            width:extent.width,
            height:third
        )))
        let middle = averageLuminance(edges.cropped(to:CGRect(
            x:extent.minX,
            y:extent.minY + third,
            width:extent.width,
            height:third
        )))
        let top = averageLuminance(edges.cropped(to:CGRect(
            x:extent.minX,
            y:extent.minY + third * 2,
            width:extent.width,
            height:extent.height - third * 2
        )))
        return FrameQuality(
            topSharpness:top,
            middleSharpness:middle,
            bottomSharpness:bottom,
            averageSharpness:(top + middle + bottom) / 3,
            brightness:averageLuminance(gray)
        )
    }

    private static func residualDifference(
        _ reference:CIImage,
        _ candidate:CIImage
    )->Float {
        let longest = max(reference.extent.width, reference.extent.height)
        let scale = min(1, 256 / max(longest, 1))
        func prepared(_ image:CIImage)->CIImage {
            let scaled = image.transformed(
                by:CGAffineTransform(scaleX:scale, y:scale)
            )
            let extent = scaled.extent
            return scaled.applyingFilter(
                "CIColorControls",
                parameters:[kCIInputSaturationKey:0]
            )
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters:[kCIInputRadiusKey:1.2]
            )
            .cropped(to:extent)
        }

        let baseline = prepared(reference)
        let comparison = prepared(candidate)
        let brightnessDelta = CGFloat(
            averageLuminance(baseline)
                - averageLuminance(comparison)
        )
        let normalized = comparison.applyingFilter(
            "CIColorMatrix",
            parameters:[
                "inputRVector":CIVector(x:1, y:0, z:0, w:0),
                "inputGVector":CIVector(x:0, y:1, z:0, w:0),
                "inputBVector":CIVector(x:0, y:0, z:1, w:0),
                "inputAVector":CIVector(x:0, y:0, z:0, w:1),
                "inputBiasVector":CIVector(
                    x:brightnessDelta,
                    y:brightnessDelta,
                    z:brightnessDelta,
                    w:0
                )
            ]
        )
        .cropped(to:baseline.extent)
        let difference = normalized.applyingFilter(
            "CIDifferenceBlendMode",
            parameters:[kCIInputBackgroundImageKey:baseline]
        )
        .cropped(to:baseline.extent)
        return averageLuminance(difference)
    }

    private static func averageLuminance(_ image:CIImage)->Float {
        guard !image.extent.isEmpty else { return 0 }
        let average = image.applyingFilter(
            "CIAreaAverage",
            parameters:[kCIInputExtentKey:CIVector(cgRect:image.extent)]
        )
        var pixel = [UInt8](repeating:0, count:4)
        context.render(
            average,
            toBitmap:&pixel,
            rowBytes:4,
            bounds:CGRect(x:0, y:0, width:1, height:1),
            format:.RGBA8,
            colorSpace:CGColorSpaceCreateDeviceRGB()
        )
        return Float(pixel[0]) / 255 * 0.2126
            + Float(pixel[1]) / 255 * 0.7152
            + Float(pixel[2]) / 255 * 0.0722
    }

    private static func render(
        _ image:CIImage,
        extent:CGRect
    )->UIImage? {
        guard let cgImage = context.createCGImage(image, from:extent) else {
            return nil
        }
        return UIImage(cgImage:cgImage, scale:1, orientation:.up)
    }

    private static func relativeGain(
        _ value:Float,
        _ baseline:Float
    )->Float {
        guard baseline > 0.0001 else { return 0 }
        return value / baseline - 1
    }

    private static func spread(_ values:[Float])->Float {
        guard let minimum = values.min(),
              let maximum = values.max() else { return 0 }
        return maximum - minimum
    }

    private static func result(
        image:UIImage? = nil,
        state:DocumentFrameFusionState,
        frameCount:Int,
        eligibleFrameCount:Int,
        startedAt:Date,
        metrics:DocumentFrameFusionMetrics? = nil,
        reason:String
    )->DocumentFrameFusionResult {
        DocumentFrameFusionResult(
            image:image,
            state:state,
            frameCount:frameCount,
            eligibleFrameCount:eligibleFrameCount,
            processingMilliseconds:max(
                0,
                Int(Date().timeIntervalSince(startedAt) * 1_000)
            ),
            metrics:metrics,
            reason:reason
        )
    }
}
