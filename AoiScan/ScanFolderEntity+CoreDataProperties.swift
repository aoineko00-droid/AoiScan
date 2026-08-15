//
//  ScanFolderEntity+CoreDataProperties.swift
//  AoiScan
//

public import Foundation
public import CoreData


extension ScanFolderEntity {
    @nonobjc public class func fetchRequest(
    )->NSFetchRequest<ScanFolderEntity> {
        NSFetchRequest<ScanFolderEntity>(
            entityName:"ScanFolderEntity"
        )
    }

    @NSManaged public var id:UUID?
    @NSManaged public var title:String?
    @NSManaged public var createdAt:Date?
    @NSManaged public var documents:NSSet?
}


extension ScanFolderEntity:Identifiable {}
