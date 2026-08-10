//
//  ScanEntity+CoreDataClass.swift
//  AoiScan
//
//  Created by Aoineko on 2026/8/8.
//
//

public import Foundation
public import CoreData

public typealias ScanEntityCoreDataClassSet = NSSet

@objc(ScanEntity)
public class ScanEntity: NSManagedObject {

    // MARK: - Diagnostics
    /// A concise, single-line summary suitable for logs.
    @objc public var diagnosticSummary: String {
        let entityName = self.entity.name ?? "ScanEntity"
        let objectIDURI = self.objectID.uriRepresentation().absoluteString
        return "\(entityName)#\(objectIDURI)"
    }

    /// A detailed, multi-line diagnostic dump.
    /// Avoids force-unwrapping to remain safe in production logging.
    @objc public func diagnosticDetails() -> String {
        var lines: [String] = []
        let entityName = self.entity.name ?? "ScanEntity"
        lines.append("Entity: \(entityName)")
        lines.append("ObjectID: \(self.objectID.uriRepresentation().absoluteString)")

        // Common metadata if available on your model
        if let createdAt = self.value(forKey: "createdAt") as? Date {
            lines.append("createdAt: \(createdAt)")
        }
        if let updatedAt = self.value(forKey: "updatedAt") as? Date {
            lines.append("updatedAt: \(updatedAt)")
        }
        if let uuid = self.value(forKey: "uuid") as? UUID {
            lines.append("uuid: \(uuid.uuidString)")
        }

        // Include changed keys if the object has pending changes
        if self.hasChanges {
            let changed = self.changedValuesForCurrentEvent()
            let changedKeys = changed.keys.sorted().joined(separator: ", ")
            lines.append("Pending Changes: [\(changedKeys)]")
        }

        return lines.joined(separator: "\n")
    }
}

