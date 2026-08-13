//
//  RegionalSharpnessAnalyzer.swift
//  AoiScan
//

import UIKit
import CoreImage


struct RegionalSharpnessAnalyzer {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )
    private let maximumPixelSize:CGFloat = 1600

    func analyze(_ image:UIImage)->RegionalSharpnessMetrics {
        guard let input = CIImage(image:downscaled(image)) else {
            return emptyMetrics
        }
        let gray = input.applyingFilter(
            "CIColorControls",
            parameters:[kCIInputSaturationKey:0]
        )
        let edges = gray.applyingFilter(
            "CIEdges",
            parameters:[kCIInputIntensityKey:2.0]
        )
        let extent = edges.extent
        let third = extent.height / 3
        guard third > 1 else { return emptyMetrics }

        let bottom = edgeEnergy(
            edges.cropped(to:CGRect(
                x:extent.minX,
                y:extent.minY,
                width:extent.width,
                height:third
            ))
        )
        let middle = edgeEnergy(
            edges.cropped(to:CGRect(
                x:extent.minX,
                y:extent.minY + third,
                width:extent.width,
                height:third
            ))
        )
        let top = edgeEnergy(
            edges.cropped(to:CGRect(
                x:extent.minX,
                y:extent.minY + third * 2,
                width:extent.width,
                height:extent.height - third * 2
            ))
        )
        let minimum = min(top, middle, bottom)
        let maximum = max(top, middle, bottom)
        let average = (top + middle + bottom) / 3
        let balance = maximum > 0 ? minimum / maximum : 0

        return RegionalSharpnessMetrics(
            top:top,
            middle:middle,
            bottom:bottom,
            balance:balance,
            average:average
        )
    }

    private func edgeEnergy(_ image:CIImage)->Double {
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
            Double(pixel[0]) * 0.2126
                + Double(pixel[1]) * 0.7152
                + Double(pixel[2]) * 0.0722
        ) / 255
    }

    private func downscaled(_ image:UIImage)->UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longest = max(width, height)
        guard longest > maximumPixelSize else { return image }
        let scale = maximumPixelSize / longest
        let size = CGSize(width:width * scale, height:height * scale)
        let renderer = UIGraphicsImageRenderer(size:size)
        return renderer.image { _ in
            image.draw(in:CGRect(origin:.zero, size:size))
        }
    }

    private var emptyMetrics:RegionalSharpnessMetrics {
        RegionalSharpnessMetrics(
            top:0,
            middle:0,
            bottom:0,
            balance:0,
            average:0
        )
    }
}
