//
//  DocumentQualityRouter.swift
//  AoiScan
//

import Foundation
import CoreGraphics


enum DocumentQualityRouter {
    static func route(
        quality:DocumentQualityScore,
        ocrQuality:OCRQualityResult,
        blocks:[OCRBlock],
        perspectiveSeverity:Float? = nil
    )->DocumentQualityRoute {
        guard ocrQuality.qualityLevel != .insufficientText,
              blocks.count >= 2 else {
            return .none("文字证据不足，不执行图像恢复")
        }

        if let perspectiveSeverity,
           perspectiveSeverity >= 0.24 {
            return DocumentQualityRoute(
                primaryIssue:.perspective,
                affectedRegion:.none,
                severity:min(perspectiveSeverity, 1),
                reason:"透视问题由 Smart Document Recovery 处理"
            )
        }

        let visual = quality.visual
        // Normal lighting variation is diagnostic information, not a reason to
        // spend another full OCR pass. Only route genuinely strong problems.
        let strongGradient = visual.illuminationGradient >= 0.075
        let strongShadow = visual.shadowSeverity >= 0.18
        let severeGradient = visual.illuminationGradient >= 0.10
        let localizedShadow = visual.shadowSeverity >= 0.095
            && visual.backgroundUniformity <= 0.88
        if severeGradient
            || (strongGradient && strongShadow)
            || localizedShadow {
            let reason = localizedShadow && !severeGradient
                ? "局部阴影与背景不均证据同时达到恢复门槛"
                : "亮度梯度与阴影证据同时达到光照恢复门槛"
            return DocumentQualityRoute(
                primaryIssue:.lighting,
                affectedRegion:.none,
                severity:min(
                    max(
                        visual.illuminationGradient / 0.18,
                        visual.shadowSeverity / 0.22
                    ),
                    1
                ),
                reason:reason
            )
        }

        // Regional sharpness differences remain in diagnostics. They are not
        // routed to production enhancement until a cheap pre-OCR metric can
        // demonstrate a reliable gain.

        if visual.backgroundUniformity < 0.58,
           visual.shadowSeverity >= 0.32 {
            return DocumentQualityRoute(
                primaryIssue:.background,
                affectedRegion:.none,
                severity:min(
                    (0.58 - visual.backgroundUniformity) * 2.2
                        + visual.shadowSeverity * 0.55,
                    1
                ),
                reason:"背景均匀度与局部暗区同时达到背景恢复门槛"
            )
        }

        return .none("没有发现需要恢复的独立质量问题")
    }

    private static func regionalSharpnessRoute(
        visual:DocumentVisualQualityResult,
        blocks:[OCRBlock]
    )->DocumentQualityRoute? {
        let values:[(DocumentRegion,Float)] = [
            (.top, visual.topClarity),
            (.middle, visual.middleClarity),
            (.bottom, visual.bottomClarity)
        ]
        guard let weakest = values.min(by:{ $0.1 < $1.1 }),
              let strongest = values.max(by:{ $0.1 < $1.1 }),
              strongest.1 > 0.08 else { return nil }

        let difference = strongest.1 - weakest.1
        let ratio = weakest.1 / max(strongest.1, 0.001)
        let blockCount = blocks.filter {
            region(for:$0.boundingBox.midY) == weakest.0
        }.count
        guard difference >= 0.14,
              ratio <= 0.72,
              blockCount >= 2 else { return nil }

        return DocumentQualityRoute(
            primaryIssue:.regionalSharpness,
            affectedRegion:weakest.0,
            severity:min(difference / 0.34, 1),
            reason:"\(weakest.0.diagnosticName)清晰度明显低于其他区域"
        )
    }

    static func region(for normalizedY:CGFloat)->DocumentRegion {
        if normalizedY >= 2.0 / 3.0 { return .top }
        if normalizedY >= 1.0 / 3.0 { return .middle }
        return .bottom
    }
}
