//
//  PersistenceController.swift
//  AoiScan
//

import CoreData


struct PersistenceController {
    
    
    static let shared = PersistenceController()
    
    
    let container: NSPersistentContainer
    
    
    init() {
        
        container = NSPersistentContainer(
            name: "AoiScanModel"
        )

        if let storeDescription = container.persistentStoreDescriptions.first {
            storeDescription.shouldMigrateStoreAutomatically = true
            storeDescription.shouldInferMappingModelAutomatically = true
        }
        
        
        container.loadPersistentStores {
            description,
            error in
            
            if let error = error {
                
                fatalError(
                    "Core Data error: \(error)"
                )
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
