//
//  OCRIndexManager.swift
//  AoiScan
//

import Foundation
import UIKit
import CoreData
import Combine
import ImageIO


final class OCRIndexManager:ObservableObject {

    static let shared = OCRIndexManager()

    static let automaticIndexingKey =
        "recognition.automaticTextIndex"

    @Published private(set) var isIndexing = false
    @Published private(set) var currentDocumentTitle:String?
    @Published private(set) var batchCompleted = 0
    @Published private(set) var batchTotal = 0

    private struct PageSource {
        let pageNumber:Int
        let imageURL:URL
        let textURL:URL
        let structuredURL:URL
    }

    private struct IndexRequest {
        let documentID:UUID
        let title:String
        let pages:[PageSource]
        let force:Bool
        let belongsToBatch:Bool
    }

    private struct SuspendedProgress {
        let position:Int
        let request:IndexRequest
        let collectedTexts:[String]
    }

    private var pending:[IndexRequest] = []
    private var scheduledDocumentIDs:Set<UUID> = []
    private var runningRequest:IndexRequest?
    private var suspendedProgress:SuspendedProgress?
    private var scheduledStartWorkItem:DispatchWorkItem?
    private var isPausedForCamera = false
    private var stopAfterCurrentPage = false

    private let context =
        PersistenceController.shared.container.viewContext


    private init() {}


    func pauseForCamera() {
        isPausedForCamera = true
        scheduledStartWorkItem?.cancel()
        scheduledStartWorkItem = nil
    }


    func resumeAfterCamera() {
        scheduledStartWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.isPausedForCamera = false
            self.continueAvailableWork()
        }

        scheduledStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline:.now() + 1.2,
            execute:workItem
        )
    }


    func automaticSettingDidChange(
        enabled:Bool
    ) {
        if enabled {
            scheduleRun(after:0.8)
        }
        else {
            cancelPendingTasks()
        }
    }


    func cancelPendingTasks() {
        scheduledStartWorkItem?.cancel()
        scheduledStartWorkItem = nil

        for request in pending {
            scheduledDocumentIDs.remove(request.documentID)
        }

        pending.removeAll()
        batchCompleted = 0
        batchTotal = 0

        if let runningRequest,
           suspendedProgress != nil {
            scheduledDocumentIDs.remove(
                runningRequest.documentID
            )
            self.runningRequest = nil
            suspendedProgress = nil
            stopAfterCurrentPage = false
            isIndexing = false
            currentDocumentTitle = nil
        }
        else if runningRequest != nil {
            stopAfterCurrentPage = true
        }
        else {
            isIndexing = false
            currentDocumentTitle = nil
        }
    }


    static var automaticIndexingEnabled:Bool {
        let defaults = UserDefaults.standard

        if let storedValue = defaults.object(
            forKey:automaticIndexingKey
        ) as? Bool {
            return storedValue
        }

        return true
    }


    func enqueueNewDocument(
        _ document:ScanEntity
    ) {
        guard Self.automaticIndexingEnabled else {
            return
        }

        enqueue(
            document,
            force:false,
            belongsToBatch:false
        )

        scheduleRun(after:1.5)
    }


    func reindexDocument(
        _ document:ScanEntity
    ) {
        guard Self.automaticIndexingEnabled else {
            rebuildSearchableText(for:document)
            return
        }

        enqueue(
            document,
            force:true,
            belongsToBatch:false
        )

        scheduleRun(after:1.0)
    }


    func indexExistingDocuments(
        _ documents:[ScanEntity]
    ) {
        let candidates = documents.filter { document in
            let text = document.searchableText?
                .trimmingCharacters(in:.whitespacesAndNewlines)

            guard let folderURL = ScanManager.shared.folderURL(
                for:document
            ) else {
                return text?.isEmpty != false
            }

            let hasMissingStructuredResult = Self.pageSources(
                in:folderURL
            )
            .contains {
                OCRStorage.load(from:$0.structuredURL) == nil
            }

            return text?.isEmpty != false
                || hasMissingStructuredResult
        }

        batchCompleted = 0
        batchTotal = candidates.count

        guard !candidates.isEmpty else {
            return
        }

        for document in candidates {
            enqueue(
                document,
                force:false,
                belongsToBatch:true
            )
        }

        scheduleRun(after:0.3)
    }


    func rebuildSearchableText(
        for document:ScanEntity
    ) {
        guard let documentID = document.id,
              let folderURL = ScanManager.shared.folderURL(
                for:document
              ) else {
            return
        }

        let text = Self.existingRecognizedText(
            in:folderURL
        )

        updateSearchableText(
            documentID:documentID,
            text:text
        )
    }


    private func enqueue(
        _ document:ScanEntity,
        force:Bool,
        belongsToBatch:Bool
    ) {
        guard let documentID = document.id,
              !scheduledDocumentIDs.contains(documentID),
              let folderURL = ScanManager.shared.folderURL(
                for:document
              ) else {
            if belongsToBatch {
                batchCompleted += 1
            }
            return
        }

        let pages = Self.pageSources(in:folderURL)

        guard !pages.isEmpty else {
            if belongsToBatch {
                batchCompleted += 1
            }
            return
        }

        let request = IndexRequest(
            documentID:documentID,
            title:document.title ?? L10n.text("未命名文档"),
            pages:pages,
            force:force,
            belongsToBatch:belongsToBatch
        )

        scheduledDocumentIDs.insert(documentID)
        pending.append(request)
    }


    private func scheduleRun(
        after delay:TimeInterval
    ) {
        guard !isPausedForCamera else {
            return
        }

        scheduledStartWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.continueAvailableWork()
        }

        scheduledStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline:.now() + delay,
            execute:workItem
        )
    }


    private func continueAvailableWork() {
        scheduledStartWorkItem = nil

        guard !isPausedForCamera else {
            return
        }

        if let progress = suspendedProgress {
            suspendedProgress = nil
            recognizePage(
                at:progress.position,
                request:progress.request,
                collectedTexts:progress.collectedTexts
            )
        }
        else {
            runNextIfNeeded()
        }
    }


    private func runNextIfNeeded() {
        guard !isPausedForCamera else {
            return
        }

        guard runningRequest == nil else {
            return
        }

        guard !pending.isEmpty else {
            isIndexing = false
            currentDocumentTitle = nil
            return
        }

        let request = pending.removeFirst()
        runningRequest = request
        isIndexing = true
        currentDocumentTitle = request.title

        recognizePage(
            at:0,
            request:request,
            collectedTexts:[]
        )
    }


    private func recognizePage(
        at position:Int,
        request:IndexRequest,
        collectedTexts:[String]
    ) {
        if stopAfterCurrentPage {
            abandon(request:request)
            return
        }

        if isPausedForCamera {
            suspendedProgress = SuspendedProgress(
                position:position,
                request:request,
                collectedTexts:collectedTexts
            )
            return
        }

        guard request.pages.indices.contains(position) else {
            finish(
                request:request,
                text:collectedTexts
                    .filter { !$0.isEmpty }
                    .joined(separator:"\n\n")
            )
            return
        }

        let page = request.pages[position]

        let existingText = (try? String(
            contentsOf:page.textURL,
            encoding:.utf8
        ))?
        .trimmingCharacters(in:.whitespacesAndNewlines)

        let usableExistingText = existingText?.isEmpty == false
            ? existingText
            : nil

        let hasStructuredResult = OCRStorage.load(
            from:page.structuredURL
        ) != nil

        if !request.force,
           let usableExistingText,
           hasStructuredResult {
            recognizePage(
                at:position + 1,
                request:request,
                collectedTexts:
                    collectedTexts + [usableExistingText]
            )
            return
        }

        if request.force {
            OCRStorage.removeIfPresent(
                at:page.structuredURL
            )
        }

        guard let image = Self.downsampledImage(
            at:page.imageURL,
            maxPixelSize:2800
        ) else {
            print(
                "文字索引跳过无法读取的页面:",
                page.imageURL.lastPathComponent
            )
            recognizePage(
                at:position + 1,
                request:request,
                collectedTexts:
                    collectedTexts + [usableExistingText ?? ""]
            )
            return
        }

        LocalTextRecognizer.recognize(
            image:image,
            pageNumber:page.pageNumber,
            background:true
        ) { result in
            var pageText = ""
            var pageResult:OCRPageResult?

            switch result {
            case .success(let recognizedResult):
                pageResult = recognizedResult
                pageText = recognizedResult.plainText
            case .failure(let error):
                print(
                    "后台文字识别未取得结果:",
                    error.localizedDescription
                )
            }

            // 用户可能在后台识别期间手动编辑并保存了这一页。
            // 非强制任务优先保留用户保存的文字，避免被自动结果覆盖。
            if !request.force,
               let manuallySavedText = try? String(
                    contentsOf:page.textURL,
                    encoding:.utf8
               ),
               !manuallySavedText.trimmingCharacters(
                    in:.whitespacesAndNewlines
               ).isEmpty {
                pageText = manuallySavedText
            }

            do {
                try pageText.write(
                    to:page.textURL,
                    atomically:true,
                    encoding:.utf8
                )
            }
            catch {
                print(
                    "文字索引文件保存失败:",
                    error.localizedDescription
                )
            }

            if let pageResult {
                do {
                    try OCRStorage.write(
                        pageResult,
                        to:page.structuredURL
                    )
                }
                catch {
                    print(
                        "结构化 OCR 文件保存失败:",
                        error.localizedDescription
                    )
                }
            }

            DispatchQueue.main.async { [weak self] in
                self?.recognizePage(
                    at:position + 1,
                    request:request,
                    collectedTexts:collectedTexts + [pageText]
                )
            }
        }
    }


    private func finish(
        request:IndexRequest,
        text:String
    ) {
        updateSearchableText(
            documentID:request.documentID,
            text:text
        )

        scheduledDocumentIDs.remove(request.documentID)
        runningRequest = nil

        if request.belongsToBatch {
            batchCompleted += 1
        }

        runNextIfNeeded()
    }


    private func abandon(
        request:IndexRequest
    ) {
        scheduledDocumentIDs.remove(request.documentID)
        runningRequest = nil
        suspendedProgress = nil
        stopAfterCurrentPage = false
        isIndexing = false
        currentDocumentTitle = nil
        runNextIfNeeded()
    }


    private func updateSearchableText(
        documentID:UUID,
        text:String
    ) {
        let request:NSFetchRequest<ScanEntity> =
            ScanEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format:"id == %@",
            documentID as CVarArg
        )

        do {
            guard let document = try context.fetch(request).first else {
                return
            }

            let trimmed = text.trimmingCharacters(
                in:.whitespacesAndNewlines
            )
            ScanManager.shared.objectWillChange.send()
            document.searchableText = trimmed.isEmpty
                ? nil
                : trimmed
            try context.save()
        }
        catch {
            context.rollback()
            print(
                "搜索索引保存失败:",
                error.localizedDescription
            )
        }
    }


    private static func downsampledImage(
        at url:URL,
        maxPixelSize:Int
    )->UIImage? {
        let sourceOptions:[CFString:Any] = [
            kCGImageSourceShouldCache:false
        ]

        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            sourceOptions as CFDictionary
        ) else {
            return nil
        }

        let thumbnailOptions:[CFString:Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:maxPixelSize,
            kCGImageSourceShouldCacheImmediately:true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return nil
        }

        return UIImage(
            cgImage:cgImage,
            scale:1,
            orientation:.up
        )
    }


    private static func pageSources(
        in folderURL:URL
    )->[PageSource] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at:folderURL,
            includingPropertiesForKeys:nil,
            options:[.skipsHiddenFiles]
        ) else {
            return []
        }

        var adjustedFiles:[Int:URL] = [:]
        var displayFiles:[Int:URL] = [:]

        for file in files where file.pathExtension.lowercased() == "jpg" {
            let name = file.deletingPathExtension().lastPathComponent

            if name.hasPrefix("adjusted_"),
               let page = Int(name.dropFirst("adjusted_".count)),
               page > 0 {
                adjustedFiles[page] = file
            }
            else if let page = Int(name), page > 0 {
                displayFiles[page] = file
            }
        }

        let pageNumbers = Set(adjustedFiles.keys)
            .union(displayFiles.keys)
            .sorted()

        return pageNumbers.compactMap { pageNumber in
            guard let imageURL = adjustedFiles[pageNumber]
                    ?? displayFiles[pageNumber] else {
                return nil
            }

            return PageSource(
                pageNumber:pageNumber,
                imageURL:imageURL,
                textURL:folderURL.appendingPathComponent(
                    "recognized_\(pageNumber).txt"
                ),
                structuredURL:OCRStorage.fileURL(
                    in:folderURL,
                    pageNumber:pageNumber
                )
            )
        }
    }


    private static func existingRecognizedText(
        in folderURL:URL
    )->String {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at:folderURL,
            includingPropertiesForKeys:nil,
            options:[.skipsHiddenFiles]
        ) else {
            return ""
        }

        let orderedFiles = files.compactMap { file -> (Int,URL)? in
            let name = file.deletingPathExtension().lastPathComponent

            guard file.pathExtension.lowercased() == "txt",
                  name.hasPrefix("recognized_"),
                  let page = Int(
                    name.dropFirst("recognized_".count)
                  ) else {
                return nil
            }

            return (page, file)
        }
        .sorted { $0.0 < $1.0 }

        return orderedFiles.compactMap {
            try? String(contentsOf:$0.1, encoding:.utf8)
        }
        .filter {
            !$0.trimmingCharacters(
                in:.whitespacesAndNewlines
            ).isEmpty
        }
        .joined(separator:"\n\n")
    }
}
