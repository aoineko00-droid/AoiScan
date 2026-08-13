//
//  GeometryQualityAnalyzer.swift
//  AoiScan
//

import Foundation
import UIKit


struct GeometryQualityAnalyzer {
    func analyze(
        corners:ScanCorners,
        sourceImage:UIImage,
        outputImage:UIImage,
        cropMargin:CGFloat
    )->RecoveryGeometryMetrics {
        let top = distance(corners.topLeft, corners.topRight)
        let bottom = distance(corners.bottomLeft, corners.bottomRight)
        let left = distance(corners.topLeft, corners.bottomLeft)
        let right = distance(corners.topRight, corners.bottomRight)
        let widthRatio = min(top, bottom) / max(max(top, bottom), 0.0001)
        let heightRatio = min(left, right) / max(max(left, right), 0.0001)
        let severity = 1 - min(widthRatio, heightRatio)
        let coverage = polygonArea(corners)
        let convex = isConvex(corners)
        let inside = points(corners).allSatisfy {
            $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1
        }
        let minimumEdgeDistance = points(corners).reduce(CGFloat.greatestFiniteMagnitude) {
            min(
                $0,
                [$1.x, $1.y, 1 - $1.x, 1 - $1.y].min() ?? 0
            )
        }
        let edgeSafety = min(max(minimumEdgeDistance / 0.025, 0), 1)
        let sourcePixels = pixelArea(sourceImage)
        let outputPixels = pixelArea(outputImage)
        let expectedPixels = max(sourcePixels * coverage, 1)
        let scale = sqrt(outputPixels / expectedPixels)
        let outputSize = pixelSize(outputImage)
        let aspect = outputSize.height > 0
            ? outputSize.width / outputSize.height
            : 0

        let ratioScore = min(widthRatio, heightRatio)
        let coverageScore = min(max((coverage - 0.03) / 0.30, 0), 1)
        let scaleScore = max(0, 1 - max(scale - 1, 0) / 0.35)
        let validity:CGFloat = convex && inside ? 1 : 0
        let score = validity * (
            ratioScore * 0.34
                + coverageScore * 0.20
                + scaleScore * 0.24
                + edgeSafety * 0.12
                + max(0, 1 - severity / 0.45) * 0.10
        )

        return RecoveryGeometryMetrics(
            documentCoverage:coverage,
            topBottomWidthRatio:widthRatio,
            leftRightHeightRatio:heightRatio,
            perspectiveSeverity:severity,
            outputScale:scale,
            outputAspectRatio:aspect,
            cropMargin:cropMargin,
            cornersAreConvex:convex,
            cornersAreInsideImage:inside,
            edgeSafety:edgeSafety,
            geometryScore:score
        )
    }

    func isSafe(_ metrics:RecoveryGeometryMetrics)->Bool {
        metrics.cornersAreConvex
            && metrics.cornersAreInsideImage
            && metrics.documentCoverage >= 0.03
            && metrics.topBottomWidthRatio >= 0.55
            && metrics.leftRightHeightRatio >= 0.55
            && metrics.outputScale <= 1.35
            && metrics.outputAspectRatio >= 0.20
            && metrics.outputAspectRatio <= 5.0
    }

    func averageCornerDistance(
        _ first:ScanCorners,
        _ second:ScanCorners
    )->CGFloat {
        zip(points(first), points(second)).reduce(CGFloat.zero) {
            $0 + distance($1.0, $1.1)
        } / 4
    }

    func maximumCornerDistance(
        _ first:ScanCorners,
        _ second:ScanCorners
    )->CGFloat {
        zip(points(first), points(second)).map {
            distance($0.0, $0.1)
        }
        .max() ?? .greatestFiniteMagnitude
    }

    private func points(_ corners:ScanCorners)->[CGPoint] {
        [
            corners.topLeft,
            corners.topRight,
            corners.bottomRight,
            corners.bottomLeft
        ]
    }

    private func polygonArea(_ corners:ScanCorners)->CGFloat {
        let values = points(corners)
        var sum:CGFloat = 0
        for index in values.indices {
            let next = values[(index + 1) % values.count]
            sum += values[index].x * next.y - next.x * values[index].y
        }
        return abs(sum) / 2
    }

    private func isConvex(_ corners:ScanCorners)->Bool {
        let values = points(corners)
        var signs:[CGFloat] = []
        for index in values.indices {
            let a = values[index]
            let b = values[(index + 1) % values.count]
            let c = values[(index + 2) % values.count]
            let cross = (b.x - a.x) * (c.y - b.y)
                - (b.y - a.y) * (c.x - b.x)
            guard abs(cross) > 0.00001 else { continue }
            signs.append(cross)
        }
        guard !signs.isEmpty else { return false }
        return signs.allSatisfy { $0 > 0 } || signs.allSatisfy { $0 < 0 }
    }

    private func distance(_ first:CGPoint, _ second:CGPoint)->CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func pixelSize(_ image:UIImage)->CGSize {
        if let cgImage = image.cgImage {
            return CGSize(width:cgImage.width, height:cgImage.height)
        }
        return CGSize(
            width:image.size.width * image.scale,
            height:image.size.height * image.scale
        )
    }

    private func pixelArea(_ image:UIImage)->CGFloat {
        let size = pixelSize(image)
        return max(size.width * size.height, 1)
    }
}
