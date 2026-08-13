//
//  TableRegionAnalyzer.swift
//  AoiScan
//

import Foundation
import CoreGraphics


/// Finds conservative table regions from repeated horizontal anchors.
/// It only uses OCR geometry and does not depend on recognized words.
struct TableRegionAnalyzer {
    private struct Row {
        var lines:[TextLine]
        var blocks:[OCRBlock]
        var midY:CGFloat

        var boundingBox:CGRect {
            blocks
                .map(\.boundingBox)
                .reduce(CGRect.null) { partial, next in
                    partial.union(next)
                }
        }
    }

    private struct AnchorCluster {
        var center:CGFloat
        var rowIndexes:Set<Int>
        var samples:Int
    }

    func analyze(
        textLines:[TextLine]
    )->[TableRegion] {
        guard textLines.count >= 6 else { return [] }

        let medianHeight = median(
            textLines.map { $0.boundingBox.height }
        )
        let rows = makeRows(
            from:textLines,
            tolerance:max(0.009, medianHeight * 0.52)
        )
        let maximumRowGap = max(0.045, medianHeight * 2.7)
        var results:[TableRegion] = []
        var current:[Row] = []

        func finishRun() {
            defer { current.removeAll(keepingCapacity:true) }
            guard let region = makeRegion(from:current) else {
                return
            }
            results.append(region)
        }

        for row in rows {
            guard row.blocks.count >= 2 else {
                finishRun()
                continue
            }

            if let previous = current.last,
               previous.midY - row.midY > maximumRowGap {
                finishRun()
            }

            current.append(row)
        }

        finishRun()

        return mergeOverlapping(results)
    }

    private func makeRows(
        from lines:[TextLine],
        tolerance:CGFloat
    )->[Row] {
        var rows:[Row] = []

        for line in lines.sorted(by:TextLine.readingOrder) {
            if let index = rows.indices.min(
                by:{
                    abs(rows[$0].midY - line.boundingBox.midY)
                        < abs(rows[$1].midY - line.boundingBox.midY)
                }
            ),
               abs(rows[index].midY - line.boundingBox.midY)
                    <= tolerance {
                rows[index].lines.append(line)
                rows[index].blocks.append(contentsOf:line.ocrBlocks)
                rows[index].midY = rows[index].lines.reduce(
                    CGFloat.zero
                ) {
                    $0 + $1.boundingBox.midY
                } / CGFloat(rows[index].lines.count)
            }
            else {
                rows.append(
                    Row(
                        lines:[line],
                        blocks:line.ocrBlocks,
                        midY:line.boundingBox.midY
                    )
                )
            }
        }

        return rows.sorted { $0.midY > $1.midY }
    }

    private func makeRegion(
        from rows:[Row]
    )->TableRegion? {
        guard rows.count >= 3 else { return nil }

        let requiredRows = max(
            3,
            Int(ceil(Double(rows.count) * 0.58))
        )
        let anchors = stableAnchors(
            rows:rows,
            requiredRows:requiredRows
        )

        guard anchors.count >= 2 else { return nil }

        let allBlocks = rows.flatMap(\.blocks)
        let regionBox = allBlocks
            .map(\.boundingBox)
            .reduce(CGRect.null) { partial, next in
                partial.union(next)
            }
        let medianBlockWidth = median(
            allBlocks.map { $0.boundingBox.width }
        )
        let multiCellRatio = CGFloat(
            rows.filter { $0.blocks.count >= 2 }.count
        ) / CGFloat(rows.count)

        if anchors.count == 2 {
            guard rows.count >= 4,
                  multiCellRatio >= 0.74,
                  medianBlockWidth <= 0.26,
                  regionBox.height <= 0.66 else {
                return nil
            }
        }

        let lines = rows.flatMap(\.lines)
        return TableRegion(
            textLines:lines,
            ocrBlocks:allBlocks
        )
    }

    private func stableAnchors(
        rows:[Row],
        requiredRows:Int
    )->[CGFloat] {
        let tolerance:CGFloat = 0.035
        var clusters:[AnchorCluster] = []

        for (rowIndex, row) in rows.enumerated() {
            for block in row.blocks {
                let anchor = block.boundingBox.minX

                if let index = clusters.indices.min(
                    by:{
                        abs(clusters[$0].center - anchor)
                            < abs(clusters[$1].center - anchor)
                    }
                ),
                   abs(clusters[index].center - anchor) <= tolerance {
                    let samples = clusters[index].samples
                    clusters[index].center = (
                        clusters[index].center * CGFloat(samples)
                            + anchor
                    ) / CGFloat(samples + 1)
                    clusters[index].samples += 1
                    clusters[index].rowIndexes.insert(rowIndex)
                }
                else {
                    clusters.append(
                        AnchorCluster(
                            center:anchor,
                            rowIndexes:[rowIndex],
                            samples:1
                        )
                    )
                }
            }
        }

        let centers = clusters.filter {
            $0.rowIndexes.count >= requiredRows
        }
        .map(\.center)
        .sorted()

        var distinct:[CGFloat] = []
        for center in centers {
            if let last = distinct.last,
               center - last < 0.07 {
                continue
            }
            distinct.append(center)
        }

        return distinct
    }

    private func mergeOverlapping(
        _ regions:[TableRegion]
    )->[TableRegion] {
        var merged:[TableRegion] = []

        for region in regions.sorted(by:{
            $0.boundingBox.maxY > $1.boundingBox.maxY
        }) {
            if let index = merged.indices.first(where:{
                overlapRatio(
                    merged[$0].boundingBox,
                    region.boundingBox
                ) >= 0.25
            }) {
                merged[index] = TableRegion(
                    textLines:merged[index].textLines
                        + region.textLines,
                    ocrBlocks:merged[index].ocrBlocks
                        + region.ocrBlocks
                )
            }
            else {
                merged.append(region)
            }
        }

        return merged
    }

    private func overlapRatio(
        _ first:CGRect,
        _ second:CGRect
    )->CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }
        let smallerArea = max(
            min(first.width * first.height, second.width * second.height),
            0.0001
        )
        return intersection.width * intersection.height / smallerArea
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
