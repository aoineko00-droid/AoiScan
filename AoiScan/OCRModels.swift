//
//  OCRModels.swift
//  AoiScan
//

import Foundation


/// A single text region returned by the OCR engine.
///
/// `boundingBox` uses Vision's normalized coordinate space: values are in
/// `0...1` and the origin is at the lower-left of the final scanned page.
struct OCRBlock:Identifiable,Codable {
    let id:UUID
    let text:String
    let boundingBox:CGRect
    let confidence:Float

    init(
        id:UUID = UUID(),
        text:String,
        boundingBox:CGRect,
        confidence:Float
    ) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}


/// Structured OCR output for one final, perspective-corrected scan page.
struct OCRPageResult:Codable {
    static let currentSchemaVersion = 1

    let schemaVersion:Int
    let pageNumber:Int
    let imageWidth:Int
    let imageHeight:Int
    let blocks:[OCRBlock]

    init(
        schemaVersion:Int = Self.currentSchemaVersion,
        pageNumber:Int,
        imageWidth:Int,
        imageHeight:Int,
        blocks:[OCRBlock]
    ) {
        self.schemaVersion = schemaVersion
        self.pageNumber = pageNumber
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.blocks = blocks
    }

    var plainText:String {
        blocks
            .map(\.text)
            .joined(separator:"\n")
            .trimmingCharacters(in:.whitespacesAndNewlines)
    }

    var averageConfidence:Float? {
        guard !blocks.isEmpty else { return nil }

        let total = blocks.reduce(Float.zero) {
            $0 + $1.confidence
        }

        return total / Float(blocks.count)
    }

    /// The document structure layer is derived from OCR geometry only.
    /// It does not run OCR again and does not change `plainText`.
    var documentBlocks:[DocumentBlock] {
        DocumentAnalyzer().analyze(
            ocrBlocks:blocks
        )
    }

    func withPageNumber(
        _ pageNumber:Int
    )->OCRPageResult {
        OCRPageResult(
            schemaVersion:schemaVersion,
            pageNumber:pageNumber,
            imageWidth:imageWidth,
            imageHeight:imageHeight,
            blocks:blocks
        )
    }
}


enum OCRStorage {
    static func fileURL(
        in folderURL:URL,
        pageNumber:Int
    )->URL {
        folderURL.appendingPathComponent(
            "ocr_\(pageNumber).json"
        )
    }

    static func write(
        _ result:OCRPageResult,
        to url:URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(result)
        try data.write(to:url, options:.atomic)

        if let documentURL = DocumentStorage.fileURL(
            pairedWithOCRURL:url
        ) {
            try DocumentStorage.write(
                DocumentPageResult(
                    pageNumber:result.pageNumber,
                    blocks:result.documentBlocks
                ),
                to:documentURL
            )
        }

        DocumentAssembler().rebuildIfPossible(
            in:url.deletingLastPathComponent()
        )
    }

    static func load(
        from url:URL
    )->OCRPageResult? {
        guard let data = try? Data(contentsOf:url) else {
            return nil
        }

        guard let result = try? JSONDecoder().decode(
            OCRPageResult.self,
            from:data
        ) else {
            return nil
        }

        // Backfill the new document layer for OCR files created by older
        // versions without repeating OCR or touching the user's text file.
        if let documentURL = DocumentStorage.fileURL(
            pairedWithOCRURL:url
        ),
           DocumentStorage.load(from:documentURL) == nil {
            try? DocumentStorage.write(
                DocumentPageResult(
                    pageNumber:result.pageNumber,
                    blocks:result.documentBlocks
                ),
                to:documentURL
            )
        }

        let finalDocumentURL = ScanDocumentStorage.fileURL(
            in:url.deletingLastPathComponent()
        )
        if !FileManager.default.fileExists(
            atPath:finalDocumentURL.path
        ) {
            DocumentAssembler().rebuildIfPossible(
                in:url.deletingLastPathComponent()
            )
        }

        return result
    }

    static func removeIfPresent(
        at url:URL
    ) {
        guard FileManager.default.fileExists(atPath:url.path) else {
            return
        }

        try? FileManager.default.removeItem(at:url)

        if let documentURL = DocumentStorage.fileURL(
            pairedWithOCRURL:url
        ) {
            DocumentStorage.removeIfPresent(at:documentURL)
        }

        DocumentAssembler().rebuildIfPossible(
            in:url.deletingLastPathComponent()
        )
    }
}
