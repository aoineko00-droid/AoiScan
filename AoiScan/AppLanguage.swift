//
//  AppLanguage.swift
//  AoiScan
//

import Foundation


enum AppLanguage:String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let storageKey = "app.language"

    var id:String { rawValue }

    var displayName:String {
        switch self {
        case .simplifiedChinese:
            return "中文"
        case .english:
            return "English"
        }
    }

    var locale:Locale {
        Locale(identifier:rawValue)
    }

    static var current:AppLanguage {
        guard let storedValue = UserDefaults.standard.string(
            forKey:storageKey
        ),
              let language = AppLanguage(rawValue:storedValue) else {
            return .simplifiedChinese
        }

        return language
    }
}


enum L10n {
    static func text(_ key:String)->String {
        let language = AppLanguage.current

        guard let path = Bundle.main.path(
            forResource:language.rawValue,
            ofType:"lproj"
        ),
              let bundle = Bundle(path:path) else {
            return key
        }

        return NSLocalizedString(
            key,
            tableName:"Localizable",
            bundle:bundle,
            value:key,
            comment:""
        )
    }

    static func format(
        _ key:String,
        _ arguments:CVarArg...
    )->String {
        String(
            format:text(key),
            locale:AppLanguage.current.locale,
            arguments:arguments
        )
    }
}
