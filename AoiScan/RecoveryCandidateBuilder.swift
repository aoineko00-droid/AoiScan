//
//  RecoveryCandidateBuilder.swift
//  AoiScan
//

import Foundation
import UIKit


struct RecoveryCandidateBuilder {
    typealias Corrector = (UIImage,ScanCorners)->UIImage?

    private let geometryAnalyzer = GeometryQualityAnalyzer()
    private let sharpnessAnalyzer = RegionalSharpnessAnalyzer()

    func build(
        sourceImage:UIImage,
        currentImage:UIImage,
        currentCorners:ScanCorners,
        stableCorners:ScanCorners?,
        stability:CaptureCornerStability?,
        allowsAlternateCorners:Bool,
        correct:Corrector
    )->[RecoveryCandidate] {
        var specifications:[(
            type:RecoveryCandidateType,
            corners:ScanCorners,
            margin:CGFloat,
            image:UIImage?
        )] = [
            (.current, currentCorners, 0, currentImage)
        ]

        let safeMargin = adaptiveMargin(for:currentCorners)
        let expanded = expandedCorners(
            currentCorners,
            amount:safeMargin
        )
        if GeometryQualityAnalyzer().maximumCornerDistance(
            currentCorners,
            expanded
        ) >= 0.0015 {
            specifications.append(
                (.safeMargin, expanded, safeMargin, nil)
            )
        }

        if allowsAlternateCorners,
           let stableCorners,
           stabilityIsUsable(stability),
           cornersAreDistinct(currentCorners, stableCorners) {
            specifications.append(
                (.stableCorners, stableCorners, 0, nil)
            )

            let averageDistance = geometryAnalyzer.averageCornerDistance(
                currentCorners,
                stableCorners
            )
            let maximumDistance = geometryAnalyzer.maximumCornerDistance(
                currentCorners,
                stableCorners
            )
            if averageDistance <= 0.025,
               maximumDistance <= 0.045 {
                specifications.append(
                    (
                        .fusedCorners,
                        fused(
                            primary:currentCorners,
                            secondary:stableCorners
                        ),
                        0,
                        nil
                    )
                )
            }
        }

        var candidates:[RecoveryCandidate] = []
        for specification in specifications {
            autoreleasepool {
                guard let image = specification.image
                    ?? correct(sourceImage, specification.corners) else {
                    return
                }
                let geometry = geometryAnalyzer.analyze(
                    corners:specification.corners,
                    sourceImage:sourceImage,
                    outputImage:image,
                    cropMargin:specification.margin
                )
                guard specification.type == .current
                    || geometryAnalyzer.isSafe(geometry) else {
                    return
                }
                let sharpness = sharpnessAnalyzer.analyze(image)
                let quickScore = Double(geometry.geometryScore) * 0.72
                    + sharpness.balance * 0.18
                    + min(sharpness.average / 0.16, 1) * 0.10
                candidates.append(
                    RecoveryCandidate(
                        type:specification.type,
                        image:image,
                        corners:specification.corners,
                        geometry:geometry,
                        sharpness:sharpness,
                        quickScore:quickScore
                    )
                )
            }
        }
        return candidates
    }

    private func stabilityIsUsable(
        _ stability:CaptureCornerStability?
    )->Bool {
        guard let stability else { return true }
        return stability.stableFrameCount >= 5
            && stability.averageCornerJitter <= 0.018
    }

    private func cornersAreDistinct(
        _ first:ScanCorners,
        _ second:ScanCorners
    )->Bool {
        geometryAnalyzer.maximumCornerDistance(first, second) >= 0.002
    }

    private func adaptiveMargin(for corners:ScanCorners)->CGFloat {
        let points = [
            corners.topLeft,
            corners.topRight,
            corners.bottomRight,
            corners.bottomLeft
        ]
        let minimumBorder = points.flatMap {
            [$0.x, $0.y, 1 - $0.x, 1 - $0.y]
        }
        .min() ?? 0

        if minimumBorder < 0.006 { return 0.003 }
        if minimumBorder < 0.018 { return 0.005 }
        return 0.004
    }

    private func expandedCorners(
        _ corners:ScanCorners,
        amount:CGFloat
    )->ScanCorners {
        let center = CGPoint(
            x:(corners.topLeft.x + corners.topRight.x
                + corners.bottomRight.x + corners.bottomLeft.x) / 4,
            y:(corners.topLeft.y + corners.topRight.y
                + corners.bottomRight.y + corners.bottomLeft.y) / 4
        )
        func expand(_ point:CGPoint)->CGPoint {
            CGPoint(
                x:min(max(point.x + (point.x - center.x) * amount, 0), 1),
                y:min(max(point.y + (point.y - center.y) * amount, 0), 1)
            )
        }
        return ScanCorners(
            topLeft:expand(corners.topLeft),
            topRight:expand(corners.topRight),
            bottomRight:expand(corners.bottomRight),
            bottomLeft:expand(corners.bottomLeft)
        )
    }

    private func fused(
        primary:ScanCorners,
        secondary:ScanCorners
    )->ScanCorners {
        func point(_ first:CGPoint, _ second:CGPoint)->CGPoint {
            CGPoint(
                x:first.x * 0.70 + second.x * 0.30,
                y:first.y * 0.70 + second.y * 0.30
            )
        }
        return ScanCorners(
            topLeft:point(primary.topLeft, secondary.topLeft),
            topRight:point(primary.topRight, secondary.topRight),
            bottomRight:point(primary.bottomRight, secondary.bottomRight),
            bottomLeft:point(primary.bottomLeft, secondary.bottomLeft)
        )
    }
}
