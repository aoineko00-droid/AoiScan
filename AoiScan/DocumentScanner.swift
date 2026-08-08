//
//  DocumentScanner.swift
//  AoiScan
//

import SwiftUI
import VisionKit
import Photos


struct DocumentScanner: UIViewControllerRepresentable {
    
    @Environment(\.dismiss)
    private var dismiss
    
    
    func makeUIViewController(
        context: Context
    ) -> VNDocumentCameraViewController {
        
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        
        return scanner
    }
    
    
    func updateUIViewController(
        _ uiViewController: VNDocumentCameraViewController,
        context: Context
    ) {
        
    }
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    
    
    class Coordinator: NSObject,
    VNDocumentCameraViewControllerDelegate {
        
        
        private var parent: DocumentScanner
        
        
        init(parent: DocumentScanner) {
            self.parent = parent
        }
        
        
        
        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            
            controller.dismiss(animated: true)
        }
        
        
        
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            
            print(
                "扫描失败:",
                error.localizedDescription
            )
            
            controller.dismiss(animated: true)
        }
        
        
        
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            
            
            print(
                "扫描完成，共 \(scan.pageCount) 页"
            )
            
            
            if scan.pageCount > 0 {
                
                let image = scan.imageOfPage(at: 0)
                
                
                UIImageWriteToSavedPhotosAlbum(
                    image,
                    self,
                    #selector(saveComplete),
                    nil
                )
            }
            
            
            controller.dismiss(animated: true)
        }
        
        
        
        @objc func saveComplete(
            _ image: UIImage,
            didFinishSavingWithError error: Error?,
            contextInfo: UnsafeRawPointer
        ) {
            
            if let error = error {
                
                print(
                    "保存失败:",
                    error.localizedDescription
                )
                
            } else {
                
                print(
                    "保存成功"
                )
            }
        }
    }
}
