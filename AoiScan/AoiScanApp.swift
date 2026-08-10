//
//  AoiScanApp.swift
//  AoiScan
//

import SwiftUI
import CoreData


@main
struct AoiScanApp: App {
    
    
    let persistenceController = PersistenceController.shared


    @AppStorage(AppLanguage.storageKey)
    private var appLanguage = AppLanguage.simplifiedChinese.rawValue


    private var selectedLanguage:AppLanguage {
        AppLanguage(rawValue:appLanguage) ?? .simplifiedChinese
    }
    
    
    var body: some Scene {
        
        WindowGroup {
            
            ContentView()
                .environment(
                    \.locale,
                    selectedLanguage.locale
                )
                .environment(
                    \.managedObjectContext,
                    persistenceController.container.viewContext
                )
            
        }
    }
}
