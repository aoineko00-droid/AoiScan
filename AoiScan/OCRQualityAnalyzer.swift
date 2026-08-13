//
//  OCRQualityAnalyzer.swift
//  AoiScan
//

import Foundation
import CoreGraphics


struct OCRQualityAnalyzer {
    private let lowConfidenceThreshold:Float = 0.70

    func analyze(blocks:[OCRBlock])->OCRQualityResult {
        let usable = blocks.filter {
            !$0.text.trimmingCharacters(
                in:.whitespacesAndNewlines
            ).isEmpty
                && $0.boundingBox.width > 0
                && $0.boundingBox.height > 0
        }

        guard !usable.isEmpty else {
            return OCRQualityResult(
                averageConfidence:0,
                weightedConfidence:0,
                lowConfidenceBlocks:[],
                lowConfidenceRatio:1,
                recognizedBlockCount:0,
                recognizedCharacterCount:0,
                textCoverage:0,
                qualityScore:0,
                qualityLevel:.insufficientText
            )
        }

        let average = usable.reduce(Float.zero) {
            $0 + $1.confidence
        } / Float(usable.count)
        let characterCounts = usable.map {
            meaningfulCharacterCount(in:$0.text)
        }
        let totalCharacters = characterCounts.reduce(0, +)
        let totalWeight = characterCounts.reduce(Float.zero) {
            $0 + Float(max($1, 1))
        }
        let weighted = zip(usable, characterCounts).reduce(
            Float.zero
        ) { partial, value in
            partial
                + value.0.confidence
                * Float(max(value.1, 1))
        } / max(totalWeight, 1)
        let lowConfidence = usable.filter {
            $0.confidence < lowConfidenceThreshold
        }
        let lowRatio = Float(lowConfidence.count)
            / Float(usable.count)
        let coverage = combinedCoverage(
            usable.map(\.boundingBox)
        )

        let confidenceComponent = weighted * 0.72
        let lowConfidenceComponent = (1 - lowRatio) * 0.10
        let characterComponent = min(
            Float(totalCharacters) / 240,
            1
        ) * 0.10
        let coverageComponent = min(
            Float(coverage / 0.24),
            1
        ) * 0.08
        let score = min(
            max(
                confidenceComponent
                    + lowConfidenceComponent
                    + characterComponent
                    + coverageComponent,
                0
            ),
            1
        )

        let level:OCRQualityLevel
        if totalCharacters < 3 {
            level = .insufficientText
        }
        else if weighted >= 0.90,
                lowRatio <= 0.15 {
            level = .excellent
        }
        else if weighted >= 0.72 {
            level = .normal
        }
        else {
            level = .poor
        }

        return OCRQualityResult(
            averageConfidence:average,
            weightedConfidence:weighted,
            lowConfidenceBlocks:lowConfidence,
            lowConfidenceRatio:lowRatio,
            recognizedBlockCount:usable.count,
            recognizedCharacterCount:totalCharacters,
            textCoverage:coverage,
            qualityScore:score,
            qualityLevel:level
        )
    }

    private func meaningfulCharacterCount(
        in text:String
    )->Int {
        text.unicodeScalars.reduce(0) { count, scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                ? count
                : count + 1
        }
    }

    /// Approximates the union area without counting overlapping OCR boxes
    /// twice. Vision text regions normally form short horizontal strips, so a
    /// small grid gives stable comparison metrics at very low cost.
    private func combinedCoverage(
        _ rectangles:[CGRect]
    )->CGFloat {
        let columns = 48
        let rows = 64
        var occupied = Array(
            repeating:false,
            count:columns * rows
        )

        for rawRect in rectangles {
            let rect = rawRect.intersection(
                CGRect(x:0, y:0, width:1, height:1)
            )
            guard !rect.isNull,
                  rect.width > 0,
                  rect.height > 0 else {
                continue
            }

            let minimumX = max(
                0,
                min(columns - 1, Int(floor(rect.minX * CGFloat(columns))))
            )
            let maximumX = max(
                0,
                min(columns - 1, Int(ceil(rect.maxX * CGFloat(columns))) - 1)
            )
            let minimumY = max(
                0,
                min(rows - 1, Int(floor(rect.minY * CGFloat(rows))))
            )
            let maximumY = max(
                0,
                min(rows - 1, Int(ceil(rect.maxY * CGFloat(rows))) - 1)
            )

            guard minimumX <= maximumX,
                  minimumY <= maximumY else {
                continue
            }

            for y in minimumY...maximumY {
                for x in minimumX...maximumX {
                    occupied[y * columns + x] = true
                }
            }
        }

        return CGFloat(occupied.filter { $0 }.count)
            / CGFloat(columns * rows)
    }
}
