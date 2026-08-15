//
//  DocumentShadowEnhancer.swift
//  AoiScan
//

import UIKit
import CoreImage


/// Removes slow document illumination changes without global contrast or
/// sharpening. The correction is an exposure lift blended over the original
/// RGB image by a low-frequency shadow mask. It never reconstructs RGB from a
/// grayscale composite, which keeps alpha and blend-mode semantics from
/// turning the page dark.
enum DocumentShadowEnhancer {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    private static let saturationCubeData:Data = {
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
                    let isRedOrBlue = (
                        red > green * 1.10 && red > blue * 1.08
                    ) || (
                        blue > red * 1.08 && blue > green * 1.06
                    )
                    let threshold:Float = isRedOrBlue ? 0.075 : 0.16
                    let mask = min(
                        max((saturation - threshold) / 0.11, 0),
                        1
                    )
                    values.append(contentsOf:[mask, mask, mask, 1])
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer:$0) }
    }()

    static func enhance(
        image:UIImage,
        blocks:[OCRBlock],
        severity:Float
    )->UIImage {
        guard let source = CIImage(image:image) else { return image }
        let extent = source.extent
        let shortSide = min(extent.width, extent.height)
        guard shortSide >= 64 else { return image }

        let grayscale = source.applyingFilter(
            "CIColorControls",
            parameters:[kCIInputSaturationKey:0]
        )
        .cropped(to:extent)
        let morphologyRadius = min(max(shortSide * 0.0045, 4), 14)
        let openedTextBackground = grayscale
            .clampedToExtent()
            .applyingFilter(
                "CIMorphologyMaximum",
                parameters:[kCIInputRadiusKey:morphologyRadius]
            )
            .cropped(to:extent)
        let backgroundSeed:CIImage
        if blocks.isEmpty {
            backgroundSeed = openedTextBackground
        }
        else {
            let textMask = TextEnhancementMask.make(
                blocks:maskBlocks(blocks),
                extent:extent,
                expansion:0.06
            )
            backgroundSeed = TextEnhancementMask.blend(
                adjusted:openedTextBackground,
                over:grayscale,
                mask:textMask
            )
        }

        let blurRadius = min(max(shortSide * 0.045, 36), 104)
        let background = backgroundSeed
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters:[kCIInputRadiusKey:blurRadius]
            )
            .cropped(to:extent)
        let boundedSeverity = CGFloat(min(max(severity, 0), 1))
        let maximumLift = min(0.025 + boundedSeverity * 0.035, 0.060)
        // A fixed white target brightens uniformly gray, colored or dimly lit
        // paper even when no local shadow exists. Estimate the page's own
        // bright background instead, then correct only relative deficits.
        let targetPaper = referencePaperBrightness(
            image:image,
            blocks:blocks
        ) ?? 0.86
        let effectiveTarget = max(targetPaper - 0.008, 0)

        // Convert targetPaper - localBackground into a grayscale [0, 1]
        // blend mask. This describes where a lift is needed; it is not added
        // to the image as an RGBA layer.
        let maskScale = 1 / max(maximumLift, 0.001)
        let shadowMask = background.applyingFilter(
            "CIColorMatrix",
            parameters:[
                "inputRVector":CIVector(x:-maskScale, y:0, z:0, w:0),
                "inputGVector":CIVector(x:0, y:-maskScale, z:0, w:0),
                "inputBVector":CIVector(x:0, y:0, z:-maskScale, w:0),
                "inputAVector":CIVector(x:0, y:0, z:0, w:0),
                "inputBiasVector":CIVector(
                    x:effectiveTarget * maskScale,
                    y:effectiveTarget * maskScale,
                    z:effectiveTarget * maskScale,
                    w:1
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
        let liftedRGB = source.applyingFilter(
            "CIExposureAdjust",
            parameters:[kCIInputEVKey:log2(1 + maximumLift)]
        )
        .cropped(to:extent)
        let shadowLifted = liftedRGB.applyingFilter(
            "CIBlendWithMask",
            parameters:[
                kCIInputBackgroundImageKey:source,
                kCIInputMaskImageKey:shadowMask
            ]
        )
        .cropped(to:extent)

        // Bright paper receives the correction. Dark glyph interiors are
        // progressively protected so black text is not lifted toward gray.
        let paperMask = grayscale.applyingFilter(
            "CIColorMatrix",
            parameters:[
                "inputRVector":CIVector(x:1.75, y:0, z:0, w:0),
                "inputGVector":CIVector(x:0, y:1.75, z:0, w:0),
                "inputBVector":CIVector(x:0, y:0, z:1.75, w:0),
                "inputAVector":CIVector(x:0, y:0, z:0, w:0),
                "inputBiasVector":CIVector(x:-0.42, y:-0.42, z:-0.42, w:1)
            ]
        )
        .applyingFilter(
            "CIColorClamp",
            parameters:[
                "inputMinComponents":CIVector(x:0, y:0, z:0, w:1),
                "inputMaxComponents":CIVector(x:1, y:1, z:1, w:1)
            ]
        )
        let textSafe = shadowLifted.applyingFilter(
            "CIBlendWithMask",
            parameters:[
                kCIInputBackgroundImageKey:source,
                kCIInputMaskImageKey:paperMask
            ]
        )
        .cropped(to:extent)
        let saturatedColorMask = source.applyingFilter(
            "CIColorCube",
            parameters:[
                "inputCubeDimension":24,
                "inputCubeData":saturationCubeData
            ]
        )
        .cropped(to:extent)
        let colorSafe = source.applyingFilter(
            "CIBlendWithMask",
            parameters:[
                kCIInputBackgroundImageKey:textSafe,
                kCIInputMaskImageKey:saturatedColorMask
            ]
        )
        .cropped(to:extent)

        guard let cgImage = context.createCGImage(colorSafe, from:extent) else {
            return image
        }
        return UIImage(cgImage:cgImage, scale:image.scale, orientation:.up)
    }

    private static func referencePaperBrightness(
        image:UIImage,
        blocks:[OCRBlock]
    )->CGFloat? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 96
        let ratio = CGFloat(cgImage.height)
            / CGFloat(max(cgImage.width, 1))
        let height = min(
            max(Int((CGFloat(width) * ratio).rounded()), 48),
            192
        )
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

        let mask = NormalizedRectangleRasterizer.exclusionMask(
            width:width,
            height:height,
            rectangles:blocks.map(\.boundingBox),
            expansion:0.18
        )
        var background = DocumentLuminanceHistogram()
        for index in bytes.indices where mask[index] == 0 {
            background.add(bytes[index])
        }
        if background.count < max(bytes.count / 12, 64) {
            background = DocumentLuminanceHistogram()
            for value in bytes {
                background.add(value)
            }
        }
        guard background.count > 0 else { return nil }
        let mean = CGFloat(background.mean(
            lowerQuantile:0.68,
            upperQuantile:0.92
        ))
        return min(max(mean, 0.52), 0.94)
    }

    /// TextEnhancementMask builds a Core Image compositing node for every OCR
    /// rectangle. Dense pages can contain hundreds of blocks, making a small
    /// preview slower than the correction itself. Merge dense OCR geometry
    /// into bounded horizontal/column bands for the background mask only.
    /// Original OCR blocks and their persisted geometry remain untouched.
    private static func maskBlocks(
        _ blocks:[OCRBlock]
    )->[OCRBlock] {
        let maximumCount = 96
        guard blocks.count > maximumCount else { return blocks }

        let columnCount = 3
        let rowCount = maximumCount / columnCount
        var unions = [CGRect?](
            repeating:nil,
            count:rowCount * columnCount
        )

        for block in blocks {
            let rect = block.boundingBox.intersection(
                CGRect(x:0, y:0, width:1, height:1)
            )
            guard !rect.isNull,
                  rect.width > 0,
                  rect.height > 0 else { continue }
            let row = min(
                max(Int(rect.midY * CGFloat(rowCount)), 0),
                rowCount - 1
            )
            let column = min(
                max(Int(rect.midX * CGFloat(columnCount)), 0),
                columnCount - 1
            )
            let index = row * columnCount + column
            unions[index] = unions[index].map { $0.union(rect) } ?? rect
        }

        return unions.compactMap { rect in
            guard let rect else { return nil }
            return OCRBlock(
                text:"",
                boundingBox:rect,
                confidence:1
            )
        }
    }
}
