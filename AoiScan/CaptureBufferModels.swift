//
//  CaptureBufferModels.swift
//  AoiScan
//

import Foundation
import UIKit
import ImageIO
import CoreVideo
import CoreImage


struct CaptureFrameQuality:Codable {
    let pixelWidth:Int
    let pixelHeight:Int
    let topSharpness:Double
    let middleSharpness:Double
    let bottomSharpness:Double
    let averageSharpness:Double
    let sharpnessBalance:Double
    let brightness:Double
    let exposureScore:Double
    let documentCoverage:CGFloat
    let cornerJitter:CGFloat?
    let overallScore:Double
}


final class CapturePixelFrame {
    let pixelBuffer:CVPixelBuffer
    let pixelWidth:Int
    let pixelHeight:Int
    let storageBytes:Int
    let targetMaximumEdge:Int
    let usedFallbackResolution:Bool

    init(
        pixelBuffer:CVPixelBuffer,
        targetMaximumEdge:Int,
        usedFallbackResolution:Bool
    ) {
        self.pixelBuffer = pixelBuffer
        self.pixelWidth = CVPixelBufferGetWidth(pixelBuffer)
        self.pixelHeight = CVPixelBufferGetHeight(pixelBuffer)
        self.storageBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            * CVPixelBufferGetHeight(pixelBuffer)
        self.targetMaximumEdge = targetMaximumEdge
        self.usedFallbackResolution = usedFallbackResolution
    }

    func makeImage()->UIImage? {
        let image = CIImage(cvPixelBuffer:pixelBuffer)
        let context = CIContext(options:[.cacheIntermediates:false])
        guard let cgImage = context.createCGImage(
            image,
            from:image.extent
        ) else { return nil }
        return UIImage(cgImage:cgImage)
    }
}


struct BufferedCaptureFrame {
    let id:UUID
    let timestamp:Date
    let pixelFrame:CapturePixelFrame
    let orientation:CGImagePropertyOrientation
    let corners:ScanCorners?
    let quality:CaptureFrameQuality

    var image:UIImage? {
        pixelFrame.makeImage()
    }
}


struct CaptureBufferSnapshot {
    let frames:[BufferedCaptureFrame]
    let frozenAt:Date
    let diagnosticsOnly:Bool
}


enum BestFrameSource:String,Codable {
    case formalPhoto
    case bufferedFrame
}


enum BestFrameComparisonState:String,Codable {
    case noBufferedFrames
    case diagnosticsOnly
    case skippedInsufficientResolution
    case skippedMissingStability
    case skippedExposure
    case comparedNoImprovement
    case selectedBufferedFrame
}


struct BestFrameSelectionResult {
    let image:UIImage
    let corners:ScanCorners?
    let source:BestFrameSource
    let formalPixelWidth:Int
    let formalPixelHeight:Int
    let formalQuality:CaptureFrameQuality?
    let selectedQuality:CaptureFrameQuality?
    let candidates:[BufferedCaptureFrame]
    let comparisonState:BestFrameComparisonState
    let processingMilliseconds:Int
    let reason:String
}
