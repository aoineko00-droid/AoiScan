//
//  WordExporter.swift
//  AoiScan
//

import Foundation


struct WordExporter {
    func export(
        document:ScanDocument,
        to folderURL:URL
    ) throws -> URL {
        let baseName = safeFileName(
            document.title.isEmpty
                ? L10n.text("扫描文档")
                : document.title
        )
        let url = folderURL
            .appendingPathComponent(baseName)
            .appendingPathExtension("docx")
        try DOCXPackageWriter().write(
            document:document,
            to:url
        )
        return url
    }

    private func safeFileName(_ value:String)->String {
        let forbidden = CharacterSet(
            charactersIn:"/:\\?%*|\"<>"
        )
        let components = value.components(
            separatedBy:forbidden
        )
        let cleaned = components
            .joined(separator:"-")
            .trimmingCharacters(in:.whitespacesAndNewlines)
        return cleaned.isEmpty ? "AoiScan" : cleaned
    }

}
