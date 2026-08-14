//
//  SmartDocumentRecovery.swift
//  AoiScan
//

import Foundation
import UIKit


enum SmartDocumentRecovery {
    static func process(
        sourceImage:UIImage,
        currentImage:UIImage,
        currentCorners:ScanCorners?,
        stableCorners:ScanCorners?,
        stability:CaptureCornerStability?,
        allowsAlternateCorners:Bool,
        pageNumber:Int,
        correct:@escaping RecoveryCandidateBuilder.Corrector,
        completion:@escaping(SmartDocumentRecoveryOutput)->Void
    ) {
        let startedAt = Date()
        guard let currentCorners else {
            let output = SmartDocumentRecoveryOutput(
                image:currentImage,
                corners:nil,
                selectedType:.current,
                trials:[],
                processingMilliseconds:0,
                selectionReason:"没有可用于恢复的纸张四角",
                enhancementSeed:nil
            )
            DispatchQueue.main.async {
                RecoveryDiagnostics.record(
                    output:output,
                    pageNumber:pageNumber,
                    stability:stability
                )
                completion(output)
            }
            return
        }

        guard requiresRecoveryAnalysis(
            currentCorners:currentCorners,
            stableCorners:stableCorners,
            stability:stability,
            allowsAlternateCorners:allowsAlternateCorners
        ) else {
            let output = SmartDocumentRecoveryOutput(
                image:currentImage,
                corners:currentCorners,
                selectedType:.current,
                trials:[],
                processingMilliseconds:Int(
                    Date().timeIntervalSince(startedAt) * 1000
                ),
                selectionReason:"几何与边缘处于安全范围，跳过恢复候选生成和恢复OCR",
                enhancementSeed:nil
            )
            DispatchQueue.main.async {
                RecoveryDiagnostics.record(
                    output:output,
                    pageNumber:pageNumber,
                    stability:stability
                )
                completion(output)
            }
            return
        }

        DispatchQueue.global(qos:.userInitiated).async {
            autoreleasepool {
                let candidates = RecoveryCandidateBuilder().build(
                    sourceImage:sourceImage,
                    currentImage:currentImage,
                    currentCorners:currentCorners,
                    stableCorners:stableCorners,
                    stability:stability,
                    allowsAlternateCorners:allowsAlternateCorners,
                    correct:correct
                )

                RecoveryCandidateEvaluator.evaluate(
                    candidates:candidates,
                    pageNumber:pageNumber,
                    startedAt:startedAt
                ) { output in
                    RecoveryDiagnostics.record(
                        output:output,
                        pageNumber:pageNumber,
                        stability:stability
                    )
                    completion(output)
                }
            }
        }
    }

    private static func requiresRecoveryAnalysis(
        currentCorners:ScanCorners,
        stableCorners:ScanCorners?,
        stability:CaptureCornerStability?,
        allowsAlternateCorners:Bool
    )->Bool {
        let top = distance(currentCorners.topLeft, currentCorners.topRight)
        let bottom = distance(
            currentCorners.bottomLeft,
            currentCorners.bottomRight
        )
        let left = distance(currentCorners.topLeft, currentCorners.bottomLeft)
        let right = distance(
            currentCorners.topRight,
            currentCorners.bottomRight
        )
        let widthRatio = min(top, bottom) / max(max(top, bottom), 0.0001)
        let heightRatio = min(left, right) / max(max(left, right), 0.0001)
        let perspectiveSeverity = 1 - min(widthRatio, heightRatio)
        let minimumBorder = points(currentCorners).flatMap {
            [$0.x, $0.y, 1 - $0.x, 1 - $0.y]
        }.min() ?? 0

        if perspectiveSeverity >= 0.18 || minimumBorder < 0.010 {
            return true
        }

        guard allowsAlternateCorners,
              let stableCorners,
              stability?.stableFrameCount ?? 0 >= 5,
              stability?.averageCornerJitter ?? 1 <= 0.018 else {
            return false
        }
        let maximumDifference = zip(
            points(currentCorners),
            points(stableCorners)
        ).map { distance($0.0, $0.1) }.max() ?? 0
        return maximumDifference >= 0.014
    }

    private static func points(_ corners:ScanCorners)->[CGPoint] {
        [
            corners.topLeft,
            corners.topRight,
            corners.bottomRight,
            corners.bottomLeft
        ]
    }

    private static func distance(_ first:CGPoint,_ second:CGPoint)->CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
}
