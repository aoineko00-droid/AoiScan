//
//  RecognitionDiagnostics.swift
//  AoiScan
//

import Foundation
import Combine


enum RecognitionSettings {

    private enum Key {
        static let smallDocumentFallback =
            "recognition.smallDocumentFallback"
        static let captureGuidance =
            "recognition.captureGuidance"
        static let defaultFlash =
            "camera.defaultFlash"
    }


    static var smallDocumentFallbackEnabled:Bool {
        get {
            if UserDefaults.standard.object(
                forKey:Key.smallDocumentFallback
            ) == nil {
                return true
            }

            return UserDefaults.standard.bool(
                forKey:Key.smallDocumentFallback
            )
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey:Key.smallDocumentFallback
            )
        }
    }


    static var captureGuidanceEnabled:Bool {
        get {
            if UserDefaults.standard.object(
                forKey:Key.captureGuidance
            ) == nil {
                return true
            }

            return UserDefaults.standard.bool(
                forKey:Key.captureGuidance
            )
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey:Key.captureGuidance
            )
        }
    }


    static var defaultFlashEnabled:Bool {
        get {
            if UserDefaults.standard.object(
                forKey:Key.defaultFlash
            ) == nil {
                return true
            }

            return UserDefaults.standard.bool(
                forKey:Key.defaultFlash
            )
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey:Key.defaultFlash
            )
        }
    }
}


struct RecognitionLogEntry:Identifiable,Codable,Hashable {
    let id:UUID
    let date:Date
    let level:String
    let category:String
    let message:String
    let details:String?
}


final class RecognitionLogStore:ObservableObject {

    static let shared = RecognitionLogStore()

    @Published
    private(set) var entries:[RecognitionLogEntry] = []

    private let maximumEntryCount = 250

    private let fileURL:URL


    private init(){
        let baseURL = FileManager.default.urls(
            for:.applicationSupportDirectory,
            in:.userDomainMask
        )[0]
        .appendingPathComponent(
            "AoiScan",
            isDirectory:true
        )

        try? FileManager.default.createDirectory(
            at:baseURL,
            withIntermediateDirectories:true
        )

        fileURL = baseURL.appendingPathComponent(
            "recognition_logs.json"
        )

        load()
    }


    func add(
        level:String = "信息",
        category:String,
        message:String,
        details:String? = nil
    ){
        let entry = RecognitionLogEntry(
            id:UUID(),
            date:Date(),
            level:level,
            category:category,
            message:message,
            details:details
        )

        DispatchQueue.main.async {
            self.entries.insert(entry, at:0)

            if self.entries.count > self.maximumEntryCount {
                self.entries.removeLast(
                    self.entries.count - self.maximumEntryCount
                )
            }

            self.save()
        }
    }


    func clear(){
        entries.removeAll()
        save()
    }


    func exportedText()->String {
        guard !entries.isEmpty else {
            return "AoiScan 暂无识别日志"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let header = [
            "AoiScan 识别日志",
            "导出时间：\(formatter.string(from:Date()))",
            "说明：日志不包含扫描图片和识别文字内容。",
            ""
        ]

        let lines = entries.map { entry in
            var line = "[\(formatter.string(from:entry.date))] [\(entry.level)] [\(entry.category)] \(entry.message)"

            if let details = entry.details,
               !details.isEmpty {
                line += " | \(details)"
            }

            return line
        }

        return (header + lines).joined(separator:"\n")
    }


    private func load(){
        guard let data = try? Data(contentsOf:fileURL),
              let decoded = try? JSONDecoder().decode(
                [RecognitionLogEntry].self,
                from:data
              ) else {
            return
        }

        entries = Array(decoded.prefix(maximumEntryCount))
    }


    private func save(){
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }

        try? data.write(
            to:fileURL,
            options:.atomic
        )
    }
}
