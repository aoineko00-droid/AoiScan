//
//  CaptureFrameQualityAnalyzer.swift
//  AoiScan
//

import UIKit
import CoreImage
import CoreVideo


enum CaptureFrameQualityAnalyzer {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )
    private static let maximumAnalysisEdge:CGFloat = 960

    static func analyze(
        image:UIImage,
        corners:ScanCorners?,
        referenceCorners:ScanCorners? = nil
    )->CaptureFrameQuality {
        let pixelWidth = image.cgImage?.width
            ?? Int(image.size.width * image.scale)
        let pixelHeight = image.cgImage?.height
            ?? Int(image.size.height * image.scale)
        guard let source = CIImage(image:image) else {
            return empty(pixelWidth:pixelWidth, pixelHeight:pixelHeight)
        }
        return analyze(
            source:source,
            pixelWidth:pixelWidth,
            pixelHeight:pixelHeight,
            corners:corners,
            referenceCorners:referenceCorners
        )
    }

    static func analyze(
        pixelBuffer:CVPixelBuffer,
        corners:ScanCorners?,
        referenceCorners:ScanCorners? = nil
    )->CaptureFrameQuality {
        let pixelWidth = CVPixelBufferGetWidth(pixelBuffer)
        let pixelHeight = CVPixelBufferGetHeight(pixelBuffer)
        return analyze(
            source:CIImage(cvPixelBuffer:pixelBuffer),
            pixelWidth:pixelWidth,
            pixelHeight:pixelHeight,
            corners:corners,
            referenceCorners:referenceCorners
        )
    }

    private static func analyze(
        source:CIImage,
        pixelWidth:Int,
        pixelHeight:Int,
        corners:ScanCorners?,
        referenceCorners:ScanCorners?
    )->CaptureFrameQuality {
        let longest = max(source.extent.width, source.extent.height)
        let scale = min(1, maximumAnalysisEdge / max(longest, 1))
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
        let bottom = edgeEnergy(edges.cropped(to:CGRect(
            x:extent.minX,
            y:extent.minY,
            width:extent.width,
            height:third
        )))
        let middle = edgeEnergy(edges.cropped(to:CGRect(
            x:extent.minX,
            y:extent.minY + third,
            width:extent.width,
            height:third
        )))
        let top = edgeEnergy(edges.cropped(to:CGRect(
            x:extent.minX,
            y:extent.minY + third * 2,
            width:extent.width,
            height:extent.height - third * 2
        )))
        let average = (top + middle + bottom) / 3
        let maximum = max(top, middle, bottom)
        let balance = maximum > 0
            ? min(top, middle, bottom) / maximum : 0
        let brightness = averageLuminance(gray)
        let exposureScore = max(
            0,
            1 - abs(brightness - 0.72) / 0.58
        )
        let coverage:CGFloat
        if let corners {
            coverage = polygonArea(corners)
        }
        else {
            coverage = 0
        }
        let jitter = corners.flatMap { corners in
            referenceCorners.map {
                maximumCornerDistance(corners, $0)
            }
        }
        let coverageScore = corners == nil
            ? 0.45
            : min(max(Double((coverage - 0.05) / 0.45), 0), 1)
        let stabilityScore = jitter.map {
            max(0, 1 - Double($0 / 0.055))
        } ?? 0.55
        let sharpnessScore = min(average / 0.20, 1)
        let overall = sharpnessScore * 0.48
            + balance * 0.22
            + exposureScore * 0.12
            + coverageScore * 0.10
            + stabilityScore * 0.08

        return CaptureFrameQuality(
            pixelWidth:pixelWidth,
            pixelHeight:pixelHeight,
            topSharpness:top,
            middleSharpness:middle,
            bottomSharpness:bottom,
            averageSharpness:average,
            sharpnessBalance:balance,
            brightness:brightness,
            exposureScore:exposureScore,
            documentCoverage:coverage,
            cornerJitter:jitter,
            overallScore:overall
        )
    }

    private static func edgeEnergy(_ image:CIImage)->Double {
        averageRGBA(image).map {
            Double($0.0) * 0.2126
                + Double($0.1) * 0.7152
                + Double($0.2) * 0.0722
        } ?? 0
    }

    private static func averageLuminance(_ image:CIImage)->Double {
        averageRGBA(image).map {
            Double($0.0) * 0.2126
                + Double($0.1) * 0.7152
                + Double($0.2) * 0.0722
        } ?? 0
    }

    private static func averageRGBA(
        _ image:CIImage
    )->(Float,Float,Float,Float)? {
        guard !image.extent.isEmpty else { return nil }
        let average = image.applyingFilter(
            "CIAreaAverage",
            parameters:[kCIInputExtentKey:CIVector(cgRect:image.extent)]
        )
        var pixel = [UInt8](repeating:0, count:4)
        Self.context.render(
            average,
            toBitmap:&pixel,
            rowBytes:4,
            bounds:CGRect(x:0, y:0, width:1, height:1),
            format:.RGBA8,
            colorSpace:CGColorSpaceCreateDeviceRGB()
        )
        return (
            Float(pixel[0]) / 255,
            Float(pixel[1]) / 255,
            Float(pixel[2]) / 255,
            Float(pixel[3]) / 255
        )
    }

    private static func polygonArea(_ corners:ScanCorners)->CGFloat {
        let points = [
            corners.topLeft,
            corners.topRight,
            corners.bottomRight,
            corners.bottomLeft
        ]
        var total:CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            total += points[index].x * next.y - next.x * points[index].y
        }
        return abs(total) / 2
    }

    private static func maximumCornerDistance(
        _ first:ScanCorners,
        _ second:ScanCorners
    )->CGFloat {
        zip(
            [first.topLeft,first.topRight,first.bottomRight,first.bottomLeft],
            [second.topLeft,second.topRight,second.bottomRight,second.bottomLeft]
        ).map { hypot($0.0.x - $0.1.x, $0.0.y - $0.1.y) }
        .max() ?? .greatestFiniteMagnitude
    }

    private static func empty(
        pixelWidth:Int,
        pixelHeight:Int
    )->CaptureFrameQuality {
        CaptureFrameQuality(
            pixelWidth:pixelWidth,
            pixelHeight:pixelHeight,
            topSharpness:0,
            middleSharpness:0,
            bottomSharpness:0,
            averageSharpness:0,
            sharpnessBalance:0,
            brightness:0,
            exposureScore:0,
            documentCoverage:0,
            cornerJitter:nil,
            overallScore:0
        )
    }
}
