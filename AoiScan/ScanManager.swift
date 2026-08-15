//
//  ScanManager.swift
//  AoiScan
//

import Foundation
import CoreData
import Combine


enum ScanFolderError:LocalizedError {
    case emptyName
    case nameTooLong
    case duplicateName
    case folderMissing

    var errorDescription:String? {
        switch self {
        case .emptyName:
            return L10n.text("文件夹名称不能为空。")
        case .nameTooLong:
            return L10n.text("文件夹名称不能超过 50 个字符。")
        case .duplicateName:
            return L10n.text("已存在同名文件夹。")
        case .folderMissing:
            return L10n.text("选择的文件夹已不存在。")
        }
    }
}


class ScanManager: ObservableObject {
    
    
    static let shared = ScanManager()
    
    
    // 扫描文档列表
    @Published var documents: [ScanEntity] = []


    @Published var folders:[ScanFolderEntity] = []
    
    
    private let context =
    PersistenceController.shared.container.viewContext


    nonisolated static var documentsRootURL:URL {

        FileManager.default.urls(
            for:.documentDirectory,
            in:.userDomainMask
        )[0]
        .appendingPathComponent(
            "AoiScan",
            isDirectory:true
        )

    }


    nonisolated static func documentFolderURL(
        for identifier:String
    )->URL {

        let safeIdentifier = URL(
            fileURLWithPath:identifier
        ).lastPathComponent

        return documentsRootURL.appendingPathComponent(
            safeIdentifier,
            isDirectory:true
        )

    }
    
    
    private init() {

        loadFolders()
        loadDocuments()
        
    }


    // MARK: - 用户文件夹

    func loadFolders() {
        let request:NSFetchRequest<ScanFolderEntity> =
            ScanFolderEntity.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(
                key:"createdAt",
                ascending:true
            )
        ]

        do {
            folders = try context.fetch(request)
        }
        catch {
            print(
                "加载文件夹失败:",
                error.localizedDescription
            )
        }
    }


    @discardableResult
    func createFolder(
        named name:String
    ) throws->ScanFolderEntity {
        let title = try validatedFolderName(name)
        let folder = ScanFolderEntity(context:context)
        folder.id = UUID()
        folder.title = title
        folder.createdAt = Date()

        do {
            try context.save()
            loadFolders()
            return folder
        }
        catch {
            context.rollback()
            throw error
        }
    }


    func renameFolder(
        _ folder:ScanFolderEntity,
        newName:String
    ) throws {
        let title = try validatedFolderName(
            newName,
            excluding:folder.id
        )
        folder.title = title

        do {
            try context.save()
            loadFolders()
        }
        catch {
            context.rollback()
            throw error
        }
    }


    func deleteFolder(
        _ folder:ScanFolderEntity
    ) throws {
        for document in documents where document.parentFolder == folder {
            document.parentFolder = nil
        }
        context.delete(folder)

        do {
            try context.save()
            loadFolders()
            loadDocuments()
        }
        catch {
            context.rollback()
            throw error
        }
    }


    func moveDocuments(
        _ documents:[ScanEntity],
        to folderID:UUID?
    ) throws {
        let destination:ScanFolderEntity?

        if let folderID {
            guard let folder = folder(withID:folderID) else {
                throw ScanFolderError.folderMissing
            }
            destination = folder
        }
        else {
            destination = nil
        }

        for document in documents {
            document.parentFolder = destination
        }

        do {
            try context.save()
            loadDocuments()
            loadFolders()
        }
        catch {
            context.rollback()
            throw error
        }
    }


    func folder(withID id:UUID?)->ScanFolderEntity? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }


    func documentCount(in folder:ScanFolderEntity)->Int {
        documents.reduce(0) { count,document in
            count + (document.parentFolder == folder ? 1 : 0)
        }
    }


    private func validatedFolderName(
        _ name:String,
        excluding excludedID:UUID? = nil
    ) throws->String {
        let title = name.trimmingCharacters(
            in:.whitespacesAndNewlines
        )

        guard !title.isEmpty else {
            throw ScanFolderError.emptyName
        }
        guard title.count <= 50 else {
            throw ScanFolderError.nameTooLong
        }

        let duplicate = folders.contains { folder in
            folder.id != excludedID
                && (folder.title ?? "").compare(
                    title,
                    options:[.caseInsensitive, .diacriticInsensitive],
                    range:nil,
                    locale:AppLanguage.current.locale
                ) == .orderedSame
        }
        guard !duplicate else {
            throw ScanFolderError.duplicateName
        }

        return title
    }
    
    
    
    // MARK: - 加载文档
    
    func loadDocuments() {
        
        let request: NSFetchRequest<ScanEntity> =
        ScanEntity.fetchRequest()
        
        
        request.sortDescriptors = [
            
            NSSortDescriptor(
                key: "createdAt",
                ascending: false
            )
            
        ]
        
        
        do {

            let fetchedDocuments = try context.fetch(request)
            var validDocuments:[ScanEntity] = []
            var migratedRecord = false


            for document in fetchedDocuments {

                let originalPath = document.folderPath


                if let folderURL = folderURL(
                    for:document,
                    migrateIfNeeded:true
                ) {

                    validDocuments.append(document)

                    if document.folderPath != originalPath {
                        migratedRecord = true

                        print(
                            "已迁移扫描记录路径:",
                            folderURL.lastPathComponent
                        )
                    }

                }
                else {

                    print(
                        "暂时无法定位扫描文件，已保留记录:",
                        originalPath ?? "空路径"
                    )

                }

            }


            if migratedRecord && context.hasChanges {
                try context.save()
            }


            documents = validDocuments
            
        } catch {
            
            print(
                "加载扫描记录失败:",
                error.localizedDescription
            )
            
        }

    }



    // MARK: - 扫描文件夹

    func folderURL(
        for document:ScanEntity,
        migrateIfNeeded:Bool = true
    )->URL? {

        guard let storedPath = document.folderPath?
            .trimmingCharacters(in:.whitespacesAndNewlines),
              !storedPath.isEmpty,
              let identifier = Self.storageIdentifier(
                from:storedPath
              )
        else {
            return nil
        }


        let currentURL = Self.documentFolderURL(
            for:identifier
        )


        if Self.directoryExists(at:currentURL) {

            if migrateIfNeeded,
               document.folderPath != identifier {
                document.folderPath = identifier
            }

            return currentURL
        }


        if (storedPath as NSString).isAbsolutePath {

            let legacyURL = URL(
                fileURLWithPath:storedPath,
                isDirectory:true
            )

            if Self.directoryExists(at:legacyURL) {
                return legacyURL
            }

        }


        return nil
    }


    private static func storageIdentifier(
        from path:String
    )->String? {

        let identifier = URL(
            fileURLWithPath:path
        ).lastPathComponent
        .trimmingCharacters(in:.whitespacesAndNewlines)

        return identifier.isEmpty ? nil : identifier
    }


    private static func directoryExists(
        at url:URL
    )->Bool {

        var isDirectory:ObjCBool = false

        return FileManager.default.fileExists(
            atPath:url.path,
            isDirectory:&isDirectory
        ) && isDirectory.boolValue
    }
    
    
    
    // MARK: - 新增扫描记录
    
    func addDocument(folderPath: String) {

        guard let folderIdentifier = Self.storageIdentifier(
            from:folderPath
        ) else {
            print("新增扫描记录失败: 文件夹标识为空")
            return
        }
        
        let context = self.context
        let document = ScanEntity(context: context)
        document.id = UUID()
        
        // 从现有文档中查找最大编号
        let legacyPrefix = "扫描文件#"
        let localizedPrefix = L10n.text("扫描文件#")
        let supportedPrefixes = [
            legacyPrefix,
            "Scan #"
        ]
        var maxIndex = 0
        
        for doc in documents {
            if let title = doc.title,
               let prefix = supportedPrefixes.first(
                where:title.hasPrefix
               ) {
                let suffix = title.dropFirst(prefix.count)
                if let num = Int(suffix), num > maxIndex {
                    maxIndex = num
                }
            }
        }
        
        document.title = "\(localizedPrefix)\(maxIndex + 1)"
        document.folderPath = folderIdentifier
        document.createdAt = Date()
        save()
        
    }
    
    
    
    // MARK: - 删除
    
    func deleteDocument(
        _ document: ScanEntity
    ) {
        do {
            try deleteDocuments([document])
        }
        catch {
            print(
                "删除扫描文件失败，已保留扫描记录:",
                error.localizedDescription
            )
        }

    }


    func deleteDocuments(
        _ documents:[ScanEntity]
    ) throws {
        guard !documents.isEmpty else {
            return
        }

        let references = documents.compactMap { document in
            fileReference(
                for:document,
                requireFolder:false
            )
        }
        let stagedDeletion = try ScanFileOperationService.stageDeletion(
            references
        )

        for document in documents {
            context.delete(document)
        }

        do {
            try context.save()
        }
        catch {
            context.rollback()
            stagedDeletion.rollback()
            throw error
        }

        stagedDeletion.commit()
        loadDocuments()
    }


    // MARK: - 批量文件操作

    func fileReferences(
        for documents:[ScanEntity]
    ) throws->[ScanDocumentFileReference] {
        try documents.map { document in
            guard let reference = fileReference(
                for:document,
                requireFolder:true
            ) else {
                throw ScanFileOperationError.unreadableDocument(
                    document.title ?? L10n.text("未命名文档")
                )
            }
            return reference
        }
    }


    // MARK: - 文档页面操作

    @discardableResult
    func appendPages(
        from appendedFolderURL:URL,
        toDocumentID documentID:UUID
    ) async throws->Int {
        guard let document = document(withID:documentID),
              let folderURL = folderURL(
                for:document,
                migrateIfNeeded:false
              ) else {
            throw ScanPageOperationError.unreadableDocument
        }

        let existingPageCount = try await Task.detached(
            priority:.userInitiated
        ) {
            try ScanPageOperationService.pageNumbers(
                in:folderURL
            ).count
        }.value
        let result = try await Task.detached(
            priority:.userInitiated
        ) {
            try ScanPageOperationService.appendPages(
                from:appendedFolderURL,
                to:folderURL
            )
        }.value
        completePageMutation(
            document:document,
            folderURL:folderURL,
            result:result
        )
        return existingPageCount
    }

    @discardableResult
    func deletePage(
        _ pageNumber:Int,
        from document:ScanEntity
    ) async throws->Int {
        guard let folderURL = folderURL(
            for:document,
            migrateIfNeeded:false
        ) else {
            throw ScanPageOperationError.unreadableDocument
        }

        let result = try await Task.detached(
            priority:.userInitiated
        ) {
            try ScanPageOperationService.deletePage(
                pageNumber,
                in:folderURL
            )
        }.value
        completePageMutation(
            document:document,
            folderURL:folderURL,
            result:result
        )
        return result.pageCount
    }

    func reorderPages(
        _ orderedPageNumbers:[Int],
        in document:ScanEntity
    ) async throws {
        guard let folderURL = folderURL(
            for:document,
            migrateIfNeeded:false
        ) else {
            throw ScanPageOperationError.unreadableDocument
        }

        let result = try await Task.detached(
            priority:.userInitiated
        ) {
            try ScanPageOperationService.reorderPages(
                orderedPageNumbers,
                in:folderURL
            )
        }.value
        completePageMutation(
            document:document,
            folderURL:folderURL,
            result:result
        )
    }


    func registerMergedDocument(
        _ result:ScanMergeResult,
        parentFolderID:UUID? = nil,
        deletingDocumentIDs:Set<UUID> = []
    ) throws {
        do {
            _ = try DocumentAssembler().rebuild(
                in:result.folderURL,
                title:result.title,
                createdAt:result.createdAt,
                id:result.documentID
            )
        }
        catch DocumentAssemblerError.noStructuredOCR {
            ScanDocumentStorage.removeIfPresent(in:result.folderURL)
        }
        catch {
            print(
                "合并后重建文档结构失败:",
                error.localizedDescription
            )
        }

        let originalDocuments = documents.filter { document in
            guard let id = document.id else { return false }
            return deletingDocumentIDs.contains(id)
        }
        let originalReferences = originalDocuments.compactMap { document in
            fileReference(
                for:document,
                requireFolder:false
            )
        }
        let stagedDeletion:StagedScanDeletion?
        if originalReferences.isEmpty {
            stagedDeletion = nil
        }
        else {
            stagedDeletion = try ScanFileOperationService.stageDeletion(
                originalReferences
            )
        }

        let document = ScanEntity(context:context)
        document.id = result.documentID
        document.title = result.title
        document.createdAt = result.createdAt
        document.folderPath = result.folderIdentifier
        document.searchableText = result.searchableText
        document.parentFolder = folder(withID:parentFolderID)

        for originalDocument in originalDocuments {
            context.delete(originalDocument)
        }

        do {
            try context.save()
            stagedDeletion?.commit()
            loadDocuments()
            OCRIndexManager.shared.enqueueNewDocument(document)
        }
        catch {
            context.rollback()
            stagedDeletion?.rollback()
            throw error
        }
    }


    func registerImportedPDFs(
        _ results:[ImportedPDFResult],
        parentFolderID:UUID?
    ) throws {
        guard !results.isEmpty else { return }

        let destination:ScanFolderEntity?
        if let parentFolderID {
            guard let folder = folder(withID:parentFolderID) else {
                throw ScanFolderError.folderMissing
            }
            destination = folder
        }
        else {
            destination = nil
        }

        var importedDocuments:[ScanEntity] = []
        for result in results {
            let document = ScanEntity(context:context)
            document.id = result.documentID
            document.title = result.title
            document.createdAt = result.createdAt
            document.folderPath = result.folderIdentifier
            document.parentFolder = destination
            importedDocuments.append(document)
        }

        do {
            try context.save()
            loadDocuments()
            for document in importedDocuments {
                OCRIndexManager.shared.enqueueNewDocument(document)
            }
        }
        catch {
            context.rollback()
            throw error
        }
    }


    private func fileReference(
        for document:ScanEntity,
        requireFolder:Bool
    )->ScanDocumentFileReference? {
        let resolvedFolderURL = folderURL(
            for:document,
            migrateIfNeeded:false
        )

        if requireFolder && resolvedFolderURL == nil {
            return nil
        }

        let id = document.id ?? UUID()

        return ScanDocumentFileReference(
            id:id,
            title:document.title ?? L10n.text("未命名文档"),
            createdAt:document.createdAt ?? Date(),
            folderURL:resolvedFolderURL
                ?? Self.documentFolderURL(for:id.uuidString),
            searchableText:document.searchableText
        )
    }
    
    
    
    // MARK: - 重命名
    
    func renameDocument(
        _ document: ScanEntity,
        newName: String
    ) {
        // Normalize new name
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Do not update if empty name; simply return without side effects
            return
        }

        // Only update Core Data title if changed
        if document.title != trimmed {
            document.title = trimmed
        }

        // Persist changes locally; avoid any external UI/URL/actions here
        save()
    }


    private func document(withID id:UUID)->ScanEntity? {
        documents.first { $0.id == id }
    }


    private func completePageMutation(
        document:ScanEntity,
        folderURL:URL,
        result:ScanPageOperationResult
    ) {
        do {
            _ = try DocumentAssembler().rebuild(
                in:folderURL,
                title:document.title ?? L10n.text("未命名文档"),
                createdAt:document.createdAt ?? Date(),
                id:document.id ?? UUID()
            )
        }
        catch DocumentAssemblerError.noStructuredOCR {
            ScanDocumentStorage.removeIfPresent(in:folderURL)
        }
        catch {
            print(
                "页面操作后重建文档结构失败:",
                error.localizedDescription
            )
        }

        objectWillChange.send()
        document.searchableText = result.searchableText

        do {
            try context.save()
        }
        catch {
            context.rollback()
            print(
                "页面操作后保存搜索索引失败:",
                error.localizedDescription
            )
        }

        OCRIndexManager.shared.enqueueNewDocument(document)
    }
    
    
    
    // MARK: - 保存
    
    private func save() {
        
        
        do {
            
            try context.save()
            
            loadDocuments()
            
            
        } catch {
            
            print(
                "保存失败:",
                error.localizedDescription
            )
            
        }
        
    }
    
    
}
