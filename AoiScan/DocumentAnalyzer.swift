//
//  DocumentAnalyzer.swift
//  AoiScan
//

import Foundation
import CoreGraphics


/// Conservative rule-based layout analysis performed after OCR.
///
/// This layer never runs OCR again and never changes the plain text presented
/// to the user. It converts OCR geometry through the following stages:
/// OCRBlock -> TextLine -> ColumnRegion -> table/paragraph -> DocumentBlock.
struct DocumentAnalyzer {
    private struct PositionedBlock {
        let block:DocumentBlock
        let columnIndex:Int?
        let isTitle:Bool
    }

    func analyze(
        ocrBlocks:[OCRBlock]
    )->[DocumentBlock] {
        let blocks = ocrBlocks.filter {
            !$0.text.trimmingCharacters(
                in:.whitespacesAndNewlines
            ).isEmpty
                && $0.boundingBox.width > 0
                && $0.boundingBox.height > 0
        }

        guard !blocks.isEmpty else { return [] }

        let lines = LineAnalyzer().analyze(
            ocrBlocks:blocks
        )
        guard !lines.isEmpty else { return [] }

        let medianHeight = median(
            lines.map { $0.boundingBox.height }
        )
        let titleLines = detectTitleLines(
            in:lines,
            medianHeight:medianHeight
        )
        let titleIDs = Set(titleLines.map(\.id))
        let bodyLines = lines.filter {
            !titleIDs.contains($0.id)
        }

        // Columns are inferred before semantic grouping. Table regions are
        // then removed from paragraph input so aligned cells cannot become a
        // normal paragraph.
        let columnLayout = ColumnAnalyzer().analyze(
            textLines:bodyLines
        )
        let tableRegions = TableRegionAnalyzer().analyze(
            textLines:bodyLines
        )
        let tableLineIDs = Set(
            tableRegions.flatMap(\.textLines).map(\.id)
        )

        var positioned:[PositionedBlock] = []

        if !titleLines.isEmpty {
            positioned.append(
                PositionedBlock(
                    block:makeDocumentBlock(
                        type:.title,
                        lines:titleLines
                    ),
                    columnIndex:nil,
                    isTitle:true
                )
            )
        }

        for table in tableRegions {
            positioned.append(
                PositionedBlock(
                    block:makeDocumentBlock(
                        type:.table,
                        blocks:table.ocrBlocks
                    ),
                    columnIndex:columnIndex(
                        for:table.boundingBox,
                        columns:columnLayout.columns
                    ),
                    isTitle:false
                )
            )
        }

        for column in columnLayout.columns {
            let availableLines = column.textLines.filter {
                !tableLineIDs.contains($0.id)
                    && !titleIDs.contains($0.id)
            }
            let groups = groupParagraphs(
                availableLines,
                columnWidth:max(column.boundingBox.width, 0.1),
                medianHeight:medianHeight
            )

            for group in groups {
                positioned.append(
                    PositionedBlock(
                        block:makeParagraphBlock(lines:group),
                        columnIndex:column.index,
                        isTitle:false
                    )
                )
            }
        }

        let columnLineIDs = Set(
            columnLayout.columns
                .flatMap(\.textLines)
                .map(\.id)
        )
        let remainingSpanningLines = bodyLines.filter {
            !columnLineIDs.contains($0.id)
                && !tableLineIDs.contains($0.id)
        }
        let spanningGroups = groupParagraphs(
            remainingSpanningLines,
            columnWidth:1,
            medianHeight:medianHeight
        )

        for group in spanningGroups {
            positioned.append(
                PositionedBlock(
                    block:makeParagraphBlock(lines:group),
                    columnIndex:nil,
                    isTitle:false
                )
            )
        }

        return order(
            positioned,
            columns:columnLayout.columns
        )
        .enumerated()
        .map { readingOrder, item in
            item.block.withLayout(
                readingOrder:readingOrder,
                columnIndex:item.columnIndex
            )
        }
    }

    private func detectTitleLines(
        in lines:[TextLine],
        medianHeight:CGFloat
    )->[TextLine] {
        guard medianHeight > 0 else { return [] }

        let candidates = lines.compactMap {
            line -> (TextLine,CGFloat)? in

            let box = line.boundingBox
            guard box.maxY >= 0.68,
                  containsMeaningfulCharacters(line.text),
                  !containsOnlyDigitsAndPunctuation(line.text) else {
                return nil
            }

            let heightRatio = box.height / medianHeight
            let centerDistance = abs(box.midX - 0.5)
            var score:CGFloat = 0

            if box.midY >= 0.78 {
                score += 1.2
            }
            else if box.midY >= 0.68 {
                score += 0.7
            }

            if heightRatio >= 1.45 {
                score += 1.6
            }
            else if heightRatio >= 1.20 {
                score += 0.9
            }

            if centerDistance <= 0.10 {
                score += 1.1
            }
            else if centerDistance <= 0.18 {
                score += 0.6
            }

            if line.text.count <= 80 {
                score += 0.25
            }

            if line.averageConfidence >= 0.5 {
                score += 0.15
            }

            guard score >= 2.45 else { return nil }
            return (line, score)
        }

        guard !candidates.isEmpty else { return [] }

        let bestScore = candidates.map(\.1).max() ?? 0
        let bestY = candidates
            .filter { $0.1 >= bestScore - 0.45 }
            .map { $0.0.boundingBox.midY }
            .max() ?? 0

        return candidates.filter {
            $0.1 >= bestScore - 0.45
                && abs($0.0.boundingBox.midY - bestY)
                    <= max(medianHeight * 2.4, 0.055)
        }
        .map(\.0)
        .sorted(by:TextLine.readingOrder)
    }

    private func groupParagraphs(
        _ lines:[TextLine],
        columnWidth:CGFloat,
        medianHeight:CGFloat
    )->[[TextLine]] {
        let ordered = lines.sorted(by:TextLine.readingOrder)
        guard !ordered.isEmpty else { return [] }

        let positiveGaps = zip(
            ordered,
            ordered.dropFirst()
        )
        .compactMap { previous, current -> CGFloat? in
            let gap = previous.boundingBox.minY
                - current.boundingBox.maxY
            return gap >= 0 ? gap : nil
        }
        let normalGap = median(positiveGaps)
        let maximumGap = min(
            0.060,
            max(
                medianHeight * 1.55,
                normalGap * 1.85,
                0.024
            )
        )
        let leadingTolerance = max(
            0.028,
            min(0.070, columnWidth * 0.13)
        )
        var groups:[[TextLine]] = []

        for line in ordered {
            guard var current = groups.popLast(),
                  let previous = current.last else {
                groups.append([line])
                continue
            }

            if shouldJoin(
                previous:previous,
                current:line,
                paragraphLeading:current.first?.boundingBox.minX
                    ?? previous.boundingBox.minX,
                maximumGap:maximumGap,
                leadingTolerance:leadingTolerance,
                medianHeight:medianHeight
            ) {
                current.append(line)
                groups.append(current)
            }
            else {
                groups.append(current)
                groups.append([line])
            }
        }

        return groups
    }

    private func shouldJoin(
        previous:TextLine,
        current:TextLine,
        paragraphLeading:CGFloat,
        maximumGap:CGFloat,
        leadingTolerance:CGFloat,
        medianHeight:CGFloat
    )->Bool {
        let verticalGap = previous.boundingBox.minY
            - current.boundingBox.maxY

        guard verticalGap >= -medianHeight * 0.48,
              verticalGap <= maximumGap,
              hasCompatibleHeight(previous, current) else {
            return false
        }

        let leadingDifference = abs(
            previous.boundingBox.minX
                - current.boundingBox.minX
        )
        let paragraphLeadingDifference = abs(
            paragraphLeading - current.boundingBox.minX
        )
        let overlap = horizontalOverlapRatio(
            previous.boundingBox,
            current.boundingBox
        )

        return leadingDifference <= leadingTolerance
            || paragraphLeadingDifference <= leadingTolerance
            || overlap >= 0.55
    }

    private func hasCompatibleHeight(
        _ first:TextLine,
        _ second:TextLine
    )->Bool {
        let smaller = max(
            min(
                first.boundingBox.height,
                second.boundingBox.height
            ),
            0.001
        )
        let larger = max(
            first.boundingBox.height,
            second.boundingBox.height
        )
        return larger / smaller <= 2.15
    }

    private func horizontalOverlapRatio(
        _ first:CGRect,
        _ second:CGRect
    )->CGFloat {
        let overlap = max(
            0,
            min(first.maxX, second.maxX)
                - max(first.minX, second.minX)
        )
        let smallerWidth = max(
            min(first.width, second.width),
            0.001
        )
        return overlap / smallerWidth
    }

    private func makeParagraphBlock(
        lines:[TextLine]
    )->DocumentBlock {
        let text = lines.map(\.text)
            .joined()
            .trimmingCharacters(in:.whitespacesAndNewlines)
        let type:DocumentBlockType =
            lines.count > 1 || text.count >= 4
            ? .paragraph
            : .unknown

        return makeDocumentBlock(
            type:type,
            lines:lines
        )
    }

    private func makeDocumentBlock(
        type:DocumentBlockType,
        lines:[TextLine]
    )->DocumentBlock {
        makeDocumentBlock(
            type:type,
            blocks:lines.flatMap(\.ocrBlocks)
        )
    }

    private func makeDocumentBlock(
        type:DocumentBlockType,
        blocks:[OCRBlock]
    )->DocumentBlock {
        let unique = Dictionary(
            blocks.map { ($0.id, $0) },
            uniquingKeysWith:{ first, _ in first }
        )
        .values
        .sorted(by:OCRBlock.readingOrder)
        let boundingBox = unique
            .map(\.boundingBox)
            .reduce(CGRect.null) { partial, next in
                partial.union(next)
            }
            .intersection(
                CGRect(x:0, y:0, width:1, height:1)
            )

        return DocumentBlock(
            type:type,
            ocrBlocks:unique,
            boundingBox:boundingBox.isNull ? .zero : boundingBox
        )
    }

    private func columnIndex(
        for box:CGRect,
        columns:[ColumnRegion]
    )->Int? {
        guard columns.count > 1,
              box.width > 0 else {
            return columns.first?.index
        }

        let candidates = columns.compactMap {
            column -> (Int,CGFloat)? in
            let horizontalIntersection = max(
                0,
                min(box.maxX, column.boundingBox.maxX)
                    - max(box.minX, column.boundingBox.minX)
            )
            let coverage = horizontalIntersection / box.width

            guard coverage >= 0.62,
                  box.width <= column.boundingBox.width * 1.35 else {
                return nil
            }

            return (column.index, coverage)
        }

        return candidates.max { $0.1 < $1.1 }?.0
    }

    private func order(
        _ items:[PositionedBlock],
        columns:[ColumnRegion]
    )->[PositionedBlock] {
        let titles = items.filter(\.isTitle).sorted {
            $0.block.boundingBox.maxY > $1.block.boundingBox.maxY
        }
        let body = items.filter { !$0.isTitle }

        guard columns.count > 1 else {
            return titles + body.sorted(by:verticalBlockOrder)
        }

        let columnTop = columns.map {
            $0.boundingBox.maxY
        }.max() ?? 1
        let columnBottom = columns.map {
            $0.boundingBox.minY
        }.min() ?? 0
        let topSpanning = body.filter {
            $0.columnIndex == nil
                && $0.block.boundingBox.minY >= columnTop - 0.03
        }
        .sorted(by:verticalBlockOrder)
        let bottomSpanning = body.filter {
            $0.columnIndex == nil
                && $0.block.boundingBox.maxY <= columnBottom + 0.03
        }
        .sorted(by:verticalBlockOrder)
        let edgeSpanningIDs = Set(
            (topSpanning + bottomSpanning).map { $0.block.id }
        )
        let middleSpanning = body.filter {
            $0.columnIndex == nil
                && !edgeSpanningIDs.contains($0.block.id)
        }
        .sorted(by:verticalBlockOrder)
        let columnItems = columns.sorted {
            $0.index < $1.index
        }
        .flatMap { column in
            body.filter {
                $0.columnIndex == column.index
            }
            .sorted(by:verticalBlockOrder)
        }

        return titles
            + topSpanning
            + columnItems
            + middleSpanning
            + bottomSpanning
    }

    private func verticalBlockOrder(
        _ first:PositionedBlock,
        _ second:PositionedBlock
    )->Bool {
        let difference = abs(
            first.block.boundingBox.maxY
                - second.block.boundingBox.maxY
        )

        if difference > 0.012 {
            return first.block.boundingBox.maxY
                > second.block.boundingBox.maxY
        }

        return first.block.boundingBox.minX
            < second.block.boundingBox.minX
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

    private func containsMeaningfulCharacters(
        _ text:String
    )->Bool {
        text.unicodeScalars.contains {
            CharacterSet.letters.contains($0)
                || CharacterSet.decimalDigits.contains($0)
        }
    }

    private func containsOnlyDigitsAndPunctuation(
        _ text:String
    )->Bool {
        let meaningfulScalars = text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        }

        guard !meaningfulScalars.isEmpty else { return true }

        return meaningfulScalars.allSatisfy {
            CharacterSet.decimalDigits.contains($0)
        }
    }
}
