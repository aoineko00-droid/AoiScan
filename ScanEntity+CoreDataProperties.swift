//
//  ScanEntity+CoreDataProperties.swift
//  AoiScan
//
//  Created by Aoineko on 2026/8/8.
//
//

public import Foundation
public import CoreData


public typealias ScanEntityCoreDataPropertiesSet = NSSet

extension ScanEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ScanEntity> {
        return NSFetchRequest<ScanEntity>(entityName: "ScanEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var folderPath: String?
    @NSManaged public var searchableText: String?

}

extension ScanEntity : Identifiable {

}
