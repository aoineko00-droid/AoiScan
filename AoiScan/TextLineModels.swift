//
//  TextLineModels.swift
//  AoiScan
//

import Foundation
import CoreGraphics


/// One visual text line assembled from one or more OCR observations.
///
/// All rectangles use Vision's normalized lower-left coordinate space.
struct TextLine:Identifiable {
    let id:UUID
    let ocrBlocks:[OCRBlock]
    let boundingBox:CGRect
    let baselineY:CGFloat

    init(
        id:UUID = UUID(),
        ocrBlocks:[OCRBlock]
    ) {
        let ordered = ocrBlocks.sorted {
            $0.boundingBox.minX < $1.boundingBox.minX
        }
        let union = ordered
            .map(\.boundingBox)
            .reduce(CGRect.null) { partial, next in
                partial.union(next)
            }
            .intersection(
                CGRect(x:0, y:0, width:1, height:1)
            )

        self.id = id
        self.ocrBlocks = ordered
        self.boundingBox = union.isNull ? .zero : union
        self.baselineY = ordered.isEmpty
            ? 0
            : ordered.reduce(CGFloat.zero) {
                $0 + $1.boundingBox.minY
            } / CGFloat(ordered.count)
    }

    var text:String {
        ocrBlocks.reduce(into:"") { result, block in
            let next = block.text.trimmingCharacters(
                in:.whitespacesAndNewlines
            )
            guard !next.isEmpty else { return }

            if let previous = result.unicodeScalars.last,
               let first = next.unicodeScalars.first,
               CharacterSet.alphanumerics.contains(previous),
               CharacterSet.alphanumerics.contains(first),
               previous.isASCII,
               first.isASCII {
                result.append(" ")
            }

            result.append(next)
        }
    }

    var averageConfidence:Float {
        guard !ocrBlocks.isEmpty else { return 0 }
        return ocrBlocks.reduce(Float.zero) {
            $0 + $1.confidence
        } / Float(ocrBlocks.count)
    }
}


/// A horizontal reading region inferred from text-line distribution.
struct ColumnRegion:Identifiable {
    let id:UUID
    let index:Int
    let textLines:[TextLine]
    let boundingBox:CGRect

    init(
        id:UUID = UUID(),
        index:Int,
        textLines:[TextLine]
    ) {
        let ordered = textLines.sorted(by:TextLine.readingOrder)
        let union = ordered
            .map(\.boundingBox)
            .reduce(CGRect.null) { partial, next in
                partial.union(next)
            }
            .intersection(
                CGRect(x:0, y:0, width:1, height:1)
            )

        self.id = id
        self.index = index
        self.textLines = ordered
        self.boundingBox = union.isNull ? .zero : union
    }
}


struct ColumnLayout {
    let columns:[ColumnRegion]
    let spanningLines:[TextLine]

    var isMultiColumn:Bool {
        columns.count > 1
    }
}


/// A conservative geometry-only table candidate.
struct TableRegion:Identifiable {
    let id:UUID
    let textLines:[TextLine]
    let ocrBlocks:[OCRBlock]
    let boundingBox:CGRect

    init(
        id:UUID = UUID(),
        textLines:[TextLine],
        ocrBlocks:[OCRBlock]
    ) {
        let uniqueBlocks = Dictionary(
            ocrBlocks.map { ($0.id, $0) },
            uniquingKeysWith:{ first, _ in first }
        )
        .values
        .sorted(by:OCRBlock.readingOrder)
        let union = uniqueBlocks
            .map(\.boundingBox)
            .reduce(CGRect.null) { partial, next in
                partial.union(next)
            }
            .intersection(
                CGRect(x:0, y:0, width:1, height:1)
            )

        self.id = id
        self.textLines = textLines.sorted(by:TextLine.readingOrder)
        self.ocrBlocks = uniqueBlocks
        self.boundingBox = union.isNull ? .zero : union
    }
}


extension TextLine {
    nonisolated static func readingOrder(
        _ first:TextLine,
        _ second:TextLine
    )->Bool {
        let verticalDifference = abs(
            first.boundingBox.midY - second.boundingBox.midY
        )

        if verticalDifference > 0.012 {
            return first.boundingBox.midY
                > second.boundingBox.midY
        }

        return first.boundingBox.minX
            < second.boundingBox.minX
    }
}


extension OCRBlock {
    nonisolated static func readingOrder(
        _ first:OCRBlock,
        _ second:OCRBlock
    )->Bool {
        let verticalDifference = abs(
            first.boundingBox.midY - second.boundingBox.midY
        )

        if verticalDifference > 0.012 {
            return first.boundingBox.midY
                > second.boundingBox.midY
        }

        return first.boundingBox.minX
            < second.boundingBox.minX
    }
}
