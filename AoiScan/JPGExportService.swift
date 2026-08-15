//
//  JPGExportService.swift
//  AoiScan
//

import Foundation


enum JPGExportError:LocalizedError {
    case noPages(String)

    var errorDescription:String? {
        switch self {
        case .noPages(let title):
            return L10n.format(
                "当前文件没有可分享的 JPG 扫描页：%@",
                title as NSString
            )
        }
    }
}


struct JPGExportService {
    nonisolated static func exportDocuments(
        _ references:[ScanDocumentFileReference]
    ) throws->[URL] {
        let fileManager = FileManager.default
        let exportRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "AoiScan-JPG-Exports",
                isDirectory:true
            )
        let exportFolder = exportRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory:true
        )
        var usedNames:Set<String> = []

        do {
            try fileManager.createDirectory(
                at:exportFolder,
                withIntermediateDirectories:true
            )

            var exportedURLs:[URL] = []
            for reference in references {
                let imageURLs = try PDFManager.orderedPageImageURLs(
                    in:reference.folderURL
                )
                guard !imageURLs.isEmpty else {
                    throw JPGExportError.noPages(reference.title)
                }

                for (index,imageURL) in imageURLs.enumerated() {
                    let stem = imageURLs.count == 1
                        ? safeFileName(reference.title)
                        : "\(safeFileName(reference.title))_\(index + 1)"
                    let destinationURL = uniqueDestinationURL(
                        stem:stem,
                        exportFolder:exportFolder,
                        usedNames:&usedNames
                    )
                    try fileManager.copyItem(
                        at:imageURL,
                        to:destinationURL
                    )
                    exportedURLs.append(destinationURL)
                }
            }

            return exportedURLs
        }
        catch {
            if fileManager.fileExists(atPath:exportFolder.path) {
                try? fileManager.removeItem(at:exportFolder)
            }
            throw error
        }
    }

    nonisolated private static func uniqueDestinationURL(
        stem:String,
        exportFolder:URL,
        usedNames:inout Set<String>
    )->URL {
        var candidate = stem
        var suffix = 2

        while usedNames.contains(candidate.lowercased()) {
            candidate = "\(stem)-\(suffix)"
            suffix += 1
        }
        usedNames.insert(candidate.lowercased())

        return exportFolder
            .appendingPathComponent(candidate)
            .appendingPathExtension("jpg")
    }

    nonisolated private static func safeFileName(
        _ title:String
    )->String {
        let invalid = CharacterSet(
            charactersIn:"/\\:?%*|\"<>"
        ).union(.controlCharacters)
        let candidate = title
            .components(separatedBy:invalid)
            .filter { !$0.isEmpty }
            .joined(separator:"-")
            .trimmingCharacters(in:.whitespacesAndNewlines)
        let limited = String(candidate.prefix(80))
            .trimmingCharacters(in:.whitespacesAndNewlines)

        return limited.isEmpty ? "AoiScan" : limited
    }
}
