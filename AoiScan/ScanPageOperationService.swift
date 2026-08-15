//
//  ScanPageOperationService.swift
//  AoiScan
//

import Foundation


struct ScanPageOperationResult:Sendable {
    let pageCount:Int
    let searchableText:String?
}


enum ScanPageOperationError:LocalizedError {
    case unreadableDocument
    case invalidPage
    case invalidOrder
    case emptyDocument

    var errorDescription:String? {
        switch self {
        case .unreadableDocument:
            return L10n.text("无法读取当前扫描文档。")
        case .invalidPage:
            return L10n.text("当前页面已不存在。")
        case .invalidOrder:
            return L10n.text("页面顺序已变化，请重新打开全部页面。")
        case .emptyDocument:
            return L10n.text("扫描文档至少需要保留一页。")
        }
    }
}


struct ScanPageOperationService {
    nonisolated static func pageNumbers(
        in folderURL:URL
    ) throws->[Int] {
        let files = try FileManager.default.contentsOfDirectory(
            at:folderURL,
            includingPropertiesForKeys:nil,
            options:[.skipsHiddenFiles]
        )
        var pages:Set<Int> = []

        for file in files where file.pathExtension.lowercased() == "jpg" {
            let name = file.deletingPathExtension().lastPathComponent

            if let page = positivePageNumber(name) {
                pages.insert(page)
                continue
            }

            for prefix in ["original_", "adjusted_", "preview_"]
            where name.hasPrefix(prefix) {
                if let page = positivePageNumber(
                    String(name.dropFirst(prefix.count))
                ) {
                    pages.insert(page)
                }
            }
        }

        return pages.sorted()
    }

    nonisolated static func appendPages(
        from appendedFolderURL:URL,
        to documentFolderURL:URL
    ) throws->ScanPageOperationResult {
        let existingPages = try pageNumbers(in:documentFolderURL)
        let appendedPages = try pageNumbers(in:appendedFolderURL)

        guard !existingPages.isEmpty else {
            throw ScanPageOperationError.unreadableDocument
        }
        guard !appendedPages.isEmpty else {
            throw ScanPageOperationError.emptyDocument
        }

        let sources = existingPages.map {
            PageSource(
                folderURL:documentFolderURL,
                pageNumber:$0
            )
        } + appendedPages.map {
            PageSource(
                folderURL:appendedFolderURL,
                pageNumber:$0
            )
        }

        return try replaceDocumentPages(
            in:documentFolderURL,
            with:sources
        )
    }

    nonisolated static func deletePage(
        _ pageNumber:Int,
        in documentFolderURL:URL
    ) throws->ScanPageOperationResult {
        let pages = try pageNumbers(in:documentFolderURL)
        guard pages.contains(pageNumber) else {
            throw ScanPageOperationError.invalidPage
        }

        let remainingPages = pages.filter { $0 != pageNumber }
        guard !remainingPages.isEmpty else {
            throw ScanPageOperationError.emptyDocument
        }

        return try replaceDocumentPages(
            in:documentFolderURL,
            with:remainingPages.map {
                PageSource(
                    folderURL:documentFolderURL,
                    pageNumber:$0
                )
            }
        )
    }

    nonisolated static func reorderPages(
        _ orderedPageNumbers:[Int],
        in documentFolderURL:URL
    ) throws->ScanPageOperationResult {
        let pages = try pageNumbers(in:documentFolderURL)
        guard orderedPageNumbers.count == pages.count,
              Set(orderedPageNumbers) == Set(pages) else {
            throw ScanPageOperationError.invalidOrder
        }

        return try replaceDocumentPages(
            in:documentFolderURL,
            with:orderedPageNumbers.map {
                PageSource(
                    folderURL:documentFolderURL,
                    pageNumber:$0
                )
            }
        )
    }
}


private extension ScanPageOperationService {
    struct PageSource:Sendable {
        let folderURL:URL
        let pageNumber:Int
    }

    nonisolated static func replaceDocumentPages(
        in documentFolderURL:URL,
        with sources:[PageSource]
    ) throws->ScanPageOperationResult {
        guard !sources.isEmpty,
              directoryExists(at:documentFolderURL) else {
            throw ScanPageOperationError.unreadableDocument
        }

        let fileManager = FileManager.default
        let parentURL = documentFolderURL.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(
            ".aoiscan-pages-\(UUID().uuidString)",
            isDirectory:true
        )
        let backupURL = parentURL.appendingPathComponent(
            ".aoiscan-pages-backup-\(UUID().uuidString)",
            isDirectory:true
        )
        var movedOriginalToBackup = false

        do {
            try fileManager.copyItem(
                at:documentFolderURL,
                to:stagingURL
            )
            try removeManagedPageFiles(in:stagingURL)

            var metadata:[ [String:Any] ] = []
            var metadataCache:[URL:[Int:[String:Any]]] = [:]

            for (offset, source) in sources.enumerated() {
                let newPageNumber = offset + 1
                try copyPageFiles(
                    from:source.folderURL,
                    oldPageNumber:source.pageNumber,
                    to:stagingURL,
                    newPageNumber:newPageNumber
                )

                let records:[Int:[String:Any]]
                if let cached = metadataCache[source.folderURL] {
                    records = cached
                }
                else {
                    let loaded = try metadataByPage(
                        in:source.folderURL
                    )
                    metadataCache[source.folderURL] = loaded
                    records = loaded
                }

                var record = records[source.pageNumber]
                    ?? ["pageNumber":source.pageNumber]
                record["pageNumber"] = newPageNumber
                metadata.append(record)
            }

            try writeMetadata(metadata, to:stagingURL)

            try fileManager.moveItem(
                at:documentFolderURL,
                to:backupURL
            )
            movedOriginalToBackup = true

            do {
                try fileManager.moveItem(
                    at:stagingURL,
                    to:documentFolderURL
                )
            }
            catch {
                try? fileManager.moveItem(
                    at:backupURL,
                    to:documentFolderURL
                )
                movedOriginalToBackup = false
                throw error
            }

            try? fileManager.removeItem(at:backupURL)
            movedOriginalToBackup = false

            return ScanPageOperationResult(
                pageCount:sources.count,
                searchableText:recognizedText(
                    in:documentFolderURL,
                    pageCount:sources.count
                )
            )
        }
        catch {
            if fileManager.fileExists(atPath:stagingURL.path) {
                try? fileManager.removeItem(at:stagingURL)
            }
            if movedOriginalToBackup,
               !fileManager.fileExists(atPath:documentFolderURL.path),
               fileManager.fileExists(atPath:backupURL.path) {
                try? fileManager.moveItem(
                    at:backupURL,
                    to:documentFolderURL
                )
            }
            throw error
        }
    }

    nonisolated static func removeManagedPageFiles(
        in folderURL:URL
    ) throws {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at:folderURL,
            includingPropertiesForKeys:nil,
            options:[.skipsHiddenFiles]
        )

        for file in files {
            let name = file.lastPathComponent
            let stem = file.deletingPathExtension().lastPathComponent
            let ext = file.pathExtension.lowercased()
            let isPageImage = ext == "jpg" && (
                positivePageNumber(stem) != nil
                    || ["original_", "adjusted_", "preview_"]
                        .contains(where:{ prefix in
                            stem.hasPrefix(prefix)
                                && positivePageNumber(
                                    String(stem.dropFirst(prefix.count))
                                ) != nil
                        })
            )
            let isPageText = ext == "txt"
                && numberedSuffix(in:stem, prefix:"recognized_") != nil
            let isPageJSON = ext == "json" && (
                numberedSuffix(in:stem, prefix:"ocr_") != nil
                    || numberedSuffix(
                        in:stem,
                        prefix:"document_"
                    ) != nil
            )
            let isGeneratedExport = ["pdf", "docx"].contains(ext)
                && name != "source.pdf"

            if isPageImage
                || isPageText
                || isPageJSON
                || name == "scan_metadata.json"
                || name == "document.json"
                || isGeneratedExport {
                try fileManager.removeItem(at:file)
            }
        }
    }

    nonisolated static func copyPageFiles(
        from sourceFolder:URL,
        oldPageNumber:Int,
        to destinationFolder:URL,
        newPageNumber:Int
    ) throws {
        let fileManager = FileManager.default
        let mappings:[(String,String)] = [
            (
                "original_\(oldPageNumber).jpg",
                "original_\(newPageNumber).jpg"
            ),
            (
                "adjusted_\(oldPageNumber).jpg",
                "adjusted_\(newPageNumber).jpg"
            ),
            ("\(oldPageNumber).jpg", "\(newPageNumber).jpg"),
            (
                "preview_\(oldPageNumber).jpg",
                "preview_\(newPageNumber).jpg"
            ),
            (
                "recognized_\(oldPageNumber).txt",
                "recognized_\(newPageNumber).txt"
            )
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

        let displayURL = destinationFolder.appendingPathComponent(
            "\(newPageNumber).jpg"
        )
        if !fileManager.fileExists(atPath:displayURL.path) {
            let fallbackNames = [
                "preview_\(newPageNumber).jpg",
                "adjusted_\(newPageNumber).jpg",
                "original_\(newPageNumber).jpg"
            ]
            guard let fallbackURL = fallbackNames
                .map(destinationFolder.appendingPathComponent)
                .first(where:{
                    fileManager.fileExists(atPath:$0.path)
                }) else {
                throw ScanPageOperationError.invalidPage
            }
            try fileManager.copyItem(
                at:fallbackURL,
                to:displayURL
            )
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

    nonisolated static func transformPageJSONIfPresent(
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

    nonisolated static func metadataByPage(
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
            guard let pageNumber = record["pageNumber"] as? Int,
                  pageNumber > 0 else {
                continue
            }
            result[pageNumber] = record
        }
        return result
    }

    nonisolated static func writeMetadata(
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

    nonisolated static func recognizedText(
        in folderURL:URL,
        pageCount:Int
    )->String? {
        let text = (1...pageCount).compactMap { pageNumber in
            let url = folderURL.appendingPathComponent(
                "recognized_\(pageNumber).txt"
            )
            return try? String(contentsOf:url, encoding:.utf8)
        }
        .map {
            $0.trimmingCharacters(in:.whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        .joined(separator:"\n\n")

        return text.isEmpty ? nil : text
    }

    nonisolated static func directoryExists(at url:URL)->Bool {
        var isDirectory:ObjCBool = false
        return FileManager.default.fileExists(
            atPath:url.path,
            isDirectory:&isDirectory
        ) && isDirectory.boolValue
    }

    nonisolated static func positivePageNumber(_ value:String)->Int? {
        guard let page = Int(value), page > 0 else { return nil }
        return page
    }

    nonisolated static func numberedSuffix(
        in value:String,
        prefix:String
    )->Int? {
        guard value.hasPrefix(prefix) else { return nil }
        return positivePageNumber(
            String(value.dropFirst(prefix.count))
        )
    }
}
