//
//  DocumentModels.swift
//  AoiScan
//

import Foundation
import CoreGraphics


/// The first-stage semantic role assigned to a document region.
enum DocumentBlockType:String,Codable,CaseIterable {
    case title
    case paragraph
    case table
    case image
    case unknown
}


/// A stable semantic document region.
///
/// `boundingBox` remains in Vision's normalized lower-left coordinate space.
/// `ocrBlocks` is runtime-only source data used by the debug overlay. It is
/// deliberately omitted from the new JSON schema so Word export depends on
/// the document model rather than the OCR engine's private output shape.
struct DocumentBlock:Identifiable,Codable {
    let id:UUID
    let type:DocumentBlockType
    let text:String
    let boundingBox:CGRect
    let readingOrder:Int
    let columnIndex:Int?
    let confidence:Float?
    let children:[DocumentBlock]
    let ocrBlocks:[OCRBlock]

    init(
        id:UUID = UUID(),
        type:DocumentBlockType,
        text:String,
        boundingBox:CGRect,
        readingOrder:Int = 0,
        columnIndex:Int? = nil,
        confidence:Float? = nil,
        children:[DocumentBlock] = [],
        ocrBlocks:[OCRBlock] = []
    ) {
        self.id = id
        self.type = type
        self.text = text.trimmingCharacters(
            in:.whitespacesAndNewlines
        )
        self.boundingBox = boundingBox
        self.readingOrder = readingOrder
        self.columnIndex = columnIndex
        self.confidence = confidence
        self.children = children
        self.ocrBlocks = ocrBlocks
    }

    /// Compatibility initializer used by the rule-based analyzer.
    init(
        id:UUID = UUID(),
        type:DocumentBlockType,
        ocrBlocks:[OCRBlock],
        boundingBox:CGRect,
        readingOrder:Int = 0,
        columnIndex:Int? = nil,
        children:[DocumentBlock] = []
    ) {
        let ordered = ocrBlocks.sorted(by:OCRBlock.readingOrder)
        let text = ordered
            .map(\.text)
            .joined(separator:"\n")
            .trimmingCharacters(in:.whitespacesAndNewlines)
        let confidence = ordered.isEmpty
            ? nil
            : ordered.reduce(Float.zero) {
                $0 + $1.confidence
              } / Float(ordered.count)

        self.init(
            id:id,
            type:type,
            text:text,
            boundingBox:boundingBox,
            readingOrder:readingOrder,
            columnIndex:columnIndex,
            confidence:confidence,
            children:children,
            ocrBlocks:ordered
        )
    }

    func withLayout(
        readingOrder:Int,
        columnIndex:Int?
    )->DocumentBlock {
        DocumentBlock(
            id:id,
            type:type,
            text:text,
            boundingBox:boundingBox,
            readingOrder:readingOrder,
            columnIndex:columnIndex,
            confidence:confidence,
            children:children,
            ocrBlocks:ocrBlocks
        )
    }

    private enum CodingKeys:String,CodingKey {
        case id
        case type
        case text
        case boundingBox
        case readingOrder
        case columnIndex
        case confidence
        case children
        // Schema 1 compatibility only.
        case ocrBlocks
    }

    init(from decoder:Decoder) throws {
        let container = try decoder.container(
            keyedBy:CodingKeys.self
        )
        let sourceBlocks = try container.decodeIfPresent(
            [OCRBlock].self,
            forKey:.ocrBlocks
        ) ?? []
        let decodedText = try container.decodeIfPresent(
            String.self,
            forKey:.text
        ) ?? sourceBlocks
            .sorted(by:OCRBlock.readingOrder)
            .map(\.text)
            .joined(separator:"\n")
        let decodedConfidence = try container.decodeIfPresent(
            Float.self,
            forKey:.confidence
        ) ?? (
            sourceBlocks.isEmpty
                ? nil
                : sourceBlocks.reduce(Float.zero) {
                    $0 + $1.confidence
                  } / Float(sourceBlocks.count)
        )

        id = try container.decodeIfPresent(
            UUID.self,
            forKey:.id
        ) ?? UUID()
        type = try container.decode(
            DocumentBlockType.self,
            forKey:.type
        )
        text = decodedText.trimmingCharacters(
            in:.whitespacesAndNewlines
        )
        boundingBox = try container.decode(
            CGRect.self,
            forKey:.boundingBox
        )
        readingOrder = try container.decodeIfPresent(
            Int.self,
            forKey:.readingOrder
        ) ?? 0
        columnIndex = try container.decodeIfPresent(
            Int.self,
            forKey:.columnIndex
        )
        confidence = decodedConfidence
        children = try container.decodeIfPresent(
            [DocumentBlock].self,
            forKey:.children
        ) ?? []
        ocrBlocks = sourceBlocks
    }

    func encode(to encoder:Encoder) throws {
        var container = encoder.container(
            keyedBy:CodingKeys.self
        )
        try container.encode(id, forKey:.id)
        try container.encode(type, forKey:.type)
        try container.encode(text, forKey:.text)
        try container.encode(boundingBox, forKey:.boundingBox)
        try container.encode(readingOrder, forKey:.readingOrder)
        try container.encodeIfPresent(
            columnIndex,
            forKey:.columnIndex
        )
        try container.encodeIfPresent(
            confidence,
            forKey:.confidence
        )
        if !children.isEmpty {
            try container.encode(children, forKey:.children)
        }
    }
}


/// Rule-based layout analysis persisted for one scanned page.
struct DocumentPageResult:Codable {
    static let currentSchemaVersion = 2

    let schemaVersion:Int
    let pageNumber:Int
    let blocks:[DocumentBlock]

    init(
        schemaVersion:Int = Self.currentSchemaVersion,
        pageNumber:Int,
        blocks:[DocumentBlock]
    ) {
        self.schemaVersion = schemaVersion
        self.pageNumber = pageNumber
        self.blocks = blocks
    }
}


enum DocumentStorage {
    static func fileURL(
        in folderURL:URL,
        pageNumber:Int
    )->URL {
        folderURL.appendingPathComponent(
            "document_\(pageNumber).json"
        )
    }

    static func fileURL(
        pairedWithOCRURL ocrURL:URL
    )->URL? {
        let fileName = ocrURL
            .deletingPathExtension()
            .lastPathComponent

        guard fileName.hasPrefix("ocr_"),
              let pageNumber = Int(
                fileName.dropFirst("ocr_".count)
              ) else {
            return nil
        }

        return fileURL(
            in:ocrURL.deletingLastPathComponent(),
            pageNumber:pageNumber
        )
    }

    static func write(
        _ result:DocumentPageResult,
        to url:URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(result)
        try data.write(to:url, options:.atomic)
    }

    static func load(
        from url:URL
    )->DocumentPageResult? {
        guard let data = try? Data(contentsOf:url) else {
            return nil
        }

        return try? JSONDecoder().decode(
            DocumentPageResult.self,
            from:data
        )
    }

    static func removeIfPresent(
        at url:URL
    ) {
        guard FileManager.default.fileExists(atPath:url.path) else {
            return
        }

        try? FileManager.default.removeItem(at:url)
    }
}
