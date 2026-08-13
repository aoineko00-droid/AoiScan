//
//  LineAnalyzer.swift
//  AoiScan
//

import Foundation
import CoreGraphics


/// Groups OCR observations that visually belong to the same text line.
///
/// The horizontal-gap limit deliberately prevents equally high lines from
/// opposite columns from being merged together.
struct LineAnalyzer {
    private struct WorkingLine {
        var blocks:[OCRBlock]

        var boundingBox:CGRect {
            blocks
                .map(\.boundingBox)
                .reduce(CGRect.null) { partial, next in
                    partial.union(next)
                }
        }

        var midY:CGFloat {
            boundingBox.midY
        }
    }

    func analyze(
        ocrBlocks:[OCRBlock]
    )->[TextLine] {
        let blocks = ocrBlocks.filter {
            !$0.text.trimmingCharacters(
                in:.whitespacesAndNewlines
            ).isEmpty
                && $0.boundingBox.width > 0
                && $0.boundingBox.height > 0
        }

        guard !blocks.isEmpty else { return [] }

        let medianHeight = median(
            blocks.map { $0.boundingBox.height }
        )
        let maximumHorizontalGap = max(
            0.016,
            min(0.040, medianHeight * 1.65)
        )
        let ordered = blocks.sorted(by:OCRBlock.readingOrder)
        var workingLines:[WorkingLine] = []

        for block in ordered {
            var bestIndex:Int?
            var bestScore = CGFloat.greatestFiniteMagnitude

            for index in workingLines.indices {
                let lineBox = workingLines[index].boundingBox

                guard hasCompatibleHeight(lineBox, block.boundingBox),
                      isSameBaseline(
                        lineBox,
                        block.boundingBox,
                        medianHeight:medianHeight
                      ) else {
                    continue
                }

                let horizontalGap = gapBetween(
                    lineBox,
                    block.boundingBox
                )

                guard horizontalGap <= maximumHorizontalGap else {
                    continue
                }

                let score = abs(
                    workingLines[index].midY
                        - block.boundingBox.midY
                ) + horizontalGap * 0.35

                if score < bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }

            if let bestIndex {
                workingLines[bestIndex].blocks.append(block)
            }
            else {
                workingLines.append(
                    WorkingLine(blocks:[block])
                )
            }
        }

        return workingLines
            .map { TextLine(ocrBlocks:$0.blocks) }
            .sorted(by:TextLine.readingOrder)
    }

    private func isSameBaseline(
        _ first:CGRect,
        _ second:CGRect,
        medianHeight:CGFloat
    )->Bool {
        let overlap = max(
            0,
            min(first.maxY, second.maxY)
                - max(first.minY, second.minY)
        )
        let smallerHeight = max(
            min(first.height, second.height),
            0.001
        )
        let overlapRatio = overlap / smallerHeight
        let centerTolerance = max(
            0.007,
            medianHeight * 0.46
        )

        return overlapRatio >= 0.48
            || abs(first.midY - second.midY) <= centerTolerance
    }

    private func hasCompatibleHeight(
        _ first:CGRect,
        _ second:CGRect
    )->Bool {
        let smaller = max(min(first.height, second.height), 0.001)
        let larger = max(first.height, second.height)
        return larger / smaller <= 2.25
    }

    private func gapBetween(
        _ first:CGRect,
        _ second:CGRect
    )->CGFloat {
        if first.maxX < second.minX {
            return second.minX - first.maxX
        }

        if second.maxX < first.minX {
            return first.minX - second.maxX
        }

        return 0
    }

    private func median(
        _ values:[CGFloat]
    )->CGFloat {
        guard !values.isEmpty else { return 0 }
        let ordered = values.sorted()
        let middle = ordered.count / 2

        if ordered.count.isMultiple(of:2) {
            return (ordered[middle - 1] + ordered[middle]) / 2
        }

        return ordered[middle]
    }
}
