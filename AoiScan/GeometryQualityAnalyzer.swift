//
//  GeometryQualityAnalyzer.swift
//  AoiScan
//

import Foundation
import UIKit


struct AutomaticCropSafetyAssessment {
    let isSafe:Bool
    let baseGeometrySafe:Bool
    let minimumCoverage:CGFloat
    let referenceCoverage:CGFloat?
    let completenessConfirmed:Bool
    let firstRejectedMetric:String?
    let firstRejectedMetricValue:CGFloat?
    let firstRejectedMetricThreshold:CGFloat?
}


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
        isBaseSafe(metrics, maximumOutputScale:1.35)
    }

    private func isBaseSafe(
        _ metrics:RecoveryGeometryMetrics,
        maximumOutputScale:CGFloat
    )->Bool {
        metrics.cornersAreConvex
            && metrics.cornersAreInsideImage
            && metrics.documentCoverage >= 0.03
            && metrics.topBottomWidthRatio >= 0.55
            && metrics.leftRightHeightRatio >= 0.55
            && metrics.outputScale <= maximumOutputScale
            && metrics.outputAspectRatio >= 0.20
            && metrics.outputAspectRatio <= 5.0
    }

    private func firstRejectedMetric(
        _ metrics:RecoveryGeometryMetrics,
        maximumOutputScale:CGFloat
    )->(String, CGFloat, CGFloat)? {
        if !metrics.cornersAreConvex {
            return ("cornersConvex", metrics.cornersAreConvex ? 1 : 0, 1)
        }
        if !metrics.cornersAreInsideImage {
            return ("cornersInsideImage", 0, 1)
        }
        if metrics.documentCoverage < 0.03 {
            return ("coverage", metrics.documentCoverage, 0.03)
        }
        if metrics.topBottomWidthRatio < 0.55 {
            return ("topBottomWidthRatio", metrics.topBottomWidthRatio, 0.55)
        }
        if metrics.leftRightHeightRatio < 0.55 {
            return ("leftRightHeightRatio", metrics.leftRightHeightRatio, 0.55)
        }
        if metrics.outputScale > maximumOutputScale {
            return ("outputScale", metrics.outputScale, maximumOutputScale)
        }
        if metrics.outputAspectRatio < 0.20 {
            return ("aspectRatio", metrics.outputAspectRatio, 0.20)
        }
        if metrics.outputAspectRatio > 5.0 {
            return ("aspectRatio", metrics.outputAspectRatio, 5.0)
        }
        return nil
    }

    func assessAutomaticCrop(
        _ metrics:RecoveryGeometryMetrics,
        stableReferenceCorners:ScanCorners?,
        smallCandidateCompletenessConfirmed:Bool = false,
        requiresExplicitCompletenessEvidence:Bool = false
    )->AutomaticCropSafetyAssessment {
        // A completeness-confirmed small sheet can legitimately produce a larger
        // rectified output scale because a small trapezoid is expanded to its
        // full document resolution. Keep the ordinary 1.35 ceiling for every
        // other path. Edge distance remains diagnostic only: a complete page
        // near the camera boundary naturally has a small inset.
        let maximumOutputScale:CGFloat = smallCandidateCompletenessConfirmed
            ? 1.85 : 1.35
        let baseGeometrySafe = isBaseSafe(
            metrics,
            maximumOutputScale:maximumOutputScale
        )
        let referenceCoverage = stableReferenceCorners.map {
            polygonArea($0)
        }
        // A small, high-confidence Vision rectangle can be a text box or a
        // table inside the page. Without a stable reference, prefer keeping
        // the complete photo over automatically discarding most of it. With
        // a stable reference, allow perspective variation but reject a crop
        // that retains less than 55% of the referenced document area.
        let minimumCoverage:CGFloat
        if let referenceCoverage,
           referenceCoverage >= 0.03 {
            minimumCoverage = max(
                smallCandidateCompletenessConfirmed ? 0.12 : 0.15,
                referenceCoverage * 0.55
            )
        }
        else {
            minimumCoverage = smallCandidateCompletenessConfirmed
                ? 0.12 : 0.15
        }
        // Strict/stable candidates may use the existing area completeness
        // check. A fallback rectangle must carry explicit outer-page and text
        // evidence; area alone can describe an internal table just as easily.
        let completenessConfirmed = requiresExplicitCompletenessEvidence
            ? smallCandidateCompletenessConfirmed
            : metrics.documentCoverage >= 0.25
                || smallCandidateCompletenessConfirmed

        let baseReject = firstRejectedMetric(
            metrics,
            maximumOutputScale:maximumOutputScale
        )
        let isSafe = baseGeometrySafe
            && metrics.documentCoverage >= minimumCoverage
            && completenessConfirmed

        var firstReject:(String, CGFloat, CGFloat)?
        if let baseReject {
            firstReject = baseReject
        }
        else if metrics.documentCoverage < minimumCoverage {
            firstReject = (
                "minimumCoverage",
                metrics.documentCoverage,
                minimumCoverage
            )
        }
        else if !completenessConfirmed {
            firstReject = requiresExplicitCompletenessEvidence
                ? (
                    "completePageEvidence",
                    smallCandidateCompletenessConfirmed ? 1 : 0,
                    1
                )
                : (
                    "completenessConfirmed",
                    metrics.documentCoverage,
                    0.25
                )
        }

        return AutomaticCropSafetyAssessment(
            isSafe:isSafe,
            baseGeometrySafe:baseGeometrySafe,
            minimumCoverage:minimumCoverage,
            referenceCoverage:referenceCoverage,
            completenessConfirmed:completenessConfirmed,
            firstRejectedMetric:firstReject?.0,
            firstRejectedMetricValue:firstReject?.1,
            firstRejectedMetricThreshold:firstReject?.2
        )
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
