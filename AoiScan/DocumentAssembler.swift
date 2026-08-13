//
//  DocumentAssembler.swift
//  AoiScan
//

import Foundation


enum DocumentAssemblerError:LocalizedError {
    case noStructuredOCR

    var errorDescription:String? {
        switch self {
        case .noStructuredOCR:
            return L10n.text(
                "尚未取得结构化文字，请稍后重试或先打开文字识别。"
            )
        }
    }
}


/// Builds the final document model without rerunning OCR.
struct DocumentAssembler {
    func assemble(
        pageResults:[OCRPageResult],
        title:String,
        createdAt:Date = Date(),
        id:UUID = UUID()
    ) throws -> ScanDocument {
        guard !pageResults.isEmpty else {
            throw DocumentAssemblerError.noStructuredOCR
        }

        let pages = pageResults
            .sorted { $0.pageNumber < $1.pageNumber }
            .map { result in
                DocumentPage(
                    pageNumber:result.pageNumber,
                    imageWidth:result.imageWidth,
                    imageHeight:result.imageHeight,
                    blocks:result.documentBlocks
                )
            }

        return ScanDocument(
            id:id,
            title:title,
            createdAt:createdAt,
            pages:pages
        )
    }

    @discardableResult
    func rebuild(
        in folderURL:URL,
        title:String = "",
        createdAt:Date = Date(),
        id:UUID = UUID()
    ) throws -> ScanDocument {
        let results = structuredOCRResults(in:folderURL)
        let document = try assemble(
            pageResults:results,
            title:title,
            createdAt:createdAt,
            id:id
        )
        try ScanDocumentStorage.write(
            document,
            to:ScanDocumentStorage.fileURL(in:folderURL)
        )
        return document
    }

    func rebuildIfPossible(in folderURL:URL) {
        do {
            _ = try rebuild(in:folderURL)
        }
        catch DocumentAssemblerError.noStructuredOCR {
            ScanDocumentStorage.removeIfPresent(in:folderURL)
        }
        catch {
            print("最终文档结构保存失败:", error)
        }
    }

    private func structuredOCRResults(
        in folderURL:URL
    )->[OCRPageResult] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at:folderURL,
            includingPropertiesForKeys:nil,
            options:[.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()

        return urls.compactMap { url -> OCRPageResult? in
            let name = url.lastPathComponent
            guard name.hasPrefix("ocr_"),
                  url.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf:url) else {
                return nil
            }
            return try? decoder.decode(
                OCRPageResult.self,
                from:data
            )
        }
        .sorted { $0.pageNumber < $1.pageNumber }
    }
}
