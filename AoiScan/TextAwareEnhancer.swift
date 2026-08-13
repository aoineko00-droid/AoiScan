//
//  TextAwareEnhancer.swift
//  AoiScan
//

import UIKit
import CoreImage


/// Coordinates independent image operations. Individual modules remain
/// testable and no operation is silently enabled by another one.
enum TextAwareEnhancer {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    static func enhance(
        image:UIImage,
        blocks:[OCRBlock],
        parameters:EnhancementParameters
    )->UIImage {
        SmartColorEnhancer.enhance(
            image:image,
            blocks:blocks,
            parameters:parameters
        )
    }
}
