//
//  ScanDocumentThumbnailView.swift
//  AoiScan
//

import SwiftUI
import ImageIO
import UIKit


struct ScanDocumentThumbnailView:View {
    let folderURL:URL?

    @State private var thumbnail:UIImage?

    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:8, style:.continuous)
                .fill(Color(.secondarySystemBackground))

            if let thumbnail {
                Image(uiImage:thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
            else {
                Image(systemName:"doc.text.image")
                    .font(.system(size:22, weight:.regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width:52, height:68)
        .clipShape(
            RoundedRectangle(cornerRadius:8, style:.continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius:8, style:.continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth:0.5)
        }
        .accessibilityHidden(true)
        .task(id:folderURL?.path) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        thumbnail = nil
        guard let folderURL else { return }

        let source = await Task.detached(priority:.utility) {
            ScanDocumentThumbnailPipeline.sourceInfo(
                in:folderURL
            )
        }.value
        guard !Task.isCancelled,
              let source else {
            return
        }

        if let cachedData = await ScanThumbnailDataCache.shared
            .data(for:source.cacheKey),
           let cachedImage = UIImage(data:cachedData) {
            thumbnail = cachedImage
            return
        }

        let data = await Task.detached(priority:.utility) {
            ScanDocumentThumbnailPipeline.thumbnailData(
                at:source.imageURL
            )
        }.value
        guard !Task.isCancelled,
              let data,
              let image = UIImage(data:data) else {
            return
        }

        await ScanThumbnailDataCache.shared.store(
            data,
            for:source.cacheKey
        )
        thumbnail = image
    }
}


private struct ScanThumbnailSourceInfo:Sendable {
    let imageURL:URL
    let cacheKey:String
}


private enum ScanDocumentThumbnailPipeline {
    nonisolated static func sourceInfo(
        in folderURL:URL
    )->ScanThumbnailSourceInfo? {
        guard let imageURLs = try? PDFManager
            .orderedPageImageURLs(in:folderURL),
              let imageURL = imageURLs.first else {
            return nil
        }

        let values = try? imageURL.resourceValues(
            forKeys:[.contentModificationDateKey, .fileSizeKey]
        )
        let modified = values?.contentModificationDate?
            .timeIntervalSinceReferenceDate ?? 0
        let fileSize = values?.fileSize ?? 0
        let cacheKey = "\(imageURL.path)|\(modified)|\(fileSize)"

        return ScanThumbnailSourceInfo(
            imageURL:imageURL,
            cacheKey:cacheKey
        )
    }

    nonisolated static func thumbnailData(
        at imageURL:URL
    )->Data? {
        guard let source = CGImageSourceCreateWithURL(
            imageURL as CFURL,
            nil
        ) else {
            return nil
        }

        let options:[CFString:Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:160,
            kCGImageSourceShouldCacheImmediately:true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return UIImage(
            cgImage:cgImage,
            scale:1,
            orientation:.up
        ).jpegData(compressionQuality:0.82)
    }
}


private actor ScanThumbnailDataCache {
    static let shared = ScanThumbnailDataCache()

    private let countLimit = 120
    private var values:[String:Data] = [:]
    private var insertionOrder:[String] = []

    func data(for key:String)->Data? {
        values[key]
    }

    func store(_ data:Data, for key:String) {
        if values[key] == nil {
            insertionOrder.append(key)
        }
        values[key] = data

        while insertionOrder.count > countLimit {
            let expiredKey = insertionOrder.removeFirst()
            values.removeValue(forKey:expiredKey)
        }
    }
}
