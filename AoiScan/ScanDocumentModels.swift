//
//  ScanDocumentModels.swift
//  AoiScan
//

import Foundation


enum DocumentCoordinateSpace:String,Codable {
    case visionNormalizedBottomLeft
}


/// One page in AoiScan's stable, exporter-independent document model.
struct DocumentPage:Identifiable,Codable {
    let id:UUID
    let pageNumber:Int
    let imageWidth:Int
    let imageHeight:Int
    let coordinateSpace:DocumentCoordinateSpace
    let blocks:[DocumentBlock]

    init(
        id:UUID = UUID(),
        pageNumber:Int,
        imageWidth:Int,
        imageHeight:Int,
        coordinateSpace:DocumentCoordinateSpace =
            .visionNormalizedBottomLeft,
        blocks:[DocumentBlock]
    ) {
        self.id = id
        self.pageNumber = pageNumber
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.coordinateSpace = coordinateSpace
        self.blocks = blocks.sorted {
            $0.readingOrder < $1.readingOrder
        }
    }
}


/// The stable bridge between layout analysis and all future exporters.
struct ScanDocument:Identifiable,Codable {
    static let currentSchemaVersion = 1

    let schemaVersion:Int
    let id:UUID
    let title:String
    let createdAt:Date
    let pages:[DocumentPage]

    init(
        schemaVersion:Int = Self.currentSchemaVersion,
        id:UUID = UUID(),
        title:String,
        createdAt:Date = Date(),
        pages:[DocumentPage]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title.trimmingCharacters(
            in:.whitespacesAndNewlines
        )
        self.createdAt = createdAt
        self.pages = pages.sorted {
            $0.pageNumber < $1.pageNumber
        }
    }
}


enum ScanDocumentStorage {
    static func fileURL(in folderURL:URL)->URL {
        folderURL.appendingPathComponent("document.json")
    }

    static func write(
        _ document:ScanDocument,
        to url:URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(
            to:url,
            options:.atomic
        )
    }

    static func load(from url:URL)->ScanDocument? {
        guard let data = try? Data(contentsOf:url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            ScanDocument.self,
            from:data
        )
    }

    static func removeIfPresent(in folderURL:URL) {
        let url = fileURL(in:folderURL)
        guard FileManager.default.fileExists(atPath:url.path) else {
            return
        }
        try? FileManager.default.removeItem(at:url)
    }
}
