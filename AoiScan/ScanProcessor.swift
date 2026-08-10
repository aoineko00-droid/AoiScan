//
//  ScanProcessor.swift
//  AoiScan
//

import UIKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import ImageIO


struct ScanCorners:Equatable,Codable {
    var topLeft:CGPoint
    var topRight:CGPoint
    var bottomRight:CGPoint
    var bottomLeft:CGPoint
}


struct ScanPageMetadata:Codable {
    let pageNumber:Int
    var corners:ScanCorners?
    var filter:ScanPageFilter? = nil
}


enum ScanPageFilter:String,CaseIterable,Hashable,Codable {
    case smart = "智能"
    case color = "原图"
    case blackWhite = "黑白"

    var localizedTitle:String {
        L10n.text(rawValue)
    }
}


struct ScanPage:Identifiable {
    let id:UUID
    var originalImage:UIImage
    var adjustedImage:UIImage
    var previewImage:UIImage
    var detectedCorners:ScanCorners?
    var suggestedCropCorners:ScanCorners?
    var filter:ScanPageFilter
    private(set) var temporaryDirectoryURL:URL?
    private(set) var originalImageURL:URL?
    private(set) var adjustedImageURL:URL?
    private(set) var previewImageURL:URL?

    init(
        id:UUID = UUID(),
        originalImage:UIImage,
        adjustedImage:UIImage,
        previewImage:UIImage,
        detectedCorners:ScanCorners?,
        suggestedCropCorners:ScanCorners? = nil,
        filter:ScanPageFilter = .smart
    ) {
        self.id = id
        self.originalImage = originalImage
        self.adjustedImage = adjustedImage
        self.previewImage = previewImage
        self.detectedCorners = detectedCorners
        self.suggestedCropCorners = suggestedCropCorners
        self.filter = filter
        self.temporaryDirectoryURL = nil
        self.originalImageURL = nil
        self.adjustedImageURL = nil
        self.previewImageURL = nil
    }


    mutating func storeInTemporaryFiles() throws {

        try replaceStoredImages(
            original:originalImage,
            adjusted:adjustedImage,
            preview:previewImage
        )

    }


    mutating func replaceStoredImages(
        original:UIImage,
        adjusted:UIImage,
        preview:UIImage
    ) throws {

        let directory = try temporaryDirectoryURL
            ?? ScanPageStorage.createPageDirectory(
                identifier:id
            )
        let originalURL = directory.appendingPathComponent(
            "original.jpg"
        )
        let adjustedURL = directory.appendingPathComponent(
            "adjusted.jpg"
        )
        let previewURL = directory.appendingPathComponent(
            "preview.jpg"
        )

        do {
            try ScanPageStorage.writeJPEG(
                original,
                to:originalURL,
                quality:0.95
            )
            try ScanPageStorage.writeJPEG(
                adjusted,
                to:adjustedURL,
                quality:0.95
            )
            try ScanPageStorage.writeJPEG(
                preview,
                to:previewURL,
                quality:0.92
            )
        }
        catch {
            if temporaryDirectoryURL == nil {
                try? FileManager.default.removeItem(
                    at:directory
                )
            }
            throw error
        }

        temporaryDirectoryURL = directory
        self.originalImageURL = originalURL
        self.adjustedImageURL = adjustedURL
        self.previewImageURL = previewURL

        originalImage = ScanPageStorage.thumbnail(
            at:originalURL,
            maxPixelSize:640
        ) ?? original
        adjustedImage = ScanPageStorage.thumbnail(
            at:adjustedURL,
            maxPixelSize:640
        ) ?? adjusted
        previewImage = ScanPageStorage.thumbnail(
            at:previewURL,
            maxPixelSize:1600
        ) ?? preview
    }


    mutating func replaceStoredPreview(
        _ image:UIImage
    ) throws {

        guard let previewImageURL else {
            previewImage = image
            return
        }

        try ScanPageStorage.writeJPEG(
            image,
            to:previewImageURL,
            quality:0.92
        )

        previewImage = ScanPageStorage.thumbnail(
            at:previewImageURL,
            maxPixelSize:1600
        ) ?? image
    }


    func fullResolutionOriginalImage()->UIImage {

        ScanPageStorage.image(
            at:originalImageURL
        ) ?? originalImage
    }


    func fullResolutionAdjustedImage()->UIImage {

        ScanPageStorage.image(
            at:adjustedImageURL
        ) ?? adjustedImage
    }


    func writeFullResolutionImages(
        originalURL:URL,
        adjustedURL:URL,
        previewURL:URL
    ) throws {

        try ScanPageStorage.copyOrWrite(
            sourceURL:self.originalImageURL,
            fallbackImage:originalImage,
            destinationURL:originalURL,
            quality:0.95
        )
        try ScanPageStorage.copyOrWrite(
            sourceURL:self.adjustedImageURL,
            fallbackImage:adjustedImage,
            destinationURL:adjustedURL,
            quality:0.95
        )
        try ScanPageStorage.copyOrWrite(
            sourceURL:self.previewImageURL,
            fallbackImage:previewImage,
            destinationURL:previewURL,
            quality:0.92
        )
    }


    func removeTemporaryFiles() {

        guard let temporaryDirectoryURL else {
            return
        }

        try? FileManager.default.removeItem(
            at:temporaryDirectoryURL
        )
    }


    static func removeStaleTemporaryFiles() {
        ScanPageStorage.removeStaleFiles()
    }
}


private enum ScanPageStorageError:Error {
    case imageEncodingFailed
    case temporaryFileMissing
}


private enum ScanPageStorage {
    private static var rootURL:URL {
        FileManager.default.urls(
            for:.cachesDirectory,
            in:.userDomainMask
        )[0]
        .appendingPathComponent(
            "AoiScanPendingPages",
            isDirectory:true
        )
    }


    static func createPageDirectory(
        identifier:UUID
    ) throws ->URL {

        let directory = rootURL.appendingPathComponent(
            identifier.uuidString,
            isDirectory:true
        )

        try FileManager.default.createDirectory(
            at:directory,
            withIntermediateDirectories:true
        )

        return directory
    }


    static func writeJPEG(
        _ image:UIImage,
        to url:URL,
        quality:CGFloat
    ) throws {

        guard let data = image.jpegData(
            compressionQuality:quality
        ) else {
            throw ScanPageStorageError.imageEncodingFailed
        }

        try data.write(
            to:url,
            options:.atomic
        )
    }


    static func image(
        at url:URL?
    )->UIImage? {

        guard let url,
              FileManager.default.fileExists(
                atPath:url.path
              ) else {
            return nil
        }

        return UIImage(
            contentsOfFile:url.path
        )
    }


    static func thumbnail(
        at url:URL,
        maxPixelSize:Int
    )->UIImage? {

        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            nil
        ) else {
            return nil
        }

        let options:[CFString:Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:maxPixelSize,
            kCGImageSourceShouldCacheImmediately:true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return UIImage(
            cgImage:cgImage,
            scale:1,
            orientation:.up
        )
    }


    static func copyOrWrite(
        sourceURL:URL?,
        fallbackImage:UIImage,
        destinationURL:URL,
        quality:CGFloat
    ) throws {

        if let sourceURL {

            guard FileManager.default.fileExists(
                atPath:sourceURL.path
            ) else {
                throw ScanPageStorageError.temporaryFileMissing
            }

            try FileManager.default.copyItem(
                at:sourceURL,
                to:destinationURL
            )
            return
        }

        try writeJPEG(
            fallbackImage,
            to:destinationURL,
            quality:quality
        )
    }


    static func removeStaleFiles() {

        guard FileManager.default.fileExists(
            atPath:rootURL.path
        ) else {
            return
        }

        try? FileManager.default.removeItem(
            at:rootURL
        )
    }
}


struct CropResult {
    let image:UIImage
    let sourceImage:UIImage
    let corners:ScanCorners
    let automaticCorners:ScanCorners?
}


private struct SmallDocumentDetectionResult {
    let selectedRectangles:[VNRectangleObservation]
    let suggestedCropCorners:ScanCorners?
    let rectangleCandidateCount:Int
    let textObservationCount:Int
    let textObservations:[VNRecognizedTextObservation]
    let detectionSource:String
}


enum DocumentRectangleSelector {
    static func corners(
        from rectangle:VNRectangleObservation
    )->ScanCorners {
        func uiPoint(_ point:CGPoint)->CGPoint {
            CGPoint(x:point.x, y:1 - point.y)
        }

        return ScanCorners(
            topLeft:uiPoint(rectangle.topLeft),
            topRight:uiPoint(rectangle.topRight),
            bottomRight:uiPoint(rectangle.bottomRight),
            bottomLeft:uiPoint(rectangle.bottomLeft)
        )
    }

    static func best(
        in observations:[VNRectangleObservation],
        preferredCorners:ScanCorners? = nil
    )->VNRectangleObservation? {
        observations
            .filter { isPlausible($0) }
            .max {
                score($0, preferredCorners:preferredCorners)
                    < score($1, preferredCorners:preferredCorners)
            }
    }


    static func bestSmallDocument(
        in observations:[VNRectangleObservation],
        textObservations:[VNRecognizedTextObservation]
    )->VNRectangleObservation? {
        observations
            .filter {
                isSmallDocumentPlausible(
                    $0,
                    textObservations:textObservations
                )
            }
            .max {
                smallDocumentScore(
                    $0,
                    textObservations:textObservations
                )
                < smallDocumentScore(
                    $1,
                    textObservations:textObservations
                )
            }
    }


    static func bestBookPagePair(
        in observations:[VNRectangleObservation],
        textObservations:[VNRecognizedTextObservation]
    )->[VNRectangleObservation]? {
        let candidates = observations.filter {
            isSmallDocumentPlausible(
                $0,
                textObservations:textObservations
            )
        }

        guard candidates.count >= 2 else {
            return nil
        }

        var bestPair:[VNRectangleObservation]?
        var bestPairScore = -CGFloat.greatestFiniteMagnitude

        for firstIndex in 0..<(candidates.count - 1) {
            for secondIndex in (firstIndex + 1)..<candidates.count {
                let first = candidates[firstIndex]
                let second = candidates[secondIndex]
                let firstBox = first.boundingBox
                let secondBox = second.boundingBox
                let firstArea = firstBox.width * firstBox.height
                let secondArea = secondBox.width * secondBox.height
                let smallerArea = min(firstArea, secondArea)
                let largerArea = max(firstArea, secondArea)
                let overlap = firstBox.intersection(secondBox)
                let overlapArea = overlap.isNull
                    ? 0
                    : overlap.width * overlap.height
                let verticalOverlap = max(
                    min(firstBox.maxY, secondBox.maxY)
                        - max(firstBox.minY, secondBox.minY),
                    0
                )
                let verticalOverlapRatio = verticalOverlap
                    / max(min(firstBox.height, secondBox.height), 0.0001)
                let union = firstBox.union(secondBox)
                let unionCenterDistance = distance(
                    CGPoint(x:union.midX, y:union.midY),
                    CGPoint(x:0.5, y:0.5)
                )
                let pageCenterDistance = abs(
                    firstBox.midX - secondBox.midX
                )
                let leftBox = firstBox.midX <= secondBox.midX
                    ? firstBox
                    : secondBox
                let rightBox = firstBox.midX <= secondBox.midX
                    ? secondBox
                    : firstBox
                let horizontalGap = max(
                    rightBox.minX - leftBox.maxX,
                    0
                )

                guard smallerArea / max(largerArea, 0.0001) >= 0.50,
                      overlapArea / max(smallerArea, 0.0001) <= 0.20,
                      verticalOverlapRatio >= 0.68,
                      abs(firstBox.midY - secondBox.midY) <= 0.10,
                      pageCenterDistance >= 0.16,
                      horizontalGap <= 0.12,
                      leftBox.midX < 0.52,
                      rightBox.midX > 0.48,
                      union.width >= union.height * 1.05,
                      unionCenterDistance <= 0.25 else {
                    continue
                }

                let alignmentScore = verticalOverlapRatio
                let sizeSimilarity = smallerArea
                    / max(largerArea, 0.0001)
                let pairScore = smallDocumentScore(
                    first,
                    textObservations:textObservations
                )
                    + smallDocumentScore(
                        second,
                        textObservations:textObservations
                    )
                    + alignmentScore * 0.25
                    + sizeSimilarity * 0.20
                    - unionCenterDistance * 0.15

                if pairScore > bestPairScore {
                    bestPairScore = pairScore
                    bestPair = [first, second].sorted {
                        $0.boundingBox.midX < $1.boundingBox.midX
                    }
                }
            }
        }

        return bestPair
    }


    static func mergedBookCorners(
        from rectangles:[VNRectangleObservation]
    )->ScanCorners? {
        guard rectangles.count == 2 else {
            return nil
        }

        let sorted = rectangles.sorted {
            $0.boundingBox.midX < $1.boundingBox.midX
        }
        let left = corners(from:sorted[0])
        let right = corners(from:sorted[1])

        return ScanCorners(
            topLeft:left.topLeft,
            topRight:right.topRight,
            bottomRight:right.bottomRight,
            bottomLeft:left.bottomLeft
        )
    }


    static func diagnosticDetails(
        for rectangle:VNRectangleObservation
    )->String {
        let box = rectangle.boundingBox
        let area = box.width * box.height
        let centerDistance = distance(
            CGPoint(x:box.midX, y:box.midY),
            CGPoint(x:0.5, y:0.5)
        )

        return L10n.format(
                "置信度 %.2f，画面占比 %.1f%%，中心距离 %.2f",
            rectangle.confidence,
            area * 100,
            centerDistance
        )
    }

    private static func isPlausible(
        _ rectangle:VNRectangleObservation
    )->Bool {
        let box = rectangle.boundingBox
        let boxArea = box.width * box.height
        let polygonArea = quadrilateralArea(rectangle)
        let edgeLengths = [
            distance(rectangle.topLeft, rectangle.topRight),
            distance(rectangle.topRight, rectangle.bottomRight),
            distance(rectangle.bottomRight, rectangle.bottomLeft),
            distance(rectangle.bottomLeft, rectangle.topLeft)
        ]
        let borderInset = min(
            box.minX,
            box.minY,
            1 - box.maxX,
            1 - box.maxY
        )

        guard boxArea >= 0.060,
              polygonArea >= 0.050,
              edgeLengths.min() ?? 0 >= 0.080,
              boxArea > 0,
              polygonArea / boxArea >= 0.52,
              borderInset >= 0.0015 else {
            return false
        }

        return true
    }


    private static func isSmallDocumentPlausible(
        _ rectangle:VNRectangleObservation,
        textObservations:[VNRecognizedTextObservation]
    )->Bool {
        let box = rectangle.boundingBox
        let boxArea = box.width * box.height
        let polygonArea = quadrilateralArea(rectangle)
        let edgeLengths = [
            distance(rectangle.topLeft, rectangle.topRight),
            distance(rectangle.topRight, rectangle.bottomRight),
            distance(rectangle.bottomRight, rectangle.bottomLeft),
            distance(rectangle.bottomLeft, rectangle.topLeft)
        ]
        let centerDistance = distance(
            CGPoint(x:box.midX, y:box.midY),
            CGPoint(x:0.5, y:0.5)
        )
        let containedTextCount = textObservations.filter {
            box.intersects($0.boundingBox)
        }
        .count

        guard boxArea >= 0.055,
              boxArea <= 0.82,
              polygonArea >= 0.045,
              edgeLengths.min() ?? 0 >= 0.070,
              polygonArea / max(boxArea, 0.0001) >= 0.40,
              centerDistance <= 0.48 else {
            return false
        }

        // 宽松规则必须具有文字证据；面积较大的高置信度纸张可作为备用。
        return containedTextCount >= 2
            || (
                rectangle.confidence >= 0.58
                && boxArea >= 0.065
            )
    }


    private static func smallDocumentScore(
        _ rectangle:VNRectangleObservation,
        textObservations:[VNRecognizedTextObservation]
    )->CGFloat {
        let box = rectangle.boundingBox
        let area = box.width * box.height
        let centerDistance = distance(
            CGPoint(x:box.midX, y:box.midY),
            CGPoint(x:0.5, y:0.5)
        )
        let centerScore = 1 - min(centerDistance / 0.48, 1)
        let areaScore = min(area / 0.25, 1)
        let shapeScore = min(
            quadrilateralArea(rectangle) / max(area, 0.0001),
            1
        )
        let intersectingTexts = textObservations.filter {
            box.intersects($0.boundingBox)
        }
        let textCountScore = min(
            CGFloat(intersectingTexts.count) / 10,
            1
        )
        let textArea = intersectingTexts.reduce(CGFloat.zero) {
            partial,
            observation in

            let intersection = box.intersection(
                observation.boundingBox
            )

            guard !intersection.isNull else {
                return partial
            }

            return partial + intersection.width * intersection.height
        }
        let textDensityScore = min(
            textArea / max(area * 0.08, 0.0001),
            1
        )
        let textScore = textCountScore * 0.70
            + textDensityScore * 0.30

        return textScore * 0.34
            + centerScore * 0.25
            + CGFloat(rectangle.confidence) * 0.18
            + shapeScore * 0.13
            + areaScore * 0.10
    }

    private static func score(
        _ rectangle:VNRectangleObservation,
        preferredCorners:ScanCorners?
    )->CGFloat {
        let box = rectangle.boundingBox
        let area = box.width * box.height
        let areaScore = min(area / 0.72, 1)
        let centerDistance = distance(
            CGPoint(x:box.midX, y:box.midY),
            CGPoint(x:0.5, y:0.5)
        )
        let centerScore = 1 - min(centerDistance / 0.707, 1)
        let shapeScore = min(
            quadrilateralArea(rectangle) / max(area, 0.0001),
            1
        )
        let borderInset = min(
            box.minX,
            box.minY,
            1 - box.maxX,
            1 - box.maxY
        )
        let borderScore = min(max(borderInset / 0.035, 0), 1)
        let confidenceScore = CGFloat(rectangle.confidence)

        guard let preferredCorners else {
            return areaScore * 0.35
                + centerScore * 0.18
                + confidenceScore * 0.20
                + shapeScore * 0.17
                + borderScore * 0.10
        }

        let detectedCorners = corners(from:rectangle)
        let similarity = 1 - min(
            averageCornerDistance(
                detectedCorners,
                preferredCorners
            ) / 0.20,
            1
        )

        return similarity * 0.45
            + areaScore * 0.20
            + centerScore * 0.12
            + confidenceScore * 0.10
            + shapeScore * 0.08
            + borderScore * 0.05
    }

    private static func quadrilateralArea(
        _ rectangle:VNRectangleObservation
    )->CGFloat {
        let points = [
            rectangle.topLeft,
            rectangle.topRight,
            rectangle.bottomRight,
            rectangle.bottomLeft
        ]
        var sum:CGFloat = 0

        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y
                - next.x * points[index].y
        }

        return abs(sum) / 2
    }

    private static func averageCornerDistance(
        _ first:ScanCorners,
        _ second:ScanCorners
    )->CGFloat {
        let distances = [
            distance(first.topLeft, second.topLeft),
            distance(first.topRight, second.topRight),
            distance(first.bottomRight, second.bottomRight),
            distance(first.bottomLeft, second.bottomLeft)
        ]
        return distances.reduce(0, +) / CGFloat(distances.count)
    }

    private static func distance(
        _ first:CGPoint,
        _ second:CGPoint
    )->CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
}


enum DocumentImageFilter {
    private static let context = CIContext(
        options:[.cacheIntermediates:false]
    )

    static func apply(
        _ filter:ScanPageFilter,
        to image:UIImage
    )->UIImage {
        guard filter != .color,
              let input = CIImage(image:image) else {
            return image
        }

        let smart = smartImage(from:input)
        let output:CIImage

        switch filter {
        case .smart:
            output = smart

        case .color:
            output = input

        case .blackWhite:
            let grayscale = smart.applyingFilter(
                "CIColorControls",
                parameters:[
                    kCIInputSaturationKey:0,
                    kCIInputBrightnessKey:0,
                    kCIInputContrastKey:1.05
                ]
            )

            // 压暗中间色，保留细文字、表格线和浅色笔迹。
            let preservedInk = grayscale.applyingFilter(
                "CIGammaAdjust",
                parameters:[
                    "inputPower":1.32
                ]
            )

            // 在保留中间色信息后再拉开黑白，避免先提亮造成细线丢失。
            let highContrast = preservedInk.applyingFilter(
                "CIColorControls",
                parameters:[
                    kCIInputBrightnessKey:0.012,
                    kCIInputContrastKey:1.42
                ]
            )

            let strengthenedInk = highContrast.applyingFilter(
                "CIMorphologyMinimum",
                parameters:[kCIInputRadiusKey:0.85]
            )

            output = strengthenedInk.applyingFilter(
                "CIUnsharpMask",
                parameters:[
                    kCIInputRadiusKey:0.80,
                    kCIInputIntensityKey:0.62
                ]
            )
        }

        guard let cgImage = context.createCGImage(
            output,
            from:input.extent
        ) else {
            return image
        }

        return UIImage(
            cgImage:cgImage,
            scale:image.scale,
            orientation:.up
        )
    }

    private static func smartImage(
        from input:CIImage
    )->CIImage {
        let extent = input.extent
        let average = averageLuminance(of:input)

        let noiseLevel = average < 0.55 ? 0.025 : 0.018
        let denoised = input.applyingFilter(
            "CINoiseReduction",
            parameters:[
                "inputNoiseLevel":noiseLevel,
                "inputSharpness":0.28
            ]
        )

        let blurRadius = min(
            max(min(extent.width, extent.height) * 0.035, 24),
            80
        )
        let background = denoised
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters:[kCIInputRadiusKey:blurRadius]
            )
            .cropped(to:extent)
            .applyingFilter(
                "CIColorControls",
                parameters:[kCIInputSaturationKey:0]
            )

        let normalizationStrength:CGFloat
        if average < 0.52 {
            normalizationStrength = 0.88
        } else if average < 0.72 {
            normalizationStrength = 0.76
        } else {
            normalizationStrength = 0.62
        }

        let divided = background.applyingFilter(
            "CIDivideBlendMode",
            parameters:[kCIInputBackgroundImageKey:denoised]
        )
        .cropped(to:extent)

        let normalized = denoised.applyingFilter(
            "CIDissolveTransition",
            parameters:[
                kCIInputTargetImageKey:divided,
                kCIInputTimeKey:normalizationStrength
            ]
        )
        .cropped(to:extent)

        let shadowAdjusted = normalized.applyingFilter(
            "CIHighlightShadowAdjust",
            parameters:[
                "inputShadowAmount":average < 0.58 ? 0.42 : 0.28,
                "inputHighlightAmount":0.94
            ]
        )

        let contrast = average < 0.55 ? 1.22 : 1.16
        let brightness = average < 0.55 ? 0.035 : 0.015
        let colorAdjusted = shadowAdjusted.applyingFilter(
            "CIColorControls",
            parameters:[
                kCIInputSaturationKey:1.02,
                kCIInputBrightnessKey:brightness,
                kCIInputContrastKey:contrast
            ]
        )

        return colorAdjusted.applyingFilter(
            "CIUnsharpMask",
            parameters:[
                kCIInputRadiusKey:1.25,
                kCIInputIntensityKey:0.52
            ]
        )
        .cropped(to:extent)
    }

    private static func averageLuminance(
        of image:CIImage
    )->CGFloat {
        let average = image.applyingFilter(
            "CIAreaAverage",
            parameters:[kCIInputExtentKey:CIVector(cgRect:image.extent)]
        )

        guard let cgImage = context.createCGImage(
            average,
            from:CGRect(x:0, y:0, width:1, height:1)
        ),
        let provider = cgImage.dataProvider,
        let data = provider.data,
        let bytes = CFDataGetBytePtr(data),
        CFDataGetLength(data) >= 3 else {
            return 0.72
        }

        let red = CGFloat(bytes[0]) / 255
        let green = CGFloat(bytes[1]) / 255
        let blue = CGFloat(bytes[2]) / 255

        return red * 0.2126
            + green * 0.7152
            + blue * 0.0722
    }
}


class ScanProcessor {
    
    
    static let shared =
    ScanProcessor()
    
    
    private let queue =
    DispatchQueue(
        label:"aoi.scan.processor"
    )


    private let renderContext = CIContext(
        options:[.cacheIntermediates:false]
    )
    
    
    private init(){
        ScanPage.removeStaleTemporaryFiles()
    }
    
    
    
    
    private func legacyProcess(
        image:UIImage,
        completion:
        @escaping(UIImage)->Void
    ){
        
        
        queue.async {
            
            
            autoreleasepool {
                
                
                let fixed =
                self.fixOrientation(
                    image
                )
                
                
                guard let cgImage =
                        fixed.cgImage
                else {
                    
                    DispatchQueue.main.async {
                        
                        completion(
                            fixed
                        )
                        
                    }
                    
                    return
                    
                }
                
                
                let request =
                VNDetectRectanglesRequest {
                    
                    request,error in
                    
                    
                    var result =
                    fixed
                    
                    
                    if let rectangle =
                        request.results?.first
                        as? VNRectangleObservation {
                        
                        
                        print(
                            "✅ 检测到文档"
                        )
                        
                        
                        result =
                        self.correct(
                            image:
                                fixed,
                            corners:
                                DocumentRectangleSelector.corners(
                                    from:rectangle
                                )
                        )
                        ??
                        fixed
                        
                        
                    }
                    else {
                        
                        print(
                            "⚠️ 未检测到文档"
                        )
                        
                    }
                    
                    
                    
                    result =
                    self.enhance(
                        result
                    )
                    
                    
                    DispatchQueue.main.async {
                        
                        completion(
                            result
                        )
                        
                    }
                    
                    
                }
                
                
                request.minimumConfidence =
                0.7
                
                
                request.maximumObservations =
                1
                
                
                request.minimumAspectRatio =
                0.2
                
                
                request.maximumAspectRatio =
                5.0
                
                
                request.minimumSize =
                0.2
                
                
                
                let handler =
                VNImageRequestHandler(
                    cgImage:
                        cgImage,
                    options:
                        [:]
                )
                
                
                try?
                handler.perform(
                    [request]
                )
                
                
            }
            
            
        }
        
        
    }
    
    
    
    
    
    
    // MARK: 扫描处理


    func process(
        image:UIImage,
        preferredCorners:ScanCorners? = nil,
        completion:@escaping([ScanPage])->Void
    ){
        queue.async {


            autoreleasepool {


                let fixed = self.fixOrientation(
                    image
                )


                guard let cgImage = fixed.cgImage else {
                    let page = self.makeScanPage(
                        originalImage:fixed,
                        adjustedImage:fixed,
                        detectedCorners:nil,
                        suggestedCropCorners:nil
                    )

                    DispatchQueue.main.async {
                        completion([page])
                    }

                    return

                }


                let rectangle = self.detectRectangle(
                    in:cgImage
                )


                var result = fixed
                var detectedCorners:ScanCorners?
                var suggestedCropCorners:ScanCorners?


                if let rectangle {

                    print("✅ 高分辨率严格识别到纸张")

                    let selectedCorners = self.insetCorners(
                        DocumentRectangleSelector.corners(
                            from:rectangle
                        )
                    )
                    detectedCorners = selectedCorners

                    result = self.correct(
                        image:fixed,
                        corners:selectedCorners
                    ) ?? fixed

                    RecognitionLogStore.shared.add(
                        category:"严格识别",
                        message:"识别并校准纸张成功",
                        details:DocumentRectangleSelector
                            .diagnosticDetails(for:rectangle)
                    )

                }
                else {

                    // 低分辨率预览的结果只在严格高分辨率识别失败时作为备用。
                    // 它必须已经通过连续多帧稳定性检查和几何检查。
                    if let preferredCorners,
                       self.cornersAreUsable(preferredCorners) {

                        let selectedCorners = self.insetCorners(
                            preferredCorners
                        )

                        if let corrected = self.correct(
                            image:fixed,
                            corners:selectedCorners
                        ){

                            detectedCorners = selectedCorners
                            result = corrected

                            print("✅ 高分辨率识别未命中，已使用连续稳定的纸张定位")

                            RecognitionLogStore.shared.add(
                                category:"连续帧定位",
                                message:"严格识别未命中，使用拍摄前稳定定位校准成功",
                                details:self.cornerDiagnosticDetails(
                                    selectedCorners
                                )
                            )

                        }
                        else {

                            print("⚠️ 备用纸张定位无法校正，请在预览中手动调整")

                            RecognitionLogStore.shared.add(
                                level:"警告",
                                category:"连续帧定位",
                                message:"稳定定位无法完成透视校准"
                            )

                        }

                    }


                    // 只有严格识别和连续帧定位均未成功时，才运行宽松兜底。
                    if case nil = detectedCorners,
                       RecognitionSettings.smallDocumentFallbackEnabled {

                        var fallback = self.detectSmallDocument(
                            in:cgImage
                        )

                        if fallback.selectedRectangles.isEmpty {
                            let enhanced = self.detectEnhancedDocument(
                                in:cgImage,
                                textObservations:fallback.textObservations,
                                suggestedCropCorners:
                                    fallback.suggestedCropCorners
                            )

                            fallback = SmallDocumentDetectionResult(
                                selectedRectangles:
                                    enhanced.selectedRectangles,
                                suggestedCropCorners:
                                    fallback.suggestedCropCorners
                                        ?? enhanced.suggestedCropCorners,
                                rectangleCandidateCount:
                                    fallback.rectangleCandidateCount
                                        + enhanced.rectangleCandidateCount,
                                textObservationCount:
                                    fallback.textObservationCount,
                                textObservations:
                                    fallback.textObservations,
                                detectionSource:
                                    enhanced.detectionSource
                            )
                        }

                        suggestedCropCorners = fallback
                            .suggestedCropCorners

                        if fallback.selectedRectangles.count == 2,
                           let mergedCorners = DocumentRectangleSelector
                            .mergedBookCorners(
                                from:fallback.selectedRectangles
                            ) {
                            let selectedCorners = self.insetCorners(
                                mergedCorners
                            )

                            if self.cornersAreUsable(selectedCorners),
                               let corrected = self.correct(
                                image:fixed,
                                corners:selectedCorners
                               ) {
                                detectedCorners = selectedCorners
                                result = corrected

                                print("✅ 识别到摊开书本，已忽略中缝并合并外框")

                                RecognitionLogStore.shared.add(
                                    category:"书本合并",
                                    message:"识别到左右书页，已合并为一个完整裁切范围",
                                    details:L10n.format(
                                        "来源 %@，矩形候选 %d 个，文字区域 %d 个；%@",
                                        L10n.text(fallback.detectionSource),
                                        fallback.rectangleCandidateCount,
                                        fallback.textObservationCount,
                                        self.cornerDiagnosticDetails(selectedCorners)
                                    )
                                )
                            }
                            else {
                                RecognitionLogStore.shared.add(
                                    level:"警告",
                                    category:"书本合并",
                                    message:"找到左右书页，但合并后的外框无法完成校准",
                                    details:L10n.format(
                                        "来源 %@，矩形候选 %d 个",
                                        L10n.text(fallback.detectionSource),
                                        fallback.rectangleCandidateCount
                                    )
                                )
                            }
                        }

                        if case nil = detectedCorners,
                           fallback.selectedRectangles.count == 1,
                           let rectangle = fallback
                            .selectedRectangles.first {
                            let selectedCorners = self.insetCorners(
                                DocumentRectangleSelector.corners(
                                    from:rectangle
                                )
                            )

                            if let corrected = self.correct(
                                image:fixed,
                                corners:selectedCorners
                            ) {
                                detectedCorners = selectedCorners
                                result = corrected

                                print("✅ 书页/小文档兜底识别成功")

                                RecognitionLogStore.shared.add(
                                    category:fallback.detectionSource
                                        == "原图兜底"
                                        ? "书页兜底"
                                        : "增强识别",
                                    message:"识别并校准单页书页或小文档成功",
                                    details:L10n.format(
                                        "来源 %@，矩形候选 %d 个，文字区域 %d 个；%@",
                                        L10n.text(fallback.detectionSource),
                                        fallback.rectangleCandidateCount,
                                        fallback.textObservationCount,
                                        DocumentRectangleSelector
                                            .diagnosticDetails(for:rectangle)
                                    )
                                )
                            }
                            else {
                                RecognitionLogStore.shared.add(
                                    level:"警告",
                                    category:"书页兜底",
                                    message:"找到候选书页，但透视校准失败",
                                    details:L10n.format(
                                        "来源 %@，矩形候选 %d 个，文字区域 %d 个",
                                        L10n.text(fallback.detectionSource),
                                        fallback.rectangleCandidateCount,
                                        fallback.textObservationCount
                                    )
                                )
                            }
                        }

                        if case nil = detectedCorners {
                            print("⚠️ 未检测到完整纸张，请在预览中手动调整")

                            let failureMessage = suggestedCropCorners.map {
                                _ in
                                "未找到完整纸张，已根据文字区域生成手动裁切初始框"
                            }
                            ?? "未找到可用纸张，进入手动裁切"

                            RecognitionLogStore.shared.add(
                                level:"警告",
                                category:"识别失败",
                                message:failureMessage,
                                details:L10n.format(
                                    fallback.rectangleCandidateCount > 0
                                        ? "已尝试原图及增强通道；矩形候选 %d 个，文字区域 %d 个；候选未通过中心位置、几何形状或文字证据检查"
                                        : "已尝试原图及增强通道；矩形候选 %d 个，文字区域 %d 个；Vision 未检测到矩形候选",
                                    fallback.rectangleCandidateCount,
                                    fallback.textObservationCount
                                )
                            )
                        }
                    }
                    else if case nil = detectedCorners {
                        print("⚠️ 未检测到完整纸张，请在预览中手动调整")

                        RecognitionLogStore.shared.add(
                            level:"警告",
                            category:"识别失败",
                            message:"严格识别未命中，书页与小文档兜底已关闭"
                        )
                    }

                }


                let page = self.makeScanPage(
                    originalImage:fixed,
                    adjustedImage:result,
                    detectedCorners:detectedCorners,
                    suggestedCropCorners:suggestedCropCorners
                )


                DispatchQueue.main.async {
                    completion([page])
                }


            }


        }


    }


    func detectAutomaticCropCorners(
        in image:UIImage,
        completion:@escaping(ScanCorners?)->Void
    ) {
        queue.async {
            autoreleasepool {
                let fixed = self.fixOrientation(image)

                guard let cgImage = fixed.cgImage else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }

                var selectedCorners:ScanCorners?

                if let rectangle = self.detectRectangle(
                    in:cgImage
                ) {
                    selectedCorners = DocumentRectangleSelector
                        .corners(from:rectangle)
                }
                else if RecognitionSettings
                    .smallDocumentFallbackEnabled {
                    var fallback = self.detectSmallDocument(
                        in:cgImage
                    )

                    if fallback.selectedRectangles.isEmpty {
                        let enhanced = self.detectEnhancedDocument(
                            in:cgImage,
                            textObservations:
                                fallback.textObservations,
                            suggestedCropCorners:
                                fallback.suggestedCropCorners
                        )

                        fallback = SmallDocumentDetectionResult(
                            selectedRectangles:
                                enhanced.selectedRectangles,
                            suggestedCropCorners:
                                fallback.suggestedCropCorners
                                    ?? enhanced.suggestedCropCorners,
                            rectangleCandidateCount:
                                fallback.rectangleCandidateCount
                                    + enhanced.rectangleCandidateCount,
                            textObservationCount:
                                fallback.textObservationCount,
                            textObservations:
                                fallback.textObservations,
                            detectionSource:
                                enhanced.detectionSource
                        )
                    }

                    if fallback.selectedRectangles.count == 2 {
                        selectedCorners = DocumentRectangleSelector
                            .mergedBookCorners(
                                from:fallback.selectedRectangles
                            )
                    }
                    else if let rectangle = fallback
                        .selectedRectangles.first {
                        selectedCorners = DocumentRectangleSelector
                            .corners(from:rectangle)
                    }
                    else {
                        selectedCorners = fallback
                            .suggestedCropCorners
                    }
                }

                let usableCorners = selectedCorners.map {
                    self.insetCorners($0)
                }
                .flatMap {
                    self.cornersAreUsable($0) ? $0 : nil
                }

                DispatchQueue.main.async {
                    completion(usableCorners)
                }
            }
        }
    }


    private func makeScanPage(
        originalImage:UIImage,
        adjustedImage:UIImage,
        detectedCorners:ScanCorners?,
        suggestedCropCorners:ScanCorners?
    )->ScanPage {
        let previewImage = DocumentImageFilter.apply(
            .smart,
            to:adjustedImage
        )
        var page = ScanPage(
            originalImage:originalImage,
            adjustedImage:adjustedImage,
            previewImage:previewImage,
            detectedCorners:detectedCorners,
            suggestedCropCorners:suggestedCropCorners,
            filter:.smart
        )

        do {
            try page.storeInTemporaryFiles()
        }
        catch {
            print("扫描页临时保存失败:", error)

            RecognitionLogStore.shared.add(
                level:"警告",
                category:"临时文件",
                message:"扫描页临时保存失败",
                details:error.localizedDescription
            )
        }

        return page
    }




    private func detectRectangle(
        in image:CGImage
    )->VNRectangleObservation? {


        let request = VNDetectRectanglesRequest()

        request.minimumConfidence = 0.62
        request.maximumObservations = 8
        request.minimumAspectRatio = 0.12
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.16
        request.quadratureTolerance = 30


        let handler = VNImageRequestHandler(
            cgImage:image,
            orientation:.up,
            options:[:]
        )


        do {

            try handler.perform([request])

            return DocumentRectangleSelector.best(
                in:request.results ?? []
            )

        }
        catch {

            print(
                "文档检测失败:",
                error
            )

            RecognitionLogStore.shared.add(
                level:"警告",
                category:"严格识别",
                message:"Vision 文档检测请求失败",
                details:error.localizedDescription
            )

            return nil

        }


    }


    private func detectSmallDocument(
        in image:CGImage
    )->SmallDocumentDetectionResult {
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.minimumConfidence = 0.42
        rectangleRequest.maximumObservations = 8
        rectangleRequest.minimumAspectRatio = 0.10
        rectangleRequest.maximumAspectRatio = 1.0
        rectangleRequest.minimumSize = 0.055
        rectangleRequest.quadratureTolerance = 42

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        textRequest.minimumTextHeight = 0.006

        let handler = VNImageRequestHandler(
            cgImage:image,
            orientation:.up,
            options:[:]
        )

        do {
            try handler.perform([
                rectangleRequest,
                textRequest
            ])

            let rectangles = rectangleRequest.results ?? []
            let texts = textRequest.results ?? []
            let selectedPair = DocumentRectangleSelector
                .bestBookPagePair(
                    in:rectangles,
                    textObservations:texts
                )
            let selectedSingle = DocumentRectangleSelector
                .bestSmallDocument(
                    in:rectangles,
                    textObservations:texts
                )
            let selectedRectangles = selectedPair
                ?? selectedSingle.map { [$0] }
                ?? []

            return SmallDocumentDetectionResult(
                selectedRectangles:selectedRectangles,
                suggestedCropCorners:estimatedCropCorners(
                    from:texts
                ),
                rectangleCandidateCount:rectangles.count,
                textObservationCount:texts.count,
                textObservations:texts,
                detectionSource:"原图兜底"
            )
        }
        catch {
            RecognitionLogStore.shared.add(
                level:"警告",
                category:"书页兜底",
                message:"宽松识别请求失败",
                details:error.localizedDescription
            )

            return SmallDocumentDetectionResult(
                selectedRectangles:[],
                suggestedCropCorners:nil,
                rectangleCandidateCount:0,
                textObservationCount:0,
                textObservations:[],
                detectionSource:"原图兜底"
            )
        }
    }


    private func detectEnhancedDocument(
        in image:CGImage,
        textObservations:[VNRecognizedTextObservation],
        suggestedCropCorners:ScanCorners?
    )->SmallDocumentDetectionResult {
        let variants = enhancedDetectionVariants(
            from:image
        )
        var channelResults:[(
            name:String,
            rectangles:[VNRectangleObservation]
        )] = []

        for variant in variants {
            guard let rendered = renderContext.createCGImage(
                variant.image,
                from:variant.image.extent
            ) else {
                continue
            }

            let request = VNDetectRectanglesRequest()
            request.minimumConfidence = 0.30
            request.maximumObservations = 12
            request.minimumAspectRatio = 0.08
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.045
            request.quadratureTolerance = 48

            let handler = VNImageRequestHandler(
                cgImage:rendered,
                orientation:.up,
                options:[:]
            )

            do {
                try handler.perform([request])
                channelResults.append((
                    name:variant.name,
                    rectangles:request.results ?? []
                ))
            }
            catch {
                continue
            }
        }

        let rectangles = channelResults.flatMap {
            $0.rectangles
        }
        let selectedPair = DocumentRectangleSelector
            .bestBookPagePair(
                in:rectangles,
                textObservations:textObservations
            )
        let selectedSingle = DocumentRectangleSelector
            .bestSmallDocument(
                in:rectangles,
                textObservations:textObservations
            )
        let selectedRectangles = selectedPair
            ?? selectedSingle.map { [$0] }
            ?? []

        let sourceNames = channelResults.compactMap { channel in
            selectedRectangles.contains { selected in
                channel.rectangles.contains { candidate in
                    candidate === selected
                }
            }
                ? channel.name
                : nil
        }
        let detectionSource = sourceNames.isEmpty
            ? "增强多通道"
            : sourceNames.joined(separator:"+")

        return SmallDocumentDetectionResult(
            selectedRectangles:selectedRectangles,
            suggestedCropCorners:suggestedCropCorners,
            rectangleCandidateCount:rectangles.count,
            textObservationCount:textObservations.count,
            textObservations:textObservations,
            detectionSource:detectionSource
        )
    }


    private func enhancedDetectionVariants(
        from image:CGImage
    )->[(name:String, image:CIImage)] {
        let input = CIImage(cgImage:image)
        let longestSide = CGFloat(
            max(image.width, image.height)
        )
        let scale = min(1, 1800 / max(longestSide, 1))
        let base:CIImage

        if scale < 1 {
            base = input.applyingFilter(
                "CILanczosScaleTransform",
                parameters:[
                    kCIInputScaleKey:scale,
                    kCIInputAspectRatioKey:1.0
                ]
            )
        }
        else {
            base = input
        }

        func strengthen(_ image:CIImage)->CIImage {
            let enhanced = image
                .applyingFilter(
                    "CIColorControls",
                    parameters:[
                        kCIInputSaturationKey:0,
                        kCIInputBrightnessKey:0,
                        kCIInputContrastKey:1.38
                    ]
                )
                .applyingFilter(
                    "CIUnsharpMask",
                    parameters:[
                        kCIInputRadiusKey:1.6,
                        kCIInputIntensityKey:0.70
                    ]
                )

            return enhanced.cropped(to:image.extent)
        }

        func channelImage(
            _ vector:CIVector
        )->CIImage {
            let channel = base.applyingFilter(
                "CIColorMatrix",
                parameters:[
                    "inputRVector":vector,
                    "inputGVector":vector,
                    "inputBVector":vector,
                    "inputAVector":CIVector(
                        x:0,
                        y:0,
                        z:0,
                        w:1
                    ),
                    "inputBiasVector":CIVector(
                        x:0,
                        y:0,
                        z:0,
                        w:0
                    )
                ]
            )

            return strengthen(channel)
        }

        let grayscale = strengthen(
            base.applyingFilter(
                "CIColorControls",
                parameters:[
                    kCIInputSaturationKey:0,
                    kCIInputBrightnessKey:0.01,
                    kCIInputContrastKey:1.15
                ]
            )
            .applyingFilter(
                "CIHighlightShadowAdjust",
                parameters:[
                    "inputHighlightAmount":0.82,
                    "inputShadowAmount":0.18
                ]
            )
        )

        return [
            ("增强灰度", grayscale),
            (
                "红色通道",
                channelImage(
                    CIVector(x:1, y:0, z:0, w:0)
                )
            ),
            (
                "绿色通道",
                channelImage(
                    CIVector(x:0, y:1, z:0, w:0)
                )
            ),
            (
                "蓝色通道",
                channelImage(
                    CIVector(x:0, y:0, z:1, w:0)
                )
            )
        ]
    }


    private func estimatedCropCorners(
        from observations:[VNRecognizedTextObservation]
    )->ScanCorners? {
        var centeredBoxes:[CGRect] = []

        for observation in observations {
            let box = observation.boundingBox
            let hasUsableSize = box.width >= 0.006
                && box.height >= 0.006
            let isNearCenter = box.midX >= 0.10
                && box.midX <= 0.90
                && box.midY >= 0.10
                && box.midY <= 0.90

            if hasUsableSize && isNearCenter {
                centeredBoxes.append(box)
            }
        }

        guard centeredBoxes.count >= 2 else {
            return nil
        }

        let union = centeredBoxes.dropFirst().reduce(
            centeredBoxes[0]
        ) { partial, box in
            partial.union(box)
        }

        guard union.width * union.height >= 0.012,
              union.width * union.height <= 0.75 else {
            return nil
        }

        let horizontalPadding = max(union.width * 0.18, 0.035)
        let verticalPadding = max(union.height * 0.20, 0.035)
        let expandedMinX = max(
            union.minX - horizontalPadding,
            0.02
        )
        let expandedMinY = max(
            union.minY - verticalPadding,
            0.02
        )
        let expandedWidth = min(
            union.width + horizontalPadding * 2,
            0.98 - expandedMinX
        )
        let expandedHeight = min(
            union.height + verticalPadding * 2,
            0.98 - expandedMinY
        )
        let expanded = CGRect(
            x:expandedMinX,
            y:expandedMinY,
            width:expandedWidth,
            height:expandedHeight
        )

        return ScanCorners(
            topLeft:CGPoint(
                x:expanded.minX,
                y:1 - expanded.maxY
            ),
            topRight:CGPoint(
                x:expanded.maxX,
                y:1 - expanded.maxY
            ),
            bottomRight:CGPoint(
                x:expanded.maxX,
                y:1 - expanded.minY
            ),
            bottomLeft:CGPoint(
                x:expanded.minX,
                y:1 - expanded.minY
            )
        )
    }


    private func cornerDiagnosticDetails(
        _ corners:ScanCorners
    )->String {
        let points = [
            corners.topLeft,
            corners.topRight,
            corners.bottomRight,
            corners.bottomLeft
        ]
        var area:CGFloat = 0

        for index in points.indices {
            let next = points[(index + 1) % points.count]
            area += points[index].x * next.y
                - next.x * points[index].y
        }

        return L10n.format(
            "画面占比 %.1f%%",
            abs(area) * 50
        )
    }


    private func insetCorners(
        _ corners:ScanCorners
    )->ScanCorners {
        let center = CGPoint(
            x:(corners.topLeft.x
                + corners.topRight.x
                + corners.bottomRight.x
                + corners.bottomLeft.x) / 4,
            y:(corners.topLeft.y
                + corners.topRight.y
                + corners.bottomRight.y
                + corners.bottomLeft.y) / 4
        )

        func inset(_ point:CGPoint)->CGPoint {
            // 仅保留轻微的安全内缩，避免吃掉纸张边缘。
            let amount:CGFloat = 0.002
            return CGPoint(
                x:point.x + (center.x - point.x) * amount,
                y:point.y + (center.y - point.y) * amount
            )
        }

        return ScanCorners(
            topLeft:inset(corners.topLeft),
            topRight:inset(corners.topRight),
            bottomRight:inset(corners.bottomRight),
            bottomLeft:inset(corners.bottomLeft)
        )
    }


    private func cornersAreUsable(
        _ corners:ScanCorners
    )->Bool {
        let points = [
            corners.topLeft,
            corners.topRight,
            corners.bottomRight,
            corners.bottomLeft
        ]
        guard points.allSatisfy({
            $0.x >= 0 && $0.x <= 1
                && $0.y >= 0 && $0.y <= 1
        }) else {
            return false
        }

        var area:CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            area += points[index].x * next.y
                - next.x * points[index].y
        }

        return abs(area) / 2 >= 0.03
    }




    // MARK: 修正方向
    
    
    private func fixOrientation(
        _ image:UIImage
    )->UIImage {
        
        
        if image.imageOrientation == .up {
            
            return image
            
        }
        
        
        UIGraphicsBeginImageContextWithOptions(
            image.size,
            false,
            image.scale
        )
        
        
        image.draw(
            at:.zero
        )
        
        
        let fixed =
        UIGraphicsGetImageFromCurrentImageContext()
        
        
        UIGraphicsEndImageContext()
        
        
        return fixed ?? image
        
        
    }
    
    
    
    
    
    
    // MARK: 透视矫正
    
    
    private func correct(
        image:UIImage,
        corners:ScanCorners
    )->UIImage? {
        
        
        guard let ciImage =
                CIImage(
                    image:image
                )
        else {
            
            return nil
            
        }
        
        
        let width =
        ciImage.extent.width
        
        
        let height =
        ciImage.extent.height
        
        
        
        
        func point(
            _ p:CGPoint
        )->CIVector {
            
            
            CIVector(
                
                x:
                    p.x * width,
                
                y:
                    (1 - p.y) * height
                
            )
            
            
        }
        
        
        
        
        let filter =
        CIFilter(
            name:
                "CIPerspectiveCorrection"
        )
        
        
        filter?.setValue(
            ciImage,
            forKey:
                kCIInputImageKey
        )
        
        
        filter?.setValue(
            point(corners.topLeft),
            forKey:
                "inputTopLeft"
        )
        
        
        filter?.setValue(
            point(corners.topRight),
            forKey:
                "inputTopRight"
        )
        
        
        filter?.setValue(
            point(corners.bottomLeft),
            forKey:
                "inputBottomLeft"
        )
        
        
        filter?.setValue(
            point(corners.bottomRight),
            forKey:
                "inputBottomRight"
        )
        
        
        guard let output =
                filter?.outputImage
        else {
            
            return nil
            
        }
        
        
        guard let cg =
                renderContext.createCGImage(
                    output,
                    from:
                        output.extent
                )
        else {
            
            return nil
            
        }
        
        
        return UIImage(
            cgImage:
                cg
        )
        
        
    }
    
    
    
    
    
    
    // MARK: 扫描增强
    
    
    private func enhance(
        _ image:UIImage
    )->UIImage {
        DocumentImageFilter.apply(
            .smart,
            to:image
        )
    }
    
    
}


// MARK: - Text Recognition

private enum TextRecognitionError:LocalizedError {
    case invalidImage
    case noTextFound

    var errorDescription:String? {
        switch self {
        case .invalidImage:
            return L10n.text("无法读取当前图片")
        case .noTextFound:
            return L10n.text("当前页面没有识别到文字")
        }
    }
}


enum LocalTextRecognizer {
    private static let interactiveQueue = DispatchQueue(
        label:"aoi.scan.text-recognition",
        qos:.userInitiated
    )

    private static let backgroundQueue = DispatchQueue(
        label:"aoi.scan.text-indexing",
        qos:.utility
    )

    static func recognize(
        image:UIImage,
        background:Bool = false,
        completion:@escaping (Result<String,Error>)->Void
    ) {
        guard let cgImage = image.cgImage else {
            completion(.failure(TextRecognitionError.invalidImage))
            return
        }

        let queue = background
            ? backgroundQueue
            : interactiveQueue

        queue.async {
            autoreleasepool {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        completion(.failure(error))
                        return
                    }

                    let observations = (
                        request.results as? [VNRecognizedTextObservation]
                    ) ?? []

                    let ordered = observations.sorted { first, second in
                        let verticalDifference = abs(
                            first.boundingBox.midY
                                - second.boundingBox.midY
                        )

                        if verticalDifference > 0.02 {
                            return first.boundingBox.midY
                                > second.boundingBox.midY
                        }

                        return first.boundingBox.minX
                            < second.boundingBox.minX
                    }

                    let text = ordered.compactMap {
                        $0.topCandidates(1).first?.string
                    }
                    .joined(separator:"\n")
                    .trimmingCharacters(in:.whitespacesAndNewlines)

                    guard !text.isEmpty else {
                        completion(
                            .failure(TextRecognitionError.noTextFound)
                        )
                        return
                    }

                    completion(.success(text))
                }

                request.recognitionLevel = .accurate
                request.recognitionLanguages = [
                    "zh-Hans",
                    "zh-Hant",
                    "en-US"
                ]
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(
                    cgImage:cgImage,
                    orientation:.up,
                    options:[:]
                )

                do {
                    try handler.perform([request])
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
}


struct TextRecognitionView:View {
    private struct TextShareItem:Identifiable {
        let id = UUID()
        let url:URL
    }

    private let images:[UIImage]
    private let onSave:(Int,String)->Void

    @State private var pageIndex:Int
    @State private var text:String
    @State private var pageTexts:[Int:String]
    @State private var loadedPages:Set<Int>
    @State private var isRecognizing = false
    @State private var errorMessage:String?
    @State private var copied = false
    @State private var textShareItem:TextShareItem?

    @Environment(\.dismiss)
    private var dismiss

    init(
        images:[UIImage],
        initialPage:Int,
        initialTexts:[Int:String],
        onSave:@escaping (Int,String)->Void
    ) {
        let safePage = images.isEmpty
            ? 0
            : min(max(initialPage, 0), images.count - 1)

        self.images = images
        self.onSave = onSave
        _pageIndex = State(initialValue:safePage)
        _text = State(initialValue:initialTexts[safePage] ?? "")
        _pageTexts = State(initialValue:initialTexts)
        _loadedPages = State(
            initialValue:Set(initialTexts.keys)
        )
    }

    var body:some View {
        NavigationStack {
            VStack(spacing:0) {
                ZStack {
                    TextEditor(text:$text)
                        .font(.body)
                        .padding(12)
                        .disabled(isRecognizing)

                    if isRecognizing {
                        Color.white.opacity(0.82)

                        VStack(spacing:12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("正在识别文字…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                HStack(spacing:16) {
                    Button {
                        recognizeText()
                    } label: {
                        Label("重新识别", systemImage:"text.viewfinder")
                    }
                    .disabled(isRecognizing)

                    Spacer()

                    if copied {
                        Label("已复制", systemImage:"checkmark")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }

                    Button {
                        UIPasteboard.general.string = text
                        copied = true

                        DispatchQueue.main.asyncAfter(
                            deadline:.now() + 1.5
                        ) {
                            copied = false
                        }
                    } label: {
                        Label("复制全部", systemImage:"doc.on.doc")
                    }
                    .disabled(text.isEmpty)
                }
                .padding(.horizontal,20)
                .frame(height:64)
                .background(Color(.secondarySystemBackground))

                if images.count > 1 {
                    Divider()

                    HStack(spacing:12) {
                        Button {
                            changePage(by:-1)
                        } label: {
                            Label(
                                "上一页",
                                systemImage:"chevron.left"
                            )
                        }
                        .disabled(
                            pageIndex <= 0 || isRecognizing
                        )

                        Spacer()

                        Text(pageDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            changePage(by:1)
                        } label: {
                            HStack(spacing:5) {
                                Text("下一页")
                                Image(systemName:"chevron.right")
                            }
                        }
                        .disabled(
                            pageIndex >= images.count - 1
                                || isRecognizing
                        )
                    }
                    .padding(.horizontal,20)
                    .frame(height:58)
                    .background(Color(.secondarySystemBackground))
                }
            }
            .navigationTitle("文字识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement:.topBarTrailing) {
                    Button {
                        prepareTextFileForSharing()
                    } label: {
                        Image(systemName:"square.and.arrow.up")
                    }
                    .accessibilityLabel("分享文字")
                    .disabled(
                        text.trimmingCharacters(
                            in:.whitespacesAndNewlines
                        ).isEmpty
                    )

                    Button("完成") {
                        saveCurrentPage()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(isRecognizing)
                }
            }
            .alert(
                "操作失败",
                isPresented:Binding(
                    get:{ errorMessage != nil },
                    set:{ if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role:.cancel) {}
            } message: {
                Text(
                    errorMessage
                    ?? L10n.text("无法完成当前操作")
                )
            }
        }
        .sheet(item:$textShareItem) { item in
            ShareSheet(activityItems:[item.url])
        }
        .onAppear {
            if !loadedPages.contains(pageIndex) {
                recognizeText()
            }
        }
    }

    private var pageDescription:String {
        guard !images.isEmpty else {
            return L10n.text("没有页面")
        }

        return L10n.format(
            "第 %@ 页 / 共 %@ 页",
            String(pageIndex + 1),
            String(images.count)
        )
    }

    private func prepareTextFileForSharing() {
        let trimmedText = text.trimmingCharacters(
            in:.whitespacesAndNewlines
        )
        guard !trimmedText.isEmpty else { return }

        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "AoiScanTextShare",
                    isDirectory:true
                )
            try FileManager.default.createDirectory(
                at:directory,
                withIntermediateDirectories:true
            )

            let fileName = images.count > 1
                ? L10n.format(
                    "识别文字-第%@页.txt",
                    String(pageIndex + 1)
                )
                : L10n.text("识别文字.txt")
            let fileURL = directory.appendingPathComponent(fileName)
            try text.write(
                to:fileURL,
                atomically:true,
                encoding:.utf8
            )
            textShareItem = TextShareItem(url:fileURL)
        } catch {
            errorMessage = L10n.format(
                "无法创建文字分享文件：%@",
                error.localizedDescription
            )
        }
    }

    private func saveCurrentPage() {
        pageTexts[pageIndex] = text
        loadedPages.insert(pageIndex)
        onSave(pageIndex, text)
    }

    private func changePage(by offset:Int) {
        let newPage = pageIndex + offset

        guard images.indices.contains(newPage),
              !isRecognizing else {
            return
        }

        saveCurrentPage()

        pageIndex = newPage
        text = pageTexts[newPage] ?? ""
        errorMessage = nil
        copied = false

        if !loadedPages.contains(newPage) {
            recognizeText()
        }
    }

    private func recognizeText() {
        guard !isRecognizing,
              images.indices.contains(pageIndex) else {
            return
        }

        let recognitionPage = pageIndex
        isRecognizing = true
        errorMessage = nil
        copied = false

        LocalTextRecognizer.recognize(
            image:images[recognitionPage]
        ) { result in
            DispatchQueue.main.async {
                guard recognitionPage == pageIndex else {
                    return
                }

                isRecognizing = false
                loadedPages.insert(recognitionPage)

                switch result {
                case .success(let recognizedText):
                    text = recognizedText
                    pageTexts[recognitionPage] = recognizedText
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}


// MARK: - Zoomable Scan Image

final class DocumentZoomScrollView:UIScrollView {
    let documentImageView = UIImageView()

    private var requiresImageLayout = true
    private var previousBoundsSize:CGSize = .zero

    override init(frame:CGRect) {
        super.init(frame:frame)

        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        alwaysBounceHorizontal = false
        alwaysBounceVertical = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        clipsToBounds = true

        documentImageView.contentMode = .scaleAspectFit
        documentImageView.clipsToBounds = true
        documentImageView.isAccessibilityElement = true
        documentImageView.accessibilityLabel = L10n.text("扫描图片")
        addSubview(documentImageView)
    }

    required init?(coder:NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setDocumentImage(
        _ image:UIImage,
        resetZoom:Bool
    ) {
        guard documentImageView.image !== image else {
            return
        }

        documentImageView.image = image
        requiresImageLayout = true

        if resetZoom {
            setZoomScale(minimumZoomScale, animated:false)
        }

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard bounds.width > 0,
              bounds.height > 0,
              let image = documentImageView.image,
              image.size.width > 0,
              image.size.height > 0 else {
            return
        }

        if requiresImageLayout || previousBoundsSize != bounds.size {
            setZoomScale(minimumZoomScale, animated:false)

            let fitScale = min(
                bounds.width / image.size.width,
                bounds.height / image.size.height
            )
            let fittedSize = CGSize(
                width:image.size.width * fitScale,
                height:image.size.height * fitScale
            )

            documentImageView.transform = .identity
            documentImageView.frame = CGRect(
                origin:.zero,
                size:fittedSize
            )
            contentSize = fittedSize

            previousBoundsSize = bounds.size
            requiresImageLayout = false
        }

        updateCenteringInsets()
    }

    func updateCenteringInsets() {
        let horizontal = max(
            (bounds.width - contentSize.width) / 2,
            0
        )
        let vertical = max(
            (bounds.height - contentSize.height) / 2,
            0
        )

        let insets = UIEdgeInsets(
            top:vertical,
            left:horizontal,
            bottom:vertical,
            right:horizontal
        )

        if contentInset != insets {
            contentInset = insets
        }
    }
}


struct ZoomableImageView:UIViewRepresentable {
    let image:UIImage
    var maximumZoomScale:CGFloat = 5

    func makeCoordinator()->Coordinator {
        Coordinator()
    }

    func makeUIView(
        context:Context
    )->DocumentZoomScrollView {
        let scrollView = DocumentZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = maximumZoomScale
        scrollView.panGestureRecognizer.isEnabled = false

        let doubleTap = UITapGestureRecognizer(
            target:context.coordinator,
            action:#selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.scrollView = scrollView
        scrollView.setDocumentImage(image, resetZoom:true)

        return scrollView
    }

    func updateUIView(
        _ scrollView:DocumentZoomScrollView,
        context:Context
    ) {
        scrollView.maximumZoomScale = maximumZoomScale
        scrollView.setDocumentImage(image, resetZoom:true)
    }

    final class Coordinator:NSObject,UIScrollViewDelegate {
        weak var scrollView:DocumentZoomScrollView?

        func viewForZooming(
            in scrollView:UIScrollView
        )->UIView? {
            self.scrollView?.documentImageView
        }

        func scrollViewDidZoom(
            _ scrollView:UIScrollView
        ) {
            guard let documentScrollView = self.scrollView else {
                return
            }

            documentScrollView.updateCenteringInsets()
            documentScrollView.panGestureRecognizer.isEnabled =
                scrollView.zoomScale
                    > scrollView.minimumZoomScale + 0.01
        }

        @objc func handleDoubleTap(
            _ gesture:UITapGestureRecognizer
        ) {
            guard let scrollView else { return }

            if scrollView.zoomScale
                > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(
                    scrollView.minimumZoomScale,
                    animated:true
                )
                return
            }

            let targetScale = min(
                2.5,
                scrollView.maximumZoomScale
            )
            let location = gesture.location(
                in:scrollView.documentImageView
            )
            let zoomSize = CGSize(
                width:scrollView.bounds.width / targetScale,
                height:scrollView.bounds.height / targetScale
            )
            let zoomRect = CGRect(
                x:location.x - zoomSize.width / 2,
                y:location.y - zoomSize.height / 2,
                width:zoomSize.width,
                height:zoomSize.height
            )

            scrollView.zoom(
                to:zoomRect,
                animated:true
            )
        }
    }
}
