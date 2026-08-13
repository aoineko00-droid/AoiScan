//
//  RecognitionDiagnostics.swift
//  AoiScan
//

import Foundation
import Combine
import AVFoundation


enum CameraFlashMode:String,CaseIterable,Identifiable {
    case off
    case automatic
    case on

    static let storageKey = "camera.defaultFlashMode"

    var id:String { rawValue }

    var title:String {
        switch self {
        case .off:
            return L10n.text("关闭")
        case .automatic:
            return L10n.text("自动")
        case .on:
            return L10n.text("开启")
        }
    }

    var captureMode:AVCaptureDevice.FlashMode {
        switch self {
        case .off:
            return .off
        case .automatic:
            return .auto
        case .on:
            return .on
        }
    }

    var symbolName:String {
        switch self {
        case .off:
            return "bolt.slash"
        case .automatic:
            return "bolt"
        case .on:
            return "bolt.fill"
        }
    }

    var next:CameraFlashMode {
        switch self {
        case .off:
            return .automatic
        case .automatic:
            return .on
        case .on:
            return .off
        }
    }
}


enum RecognitionSettings {

    private enum Key {
        static let smallDocumentFallback =
            "recognition.smallDocumentFallback"
        static let captureGuidance =
            "recognition.captureGuidance"
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


    static var defaultFlashMode:CameraFlashMode {
        get {
            guard let rawValue = UserDefaults.standard.string(
                forKey:CameraFlashMode.storageKey
            ),
                  let mode = CameraFlashMode(rawValue:rawValue) else {
                return .off
            }

            return mode
        }
        set {
            UserDefaults.standard.set(
                newValue.rawValue,
                forKey:CameraFlashMode.storageKey
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
            return L10n.text("AoiScan 暂无识别日志")
        }

        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let header = [
            L10n.text("AoiScan 识别日志"),
            L10n.format(
                "导出时间：%@",
                formatter.string(from:Date())
            ),
            L10n.text("说明：日志不包含扫描图片和识别文字内容。"),
            ""
        ]

        let lines = entries.map { entry in
            var line = "[\(formatter.string(from:entry.date))] [\(L10n.text(entry.level))] [\(L10n.text(entry.category))] \(L10n.text(entry.message))"

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
