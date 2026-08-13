//
//  ColumnAnalyzer.swift
//  AoiScan
//

import Foundation
import CoreGraphics


/// Detects one to three reading columns from horizontal whitespace and the
/// vertical coexistence of text lines. Full-width headers remain spanning.
struct ColumnAnalyzer {
    private struct SplitResult {
        let left:[TextLine]
        let right:[TextLine]
        let crossing:[TextLine]
        let score:CGFloat
    }

    func analyze(
        textLines:[TextLine]
    )->ColumnLayout {
        let lines = textLines.sorted(by:TextLine.readingOrder)
        guard !lines.isEmpty else {
            return ColumnLayout(columns:[], spanningLines:[])
        }

        var spanningIDs = Set<UUID>()
        let groups = splitRecursively(
            lines:lines,
            depth:0,
            spanningIDs:&spanningIDs
        )
        .filter { !$0.isEmpty }
        .sorted {
            union(of:$0).minX < union(of:$1).minX
        }

        let columns = groups.enumerated().map {
            ColumnRegion(
                index:$0.offset,
                textLines:$0.element
            )
        }
        let spanningLines = lines.filter {
            spanningIDs.contains($0.id)
        }

        return ColumnLayout(
            columns:columns,
            spanningLines:spanningLines.sorted(
                by:TextLine.readingOrder
            )
        )
    }

    private func splitRecursively(
        lines:[TextLine],
        depth:Int,
        spanningIDs:inout Set<UUID>
    )->[[TextLine]] {
        guard depth < 2,
              lines.count >= 6,
              let split = bestSplit(in:lines) else {
            return [lines]
        }

        spanningIDs.formUnion(split.crossing.map(\.id))

        let leftGroups = splitRecursively(
            lines:split.left,
            depth:depth + 1,
            spanningIDs:&spanningIDs
        )
        let rightGroups = splitRecursively(
            lines:split.right,
            depth:depth + 1,
            spanningIDs:&spanningIDs
        )

        return leftGroups + rightGroups
    }

    private func bestSplit(
        in lines:[TextLine]
    )->SplitResult? {
        let region = union(of:lines)
        guard region.width >= 0.42 else { return nil }

        let requiredSideCount = max(
            2,
            Int(ceil(Double(lines.count) * 0.20))
        )
        let maximumCrossingCount = max(
            2,
            Int(floor(Double(lines.count) * 0.20))
        )
        let lower = region.minX + region.width * 0.24
        let upper = region.maxX - region.width * 0.24
        let step = max(region.width / 60, 0.008)
        let separatorPadding = max(region.width * 0.012, 0.007)
        var splitX = lower
        var best:SplitResult?

        while splitX <= upper {
            let left = lines.filter {
                $0.boundingBox.midX < splitX
                    && $0.boundingBox.maxX
                        <= splitX + separatorPadding
            }
            let right = lines.filter {
                $0.boundingBox.midX >= splitX
                    && $0.boundingBox.minX
                        >= splitX - separatorPadding
            }
            let assignedIDs = Set((left + right).map(\.id))
            let crossing = lines.filter {
                !assignedIDs.contains($0.id)
            }

            guard left.count >= requiredSideCount,
                  right.count >= requiredSideCount,
                  crossing.count <= maximumCrossingCount else {
                splitX += step
                continue
            }

            let leftBox = union(of:left)
            let rightBox = union(of:right)
            let whitespace = rightBox.minX - leftBox.maxX

            guard whitespace >= max(0.022, region.width * 0.035),
                  verticalOverlapRatio(leftBox, rightBox) >= 0.34 else {
                splitX += step
                continue
            }

            let balance = CGFloat(min(left.count, right.count))
                / CGFloat(max(left.count, right.count))
            let score = whitespace * 5
                + balance
                - CGFloat(crossing.count) * 0.08
            let candidate = SplitResult(
                left:left,
                right:right,
                crossing:crossing,
                score:score
            )

            if best == nil || candidate.score > best!.score {
                best = candidate
            }

            splitX += step
        }

        return best
    }

    private func verticalOverlapRatio(
        _ first:CGRect,
        _ second:CGRect
    )->CGFloat {
        let overlap = max(
            0,
            min(first.maxY, second.maxY)
                - max(first.minY, second.minY)
        )
        let smallerHeight = max(
            min(first.height, second.height),
            0.001
        )
        return overlap / smallerHeight
    }

    private func union(
        of lines:[TextLine]
    )->CGRect {
        let result = lines
            .map(\.boundingBox)
            .reduce(CGRect.null) { partial, next in
                partial.union(next)
            }
        return result.isNull ? .zero : result
    }
}
