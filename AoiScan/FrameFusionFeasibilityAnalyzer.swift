//
//  FrameFusionFeasibilityAnalyzer.swift
//  AoiScan
//

import Foundation


enum FrameFusionRecommendation:String,Codable {
    case insufficientData
    case unstableAlignment
    case inconsistentExposure
    case noComplementaryDetail
    case testHigherResolutionBuffer
    case currentBufferEligible

    var diagnosticName:String {
        switch self {
        case .insufficientData:
            return "有效数据不足，暂不评估融合"
        case .unstableAlignment:
            return "帧间定位不稳定，不建议融合"
        case .inconsistentExposure:
            return "帧间曝光差异偏大，不建议融合"
        case .noComplementaryDetail:
            return "没有发现互补清晰区域，融合价值有限"
        case .testHigherResolutionBuffer:
            return "存在互补区域，建议下一步测试高分辨率缓存"
        case .currentBufferEligible:
            return "当前缓存满足融合实验条件"
        }
    }
}


struct FrameFusionFeasibilityResult:Codable {
    let frameCount:Int
    let stableFrameCount:Int
    let maximumCornerJitter:Double?
    let brightnessSpread:Double
    let exposureSpread:Double
    let topSharpnessGain:Double
    let middleSharpnessGain:Double
    let bottomSharpnessGain:Double
    let complementaryRegionCount:Int
    let distinctWinningFrameCount:Int
    let hasComplementaryRegions:Bool
    let currentResolutionEligible:Bool
    let storageMegabytes:Double
    let fallbackFrameCount:Int
    let analysisMilliseconds:Int
    let recommendation:FrameFusionRecommendation
    let reason:String
}


enum FrameFusionFeasibilityAnalyzer {
    static func analyze(
        snapshot:CaptureBufferSnapshot
    )->FrameFusionFeasibilityResult {
        let startedAt = Date()
        let frames = snapshot.frames
        let stable = frames.filter {
            guard $0.corners != nil,
                  let jitter = $0.quality.cornerJitter else {
                return false
            }
            return jitter <= 0.030
        }
        let source = stable.count >= 3 ? stable : frames
        let brightnessSpread = spread(source.map { $0.quality.brightness })
        let exposureSpread = spread(source.map { $0.quality.exposureScore })
        let maxJitter = stable.compactMap {
            $0.quality.cornerJitter.map(Double.init)
        }.max()
        let top = regionResult(source) { $0.quality.topSharpness }
        let middle = regionResult(source) { $0.quality.middleSharpness }
        let bottom = regionResult(source) { $0.quality.bottomSharpness }
        let regionResults = [top,middle,bottom]
        let complementaryCount = regionResults.filter { $0.gain >= 0.12 }.count
        let winningIDs = Set(
            regionResults.compactMap { result in
                result.gain >= 0.12 ? result.frameID : nil
            }
        )
        let hasComplementary = complementaryCount >= 1
            && winningIDs.count >= 2
        let resolutionEligible = source.allSatisfy {
            min($0.quality.pixelWidth, $0.quality.pixelHeight) >= 1_400
        }
        let storageMegabytes = Double(
            frames.reduce(0) { $0 + $1.pixelFrame.storageBytes }
        ) / 1_048_576
        let fallbackFrameCount = frames.filter {
            $0.pixelFrame.usedFallbackResolution
        }.count

        let recommendation:FrameFusionRecommendation
        let reason:String
        if frames.count < 3 {
            recommendation = .insufficientData
            reason = "少于3帧，无法判断局部清晰度互补性"
        }
        else if stable.count < 3 {
            recommendation = .unstableAlignment
            reason = "少于3帧具有稳定四角定位"
        }
        else if (maxJitter ?? 1) > 0.022 {
            recommendation = .unstableAlignment
            reason = "稳定帧仍存在较明显的四角偏差"
        }
        else if brightnessSpread > 0.07 || exposureSpread > 0.09 {
            recommendation = .inconsistentExposure
            reason = "多帧亮度或曝光差异超过融合安全门槛"
        }
        else if !hasComplementary {
            recommendation = .noComplementaryDetail
            reason = "各区域最佳帧相对中位帧提升不足12%"
        }
        else if !resolutionEligible {
            recommendation = .testHigherResolutionBuffer
            reason = "发现互补清晰区域，但当前缓存分辨率不足以补充正式照片细节"
        }
        else {
            recommendation = .currentBufferEligible
            reason = "稳定度、曝光、互补清晰度和分辨率均满足实验门槛"
        }

        return FrameFusionFeasibilityResult(
            frameCount:frames.count,
            stableFrameCount:stable.count,
            maximumCornerJitter:maxJitter,
            brightnessSpread:brightnessSpread,
            exposureSpread:exposureSpread,
            topSharpnessGain:top.gain,
            middleSharpnessGain:middle.gain,
            bottomSharpnessGain:bottom.gain,
            complementaryRegionCount:complementaryCount,
            distinctWinningFrameCount:winningIDs.count,
            hasComplementaryRegions:hasComplementary,
            currentResolutionEligible:resolutionEligible,
            storageMegabytes:storageMegabytes,
            fallbackFrameCount:fallbackFrameCount,
            analysisMilliseconds:max(
                0,
                Int(Date().timeIntervalSince(startedAt) * 1000)
            ),
            recommendation:recommendation,
            reason:reason
        )
    }

    private struct RegionResult {
        let gain:Double
        let frameID:UUID?
    }

    private static func regionResult(
        _ frames:[BufferedCaptureFrame],
        value:(BufferedCaptureFrame)->Double
    )->RegionResult {
        guard !frames.isEmpty else {
            return RegionResult(gain:0, frameID:nil)
        }
        let sorted = frames.sorted { value($0) < value($1) }
        let median = value(sorted[sorted.count / 2])
        guard let best = sorted.last else {
            return RegionResult(gain:0, frameID:nil)
        }
        let gain = median > 0.0001
            ? max(value(best) / median - 1, 0) : 0
        return RegionResult(gain:gain, frameID:best.id)
    }

    private static func spread(_ values:[Double])->Double {
        guard let minimum = values.min(),
              let maximum = values.max() else {
            return 0
        }
        return maximum - minimum
    }
}
