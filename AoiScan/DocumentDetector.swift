//
//  DocumentDetector.swift
//  AoiScan
//

import Foundation
import Vision
import CoreImage
import UIKit



class DocumentDetector {
    
    
    private let request:
    VNDetectRectanglesRequest
    
    
    private let sequenceHandler =
    VNSequenceRequestHandler()
    
    
    
    
    init() {
        
        
        request =
        VNDetectRectanglesRequest()
        
        
        request.minimumConfidence =
        0.6
        
        
        request.maximumObservations =
        1
        
        
        request.minimumAspectRatio =
        0.3
        
        
        request.maximumAspectRatio =
        1.0
        
        
        request.quadratureTolerance =
        20
        
        
    }
    
    
    
    
    func detect(
        image: UIImage,
        completion:
        @escaping (
            CGRect?
        ) -> Void
    ){
        
        
        guard
            let cgImage =
                image.cgImage
        else {
            
            completion(nil)
            return
            
        }
        
        
        
        let requestHandler =
        VNImageRequestHandler(
            cgImage: cgImage,
            options: [:]
        )
        
        
        
        DispatchQueue.global(
            qos:.userInitiated
        ).async {
            
            
            do {
                
                
                try requestHandler.perform(
                    [self.request]
                )
                
                
                guard
                    let observation =
                        self.request.results?.first
                else {
                    
                    DispatchQueue.main.async {
                        
                        completion(nil)
                        
                    }
                    
                    return
                    
                }
                
                
                
                let boundingBox =
                observation.boundingBox
                
                
                
                DispatchQueue.main.async {
                    
                    completion(
                        boundingBox
                    )
                    
                }
                
                
            }
            catch {
                
                
                print(
                    "检测失败:",
                    error
                )
                
                
                DispatchQueue.main.async {
                    
                    completion(nil)
                    
                }
                
                
            }
            
            
        }
        
        
    }
    
    
    
    
}
