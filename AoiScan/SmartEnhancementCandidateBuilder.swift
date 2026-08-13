//
//  SmartEnhancementCandidateBuilder.swift
//  AoiScan
//

import UIKit
import CoreImage


enum SmartEnhancementCandidateBuilder {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    static func build(
        rgbSource:UIImage,
        baselineImage:UIImage,
        blocks:[OCRBlock],
        parameters:EnhancementParameters,
        route:DocumentQualityRoute
    )->UIImage {
        switch route.primaryIssue {
        case .lighting, .background:
            return SmartColorEnhancer.enhanceIllumination(
                image:baselineImage,
                blocks:blocks,
                parameters:parameters
            )
        case .regionalSharpness:
            return RegionalSharpnessRecovery.apply(
                to:baselineImage,
                blocks:blocks,
                region:route.affectedRegion,
                severity:route.severity
            )
        case .none, .perspective:
            return baselineImage
        }
    }
}
