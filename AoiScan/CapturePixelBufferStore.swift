//
//  CapturePixelBufferStore.swift
//  AoiScan
//

import CoreVideo
import CoreImage
import ImageIO


enum CapturePixelBufferStore {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    static func makeIndependentFrame(
        from source:CVPixelBuffer,
        orientation:CGImagePropertyOrientation,
        preferredMaximumEdge:Int
    )->CapturePixelFrame? {
        if let preferred = render(
            source:source,
            orientation:orientation,
            maximumEdge:preferredMaximumEdge
        ) {
            return CapturePixelFrame(
                pixelBuffer:preferred,
                targetMaximumEdge:preferredMaximumEdge,
                usedFallbackResolution:false
            )
        }

        let fallbackEdge = 1_280
        guard preferredMaximumEdge > fallbackEdge,
              let fallback = render(
                source:source,
                orientation:orientation,
                maximumEdge:fallbackEdge
              ) else {
            return nil
        }
        return CapturePixelFrame(
            pixelBuffer:fallback,
            targetMaximumEdge:fallbackEdge,
            usedFallbackResolution:true
        )
    }

    private static func render(
        source:CVPixelBuffer,
        orientation:CGImagePropertyOrientation,
        maximumEdge:Int
    )->CVPixelBuffer? {
        let oriented = CIImage(cvPixelBuffer:source)
            .oriented(forExifOrientation:Int32(orientation.rawValue))
        let sourceExtent = oriented.extent
        guard !sourceExtent.isEmpty else { return nil }

        let scale = min(
            1,
            CGFloat(maximumEdge) / max(
                sourceExtent.width,
                sourceExtent.height,
                1
            )
        )
        let width = max(Int((sourceExtent.width * scale).rounded()), 1)
        let height = max(Int((sourceExtent.height * scale).rounded()), 1)
        let attributes:[CFString:Any] = [
            kCVPixelBufferCGImageCompatibilityKey:true,
            kCVPixelBufferCGBitmapContextCompatibilityKey:true,
            kCVPixelBufferIOSurfacePropertiesKey:[:]
        ]
        var output:CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess,
              let output else {
            return nil
        }

        let normalized = oriented.transformed(
            by:CGAffineTransform(
                translationX:-sourceExtent.minX,
                y:-sourceExtent.minY
            )
        ).transformed(
            by:CGAffineTransform(scaleX:scale, y:scale)
        )
        Self.context.render(
            normalized,
            to:output,
            bounds:CGRect(x:0, y:0, width:width, height:height),
            colorSpace:CGColorSpaceCreateDeviceRGB()
        )
        return output
    }
}
