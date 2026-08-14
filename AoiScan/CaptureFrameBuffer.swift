//
//  CaptureFrameBuffer.swift
//  AoiScan
//

import UIKit
import CoreVideo
import CoreImage
import ImageIO


final class CaptureFrameBuffer {
    private let lock = NSLock()
    private let maximumFrames = 3
    private let minimumSampleInterval:TimeInterval = 0.14
    private let preferredBufferedEdge = 1_920
    private let fallbackBufferedEdge = 1_280
    private var frames:[BufferedCaptureFrame] = []
    private var lastSampleDate = Date.distantPast
    private var isFrozen = false

    func offer(
        pixelBuffer:CVPixelBuffer,
        orientation:CGImagePropertyOrientation,
        corners:ScanCorners?,
        referenceCorners:ScanCorners?
    ) {
        let now = Date()
        lock.lock()
        guard !isFrozen,
              now.timeIntervalSince(lastSampleDate)
                >= minimumSampleInterval else {
            lock.unlock()
            return
        }
        lastSampleDate = now
        lock.unlock()

        guard let corners,
              let referenceCorners else {
            return
        }
        let jitter = maximumCornerDistance(corners, referenceCorners)
        guard jitter <= 0.035 else { return }

        let targetEdge = preferredEdgeForCurrentConditions()
        guard let pixelFrame = CapturePixelBufferStore
            .makeIndependentFrame(
                from:pixelBuffer,
                orientation:orientation,
                preferredMaximumEdge:targetEdge
            ) else {
            return
        }
        let quality = CaptureFrameQualityAnalyzer.analyze(
            pixelBuffer:pixelFrame.pixelBuffer,
            corners:corners,
            referenceCorners:referenceCorners
        )
        let frame = BufferedCaptureFrame(
            id:UUID(),
            timestamp:now,
            pixelFrame:pixelFrame,
            orientation:orientation,
            corners:corners,
            quality:quality
        )
        lock.lock()
        defer { lock.unlock() }
        guard !isFrozen else { return }
        if frames.count < maximumFrames {
            frames.append(frame)
        }
        else if let weakestIndex = frames.indices.min(by:{
            frames[$0].quality.overallScore
                < frames[$1].quality.overallScore
        }), frame.quality.overallScore
            > frames[weakestIndex].quality.overallScore + 0.01 {
            frames[weakestIndex] = frame
        }
        frames.sort { $0.timestamp < $1.timestamp }
    }

    func freeze()->CaptureBufferSnapshot {
        lock.lock()
        defer { lock.unlock() }
        isFrozen = true
        return CaptureBufferSnapshot(
            frames:frames,
            frozenAt:Date(),
            diagnosticsOnly:true
        )
    }

    func resumeAndClear() {
        lock.lock()
        defer { lock.unlock() }
        frames.removeAll(keepingCapacity:true)
        lastSampleDate = .distantPast
        isFrozen = false
    }

    func handleMemoryPressure() {
        lock.lock()
        defer { lock.unlock() }
        frames.removeAll(keepingCapacity:false)
        lastSampleDate = .distantPast
    }

    func releaseFrozenFrames() {
        lock.lock()
        defer { lock.unlock() }
        guard isFrozen else { return }
        frames.removeAll(keepingCapacity:false)
    }

    private func preferredEdgeForCurrentConditions()->Int {
        switch ProcessInfo.processInfo.thermalState {
        case .serious,.critical:
            return fallbackBufferedEdge
        case .nominal,.fair:
            return preferredBufferedEdge
        @unknown default:
            return fallbackBufferedEdge
        }
    }

    private func maximumCornerDistance(
        _ first:ScanCorners,
        _ second:ScanCorners
    )->CGFloat {
        zip(
            [first.topLeft,first.topRight,first.bottomRight,first.bottomLeft],
            [second.topLeft,second.topRight,second.bottomRight,second.bottomLeft]
        ).map {
            hypot($0.0.x - $0.1.x, $0.0.y - $0.1.y)
        }.max() ?? .greatestFiniteMagnitude
    }
}
