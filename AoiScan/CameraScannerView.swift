//
//  CameraScannerView.swift
//  AoiScan
//

import SwiftUI
import AVFoundation


struct CameraScannerView: UIViewControllerRepresentable {
    
    
    @Binding var pages:[ScanPage]
    
    @Binding var showPreview:Bool
    
    
    
    func makeUIViewController(
        context: Context
    ) -> ScannerViewController {

        OCRIndexManager.shared.pauseForCamera()
        
        
        let controller =
        ScannerViewController()
        
        
        controller.delegate =
        context.coordinator
        
        
        return controller
        
    }



    static func dismantleUIViewController(
        _ uiViewController:ScannerViewController,
        coordinator:Coordinator
    ) {

        OCRIndexManager.shared.resumeAfterCamera()

    }
    
    
    
    
    func updateUIViewController(
        _ uiViewController: ScannerViewController,
        context: Context
    ){
        
        
    }
    
    
    
    
    func makeCoordinator() -> Coordinator {
        
        
        Coordinator(self)
        
        
    }
    
    
    
    
    class Coordinator:
    NSObject,
    ScannerViewControllerDelegate {
        
        
        private var parent:
        CameraScannerView
        
        
        
        init(
            _ parent:CameraScannerView
        ){
            
            self.parent =
            parent
            
        }
        
        
        
        
        func scannerDidFinish(
            pages:[ScanPage]
        ){
            
            
            print(
                "✅ CameraScannerView收到图片"
            )
            
            
            DispatchQueue.main.async {
                
                
                self.parent.pages =
                pages
                
                
                print(
                    "✅ \(pages.count)页扫描数据保存到数组"
                )
                
                
                self.parent.showPreview =
                true
                
                
                print(
                    "✅ showPreview=true"
                )
                
                
            }
            
            
        }
        
        
    }
    
    
}
