//
//  BestFrameSelector.swift
//  AoiScan
//

import UIKit


enum BestFrameSelector {
    static func select(
        formalPhoto:UIImage,
        formalCorners:ScanCorners?,
        snapshot:CaptureBufferSnapshot
    )->BestFrameSelectionResult {
        let startedAt = Date()
        let formalPixelWidth = formalPhoto.cgImage?.width
            ?? Int(formalPhoto.size.width * formalPhoto.scale)
        let formalPixelHeight = formalPhoto.cgImage?.height
            ?? Int(formalPhoto.size.height * formalPhoto.scale)

        guard !snapshot.diagnosticsOnly else {
            return formalResult(
                photo:formalPhoto,
                corners:formalCorners,
                pixelWidth:formalPixelWidth,
                pixelHeight:formalPixelHeight,
                candidates:snapshot.frames,
                state:.diagnosticsOnly,
                startedAt:startedAt,
                reason:"高分辨率缓存处于诊断阶段，不参与正式照片替换"
            )
        }

        guard !snapshot.frames.isEmpty else {
            return formalResult(
                photo:formalPhoto,
                corners:formalCorners,
                pixelWidth:formalPixelWidth,
                pixelHeight:formalPixelHeight,
                candidates:snapshot.frames,
                state:.noBufferedFrames,
                startedAt:startedAt,
                reason:"快门前没有可用缓存帧"
            )
        }

        let resolutionEligible = snapshot.frames.filter {
            isResolutionEligible(
                buffered:$0.quality,
                formalPixelWidth:formalPixelWidth,
                formalPixelHeight:formalPixelHeight
            )
        }
        guard !resolutionEligible.isEmpty else {
            return formalResult(
                photo:formalPhoto,
                corners:formalCorners,
                pixelWidth:formalPixelWidth,
                pixelHeight:formalPixelHeight,
                candidates:snapshot.frames,
                state:.skippedInsufficientResolution,
                startedAt:startedAt,
                reason:"缓存帧分辨率不足，已在正式照片质量分析前结束比较"
            )
        }

        let stableCandidates = resolutionEligible.filter {
            guard $0.corners != nil,
                  let cornerJitter = $0.quality.cornerJitter else {
                return false
            }
            return cornerJitter <= 0.030
        }
        guard !stableCandidates.isEmpty else {
            return formalResult(
                photo:formalPhoto,
                corners:formalCorners,
                pixelWidth:formalPixelWidth,
                pixelHeight:formalPixelHeight,
                candidates:snapshot.frames,
                state:.skippedMissingStability,
                startedAt:startedAt,
                reason:"缓存帧没有取得可验证的连续四角稳定度"
            )
        }

        let eligible = stableCandidates.filter {
            $0.quality.exposureScore >= 0.72
        }
        guard !eligible.isEmpty else {
            return formalResult(
                photo:formalPhoto,
                corners:formalCorners,
                pixelWidth:formalPixelWidth,
                pixelHeight:formalPixelHeight,
                candidates:snapshot.frames,
                state:.skippedExposure,
                startedAt:startedAt,
                reason:"缓存帧曝光质量未达到安全门槛"
            )
        }

        let formalQuality = CaptureFrameQualityAnalyzer.analyze(
            image:formalPhoto,
            corners:formalCorners,
            referenceCorners:formalCorners
        )
        let best = eligible.max {
            $0.quality.overallScore < $1.quality.overallScore
        }
        let selected:BufferedCaptureFrame?
        if let best,
           isMeaningfulImprovement(
                candidate:best.quality,
                formal:formalQuality
           ) {
            selected = best
        }
        else {
            selected = nil
        }
        if let selected,
           let selectedImage = selected.image {
            return BestFrameSelectionResult(
                image:selectedImage,
                corners:selected.corners,
                source:.bufferedFrame,
                formalPixelWidth:formalPixelWidth,
                formalPixelHeight:formalPixelHeight,
                formalQuality:formalQuality,
                selectedQuality:selected.quality,
                candidates:snapshot.frames,
                comparisonState:.selectedBufferedFrame,
                processingMilliseconds:milliseconds(since:startedAt),
                reason:"缓存帧分辨率和区域质量均通过安全门槛"
            )
        }
        return BestFrameSelectionResult(
            image:formalPhoto,
            corners:formalCorners,
            source:.formalPhoto,
            formalPixelWidth:formalPixelWidth,
            formalPixelHeight:formalPixelHeight,
            formalQuality:formalQuality,
            selectedQuality:formalQuality,
            candidates:snapshot.frames,
            comparisonState:.comparedNoImprovement,
            processingMilliseconds:milliseconds(since:startedAt),
            reason:"缓存帧没有取得足够且无区域退化的质量提升"
        )
    }

    private static func isResolutionEligible(
        buffered:CaptureFrameQuality,
        formalPixelWidth:Int,
        formalPixelHeight:Int
    )->Bool {
        let bufferedLong = max(buffered.pixelWidth, buffered.pixelHeight)
        let bufferedPixels = buffered.pixelWidth * buffered.pixelHeight
        let formalPixels = max(
            formalPixelWidth * formalPixelHeight,
            1
        )
        return bufferedLong >= 2_400
            && Double(bufferedPixels) / Double(formalPixels) >= 0.62
    }

    private static func formalResult(
        photo:UIImage,
        corners:ScanCorners?,
        pixelWidth:Int,
        pixelHeight:Int,
        candidates:[BufferedCaptureFrame],
        state:BestFrameComparisonState,
        startedAt:Date,
        reason:String
    )->BestFrameSelectionResult {
        BestFrameSelectionResult(
            image:photo,
            corners:corners,
            source:.formalPhoto,
            formalPixelWidth:pixelWidth,
            formalPixelHeight:pixelHeight,
            formalQuality:nil,
            selectedQuality:nil,
            candidates:candidates,
            comparisonState:state,
            processingMilliseconds:milliseconds(since:startedAt),
            reason:reason
        )
    }

    private static func isMeaningfulImprovement(
        candidate:CaptureFrameQuality,
        formal:CaptureFrameQuality
    )->Bool {
        let scoreGain = candidate.overallScore - formal.overallScore
        let averageGain = relativeGain(
            candidate.averageSharpness,
            formal.averageSharpness
        )
        let topRetention = relativeRetention(
            candidate.topSharpness,
            formal.topSharpness
        )
        let middleRetention = relativeRetention(
            candidate.middleSharpness,
            formal.middleSharpness
        )
        let bottomRetention = relativeRetention(
            candidate.bottomSharpness,
            formal.bottomSharpness
        )
        return scoreGain >= 0.08
            && averageGain >= 0.10
            && topRetention >= 0.96
            && middleRetention >= 0.96
            && bottomRetention >= 0.96
            && candidate.sharpnessBalance
                >= formal.sharpnessBalance - 0.02
    }

    private static func relativeGain(_ value:Double,_ baseline:Double)->Double {
        guard baseline > 0.0001 else { return 0 }
        return value / baseline - 1
    }

    private static func relativeRetention(
        _ value:Double,
        _ baseline:Double
    )->Double {
        guard baseline > 0.0001 else { return 1 }
        return value / baseline
    }

    private static func milliseconds(since date:Date)->Int {
        Int(Date().timeIntervalSince(date) * 1_000)
    }
}
