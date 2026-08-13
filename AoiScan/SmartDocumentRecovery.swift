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
}
