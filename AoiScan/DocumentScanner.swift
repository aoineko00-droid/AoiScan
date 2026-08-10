//
//  DocumentScanner.swift
//  AoiScan
//

import SwiftUI


struct DocumentScanner: View {
    
    
    @Binding var showPreview: Bool
    
    
    @Binding var previewPages: [ScanPage]
    
    
    @Environment(\.dismiss)
    private var dismiss
    
    
    
    
    var body: some View {
        
        
        CameraScannerView(
            pages:
                $previewPages,
            
            showPreview:
                $showPreview
        )
        .ignoresSafeArea()
        .onChange(
            of: showPreview
        ) {
            
            
            if showPreview {
                
                
                dismiss()
                
                
            }
            
            
        }
        
        
    }
    
    
}
