//
//  ScanManager.swift
//  AoiScan
//

import Foundation
import CoreData
import Combine


class ScanManager: ObservableObject {
    
    
    static let shared = ScanManager()
    
    
    // 扫描文档列表
    @Published var documents: [ScanEntity] = []
    
    
    private let context =
    PersistenceController.shared.container.viewContext


    static var documentsRootURL:URL {

        FileManager.default.urls(
            for:.documentDirectory,
            in:.userDomainMask
        )[0]
        .appendingPathComponent(
            "AoiScan",
            isDirectory:true
        )

    }


    static func documentFolderURL(
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
        
        loadDocuments()
        
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
        let prefix = "扫描文件#"
        var maxIndex = 0
        
        for doc in documents {
            if let title = doc.title,
               title.hasPrefix(prefix) {
                let suffix = title.dropFirst(prefix.count)
                if let num = Int(suffix), num > maxIndex {
                    maxIndex = num
                }
            }
        }
        
        document.title = "\(prefix)\(maxIndex + 1)"
        document.folderPath = folderIdentifier
        document.createdAt = Date()
        save()
        
    }
    
    
    
    // MARK: - 删除
    
    func deleteDocument(
        _ document: ScanEntity
    ) {


        if let folderURL = folderURL(
            for:document,
            migrateIfNeeded:false
        ) {

            do {
                try FileManager.default.removeItem(
                    at:folderURL
                )
            }
            catch {
                print(
                    "删除扫描文件失败，已保留扫描记录:",
                    error.localizedDescription
                )
                return
            }

        }
        
        
        context.delete(document)
        
        
        save()
        
    }
    
    
    
    // MARK: - 重命名
    
    func renameDocument(
        _ document: ScanEntity,
        newName: String
    ) {
        
        
        document.title = newName
        
        
        save()
        
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
