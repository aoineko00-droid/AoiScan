//
//  NormalizedRectangleRasterizer.swift
//  AoiScan
//

import Foundation
import CoreGraphics
import Darwin


/// Converts normalized Vision-style rectangles into a compact bitmap mask.
/// The mask is used only by image-quality analysis and never changes OCR
/// geometry or persisted recognition results.
enum NormalizedRectangleRasterizer {
    static func grayscaleMaskImage(
        width:Int,
        height:Int,
        rectangles:[CGRect],
        expansion:CGFloat,
        minimumHorizontalExpansion:CGFloat = 0.004,
        minimumVerticalExpansion:CGFloat = 0.003
    )->CGImage? {
        guard width > 0,
              height > 0 else { return nil }
        var bytes = [UInt8](repeating:0, count:width * height)
        bytes.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            for rectangle in rectangles {
                guard let bounds = pixelBounds(
                    for:rectangle,
                    width:width,
                    height:height,
                    expansion:expansion,
                    minimumHorizontalExpansion:
                        minimumHorizontalExpansion,
                    minimumVerticalExpansion:
                        minimumVerticalExpansion
                ) else { continue }
                let byteCount = bounds.maximumX - bounds.minimumX
                for y in bounds.minimumY..<bounds.maximumY {
                    memset(
                        baseAddress.advanced(
                            by:y * width + bounds.minimumX
                        ),
                        255,
                        byteCount
                    )
                }
            }
        }
        guard !bytes.isEmpty,
              let provider = CGDataProvider(data:Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width:width,
            height:height,
            bitsPerComponent:8,
            bitsPerPixel:8,
            bytesPerRow:width,
            space:CGColorSpaceCreateDeviceGray(),
            bitmapInfo:CGBitmapInfo(rawValue:0),
            provider:provider,
            decode:nil,
            shouldInterpolate:false,
            intent:.defaultIntent
        )
    }

    static func exclusionMask(
        width:Int,
        height:Int,
        rectangles:[CGRect],
        expansion:CGFloat,
        minimumHorizontalExpansion:CGFloat = 0.004,
        minimumVerticalExpansion:CGFloat = 0.003
    )->[UInt8] {
        guard width > 0,
              height > 0,
              !rectangles.isEmpty else {
            return [UInt8](
                repeating:0,
                count:max(width * height, 0)
            )
        }

        var mask = [UInt8](repeating:0, count:width * height)

        for rawRectangle in rectangles {
            guard let bounds = pixelBounds(
                for:rawRectangle,
                width:width,
                height:height,
                expansion:expansion,
                minimumHorizontalExpansion:minimumHorizontalExpansion,
                minimumVerticalExpansion:minimumVerticalExpansion
            ) else { continue }
            for y in bounds.minimumY..<bounds.maximumY {
                let rowStart = y * width
                for x in bounds.minimumX..<bounds.maximumX {
                    mask[rowStart + x] = 1
                }
            }
        }

        return mask
    }

    private static func pixelBounds(
        for rawRectangle:CGRect,
        width:Int,
        height:Int,
        expansion:CGFloat,
        minimumHorizontalExpansion:CGFloat,
        minimumVerticalExpansion:CGFloat
    )->(
        minimumX:Int,
        maximumX:Int,
        minimumY:Int,
        maximumY:Int
    )? {
        let unit = CGRect(x:0, y:0, width:1, height:1)
        let rectangle = rawRectangle.intersection(unit)
        guard !rectangle.isNull,
              rectangle.width > 0,
              rectangle.height > 0 else { return nil }
        let expanded = rectangle.insetBy(
            dx:-max(
                rectangle.width * expansion,
                minimumHorizontalExpansion
            ),
            dy:-max(
                rectangle.height * expansion,
                minimumVerticalExpansion
            )
        ).intersection(unit)
        guard !expanded.isNull else { return nil }
        let minimumX = max(
            Int(floor(expanded.minX * CGFloat(width))),
            0
        )
        let maximumX = min(
            Int(ceil(expanded.maxX * CGFloat(width))),
            width
        )
        // Vision rectangles use a bottom-left origin while mask rows are
        // consumed from top to bottom.
        let minimumY = max(
            Int(floor((1 - expanded.maxY) * CGFloat(height))),
            0
        )
        let maximumY = min(
            Int(ceil((1 - expanded.minY) * CGFloat(height))),
            height
        )
        guard minimumX < maximumX,
              minimumY < maximumY else { return nil }
        return (minimumX, maximumX, minimumY, maximumY)
    }
}
