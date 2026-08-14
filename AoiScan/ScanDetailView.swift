//
//  ScanDetailView.swift
//  AoiScan
//

import SwiftUI
import CoreData
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision
import ImageIO


struct ScanDetailView: View {
    
    
    let document: ScanEntity
    
    
    @State private var originalImages:[UIImage] = []
    @State private var adjustedImages:[UIImage] = []
    @State private var displayImages:[UIImage] = []

    @State private var originalImageURLs:[URL] = []
    @State private var adjustedImageURLs:[URL] = []
    @State private var displayImageURLs:[URL] = []
    @State private var detectedCorners:[ScanCorners?] = []
    @State private var pageFilters:[ScanPageFilter] = []
    
    @State private var showRenameAlert = false
    @State private var showDeleteAlert = false
    
    @State private var newName = ""
    
    @State private var shareItem: ShareItem?
    @State private var isExportingWord = false
    @State private var showWordExportError = false
    @State private var wordExportError = ""
    
    @State private var showFilterMenu = false
    @State private var showCropSheet = false
    @State private var showTextRecognition = false
    
    @State private var currentPage = 0
    @State private var detailEnhancementTokens:[Int:UUID] = [:]
    @State private var detailEnhancementBannerToken:UUID?
    @State private var detailEnhancementBannerShownAt:Date?
    @State private var showDetailEnhancementBanner = false
    
    
    @Environment(\.dismiss)
    private var dismiss
    
    
    var body: some View {
        
        VStack {
            
            ScrollView {
                
                VStack(spacing:20) {
                    
                    Text(
                        document.title ?? L10n.text("扫描文档")
                    )
                    .font(.title2)
                    .bold()
                    
                    
                    if let date = document.createdAt {
                        
                        Text(
                            Self.formattedDate(date)
                        )
                        .foregroundColor(.gray)
                        
                    }
                    
                    
                    Divider()
                    
                    
                    if displayImages.isEmpty {
                        
                        ProgressView()
                        
                    }
                    else {
                        
                        TabView(
                            selection:$currentPage
                        ) {
                            
                            ForEach(
                                0..<displayImages.count,
                                id:\.self
                            ) { index in
                                
                                ZoomableImageView(
                                    image:displayImages[index]
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius:12
                                    )
                                )
                                .id(index)
                                .tag(index)
                                
                            }
                            
                        }
                        .frame(height:420)
                        .tabViewStyle(.page)
                        .overlay(alignment:.bottom) {
                            if showDetailEnhancementBanner {
                                detailEnhancementBanner
                                    .padding(.bottom,28)
                                    .transition(
                                        .opacity.combined(
                                            with:.move(edge:.bottom)
                                        )
                                    )
                            }
                        }
                        
                    }
                    
                }
                .padding()
                
            }
            
            
            HStack(spacing:40) {
                
                
                Button {
                    
                    showFilterMenu = true
                    
                } label:{
                    
                    Image(
                        systemName:
                            "circle.lefthalf.filled"
                    )
                    .font(.title2)
                    .padding(14)
                    .background(
                        Color.blue.opacity(0.2)
                    )
                    .cornerRadius(16)
                    
                }
                
                
                
                Button {

                    if displayImages.indices.contains(
                        currentPage
                    ) {

                        showCropSheet = true

                    }
                    
                } label:{
                    
                    Image(
                        systemName:
                            "crop"
                    )
                    .font(.title2)
                    .padding(14)
                    .background(
                        Color.green.opacity(0.2)
                    )
                    .cornerRadius(16)
                    
                }
                .disabled(displayImages.isEmpty)



                Button {

                    if imageForTextRecognition(
                        at:currentPage
                    ) != nil {

                        showTextRecognition = true

                    }

                } label:{

                    Image(
                        systemName:
                            "text.viewfinder"
                    )
                    .font(.title2)
                    .padding(14)
                    .background(
                        Color.orange.opacity(0.2)
                    )
                    .cornerRadius(16)

                }
                .disabled(displayImages.isEmpty)
                
                
            }
            .padding(.bottom,30)
            .disabled(isDetailSmartEnhancing)
            
        }
        .navigationTitle("扫描详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            
            ToolbarItemGroup(
                placement:.navigationBarTrailing
            ){
                
                
                Button {
                    
                    newName =
                    document.title ?? ""
                    
                    showRenameAlert = true
                    
                } label:{
                    
                    Label(
                        "重命名",
                        systemImage:"pencil"
                    )
                    
                }
                
                
                
                Button(
                    role:.destructive
                ){
                    
                    showDeleteAlert = true
                    
                } label:{
                    
                    Label(
                        "删除",
                        systemImage:"trash"
                    )
                    
                }
                
                
                
                Menu {

                    Button {

                        guard let url = generatePDF(
                            for:document
                        ) else {
                            print("PDF生成失败")
                            return
                        }

                        shareItem = ShareItem(url:url)

                    } label: {

                        Label(
                            "分享PDF",
                            systemImage:"doc.richtext"
                        )

                    }


                    Button {

                        exportWordDocument()

                    } label: {

                        Label(
                            "导出 Word",
                            systemImage:"doc.badge.arrow.up"
                        )

                    }
                    .disabled(isExportingWord)

                } label:{

                    Label(
                        isExportingWord
                            ? L10n.text("正在导出 Word…")
                            : L10n.text("分享"),
                        systemImage:"square.and.arrow.up"
                    )

                }
                
                
            }
            
        }



        .sheet(
            isPresented:
                $showTextRecognition
        ){

            let recognitionImages = imagesForTextRecognition()

            if !recognitionImages.isEmpty {
                TextRecognitionView(
                    images:recognitionImages,
                    initialPage:currentPage,
                    initialTexts:loadRecognizedTexts(
                        pageCount:recognitionImages.count
                    ),
                    initialResults:loadOCRPageResults(
                        pageCount:recognitionImages.count
                    )
                ) { pageIndex, text, result in

                    saveRecognizedText(
                        text,
                        result:result,
                        at:pageIndex
                    )

                    currentPage = pageIndex

                }

            }

        }
        
        
        
        .onAppear {
            
            loadImages()
            
        }

        .onDisappear {

            detailEnhancementTokens.removeAll()
            detailEnhancementBannerToken = nil
            detailEnhancementBannerShownAt = nil
            showDetailEnhancementBanner = false

        }
        
        
        
        .alert(
            "重命名",
            isPresented:
                $showRenameAlert
        ){
            
            
            TextField(
                "文件名称",
                text:$newName
            )
            
            
            Button("保存"){
                
                ScanManager.shared.renameDocument(
                    document,
                    newName:newName
                )
                
            }
            
            
            Button(
                "取消",
                role:.cancel
            ){
                
            }
            
            
        }
        
        
        .alert(
            "确定删除该文件？",
            isPresented:
                $showDeleteAlert
        ){
            
            
            Button(
                "删除",
                role:.destructive
            ){
                
                ScanManager.shared.deleteDocument(
                    document
                )
                
                dismiss()
                
            }
            
            
            Button(
                "取消",
                role:.cancel
            ){
                
            }
            
            
        }


        .alert(
            "Word 导出失败",
            isPresented:$showWordExportError
        ) {

            Button("好", role:.cancel) {}

        } message: {

            Text(wordExportError)

        }
        
        
        
        .confirmationDialog(
            "选择滤镜",
            isPresented:
                $showFilterMenu
        ){
            ForEach(ScanPageFilter.allCases, id:\.self) { filter in

                Button {

                    applyFilter(
                        filter,
                        at:currentPage
                    )

                } label: {

                    if filterForPage(currentPage) == filter {
                            Label(
                                filter.localizedTitle,
                                systemImage:"checkmark"
                            )
                        }
                        else {
                            Text(filter.localizedTitle)
                    }

                }

            }

            Button("取消", role:.cancel) {}
            
        }
        
        
        
        .sheet(
            isPresented:
                $showCropSheet
        ){
            
            if let cropImage = imageForCropping(
                at:currentPage
            ) {
                
                CropSheet(
                    image:cropImage,
                    initialCorners:
                        cornersForPage(currentPage)
                ){ result in

                    applyCrop(
                        result,
                        at:currentPage
                    )
                    
                } onCancel:{
                    
                    showCropSheet = false
                    
                }
                
            }
            
        }
        
        
        
        .sheet(item: $shareItem) { item in
            ShareSheet(
                activityItems: [item.url]
            )
        }
        
        
    }
    
    
    
    
    private static func formattedDate(
        _ date:Date
    )->String {
        
        let formatter =
        DateFormatter()
        
        formatter.dateFormat =
        "yyyyMMdd HH:mm"
        
        return formatter.string(
            from:date
        )
        
    }
    
    
    
    
    private func loadImages(){
        
        guard let folder = ScanManager.shared.folderURL(
            for:document
        )
        else {
            print("无法定位扫描文件夹")
            return
            
        }
        
        do {
            
            let files =
            try FileManager.default.contentsOfDirectory(
                at:folder,
                includingPropertiesForKeys:nil
            )


            let imageFiles =
            files
                .filter {
                    $0.pathExtension.lowercased() == "jpg"
                }
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare(
                        $1.lastPathComponent
                    ) == .orderedAscending
                }
            
            
            var originalFiles:[Int:URL] = [:]
            var adjustedFiles:[Int:URL] = [:]
            var displayFiles:[Int:URL] = [:]


            for file in imageFiles {

                let name = file.deletingPathExtension()
                    .lastPathComponent

                if name.hasPrefix("original_"),
                   let pageNumber = Int(
                    name.dropFirst("original_".count)
                   ),
                   pageNumber > 0 {
                    originalFiles[pageNumber - 1] = file
                }
                else if name.hasPrefix("adjusted_"),
                        let pageNumber = Int(
                            name.dropFirst("adjusted_".count)
                        ),
                        pageNumber > 0 {
                    adjustedFiles[pageNumber - 1] = file
                }
                else if let pageNumber = Int(name),
                        pageNumber > 0 {
                    displayFiles[pageNumber - 1] = file
                }
            }


            let pageIndices = Set(originalFiles.keys)
                .union(adjustedFiles.keys)
                .union(displayFiles.keys)

            guard let lastPageIndex = pageIndices.max() else {
                return
            }

            let pageCount = lastPageIndex + 1
            let placeholder = placeholderImage()

            func firstThumbnail(
                from urls:[URL?],
                maxPixelSize:Int
            )->UIImage {

                for case let url? in urls {
                    if let image = thumbnailImage(
                        at:url,
                        maxPixelSize:maxPixelSize
                    ) {
                        return image
                    }
                }

                return placeholder
            }


            originalImages = (0..<pageCount).map { index in
                firstThumbnail(
                    from:[
                        originalFiles[index],
                        displayFiles[index],
                        adjustedFiles[index]
                    ],
                    maxPixelSize:640
                )
            }
            adjustedImages = (0..<pageCount).map { index in
                firstThumbnail(
                    from:[
                        adjustedFiles[index],
                        displayFiles[index],
                        originalFiles[index]
                    ],
                    maxPixelSize:640
                )
            }
            displayImages = (0..<pageCount).map { index in
                firstThumbnail(
                    from:[
                        displayFiles[index],
                        adjustedFiles[index],
                        originalFiles[index]
                    ],
                    maxPixelSize:1600
                )
            }

            originalImageURLs = (0..<pageCount).map { index in
                folder.appendingPathComponent(
                    "original_\(index + 1).jpg"
                )
            }
            adjustedImageURLs = (0..<pageCount).map { index in
                folder.appendingPathComponent(
                    "adjusted_\(index + 1).jpg"
                )
            }
            displayImageURLs = (0..<pageCount).map { index in
                folder.appendingPathComponent(
                    "\(index + 1).jpg"
                )
            }

            detectedCorners = loadCorners(
                from:folder,
                pageCount:pageCount
            )

            pageFilters = loadFilters(
                from:folder,
                pageCount:pageCount
            )
            
            
        }
        catch {
            
            print(error)
            
        }
        
    }




    private func cornersForPage(
        _ index:Int
    )->ScanCorners? {


        guard detectedCorners.indices.contains(index) else {
            return nil
        }


        return detectedCorners[index]


    }




    private func loadCorners(
        from folder:URL,
        pageCount:Int
    )->[ScanCorners?] {


        var result = Array<ScanCorners?>(
            repeating:nil,
            count:pageCount
        )

        let metadataURL = folder.appendingPathComponent(
            "scan_metadata.json"
        )


        guard let data = try? Data(contentsOf:metadataURL),
              let metadata = try? JSONDecoder().decode(
                [ScanPageMetadata].self,
                from:data
              ) else {

            return result

        }


        for item in metadata {

            let index = item.pageNumber - 1

            if result.indices.contains(index) {
                result[index] = item.corners
            }

        }


        return result


    }




    private func filterForPage(
        _ index:Int
    )->ScanPageFilter {


        guard pageFilters.indices.contains(index) else {
            return .smart
        }


        return pageFilters[index]


    }




    private func loadFilters(
        from folder:URL,
        pageCount:Int
    )->[ScanPageFilter] {


        var result = Array(
            repeating:ScanPageFilter.smart,
            count:pageCount
        )

        let metadataURL = folder.appendingPathComponent(
            "scan_metadata.json"
        )


        guard let data = try? Data(contentsOf:metadataURL),
              let metadata = try? JSONDecoder().decode(
                [ScanPageMetadata].self,
                from:data
              ) else {

            return result

        }


        for item in metadata {

            let index = item.pageNumber - 1

            if result.indices.contains(index),
               let filter = item.filter {
                result[index] = filter
            }

        }


        return result


    }




    private func imageForCropping(
        at index:Int
    )->UIImage? {


        let candidateURLs:[URL?] = [
            originalImageURLs.indices.contains(index)
                ? originalImageURLs[index]
                : nil,
            displayImageURLs.indices.contains(index)
                ? displayImageURLs[index]
                : nil,
            adjustedImageURLs.indices.contains(index)
                ? adjustedImageURLs[index]
                : nil
        ]

        for case let url? in candidateURLs {
            if let image = UIImage(
                contentsOfFile:url.path
            ) {
                return image
            }
        }


        if originalImages.indices.contains(index) {

            return originalImages[index]

        }


        if displayImages.indices.contains(index) {

            return displayImages[index]

        }


        return nil


    }




    private func imageForTextRecognition(
        at index:Int
    )->UIImage? {


        if displayImages.indices.contains(index) {

            return displayImages[index]

        }


        if originalImages.indices.contains(index) {

            return originalImages[index]

        }


        return nil


    }




    private func imagesForTextRecognition()->[UIImage] {


        let images = displayImages.isEmpty
            ? originalImages
            : displayImages


        return images


    }




    private func recognizedTextURL(
        at index:Int
    )->URL? {


        guard let folderURL = ScanManager.shared.folderURL(
            for:document
        ) else {
            return nil
        }


        return folderURL.appendingPathComponent(
            "recognized_\(index + 1).txt"
        )


    }




    private func structuredOCRURL(
        at index:Int
    )->URL? {


        guard let folderURL = ScanManager.shared.folderURL(
            for:document
        ) else {
            return nil
        }


        return OCRStorage.fileURL(
            in:folderURL,
            pageNumber:index + 1
        )


    }




    private func loadRecognizedText(
        at index:Int
    )->String? {


        guard let url = recognizedTextURL(at:index),
              FileManager.default.fileExists(atPath:url.path)
        else {
            return nil
        }


        do {

            return try String(
                contentsOf:url,
                encoding:.utf8
            )

        }
        catch {

            print("识别文字读取失败:", error)
            return nil

        }


    }




    private func loadRecognizedTexts(
        pageCount:Int
    )->[Int:String] {


        var result:[Int:String] = [:]


        for index in 0..<pageCount {

            if let text = loadRecognizedText(at:index) {
                result[index] = text
            }

        }


        return result


    }




    private func loadOCRPageResults(
        pageCount:Int
    )->[Int:OCRPageResult] {


        var results:[Int:OCRPageResult] = [:]


        for index in 0..<pageCount {


            guard let url = structuredOCRURL(at:index),
                  let result = OCRStorage.load(from:url) else {
                continue
            }


            results[index] = result.withPageNumber(index + 1)


        }


        return results


    }




    private func saveRecognizedText(
        _ text:String,
        result:OCRPageResult?,
        at index:Int
    ){


        guard let url = recognizedTextURL(at:index) else {
            return
        }


        do {

            try text.write(
                to:url,
                atomically:true,
                encoding:.utf8
            )


            if let result,
               let structuredURL = structuredOCRURL(at:index) {


                try OCRStorage.write(
                    result.withPageNumber(index + 1),
                    to:structuredURL
                )


            }

            print("识别文字保存成功:", url.path)

            OCRIndexManager.shared.rebuildSearchableText(
                for:document
            )

        }
        catch {

            print("识别文字保存失败:", error)

        }


    }




    private var isDetailSmartEnhancing:Bool {
        !detailEnhancementTokens.isEmpty
    }




    private var detailEnhancementBanner:some View {


        HStack(spacing:10) {

            ProgressView()
                .tint(.white)

            VStack(alignment:.leading, spacing:2) {

                Text("智能优化中…")
                    .font(.subheadline.bold())

                Text("正在本机分析文字清晰度")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))

            }

        }
        .foregroundStyle(.white)
        .padding(.horizontal,16)
        .padding(.vertical,10)
        .background(
            .black.opacity(0.72),
            in:Capsule()
        )
        .shadow(color:.black.opacity(0.2), radius:8, y:3)


    }




    private func runSmartEnhancement(
        image:UIImage,
        at index:Int
    ) {


        guard displayImages.indices.contains(index) else { return }

        let token = UUID()
        detailEnhancementTokens[index] = token
        beginDetailEnhancementBannerDelayIfNeeded()

        SmartEnhancementPipeline.process(
            rgbImage:image,
            pageNumber:index + 1,
            captureCorners:detectedCorners.indices.contains(index)
                ? detectedCorners[index] : nil
        ) { output in

            guard detailEnhancementTokens[index] == token,
                  filterForPage(index) == .smart,
                  displayImages.indices.contains(index) else {
                return
            }

            if displayImageURLs.indices.contains(index) {

                let saved = writeImage(
                    output.image,
                    to:displayImageURLs[index]
                )

                displayImages[index] = saved
                    ? thumbnailImage(
                        at:displayImageURLs[index],
                        maxPixelSize:1600
                      ) ?? output.image
                    : output.image

            }
            else {

                displayImages[index] = output.image

            }

            detailEnhancementTokens[index] = nil
            finishDetailEnhancementBannerIfNeeded()

        }


    }




    private func invalidateSmartEnhancement(at index:Int) {


        detailEnhancementTokens[index] = nil
        finishDetailEnhancementBannerIfNeeded()


    }




    private func beginDetailEnhancementBannerDelayIfNeeded() {


        guard detailEnhancementBannerToken == nil else { return }

        let token = UUID()
        detailEnhancementBannerToken = token

        DispatchQueue.main.asyncAfter(deadline:.now() + 0.4) {

            guard detailEnhancementBannerToken == token,
                  isDetailSmartEnhancing else {
                return
            }

            detailEnhancementBannerShownAt = Date()
            withAnimation(.easeInOut(duration:0.2)) {
                showDetailEnhancementBanner = true
            }

        }


    }




    private func finishDetailEnhancementBannerIfNeeded() {


        guard !isDetailSmartEnhancing else { return }

        let token = detailEnhancementBannerToken
        let elapsed = detailEnhancementBannerShownAt.map {
            Date().timeIntervalSince($0)
        } ?? 0.6
        let delay = showDetailEnhancementBanner
            ? max(0, 0.6 - elapsed)
            : 0

        DispatchQueue.main.asyncAfter(deadline:.now() + delay) {

            guard detailEnhancementBannerToken == token,
                  !isDetailSmartEnhancing else {
                return
            }

            withAnimation(.easeInOut(duration:0.2)) {
                showDetailEnhancementBanner = false
            }
            detailEnhancementBannerShownAt = nil
            detailEnhancementBannerToken = nil

        }


    }




    private func applyFilter(
        _ filter:ScanPageFilter,
        at index:Int
    ){


        guard adjustedImages.indices.contains(index),
              displayImages.indices.contains(index) else {
            return
        }

        invalidateSmartEnhancement(at:index)


        let sourceImage:UIImage

        let candidateURLs:[URL?] = [
            adjustedImageURLs.indices.contains(index)
                ? adjustedImageURLs[index]
                : nil,
            displayImageURLs.indices.contains(index)
                ? displayImageURLs[index]
                : nil,
            originalImageURLs.indices.contains(index)
                ? originalImageURLs[index]
                : nil
        ]

        if let fullResolutionImage = candidateURLs
            .compactMap({ $0 })
            .lazy
            .compactMap({ UIImage(contentsOfFile:$0.path) })
            .first {
            sourceImage = fullResolutionImage
        }
        else {
            sourceImage = adjustedImages[index]
        }


        let rendered = autoreleasepool {
            DocumentImageFilter.apply(
                filter,
                to:sourceImage
            )
        }


        if displayImageURLs.indices.contains(index) {

            let saved = writeImage(
                rendered,
                to:displayImageURLs[index]
            )

            displayImages[index] = saved
                ? thumbnailImage(
                    at:displayImageURLs[index],
                    maxPixelSize:1600
                  ) ?? rendered
                : rendered

        }
        else {

            displayImages[index] = rendered

        }


        if !pageFilters.indices.contains(index) {

            let missingCount = index - pageFilters.count + 1

            pageFilters.append(
                contentsOf:Array(
                    repeating:ScanPageFilter.smart,
                    count:missingCount
                )
            )

        }


        pageFilters[index] = filter
        saveCorners()

        if filter == .smart {
            runSmartEnhancement(
                image:sourceImage,
                at:index
            )
        }


    }




    private func applyCrop(
        _ result:CropResult,
        at index:Int
    ){


        invalidateSmartEnhancement(at:index)


        if originalImages.indices.contains(index) {

            if originalImageURLs.indices.contains(index) {

                let saved = writeImage(
                    result.sourceImage,
                    to:originalImageURLs[index]
                )

                originalImages[index] = saved
                    ? thumbnailImage(
                        at:originalImageURLs[index],
                        maxPixelSize:640
                      ) ?? result.sourceImage
                    : result.sourceImage

            }
            else {

                originalImages[index] = result.sourceImage

            }

        }


        if adjustedImages.indices.contains(index) {

            if adjustedImageURLs.indices.contains(index) {

                let saved = writeImage(
                    result.image,
                    to:adjustedImageURLs[index]
                )

                adjustedImages[index] = saved
                    ? thumbnailImage(
                        at:adjustedImageURLs[index],
                        maxPixelSize:640
                      ) ?? result.image
                    : result.image

            }
            else {

                adjustedImages[index] = result.image

            }

        }


        if displayImages.indices.contains(index) {

            let filteredImage = DocumentImageFilter.apply(
                filterForPage(index),
                to:result.image
            )

            if displayImageURLs.indices.contains(index) {

                let saved = writeImage(
                    filteredImage,
                    to:displayImageURLs[index]
                )

                displayImages[index] = saved
                    ? thumbnailImage(
                        at:displayImageURLs[index],
                        maxPixelSize:1600
                      ) ?? filteredImage
                    : filteredImage

            }
            else {

                displayImages[index] = filteredImage

            }

        }


        if !detectedCorners.indices.contains(index) {

            let missingCount = index - detectedCorners.count + 1

            detectedCorners.append(
                contentsOf:Array<ScanCorners?>(
                    repeating:nil,
                    count:missingCount
                )
            )

        }


        // 保存用户最终确认的四角，而不是重新识别出的初始四角。
        detectedCorners[index] = result.corners

        saveCorners()

        if let structuredURL = structuredOCRURL(at:index) {
            OCRStorage.removeIfPresent(at:structuredURL)
        }

        OCRIndexManager.shared.reindexDocument(document)


        showCropSheet = false

        if filterForPage(index) == .smart {
            runSmartEnhancement(
                image:result.image,
                at:index
            )
        }


    }




    private func saveCorners(){


        guard let folder = ScanManager.shared.folderURL(
            for:document
        ) else {
            return
        }


        let pageCount = max(
            detectedCorners.count,
            max(pageFilters.count, displayImages.count)
        )
        let metadata = (0..<pageCount).map { index in
            ScanPageMetadata(
                pageNumber:index + 1,
                corners:detectedCorners.indices.contains(index)
                    ? detectedCorners[index]
                    : nil,
                filter:filterForPage(index)
            )
        }


        do {

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(metadata)
            let metadataURL = folder.appendingPathComponent(
                "scan_metadata.json"
            )

            try data.write(
                to:metadataURL,
                options:.atomic
            )

        }
        catch {

            print(
                "裁切坐标保存失败:",
                error
            )

        }


    }




    @discardableResult
    private func writeImage(
        _ image:UIImage,
        to url:URL
    )->Bool {


        guard let data = image.jpegData(
            compressionQuality:0.95
        ) else {

            print("裁切图片编码失败")
            return false

        }


        do {

            try data.write(
                to:url,
                options:.atomic
            )

            print(
                "裁切图片保存成功:",
                url.path
            )

            return true

        }
        catch {

            print(
                "裁切图片保存失败:",
                error
            )

            return false

        }


    }




    private func generatePDF(
        for document: ScanEntity
    ) -> URL? {
        
        
        guard let folderURL = ScanManager.shared.folderURL(
            for:document
        )
        else {
            
            return nil
            
        }
        
        
        let pdfURL =
        folderURL.appendingPathComponent(
            "\(document.title ?? L10n.text("扫描文档")).pdf"
        )
        
        
        let imageURLs = displayImageURLs.isEmpty
            ? originalImageURLs
            : displayImageURLs


        let fallbackImages = displayImages.isEmpty
            ? originalImages
            : displayImages
        
        
        guard !imageURLs.isEmpty || !fallbackImages.isEmpty else {
            
            return nil
            
        }
        
        
        
        UIGraphicsBeginPDFContextToFile(
            pdfURL.path,
            .zero,
            nil
        )
        
        
        
        if !imageURLs.isEmpty {

            for index in imageURLs.indices {
                autoreleasepool {
                    let image = UIImage(
                        contentsOfFile:imageURLs[index].path
                    ) ?? (
                        fallbackImages.indices.contains(index)
                            ? fallbackImages[index]
                            : nil
                    )

                    guard let image else {
                        return
                    }

                    drawPDFPage(for:image)
                }
            }

        }
        else {

            for image in fallbackImages {
                autoreleasepool {
                    drawPDFPage(for:image)
                }
            }

        }
        
        
        
        UIGraphicsEndPDFContext()
        
        
        if FileManager.default.fileExists(
            atPath:
                pdfURL.path
        ){
            
            print(
                "PDF生成成功:",
                pdfURL.path
            )
            
            return pdfURL
            
        }
        
        
        return nil
        
    }


    private func exportWordDocument() {

        guard !isExportingWord else { return }

        guard let folderURL = ScanManager.shared.folderURL(
            for:document
        ) else {
            presentWordExportError(
                L10n.text("无法读取当前扫描文件夹。")
            )
            return
        }

        isExportingWord = true
        defer { isExportingWord = false }

        do {
            let scanDocument = try DocumentAssembler().rebuild(
                in:folderURL,
                title:document.title
                    ?? L10n.text("扫描文档"),
                createdAt:document.createdAt ?? Date(),
                id:document.id ?? UUID()
            )
            let url = try WordExporter().export(
                document:scanDocument,
                to:folderURL
            )
            shareItem = ShareItem(url:url)
        }
        catch {
            presentWordExportError(
                error.localizedDescription
            )
        }
    }


    private func presentWordExportError(
        _ message:String
    ) {
        wordExportError = message
        showWordExportError = true
    }


    private func drawPDFPage(
        for image:UIImage
    ) {

        let page = CGRect(
            x:0,
            y:0,
            width:595,
            height:842
        )

        UIGraphicsBeginPDFPageWithInfo(
            page,
            nil
        )

        let scale = min(
            page.width / image.size.width,
            page.height / image.size.height
        )
        let size = CGSize(
            width:image.size.width * scale,
            height:image.size.height * scale
        )
        let rect = CGRect(
            x:(page.width - size.width) / 2,
            y:(page.height - size.height) / 2,
            width:size.width,
            height:size.height
        )

        image.draw(in:rect)
    }


    private func thumbnailImage(
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


    private func placeholderImage()->UIImage {

        let renderer = UIGraphicsImageRenderer(
            size:CGSize(width:32, height:32)
        )

        return renderer.image { context in
            UIColor.secondarySystemBackground.setFill()
            context.fill(
                CGRect(x:0, y:0, width:32, height:32)
            )
        }
    }
    
    
    
    
}


private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}


#if false
private struct LegacyCropSheet: View {

    let image: UIImage

    var onComplete:(UIImage)->Void
    var onCancel:()->Void


    @State private var cropRect:CGRect = .zero

    @State private var imageFrame:CGRect = .zero

    @State private var moveStartRect:CGRect?
    @State private var resizeStartRect:CGRect?


    var body: some View {

        NavigationStack {

            VStack(spacing:0) {

                GeometryReader { geometry in

                    let fittedFrame = fittedImageFrame(
                        in:geometry.size
                    )

                    ZStack {

                        Color.black
                            .ignoresSafeArea()


                        Image(uiImage:image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width:fittedFrame.width,
                                height:fittedFrame.height
                            )
                            .position(
                                x:fittedFrame.midX,
                                y:fittedFrame.midY
                            )


                        dimmingPath(
                            imageFrame:fittedFrame,
                            cropRect:cropRect
                        )
                        .fill(
                            Color.black.opacity(0.55),
                            style:FillStyle(eoFill:true)
                        )


                        Rectangle()
                            .stroke(
                                Color.yellow,
                                lineWidth:2
                            )
                            .frame(
                                width:cropRect.width,
                                height:cropRect.height
                            )
                            .position(
                                x:cropRect.midX,
                                y:cropRect.midY
                            )
                            .contentShape(Rectangle())
                            .gesture(
                                moveGesture(
                                    inside:fittedFrame
                                )
                            )


                        ForEach(
                            CropCorner.allCases,
                            id:\.self
                        ) { corner in

                            Circle()
                                .fill(Color.white)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            Color.yellow,
                                            lineWidth:3
                                        )
                                }
                                .frame(
                                    width:28,
                                    height:28
                                )
                                .position(
                                    cornerPoint(
                                        for:corner,
                                        in:cropRect
                                    )
                                )
                                .gesture(
                                    resizeGesture(
                                        corner:corner,
                                        inside:fittedFrame
                                    )
                                )

                        }

                    }
                    .onAppear {

                        imageFrame = fittedFrame

                        if cropRect == .zero {
                            resetCropRect()
                        }

                    }
                    .onChange(of:geometry.size) { _, _ in

                        imageFrame = fittedFrame
                        resetCropRect()

                    }

                }


                HStack(spacing:24) {

                    Button("取消") {
                        onCancel()
                    }


                    Spacer()


                    Button("重置") {
                        resetCropRect()
                    }


                    Spacer()


                    Button("完成") {

                        if let croppedImage = croppedImage() {

                            onComplete(
                                croppedImage
                            )

                        }

                    }
                    .fontWeight(.semibold)
                    .disabled(cropRect == .zero)


                }
                .padding(.horizontal,24)
                .frame(height:64)
                .background(Color(uiColor:.systemBackground))

            }
            .navigationTitle("裁切")
            .navigationBarTitleDisplayMode(.inline)

        }

    }




    private func fittedImageFrame(
        in containerSize:CGSize
    )->CGRect {


        guard image.size.width > 0,
              image.size.height > 0
        else {

            return .zero

        }


        let scale = min(
            containerSize.width / image.size.width,
            containerSize.height / image.size.height
        )


        let size = CGSize(
            width:image.size.width * scale,
            height:image.size.height * scale
        )


        return CGRect(
            x:(containerSize.width - size.width) / 2,
            y:(containerSize.height - size.height) / 2,
            width:size.width,
            height:size.height
        )


    }




    private func resetCropRect(){


        guard imageFrame.width > 0,
              imageFrame.height > 0
        else {

            return

        }


        cropRect = imageFrame.insetBy(
            dx:imageFrame.width * 0.08,
            dy:imageFrame.height * 0.08
        )


    }




    private func dimmingPath(
        imageFrame:CGRect,
        cropRect:CGRect
    )->Path {


        var path = Path()

        path.addRect(imageFrame)
        path.addRect(cropRect)

        return path


    }




    private func cornerPoint(
        for corner:CropCorner,
        in rect:CGRect
    )->CGPoint {


        switch corner {

        case .topLeft:
            return CGPoint(x:rect.minX, y:rect.minY)

        case .topRight:
            return CGPoint(x:rect.maxX, y:rect.minY)

        case .bottomLeft:
            return CGPoint(x:rect.minX, y:rect.maxY)

        case .bottomRight:
            return CGPoint(x:rect.maxX, y:rect.maxY)

        }


    }




    private func moveGesture(
        inside bounds:CGRect
    )->some Gesture {


        DragGesture()
            .onChanged { value in

                if moveStartRect == nil {
                    moveStartRect = cropRect
                }


                guard let startRect = moveStartRect else {
                    return
                }


                let x = min(
                    max(
                        startRect.minX + value.translation.width,
                        bounds.minX
                    ),
                    bounds.maxX - startRect.width
                )


                let y = min(
                    max(
                        startRect.minY + value.translation.height,
                        bounds.minY
                    ),
                    bounds.maxY - startRect.height
                )


                cropRect = CGRect(
                    origin:CGPoint(x:x, y:y),
                    size:startRect.size
                )

            }
            .onEnded { _ in
                moveStartRect = nil
            }


    }




    private func resizeGesture(
        corner:CropCorner,
        inside bounds:CGRect
    )->some Gesture {


        DragGesture()
            .onChanged { value in

                if resizeStartRect == nil {
                    resizeStartRect = cropRect
                }


                guard let startRect = resizeStartRect else {
                    return
                }


                let minimumWidth = min(
                    CGFloat(80),
                    startRect.width
                )

                let minimumHeight = min(
                    CGFloat(80),
                    startRect.height
                )

                var left = startRect.minX
                var right = startRect.maxX
                var top = startRect.minY
                var bottom = startRect.maxY


                switch corner {

                case .topLeft:
                    left = min(
                        max(startRect.minX + value.translation.width, bounds.minX),
                        startRect.maxX - minimumWidth
                    )
                    top = min(
                        max(startRect.minY + value.translation.height, bounds.minY),
                        startRect.maxY - minimumHeight
                    )

                case .topRight:
                    right = max(
                        min(startRect.maxX + value.translation.width, bounds.maxX),
                        startRect.minX + minimumWidth
                    )
                    top = min(
                        max(startRect.minY + value.translation.height, bounds.minY),
                        startRect.maxY - minimumHeight
                    )

                case .bottomLeft:
                    left = min(
                        max(startRect.minX + value.translation.width, bounds.minX),
                        startRect.maxX - minimumWidth
                    )
                    bottom = max(
                        min(startRect.maxY + value.translation.height, bounds.maxY),
                        startRect.minY + minimumHeight
                    )

                case .bottomRight:
                    right = max(
                        min(startRect.maxX + value.translation.width, bounds.maxX),
                        startRect.minX + minimumWidth
                    )
                    bottom = max(
                        min(startRect.maxY + value.translation.height, bounds.maxY),
                        startRect.minY + minimumHeight
                    )

                }


                cropRect = CGRect(
                    x:left,
                    y:top,
                    width:right - left,
                    height:bottom - top
                )

            }
            .onEnded { _ in
                resizeStartRect = nil
            }


    }




    private func croppedImage()->UIImage? {


        let normalized = normalizedImage(
            image
        )


        guard imageFrame.width > 0,
              imageFrame.height > 0,
              let cgImage = normalized.cgImage
        else {

            return nil

        }


        let visibleRect = cropRect.intersection(
            imageFrame
        )


        guard !visibleRect.isNull,
              visibleRect.width > 0,
              visibleRect.height > 0
        else {

            return nil

        }


        let scaleX = CGFloat(cgImage.width) / imageFrame.width
        let scaleY = CGFloat(cgImage.height) / imageFrame.height


        var pixelRect = CGRect(
            x:(visibleRect.minX - imageFrame.minX) * scaleX,
            y:(visibleRect.minY - imageFrame.minY) * scaleY,
            width:visibleRect.width * scaleX,
            height:visibleRect.height * scaleY
        ).integral


        pixelRect = pixelRect.intersection(
            CGRect(
                x:0,
                y:0,
                width:cgImage.width,
                height:cgImage.height
            )
        )


        guard let croppedCGImage = cgImage.cropping(
            to:pixelRect
        ) else {

            return nil

        }


        return UIImage(
            cgImage:croppedCGImage,
            scale:1,
            orientation:.up
        )


    }




    private func normalizedImage(
        _ image:UIImage
    )->UIImage {


        guard image.imageOrientation != .up else {
            return image
        }


        let format = UIGraphicsImageRendererFormat()
        format.scale = 1


        return UIGraphicsImageRenderer(
            size:image.size,
            format:format
        ).image { _ in

            image.draw(
                in:CGRect(
                    origin:.zero,
                    size:image.size
                )
            )

        }


    }

}


private enum CropCorner:CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}
#endif


// MARK: - Perspective Crop

private struct PerspectiveCropQuad:Equatable {
    var topLeft:CGPoint
    var topRight:CGPoint
    var bottomRight:CGPoint
    var bottomLeft:CGPoint

    static let full = PerspectiveCropQuad(
        topLeft:CGPoint(x:0.06, y:0.06),
        topRight:CGPoint(x:0.94, y:0.06),
        bottomRight:CGPoint(x:0.94, y:0.94),
        bottomLeft:CGPoint(x:0.06, y:0.94)
    )

    static let all = PerspectiveCropQuad(
        topLeft:CGPoint(x:0, y:0),
        topRight:CGPoint(x:1, y:0),
        bottomRight:CGPoint(x:1, y:1),
        bottomLeft:CGPoint(x:0, y:1)
    )

    var points:[CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    func point(for corner:PerspectiveCropCorner)->CGPoint {
        switch corner {
        case .topLeft: return topLeft
        case .topRight: return topRight
        case .bottomRight: return bottomRight
        case .bottomLeft: return bottomLeft
        }
    }

    func setting(
        _ corner:PerspectiveCropCorner,
        to point:CGPoint
    )->PerspectiveCropQuad {
        var result = self
        switch corner {
        case .topLeft: result.topLeft = point
        case .topRight: result.topRight = point
        case .bottomRight: result.bottomRight = point
        case .bottomLeft: result.bottomLeft = point
        }
        return result
    }

    func translated(dx:CGFloat, dy:CGFloat)->PerspectiveCropQuad {
        PerspectiveCropQuad(
            topLeft:CGPoint(x:topLeft.x + dx, y:topLeft.y + dy),
            topRight:CGPoint(x:topRight.x + dx, y:topRight.y + dy),
            bottomRight:CGPoint(x:bottomRight.x + dx, y:bottomRight.y + dy),
            bottomLeft:CGPoint(x:bottomLeft.x + dx, y:bottomLeft.y + dy)
        )
    }

    func moving(
        edge:PerspectiveCropEdge,
        dx:CGFloat,
        dy:CGFloat
    )->PerspectiveCropQuad {
        var result = self
        switch edge {
        case .top:
            result.topLeft.y += dy
            result.topRight.y += dy
        case .right:
            result.topRight.x += dx
            result.bottomRight.x += dx
        case .bottom:
            result.bottomLeft.y += dy
            result.bottomRight.y += dy
        case .left:
            result.topLeft.x += dx
            result.bottomLeft.x += dx
        }
        return result
    }

    func rotated(clockwise:Bool)->PerspectiveCropQuad {
        if clockwise {
            return PerspectiveCropQuad(
                topLeft:rotateClockwise(bottomLeft),
                topRight:rotateClockwise(topLeft),
                bottomRight:rotateClockwise(topRight),
                bottomLeft:rotateClockwise(bottomRight)
            )
        }

        return PerspectiveCropQuad(
            topLeft:rotateCounterClockwise(topRight),
            topRight:rotateCounterClockwise(bottomRight),
            bottomRight:rotateCounterClockwise(bottomLeft),
            bottomLeft:rotateCounterClockwise(topLeft)
        )
    }

    var isValid:Bool {
        let values = points

        guard values.allSatisfy({
            $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1
        }) else {
            return false
        }

        for index in values.indices {
            let next = values[(index + 1) % values.count]
            if hypot(next.x - values[index].x, next.y - values[index].y) < 0.035 {
                return false
            }
        }

        for index in values.indices {
            let first = values[index]
            let second = values[(index + 1) % values.count]
            let third = values[(index + 2) % values.count]
            let cross = (second.x - first.x) * (third.y - second.y)
                - (second.y - first.y) * (third.x - second.x)
            if cross <= 0.0005 {
                return false
            }
        }

        return true
    }

    private func rotateClockwise(_ point:CGPoint)->CGPoint {
        CGPoint(x:1 - point.y, y:point.x)
    }

    private func rotateCounterClockwise(_ point:CGPoint)->CGPoint {
        CGPoint(x:point.y, y:1 - point.x)
    }
}


private enum PerspectiveCropCorner:CaseIterable,Hashable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}


private enum PerspectiveCropEdge:CaseIterable,Hashable {
    case top
    case right
    case bottom
    case left

    var usesHorizontalHandle:Bool {
        self == .top || self == .bottom
    }
}


private final class CropGestureAttachmentView:UIView {
    var onHostViewChange:((UIView?)->Void)?

    private func notifyHostViewChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            onHostViewChange?(window ?? superview)
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        notifyHostViewChanged()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        notifyHostViewChanged()
    }

    override func point(
        inside point:CGPoint,
        with event:UIEvent?
    )->Bool {
        false
    }
}


private struct CropCanvasGestureBridge:UIViewRepresentable {
    var onPinch:(UIGestureRecognizer.State,CGFloat,CGPoint)->Void
    var onPan:(UIGestureRecognizer.State,CGPoint)->Void

    func makeCoordinator()->Coordinator {
        Coordinator(parent:self)
    }

    func makeUIView(context:Context)->CropGestureAttachmentView {
        let view = CropGestureAttachmentView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.onHostViewChange = {
            [weak coordinator = context.coordinator, weak view]
            hostView in
            coordinator?.attach(
                to:hostView,
                coordinateView:view
            )
        }
        return view
    }

    func updateUIView(
        _ uiView:CropGestureAttachmentView,
        context:Context
    ) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(
        _ uiView:CropGestureAttachmentView,
        coordinator:Coordinator
    ) {
        coordinator.detach()
    }

    final class Coordinator:NSObject,UIGestureRecognizerDelegate {
        var parent:CropCanvasGestureBridge
        weak var attachedView:UIView?
        weak var coordinateView:UIView?

        private lazy var pinchGesture:UIPinchGestureRecognizer = {
            let gesture = UIPinchGestureRecognizer(
                target:self,
                action:#selector(handlePinch(_:))
            )
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()

        private lazy var panGesture:UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(
                target:self,
                action:#selector(handlePan(_:))
            )
            gesture.minimumNumberOfTouches = 2
            gesture.maximumNumberOfTouches = 2
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()

        init(parent:CropCanvasGestureBridge) {
            self.parent = parent
        }

        func attach(
            to view:UIView?,
            coordinateView:UIView?
        ) {
            guard let view,
                  attachedView !== view else {
                self.coordinateView = coordinateView
                return
            }

            detach()
            attachedView = view
            self.coordinateView = coordinateView
            view.addGestureRecognizer(pinchGesture)
            view.addGestureRecognizer(panGesture)
        }

        func detach() {
            attachedView?.removeGestureRecognizer(pinchGesture)
            attachedView?.removeGestureRecognizer(panGesture)
            attachedView = nil
            coordinateView = nil
        }

        @objc private func handlePinch(
            _ gesture:UIPinchGestureRecognizer
        ) {
            let location = gesture.location(
                in:coordinateView
            )
            parent.onPinch(
                gesture.state,
                gesture.scale,
                location
            )
        }

        @objc private func handlePan(
            _ gesture:UIPanGestureRecognizer
        ) {
            let translation = gesture.translation(
                in:coordinateView
            )
            parent.onPan(
                gesture.state,
                translation
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer:UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith
            otherGestureRecognizer:UIGestureRecognizer
        )->Bool {
            true
        }

        func gestureRecognizerShouldBegin(
            _ gestureRecognizer:UIGestureRecognizer
        )->Bool {
            guard let coordinateView else {
                return false
            }

            let location = gestureRecognizer.location(
                in:coordinateView
            )
            return coordinateView.bounds.contains(location)
        }
    }
}


struct CropSheet:View {
    private let onComplete:(CropResult)->Void
    private let onCancel:()->Void

    @State private var workingImage:UIImage
    @State private var quad:PerspectiveCropQuad = .full
    @State private var automaticQuad:PerspectiveCropQuad?
    @State private var isDetectingAutomaticCrop = false

    @State private var cornerStartQuad:PerspectiveCropQuad?
    @State private var edgeStartQuad:PerspectiveCropQuad?
    @State private var moveStartQuad:PerspectiveCropQuad?

    @State private var canvasScale:CGFloat = 1
    @State private var horizontalViewportPosition:Double = 0
    @State private var verticalViewportPosition:Double = 0

    private let minimumCanvasScale:CGFloat = 1
    private let maximumCanvasScale:CGFloat = 4
    private let canvasScaleStep:CGFloat = 0.25

    private let cropColor = Color(
        red:0.00,
        green:0.72,
        blue:0.58
    )

    init(
        image:UIImage,
        initialCorners:ScanCorners? = nil,
        onComplete:@escaping (CropResult)->Void,
        onCancel:@escaping ()->Void
    ) {
        let normalized = Self.normalizedImage(image)
        let requestedQuad = initialCorners.map {
            PerspectiveCropQuad(
                topLeft:$0.topLeft,
                topRight:$0.topRight,
                bottomRight:$0.bottomRight,
                bottomLeft:$0.bottomLeft
            )
        } ?? .full
        let validRequestedQuad = requestedQuad.isValid
            ? requestedQuad
            : nil
        self.onComplete = onComplete
        self.onCancel = onCancel
        _workingImage = State(initialValue:normalized)
        _quad = State(
            initialValue:validRequestedQuad ?? .full
        )
        _automaticQuad = State(
            initialValue:initialCorners == nil
                ? nil
                : validRequestedQuad
        )
    }

    var body:some View {
        NavigationStack {
            VStack(spacing:0) {
                GeometryReader { geometry in
                    let leftWhiteStrip:CGFloat = 14
                    let verticalControlWidth:CGFloat = 30
                    let horizontalControlHeight:CGFloat = 30
                    let canvasSize = CGSize(
                        width:max(
                            1,
                            geometry.size.width
                                - leftWhiteStrip
                                - verticalControlWidth
                        ),
                        height:max(
                            1,
                            geometry.size.height
                                - horizontalControlHeight
                        )
                    )
                    let baseImageFrame = fittedImageFrame(
                        in:canvasSize
                    )
                    let imageFrame = zoomedImageFrame(
                        from:baseImageFrame
                    )
                    let horizontalSliderWidth = min(
                        max(80, baseImageFrame.width - 12),
                        max(80, canvasSize.width - 8)
                    )
                    let horizontalSliderY = min(
                        geometry.size.height - 14,
                        baseImageFrame.maxY + 17
                    )
                    let verticalSliderHeight = min(
                        max(80, baseImageFrame.height - 12),
                        max(80, canvasSize.height - 8)
                    )
                    let verticalSliderX = min(
                        geometry.size.width - 14,
                        leftWhiteStrip
                            + baseImageFrame.maxX
                            + 17
                    )

                    ZStack(alignment:.topLeading) {
                        ZStack {
                            Color.white

                            Image(uiImage:workingImage)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width:imageFrame.width,
                                    height:imageFrame.height
                                )
                                .position(
                                    x:imageFrame.midX,
                                    y:imageFrame.midY
                                )

                            dimmingPath(in:imageFrame)
                                .fill(
                                    Color.black.opacity(0.42),
                                    style:FillStyle(eoFill:true)
                                )

                            polygonPath(in:imageFrame)
                                .fill(Color.white.opacity(0.001))
                                .contentShape(
                                    polygonPath(in:imageFrame)
                                )
                                .gesture(
                                    moveGesture(in:imageFrame)
                                )

                            polygonPath(in:imageFrame)
                                .stroke(
                                    cropColor,
                                    style:StrokeStyle(
                                        lineWidth:2.5,
                                        lineJoin:.round
                                    )
                                )
                                .allowsHitTesting(false)

                            ForEach(
                                PerspectiveCropEdge.allCases,
                                id:\.self
                            ) { edge in
                                edgeHandle(
                                    edge,
                                    in:imageFrame
                                )
                            }

                            ForEach(
                                PerspectiveCropCorner.allCases,
                                id:\.self
                            ) { corner in
                                cornerHandle(
                                    corner,
                                    in:imageFrame
                                )
                            }
                        }
                        .frame(
                            width:canvasSize.width,
                            height:canvasSize.height
                        )
                        .clipped()
                        .offset(x:leftWhiteStrip)

                        horizontalViewportSlider
                            .frame(
                                width:horizontalSliderWidth,
                                height:26
                            )
                            .position(
                                x:leftWhiteStrip
                                    + baseImageFrame.midX,
                                y:horizontalSliderY
                            )

                        verticalViewportSlider(
                            sliderHeight:verticalSliderHeight
                        )
                        .position(
                            x:verticalSliderX,
                            y:baseImageFrame.midY
                        )
                    }
                    .frame(
                        width:geometry.size.width,
                        height:geometry.size.height,
                        alignment:.topLeading
                    )
                    .background(Color.white)
                }

                rotationControls

                Divider()

                completionControls
            }
            .background(Color.white)
            .navigationTitle("旋转裁剪")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for:.navigationBar)
            .toolbarBackground(.visible, for:.navigationBar)
        }
        .preferredColorScheme(.light)
        .onAppear {
            if automaticQuad == nil {
                detectAutomaticCrop(applyWhenFinished:true)
            }
        }
    }

    private var horizontalViewportSlider:some View {
        Slider(
            value:$horizontalViewportPosition,
            in:-1...1
        )
        .tint(cropColor)
        .controlSize(.mini)
        .padding(.horizontal,4)
        .background(
            Color.white.opacity(0.94),
            in:Capsule()
        )
        .disabled(!canvasCanMove)
        .opacity(canvasCanMove ? 0.92 : 0.32)
        .accessibilityLabel("左右微调图片")
    }

    private func verticalViewportSlider(
        sliderHeight:CGFloat
    )->some View {
        ZStack {
            Slider(
                value:$verticalViewportPosition,
                in:-1...1
            )
            .tint(cropColor)
            .controlSize(.mini)
            .frame(
                width:sliderHeight,
                height:24
            )
            .rotationEffect(.degrees(-90))
        }
        .frame(
            width:26,
            height:sliderHeight
        )
        .background(
            Color.white.opacity(0.94),
            in:Capsule()
        )
        .disabled(!canvasCanMove)
        .opacity(canvasCanMove ? 0.92 : 0.32)
        .accessibilityLabel("上下微调图片")
    }

    private var rotationControls:some View {
        HStack(spacing:0) {
            Button {
                rotate(clockwise:false)
            } label: {
                VStack(spacing:5) {
                    Image(systemName:"rotate.left")
                        .font(.title2)
                    Text("左旋转")
                        .font(.caption)
                }
                .frame(maxWidth:.infinity)
            }

            Button {
                rotate(clockwise:true)
            } label: {
                VStack(spacing:5) {
                    Image(systemName:"rotate.right")
                        .font(.title2)
                    Text("右旋转")
                        .font(.caption)
                }
                .frame(maxWidth:.infinity)
            }

            Button {
                restoreAutomaticCrop()
            } label: {
                VStack(spacing:5) {
                    if isDetectingAutomaticCrop {
                        ProgressView()
                            .controlSize(.small)
                            .frame(height:24)
                    } else {
                        Image(systemName:"viewfinder")
                            .font(.title2)
                            .frame(height:24)
                    }
                    Text("自动裁切")
                        .font(.caption)
                }
                .frame(maxWidth:.infinity)
            }
            .disabled(isDetectingAutomaticCrop)

            Button {
                quad = .all
                clearGestureState()
                resetCanvasZoom()
            } label: {
                VStack(spacing:5) {
                    Image(
                        systemName:
                            "arrow.up.left.and.arrow.down.right"
                    )
                    .font(.title2)
                    .frame(height:24)
                    Text("全部")
                        .font(.caption)
                }
                .frame(maxWidth:.infinity)
            }
        }
        .foregroundStyle(Color.primary)
        .frame(height:72)
        .background(Color.white)
    }

    private var completionControls:some View {
        HStack {
            Button {
                onCancel()
            } label: {
                Image(systemName:"xmark")
                    .font(.title2)
                    .frame(width:52, height:48)
            }

            Spacer(minLength:8)

            zoomControls

            Spacer(minLength:8)

            Button {
                if let corrected = perspectiveCorrectedImage() {
                    onComplete(
                        CropResult(
                            image:corrected,
                            sourceImage:workingImage,
                            corners:ScanCorners(
                                topLeft:quad.topLeft,
                                topRight:quad.topRight,
                                bottomRight:quad.bottomRight,
                                bottomLeft:quad.bottomLeft
                            ),
                            automaticCorners:automaticQuad.map {
                                ScanCorners(
                                    topLeft:$0.topLeft,
                                    topRight:$0.topRight,
                                    bottomRight:$0.bottomRight,
                                    bottomLeft:$0.bottomLeft
                                )
                            }
                        )
                    )
                }
            } label: {
                Image(systemName:"checkmark")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(width:52, height:48)
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal,12)
        .frame(height:64)
        .background(Color.white)
    }

    private var zoomControls:some View {
        HStack(spacing:8) {
            Button {
                changeCanvasScale(by:-canvasScaleStep)
            } label: {
                Image(systemName:"minus.magnifyingglass")
                    .font(.title3)
                    .frame(width:40, height:44)
            }
            .disabled(
                canvasScale <= minimumCanvasScale + 0.001
            )

            Text("\(Int((canvasScale * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.secondary)
                .frame(width:44)

            Button {
                changeCanvasScale(by:canvasScaleStep)
            } label: {
                Image(systemName:"plus.magnifyingglass")
                    .font(.title3)
                    .frame(width:40, height:44)
            }
            .disabled(
                canvasScale >= maximumCanvasScale - 0.001
            )
        }
        .accessibilityElement(children:.contain)
        .accessibilityLabel("裁切预览缩放")
    }

    private func fittedImageFrame(in containerSize:CGSize)->CGRect {
        let horizontalMargin:CGFloat = 10
        let verticalMargin:CGFloat = 12
        let available = CGSize(
            width:max(1, containerSize.width - horizontalMargin * 2),
            height:max(1, containerSize.height - verticalMargin * 2)
        )

        guard workingImage.size.width > 0,
              workingImage.size.height > 0 else {
            return .zero
        }

        let scale = min(
            available.width / workingImage.size.width,
            available.height / workingImage.size.height
        )
        let size = CGSize(
            width:workingImage.size.width * scale,
            height:workingImage.size.height * scale
        )

        return CGRect(
            x:(containerSize.width - size.width) / 2,
            y:(containerSize.height - size.height) / 2,
            width:size.width,
            height:size.height
        )
    }

    private func zoomedImageFrame(
        from baseFrame:CGRect
    )->CGRect {
        let size = CGSize(
            width:baseFrame.width * canvasScale,
            height:baseFrame.height * canvasScale
        )
        let horizontalLimit = max(
            0,
            baseFrame.width * (canvasScale - 1) / 2
        )
        let verticalLimit = max(
            0,
            baseFrame.height * (canvasScale - 1) / 2
        )
        let offset = CGSize(
            width:horizontalLimit
                * CGFloat(horizontalViewportPosition),
            height:-verticalLimit
                * CGFloat(verticalViewportPosition)
        )

        return CGRect(
            x:baseFrame.midX + offset.width - size.width / 2,
            y:baseFrame.midY + offset.height - size.height / 2,
            width:size.width,
            height:size.height
        )
    }

    private var canvasCanMove:Bool {
        canvasScale > minimumCanvasScale + 0.001
    }

    private func changeCanvasScale(by amount:CGFloat) {
        let newScale = clamp(
            canvasScale + amount,
            lower:minimumCanvasScale,
            upper:maximumCanvasScale
        )

        withAnimation(.easeInOut(duration:0.16)) {
            canvasScale = newScale

            if !canvasCanMove {
                horizontalViewportPosition = 0
                verticalViewportPosition = 0
            }
        }
    }

    private func resetCanvasZoom() {
        canvasScale = minimumCanvasScale
        horizontalViewportPosition = 0
        verticalViewportPosition = 0
    }

    private func screenPoint(
        _ point:CGPoint,
        in frame:CGRect
    )->CGPoint {
        CGPoint(
            x:frame.minX + point.x * frame.width,
            y:frame.minY + point.y * frame.height
        )
    }

    private func polygonPath(in frame:CGRect)->Path {
        let points = quad.points.map {
            screenPoint($0, in:frame)
        }
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to:first)
        for point in points.dropFirst() {
            path.addLine(to:point)
        }
        path.closeSubpath()
        return path
    }

    private func dimmingPath(in frame:CGRect)->Path {
        var path = Path()
        path.addRect(frame)
        path.addPath(polygonPath(in:frame))
        return path
    }

    private func edgeMidpoint(
        _ edge:PerspectiveCropEdge,
        in frame:CGRect
    )->CGPoint {
        let first:CGPoint
        let second:CGPoint

        switch edge {
        case .top:
            first = quad.topLeft
            second = quad.topRight
        case .right:
            first = quad.topRight
            second = quad.bottomRight
        case .bottom:
            first = quad.bottomLeft
            second = quad.bottomRight
        case .left:
            first = quad.topLeft
            second = quad.bottomLeft
        }

        return screenPoint(
            CGPoint(
                x:(first.x + second.x) / 2,
                y:(first.y + second.y) / 2
            ),
            in:frame
        )
    }

    private func cornerHandle(
        _ corner:PerspectiveCropCorner,
        in frame:CGRect
    )->some View {
        Circle()
            .fill(Color.white)
            .overlay {
                Circle().stroke(cropColor, lineWidth:3)
            }
            .frame(width:28, height:28)
            .position(
                screenPoint(
                    quad.point(for:corner),
                    in:frame
                )
            )
            .gesture(
                cornerGesture(corner, in:frame)
            )
    }

    private func edgeHandle(
        _ edge:PerspectiveCropEdge,
        in frame:CGRect
    )->some View {
        Capsule()
            .fill(Color.white)
            .overlay {
                Capsule().stroke(cropColor, lineWidth:3)
            }
            .frame(
                width:edge.usesHorizontalHandle ? 54 : 18,
                height:edge.usesHorizontalHandle ? 18 : 54
            )
            .contentShape(Rectangle().inset(by:-10))
            .position(edgeMidpoint(edge, in:frame))
            .gesture(edgeGesture(edge, in:frame))
    }

    private func cornerGesture(
        _ corner:PerspectiveCropCorner,
        in frame:CGRect
    )->some Gesture {
        DragGesture()
            .onChanged { value in
                if cornerStartQuad == nil {
                    cornerStartQuad = quad
                }
                guard let start = cornerStartQuad,
                      frame.width > 0,
                      frame.height > 0 else { return }

                let startPoint = start.point(for:corner)
                let point = CGPoint(
                    x:clamp(
                        startPoint.x + value.translation.width / frame.width,
                        lower:0,
                        upper:1
                    ),
                    y:clamp(
                        startPoint.y + value.translation.height / frame.height,
                        lower:0,
                        upper:1
                    )
                )
                let candidate = start.setting(corner, to:point)
                if candidate.isValid {
                    quad = candidate
                }
            }
            .onEnded { _ in
                cornerStartQuad = nil
            }
    }

    private func edgeGesture(
        _ edge:PerspectiveCropEdge,
        in frame:CGRect
    )->some Gesture {
        DragGesture()
            .onChanged { value in
                if edgeStartQuad == nil {
                    edgeStartQuad = quad
                }
                guard let start = edgeStartQuad,
                      frame.width > 0,
                      frame.height > 0 else { return }

                var dx = value.translation.width / frame.width
                var dy = value.translation.height / frame.height

                switch edge {
                case .top:
                    dx = 0
                    let values = [start.topLeft.y, start.topRight.y]
                    dy = clamp(
                        dy,
                        lower:-(values.min() ?? 0),
                        upper:1 - (values.max() ?? 1)
                    )
                case .bottom:
                    dx = 0
                    let values = [start.bottomLeft.y, start.bottomRight.y]
                    dy = clamp(
                        dy,
                        lower:-(values.min() ?? 0),
                        upper:1 - (values.max() ?? 1)
                    )
                case .left:
                    dy = 0
                    let values = [start.topLeft.x, start.bottomLeft.x]
                    dx = clamp(
                        dx,
                        lower:-(values.min() ?? 0),
                        upper:1 - (values.max() ?? 1)
                    )
                case .right:
                    dy = 0
                    let values = [start.topRight.x, start.bottomRight.x]
                    dx = clamp(
                        dx,
                        lower:-(values.min() ?? 0),
                        upper:1 - (values.max() ?? 1)
                    )
                }

                let candidate = start.moving(edge:edge, dx:dx, dy:dy)
                if candidate.isValid {
                    quad = candidate
                }
            }
            .onEnded { _ in
                edgeStartQuad = nil
            }
    }

    private func moveGesture(in frame:CGRect)->some Gesture {
        DragGesture(minimumDistance:3)
            .onChanged { value in
                if moveStartQuad == nil {
                    moveStartQuad = quad
                }
                guard let start = moveStartQuad,
                      frame.width > 0,
                      frame.height > 0 else { return }

                let points = start.points
                let minX = points.map(\.x).min() ?? 0
                let maxX = points.map(\.x).max() ?? 1
                let minY = points.map(\.y).min() ?? 0
                let maxY = points.map(\.y).max() ?? 1

                let dx = clamp(
                    value.translation.width / frame.width,
                    lower:-minX,
                    upper:1 - maxX
                )
                let dy = clamp(
                    value.translation.height / frame.height,
                    lower:-minY,
                    upper:1 - maxY
                )
                quad = start.translated(dx:dx, dy:dy)
            }
            .onEnded { _ in
                moveStartQuad = nil
            }
    }

    private func rotate(clockwise:Bool) {
        workingImage = Self.rotatedImage(
            workingImage,
            clockwise:clockwise
        )
        quad = quad.rotated(clockwise:clockwise)
        if let automaticQuad {
            self.automaticQuad = automaticQuad.rotated(
                clockwise:clockwise
            )
        }
        clearGestureState()
        resetCanvasZoom()
    }

    private func restoreAutomaticCrop() {
        if let automaticQuad {
            quad = automaticQuad
            clearGestureState()
            resetCanvasZoom()
            return
        }

        resetCanvasZoom()
        detectAutomaticCrop(applyWhenFinished:true)
    }

    private func detectAutomaticCrop(applyWhenFinished:Bool) {
        guard !isDetectingAutomaticCrop else {
            if automaticQuad == nil {
                automaticQuad = .all
                if applyWhenFinished {
                    quad = .all
                }
            }
            return
        }

        isDetectingAutomaticCrop = true

        ScanProcessor.shared.detectAutomaticCropCorners(
            in:workingImage
        ) { corners in
            let detectedQuad = corners.map {
                Self.cropQuad(from:$0)
            }

            let validQuad = detectedQuad?.isValid == true
                ? detectedQuad
                : .all
            automaticQuad = validQuad
            isDetectingAutomaticCrop = false

            if applyWhenFinished {
                quad = validQuad ?? .all
                clearGestureState()
            }
        }
    }

    private static func cropQuad(
        from corners:ScanCorners
    )->PerspectiveCropQuad {
        PerspectiveCropQuad(
            topLeft:corners.topLeft,
            topRight:corners.topRight,
            bottomRight:corners.bottomRight,
            bottomLeft:corners.bottomLeft
        )
    }

    private func clearGestureState() {
        cornerStartQuad = nil
        edgeStartQuad = nil
        moveStartQuad = nil
    }

    private func perspectiveCorrectedImage()->UIImage? {
        guard let input = CIImage(image:workingImage) else {
            return nil
        }

        let extent = input.extent
        func imagePoint(_ point:CGPoint)->CGPoint {
            CGPoint(
                x:extent.minX + point.x * extent.width,
                y:extent.minY + (1 - point.y) * extent.height
            )
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = input
        filter.topLeft = imagePoint(quad.topLeft)
        filter.topRight = imagePoint(quad.topRight)
        filter.bottomRight = imagePoint(quad.bottomRight)
        filter.bottomLeft = imagePoint(quad.bottomLeft)

        guard let output = filter.outputImage else {
            return nil
        }

        let outputRect = output.extent.integral
        guard outputRect.width > 0,
              outputRect.height > 0,
              let cgImage = CIContext().createCGImage(
                output,
                from:outputRect
              ) else {
            return nil
        }

        return UIImage(
            cgImage:cgImage,
            scale:1,
            orientation:.up
        )
    }

    private func clamp(
        _ value:CGFloat,
        lower:CGFloat,
        upper:CGFloat
    )->CGFloat {
        min(max(value, lower), upper)
    }

    private static func normalizedImage(_ image:UIImage)->UIImage {
        guard image.imageOrientation != .up || image.scale != 1 else {
            return image
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size:image.size,
            format:format
        ).image { _ in
            image.draw(
                in:CGRect(origin:.zero, size:image.size)
            )
        }
    }

    private static func rotatedImage(
        _ image:UIImage,
        clockwise:Bool
    )->UIImage {
        let newSize = CGSize(
            width:image.size.height,
            height:image.size.width
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(
            size:newSize,
            format:format
        ).image { rendererContext in
            let context = rendererContext.cgContext
            context.translateBy(
                x:newSize.width / 2,
                y:newSize.height / 2
            )
            context.rotate(
                by:clockwise ? .pi / 2 : -.pi / 2
            )
            image.draw(
                in:CGRect(
                    x:-image.size.width / 2,
                    y:-image.size.height / 2,
                    width:image.size.width,
                    height:image.size.height
                )
            )
        }
    }
}
