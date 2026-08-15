//
//  PDFImportService.swift
//  AoiScan
//

import Foundation
import PDFKit
import UIKit


struct PDFImportProgress:Sendable {
    let documentIndex:Int
    let documentCount:Int
    let pageIndex:Int
    let pageCount:Int
}


struct ImportedPDFResult:Sendable {
    let documentID:UUID
    let folderIdentifier:String
    let folderURL:URL
    let title:String
    let createdAt:Date
    let pageCount:Int
}


enum PDFImportError:LocalizedError {
    case noSelection
    case unreadable(String)
    case encrypted(String)
    case noPages(String)
    case invalidPage(String,Int)
    case imageEncodingFailed(String,Int)

    var errorDescription:String? {
        switch self {
        case .noSelection:
            return L10n.text("没有选择 PDF 文件。")
        case .unreadable(let name):
            return L10n.format("无法读取 PDF：%@", name as NSString)
        case .encrypted(let name):
            return L10n.format(
                "PDF 已加密，暂时无法导入：%@",
                name as NSString
            )
        case .noPages(let name):
            return L10n.format(
                "PDF 中没有可导入的页面：%@",
                name as NSString
            )
        case .invalidPage(let name,let page):
            return L10n.format(
                "无法读取 %@ 的第 %@ 页。",
                name as NSString,
                NSNumber(value:page)
            )
        case .imageEncodingFailed(let name,let page):
            return L10n.format(
                "无法保存 %@ 的第 %@ 页。",
                name as NSString,
                NSNumber(value:page)
            )
        }
    }
}


struct PDFImportService {
    nonisolated static func removeImportedFiles(
        _ results:[ImportedPDFResult]
    ) {
        let fileManager = FileManager.default
        for result in results
        where fileManager.fileExists(atPath:result.folderURL.path) {
            try? fileManager.removeItem(at:result.folderURL)
        }
    }

    nonisolated static func importPDFs(
        from urls:[URL],
        progress:@escaping @Sendable (PDFImportProgress)->Void
    ) throws->[ImportedPDFResult] {
        guard !urls.isEmpty else {
            throw PDFImportError.noSelection
        }

        let fileManager = FileManager.default
        var completedResults:[ImportedPDFResult] = []
        var activeStagingURL:URL?

        do {
            try fileManager.createDirectory(
                at:ScanManager.documentsRootURL,
                withIntermediateDirectories:true
            )

            for (documentIndex,sourceURL) in urls.enumerated() {
                let accessing = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let displayName = sourceURL
                    .deletingPathExtension()
                    .lastPathComponent
                guard let pdf = PDFDocument(url:sourceURL) else {
                    throw PDFImportError.unreadable(
                        sourceURL.lastPathComponent
                    )
                }
                guard !pdf.isLocked else {
                    throw PDFImportError.encrypted(
                        sourceURL.lastPathComponent
                    )
                }
                guard pdf.pageCount > 0 else {
                    throw PDFImportError.noPages(
                        sourceURL.lastPathComponent
                    )
                }

                let documentID = UUID()
                let folderIdentifier = documentID.uuidString
                let finalURL = ScanManager.documentFolderURL(
                    for:folderIdentifier
                )
                let stagingURL = ScanManager.documentsRootURL
                    .appendingPathComponent(
                        ".aoiscan-import-\(UUID().uuidString)",
                        isDirectory:true
                    )
                activeStagingURL = stagingURL

                try fileManager.createDirectory(
                    at:stagingURL,
                    withIntermediateDirectories:false
                )
                try fileManager.copyItem(
                    at:sourceURL,
                    to:stagingURL.appendingPathComponent("source.pdf")
                )

                var metadata:[ImportedPageMetadata] = []

                for pageIndex in 0..<pdf.pageCount {
                    progress(
                        PDFImportProgress(
                            documentIndex:documentIndex + 1,
                            documentCount:urls.count,
                            pageIndex:pageIndex + 1,
                            pageCount:pdf.pageCount
                        )
                    )

                    guard let page = pdf.page(at:pageIndex) else {
                        throw PDFImportError.invalidPage(
                            displayName,
                            pageIndex + 1
                        )
                    }
                    let image = renderedImage(for:page)
                    guard let data = image.jpegData(
                        compressionQuality:0.95
                    ) else {
                        throw PDFImportError.imageEncodingFailed(
                            displayName,
                            pageIndex + 1
                        )
                    }

                    let pageNumber = pageIndex + 1
                    for name in [
                        "original_\(pageNumber).jpg",
                        "adjusted_\(pageNumber).jpg",
                        "\(pageNumber).jpg"
                    ] {
                        try data.write(
                            to:stagingURL.appendingPathComponent(name),
                            options:.atomic
                        )
                    }
                    metadata.append(
                        ImportedPageMetadata(
                            pageNumber:pageNumber,
                            filter:"原图"
                        )
                    )
                }

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(metadata).write(
                    to:stagingURL.appendingPathComponent(
                        "scan_metadata.json"
                    ),
                    options:.atomic
                )
                try fileManager.moveItem(
                    at:stagingURL,
                    to:finalURL
                )
                activeStagingURL = nil

                completedResults.append(
                    ImportedPDFResult(
                        documentID:documentID,
                        folderIdentifier:folderIdentifier,
                        folderURL:finalURL,
                        title:displayName.isEmpty
                            ? "PDF"
                            : displayName,
                        createdAt:Date(),
                        pageCount:pdf.pageCount
                    )
                )
            }

            return completedResults
        }
        catch {
            if let activeStagingURL,
               fileManager.fileExists(atPath:activeStagingURL.path) {
                try? fileManager.removeItem(at:activeStagingURL)
            }
            removeImportedFiles(completedResults)
            throw error
        }
    }

    nonisolated private static func renderedImage(
        for page:PDFPage
    )->UIImage {
        let bounds = page.bounds(for:.mediaBox)
        let normalizedWidth = max(abs(bounds.width),1)
        let normalizedHeight = max(abs(bounds.height),1)
        let longEdge:CGFloat = 3000
        let scale = longEdge / max(
            normalizedWidth,
            normalizedHeight
        )
        let targetSize = CGSize(
            width:max(1,normalizedWidth * scale),
            height:max(1,normalizedHeight * scale)
        )
        let thumbnail = page.thumbnail(
            of:targetSize,
            for:.mediaBox
        )
        let renderedSize = CGSize(
            width:max(thumbnail.size.width,1),
            height:max(thumbnail.size.height,1)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size:renderedSize,
            format:format
        )

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(
                CGRect(origin:.zero, size:renderedSize)
            )
            thumbnail.draw(
                in:CGRect(origin:.zero, size:renderedSize)
            )
        }
    }
}


private struct ImportedPageMetadata:Codable {
    let pageNumber:Int
    let filter:String
}
