//
//  PDFManager.swift
//  AoiScan
//

import Foundation
import UIKit


enum PDFManagerError:LocalizedError {
    case noPages
    case unreadablePage(String)
    case outputMissing

    var errorDescription:String? {
        switch self {
        case .noPages:
            return L10n.text("当前文件没有可分享的扫描页。")
        case .unreadablePage(let name):
            return L10n.format("无法读取扫描页：%@", name as NSString)
        case .outputMissing:
            return L10n.text("无法生成 PDF 文件。")
        }
    }
}


struct PDFManager {
    nonisolated static func generatePDF(
        in folderURL:URL,
        title:String
    ) throws->URL {
        let imageURLs = try orderedPageImageURLs(in:folderURL)

        guard !imageURLs.isEmpty else {
            throw PDFManagerError.noPages
        }

        let outputURL = folderURL.appendingPathComponent(
            "\(safeFileName(title)).pdf"
        )
        let pageBounds = CGRect(x:0, y:0, width:595, height:842)
        let renderer = UIGraphicsPDFRenderer(bounds:pageBounds)
        var renderingError:Error?

        try renderer.writePDF(to:outputURL) { context in
            for url in imageURLs where renderingError == nil {
                autoreleasepool {
                    guard let image = UIImage(contentsOfFile:url.path) else {
                        renderingError = PDFManagerError.unreadablePage(
                            url.lastPathComponent
                        )
                        return
                    }

                    context.beginPage()
                    let scale = min(
                        pageBounds.width / image.size.width,
                        pageBounds.height / image.size.height
                    )
                    let size = CGSize(
                        width:image.size.width * scale,
                        height:image.size.height * scale
                    )
                    let rect = CGRect(
                        x:(pageBounds.width - size.width) / 2,
                        y:(pageBounds.height - size.height) / 2,
                        width:size.width,
                        height:size.height
                    )
                    image.draw(in:rect)
                }
            }
        }

        if let renderingError {
            try? FileManager.default.removeItem(at:outputURL)
            throw renderingError
        }

        guard FileManager.default.fileExists(atPath:outputURL.path) else {
            throw PDFManagerError.outputMissing
        }

        return outputURL
    }

    nonisolated static func pageCount(in folderURL:URL)->Int {
        (try? orderedPageImageURLs(in:folderURL).count) ?? 0
    }

    nonisolated static func orderedPageImageURLs(
        in folderURL:URL
    ) throws->[URL] {
        let files = try FileManager.default.contentsOfDirectory(
            at:folderURL,
            includingPropertiesForKeys:nil,
            options:[.skipsHiddenFiles]
        )
        var display:[Int:URL] = [:]
        var adjusted:[Int:URL] = [:]
        var original:[Int:URL] = [:]
        var preview:[Int:URL] = [:]

        for file in files where file.pathExtension.lowercased() == "jpg" {
            let name = file.deletingPathExtension().lastPathComponent

            if let page = positivePageNumber(name) {
                display[page] = file
            }
            else if name.hasPrefix("adjusted_"),
                    let page = positivePageNumber(
                        String(name.dropFirst("adjusted_".count))
                    ) {
                adjusted[page] = file
            }
            else if name.hasPrefix("original_"),
                    let page = positivePageNumber(
                        String(name.dropFirst("original_".count))
                    ) {
                original[page] = file
            }
            else if name.hasPrefix("preview_"),
                    let page = positivePageNumber(
                        String(name.dropFirst("preview_".count))
                    ) {
                preview[page] = file
            }
        }

        return Set(display.keys)
            .union(adjusted.keys)
            .union(original.keys)
            .union(preview.keys)
            .sorted()
            .compactMap { page in
                display[page]
                    ?? adjusted[page]
                    ?? original[page]
                    ?? preview[page]
            }
    }

    nonisolated private static func positivePageNumber(
        _ value:String
    )->Int? {
        guard let page = Int(value), page > 0 else {
            return nil
        }
        return page
    }

    nonisolated private static func safeFileName(
        _ title:String
    )->String {
        let invalid = CharacterSet(
            charactersIn:"/\\:?%*|\"<>"
        ).union(.controlCharacters)
        let components = title.components(separatedBy:invalid)
        let candidate = components
            .filter { !$0.isEmpty }
            .joined(separator:"-")
            .trimmingCharacters(in:.whitespacesAndNewlines)

        return candidate.isEmpty ? "AoiScan" : candidate
    }
}
