//
//  ScanFileOperationService.swift
//  AoiScan
//

import Foundation


struct ScanDocumentFileReference:Sendable {
    let id:UUID
    let title:String
    let createdAt:Date
    let folderURL:URL
    let searchableText:String?
}


struct ScanMergeResult:Sendable {
    let documentID:UUID
    let folderIdentifier:String
    let folderURL:URL
    let title:String
    let createdAt:Date
    let pageCount:Int
    let searchableText:String?
}


enum ScanFileOperationError:LocalizedError {
    case unreadableDocument(String)
    case emptyDocument(String)
    case noMergePages
    case invalidMetadata

    var errorDescription:String? {
        switch self {
        case .unreadableDocument(let title):
            return L10n.format(
                "无法读取扫描文件：%@",
                title as NSString
            )
        case .emptyDocument(let title):
            return L10n.format(
                "扫描文件没有可合并的页面：%@",
                title as NSString
            )
        case .noMergePages:
            return L10n.text("没有可合并的扫描页。")
        case .invalidMetadata:
            return L10n.text("扫描页元数据无法读取。")
        }
    }
}


struct StagedScanDeletion {
    struct Move {
        let originalURL:URL
        let stagedURL:URL
    }

    let moves:[Move]

    func rollback() {
        let fileManager = FileManager.default

        for move in moves.reversed() {
            guard fileManager.fileExists(atPath:move.stagedURL.path),
                  !fileManager.fileExists(atPath:move.originalURL.path) else {
                continue
            }

            do {
                try fileManager.moveItem(
                    at:move.stagedURL,
                    to:move.originalURL
                )
            }
            catch {
                print(
                    "恢复已暂存扫描文件失败:",
                    error.localizedDescription
                )
            }
        }
    }

    func commit() {
        let fileManager = FileManager.default

        for move in moves {
            guard fileManager.fileExists(atPath:move.stagedURL.path) else {
                continue
            }

            do {
                try fileManager.removeItem(at:move.stagedURL)
            }
            catch {
                print(
                    "清理已删除扫描文件失败:",
                    error.localizedDescription
                )
            }
        }
    }
}


struct ScanFileOperationService {
    static func stageDeletion(
        _ references:[ScanDocumentFileReference]
    ) throws->StagedScanDeletion {
        let fileManager = FileManager.default
        var moves:[StagedScanDeletion.Move] = []

        do {
            for reference in references {
                guard fileManager.fileExists(
                    atPath:reference.folderURL.path
                ) else {
                    continue
                }

                let stagedName = ".aoiscan-delete-\(UUID().uuidString)-\(reference.folderURL.lastPathComponent)"
                let stagedURL = reference.folderURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        stagedName,
                        isDirectory:true
                    )

                try fileManager.moveItem(
                    at:reference.folderURL,
                    to:stagedURL
                )
                moves.append(
                    StagedScanDeletion.Move(
                        originalURL:reference.folderURL,
                        stagedURL:stagedURL
                    )
                )
            }
        }
        catch {
            StagedScanDeletion(moves:moves).rollback()
            throw error
        }

        return StagedScanDeletion(moves:moves)
    }

    nonisolated static func merge(
        _ references:[ScanDocumentFileReference],
        title:String
    ) throws->ScanMergeResult {
        let fileManager = FileManager.default
        let documentID = UUID()
        let folderIdentifier = documentID.uuidString
        let finalURL = ScanManager.documentFolderURL(
            for:folderIdentifier
        )
        let stagingURL = ScanManager.documentsRootURL
            .appendingPathComponent(
                ".aoiscan-merge-\(UUID().uuidString)",
                isDirectory:true
            )
        let createdAt = Date()
        var nextPageNumber = 1
        var mergedMetadata:[[String:Any]] = []
        var recognizedTexts:[String] = []

        do {
            try fileManager.createDirectory(
                at:ScanManager.documentsRootURL,
                withIntermediateDirectories:true
            )
            try fileManager.createDirectory(
                at:stagingURL,
                withIntermediateDirectories:false
            )

            for reference in references {
                guard fileManager.fileExists(
                    atPath:reference.folderURL.path
                ) else {
                    throw ScanFileOperationError.unreadableDocument(
                        reference.title
                    )
                }

                let pages = try pageNumbers(in:reference.folderURL)

                guard !pages.isEmpty else {
                    throw ScanFileOperationError.emptyDocument(
                        reference.title
                    )
                }

                let metadata = try metadataByPage(
                    in:reference.folderURL
                )

                for oldPageNumber in pages {
                    try copyPageFiles(
                        from:reference.folderURL,
                        oldPageNumber:oldPageNumber,
                        to:stagingURL,
                        newPageNumber:nextPageNumber
                    )

                    var pageMetadata = metadata[oldPageNumber]
                        ?? ["pageNumber":oldPageNumber]
                    pageMetadata["pageNumber"] = nextPageNumber
                    mergedMetadata.append(pageMetadata)

                    let textURL = stagingURL.appendingPathComponent(
                        "recognized_\(nextPageNumber).txt"
                    )
                    if let text = try? String(
                        contentsOf:textURL,
                        encoding:.utf8
                    ).trimmingCharacters(in:.whitespacesAndNewlines),
                       !text.isEmpty {
                        recognizedTexts.append(text)
                    }

                    nextPageNumber += 1
                }
            }

            guard nextPageNumber > 1 else {
                throw ScanFileOperationError.noMergePages
            }

            try writeMetadata(
                mergedMetadata,
                to:stagingURL
            )
            try fileManager.moveItem(
                at:stagingURL,
                to:finalURL
            )

            let searchableText = mergedSearchableText(
                recognizedTexts:recognizedTexts,
                references:references
            )

            return ScanMergeResult(
                documentID:documentID,
                folderIdentifier:folderIdentifier,
                folderURL:finalURL,
                title:title,
                createdAt:createdAt,
                pageCount:nextPageNumber - 1,
                searchableText:searchableText
            )
        }
        catch {
            if fileManager.fileExists(atPath:stagingURL.path) {
                try? fileManager.removeItem(at:stagingURL)
            }
            if fileManager.fileExists(atPath:finalURL.path) {
                try? fileManager.removeItem(at:finalURL)
            }
            throw error
        }
    }

    nonisolated private static func pageNumbers(
        in folderURL:URL
    ) throws->[Int] {
        let files = try FileManager.default.contentsOfDirectory(
            at:folderURL,
            includingPropertiesForKeys:nil,
            options:[.skipsHiddenFiles]
        )
        var pageNumbers:Set<Int> = []

        for file in files where file.pathExtension.lowercased() == "jpg" {
            let name = file.deletingPathExtension().lastPathComponent

            if let page = positivePageNumber(name) {
                pageNumbers.insert(page)
                continue
            }

            for prefix in ["original_", "adjusted_", "preview_"]
            where name.hasPrefix(prefix) {
                if let page = positivePageNumber(
                    String(name.dropFirst(prefix.count))
                ) {
                    pageNumbers.insert(page)
                }
            }
        }

        return pageNumbers.sorted()
    }

    nonisolated private static func copyPageFiles(
        from sourceFolder:URL,
        oldPageNumber:Int,
        to destinationFolder:URL,
        newPageNumber:Int
    ) throws {
        let fileManager = FileManager.default
        let mappings:[(String,String)] = [
            ("original_\(oldPageNumber).jpg", "original_\(newPageNumber).jpg"),
            ("adjusted_\(oldPageNumber).jpg", "adjusted_\(newPageNumber).jpg"),
            ("\(oldPageNumber).jpg", "\(newPageNumber).jpg"),
            ("preview_\(oldPageNumber).jpg", "preview_\(newPageNumber).jpg"),
            ("recognized_\(oldPageNumber).txt", "recognized_\(newPageNumber).txt")
        ]

        for mapping in mappings {
            let sourceURL = sourceFolder.appendingPathComponent(mapping.0)
            guard fileManager.fileExists(atPath:sourceURL.path) else {
                continue
            }

            try fileManager.copyItem(
                at:sourceURL,
                to:destinationFolder.appendingPathComponent(mapping.1)
            )
        }

        if !fileManager.fileExists(
            atPath:destinationFolder
                .appendingPathComponent("\(newPageNumber).jpg")
                .path
        ) {
            let fallbackNames = [
                "preview_\(newPageNumber).jpg",
                "adjusted_\(newPageNumber).jpg",
                "original_\(newPageNumber).jpg"
            ]

            if let fallbackURL = fallbackNames
                .map(destinationFolder.appendingPathComponent)
                .first(where:{
                    fileManager.fileExists(atPath:$0.path)
                }) {
                try fileManager.copyItem(
                    at:fallbackURL,
                    to:destinationFolder.appendingPathComponent(
                        "\(newPageNumber).jpg"
                    )
                )
            }
        }

        try transformPageJSONIfPresent(
            sourceFolder:sourceFolder,
            sourceName:"ocr_\(oldPageNumber).json",
            destinationFolder:destinationFolder,
            destinationName:"ocr_\(newPageNumber).json",
            newPageNumber:newPageNumber
        )
        try transformPageJSONIfPresent(
            sourceFolder:sourceFolder,
            sourceName:"document_\(oldPageNumber).json",
            destinationFolder:destinationFolder,
            destinationName:"document_\(newPageNumber).json",
            newPageNumber:newPageNumber
        )
    }

    nonisolated private static func transformPageJSONIfPresent(
        sourceFolder:URL,
        sourceName:String,
        destinationFolder:URL,
        destinationName:String,
        newPageNumber:Int
    ) throws {
        let sourceURL = sourceFolder.appendingPathComponent(sourceName)
        guard FileManager.default.fileExists(atPath:sourceURL.path) else {
            return
        }

        let data = try Data(contentsOf:sourceURL)
        guard var object = try JSONSerialization.jsonObject(
            with:data
        ) as? [String:Any] else {
            throw ScanFileOperationError.invalidMetadata
        }
        object["pageNumber"] = newPageNumber
        let output = try JSONSerialization.data(
            withJSONObject:object,
            options:[.prettyPrinted, .sortedKeys]
        )
        try output.write(
            to:destinationFolder.appendingPathComponent(destinationName),
            options:.atomic
        )
    }

    nonisolated private static func metadataByPage(
        in folderURL:URL
    ) throws->[Int:[String:Any]] {
        let url = folderURL.appendingPathComponent("scan_metadata.json")
        guard FileManager.default.fileExists(atPath:url.path) else {
            return [:]
        }

        let data = try Data(contentsOf:url)
        guard let records = try JSONSerialization.jsonObject(
            with:data
        ) as? [[String:Any]] else {
            throw ScanFileOperationError.invalidMetadata
        }

        var result:[Int:[String:Any]] = [:]

        for record in records {
            guard let page = record["pageNumber"] as? Int,
                  page > 0 else {
                continue
            }
            result[page] = record
        }

        return result
    }

    nonisolated private static func writeMetadata(
        _ records:[[String:Any]],
        to folderURL:URL
    ) throws {
        let data = try JSONSerialization.data(
            withJSONObject:records,
            options:[.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to:folderURL.appendingPathComponent("scan_metadata.json"),
            options:.atomic
        )
    }

    nonisolated private static func mergedSearchableText(
        recognizedTexts:[String],
        references:[ScanDocumentFileReference]
    )->String? {
        let text = recognizedTexts.isEmpty
            ? references.compactMap(\.searchableText)
                .joined(separator:"\n\n")
            : recognizedTexts.joined(separator:"\n\n")
        let trimmed = text.trimmingCharacters(
            in:.whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func positivePageNumber(
        _ value:String
    )->Int? {
        guard let page = Int(value), page > 0 else {
            return nil
        }
        return page
    }
}
