//
//  ScanPreviewView.swift
//  AoiScan
//

import SwiftUI
import CoreData
import CoreImage
import CoreImage.CIFilterBuiltins


struct ScanPreviewView:View {
    @State private var pages:[ScanPage]
    @State private var currentPage = 0
    @State private var saving = false
    @State private var showDeleteAlert = false
    @State private var showCropSheet = false
    @State private var showFilterMenu = false
    @State private var showTextRecognition = false
    @State private var recognizedTexts:[Int:String] = [:]
    @State private var recognizedResults:[Int:OCRPageResult] = [:]
    @State private var promptedManualCropPages:Set<UUID> = []
    @State private var manuallyRecognizedPageIDs:Set<UUID> = []
    @State private var pendingEnhancementPageIDs:[UUID] = []
    @State private var activeEnhancementPageID:UUID?
    @State private var enhancementBannerToken:UUID?
    @State private var enhancementBannerShownAt:Date?
    @State private var showEnhancementBanner = false
    @State private var didScheduleInitialEnhancement = false
    @State private var viewIsActive = false

    @Environment(\.dismiss)
    private var dismiss

    init(pages:[ScanPage]) {
        _pages = State(initialValue:pages)
    }

    var body:some View {
        NavigationStack {
            VStack(spacing:0) {
                if pages.isEmpty {
                    Spacer()
                    Text("没有可预览的扫描页面")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                else {
                    TabView(selection:$currentPage) {
                        ForEach(pages.indices, id:\.self) { index in
                            VStack(spacing:12) {
                                ZoomableImageView(
                                    image:pages[index].previewImage
                                )
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius:12
                                        )
                                    )
                                    .padding(.horizontal)
                                    .id(pages[index].id)

                                Text(
                                    L10n.format(
                                        "第 %@ 页 / 共 %@ 页",
                                        String(index + 1),
                                        String(pages.count)
                                    )
                                )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode:.always))
                    .overlay(alignment:.bottom) {
                        if showEnhancementBanner {
                            enhancementBanner
                                .padding(.bottom,34)
                                .transition(
                                    .opacity.combined(with:.move(edge:.bottom))
                                )
                        }
                    }

                    Divider()

                    editingControls

                    saveButton
                }
            }
            .navigationTitle("扫描预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button {
                        discardTemporaryPagesAndDismiss()
                    } label: {
                        Image(systemName:"chevron.left")
                    }
                }

                ToolbarItem(placement:.topBarTrailing) {
                    Button {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName:"trash")
                    }
                }
            }
            .alert(
                "删除扫描？",
                isPresented:$showDeleteAlert
            ) {
                Button("取消", role:.cancel) {}
                Button("删除", role:.destructive) {
                    discardTemporaryPagesAndDismiss()
                }
            }
            .confirmationDialog(
                "选择当前页滤镜",
                isPresented:$showFilterMenu
            ) {
                ForEach(ScanPageFilter.allCases, id:\.self) { filter in
                    Button {
                        applyFilter(filter, at:currentPage)
                    } label: {
                        if pages.indices.contains(currentPage),
                           pages[currentPage].filter == filter {
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
            .sheet(isPresented:$showCropSheet) {
                if pages.indices.contains(currentPage) {
                    CropSheet(
                        image:pages[currentPage]
                            .fullResolutionOriginalImage(),
                        initialCorners:
                            pages[currentPage].detectedCorners
                            ?? pages[currentPage].suggestedCropCorners
                    ) { result in
                        applyCropResult(
                            result,
                            at:currentPage
                        )
                    } onCancel: {
                        showCropSheet = false
                    }
                }
            }
            .sheet(isPresented:$showTextRecognition) {
                if !pages.isEmpty {
                    TextRecognitionView(
                        images:pages.map(\.previewImage),
                        initialPage:currentPage,
                        initialTexts:recognizedTexts,
                        initialResults:recognizedResults
                    ) { pageIndex, text, result in
                        recognizedTexts[pageIndex] = text

                        if let result {
                            recognizedResults[pageIndex] = result
                                .withPageNumber(pageIndex + 1)
                        }

                        if pages.indices.contains(pageIndex) {
                            manuallyRecognizedPageIDs.insert(
                                pages[pageIndex].id
                            )
                        }

                        currentPage = pageIndex
                    }
                }
            }
        }
        .onAppear {
            viewIsActive = true
            presentManualCropIfNeeded()
            scheduleInitialSmartEnhancement()
        }
        .onChange(of:currentPage) { _, _ in
            presentManualCropIfNeeded()
        }
        .onDisappear {
            viewIsActive = false
            pendingEnhancementPageIDs.removeAll()
            activeEnhancementPageID = nil
            enhancementBannerToken = nil
            showEnhancementBanner = false
            removeTemporaryPageFiles()
        }
    }

    private func presentManualCropIfNeeded() {
        guard pages.indices.contains(currentPage) else { return }

        let page = pages[currentPage]
        guard page.detectedCorners == nil,
              !promptedManualCropPages.contains(page.id) else {
            return
        }

        promptedManualCropPages.insert(page.id)
        let pageID = page.id

        DispatchQueue.main.asyncAfter(deadline:.now() + 0.35) {
            guard pages.indices.contains(currentPage),
                  pages[currentPage].id == pageID else {
                return
            }
            showCropSheet = true
        }
    }

    private var editingControls:some View {
        HStack(spacing:0) {
            Button {
                if pages.indices.contains(currentPage) {
                    showCropSheet = true
                }
            } label: {
                VStack(spacing:5) {
                    Image(systemName:"crop")
                        .font(.title2)
                    Text("调整")
                        .font(.caption)
                }
                .frame(maxWidth:.infinity)
            }

            Button {
                if pages.indices.contains(currentPage) {
                    showFilterMenu = true
                }
            } label: {
                VStack(spacing:5) {
                    Image(systemName:"circle.lefthalf.filled")
                        .font(.title2)
                    Text("滤镜")
                        .font(.caption)
                }
                .frame(maxWidth:.infinity)
            }

            Button {
                if pages.indices.contains(currentPage) {
                    showTextRecognition = true
                }
            } label: {
                VStack(spacing:5) {
                    Image(systemName:"text.viewfinder")
                        .font(.title2)
                    Text("识别")
                        .font(.caption)
                }
                .frame(maxWidth:.infinity)
            }
        }
        .padding(.vertical,12)
        .disabled(isSmartEnhancing)
    }

    private var saveButton:some View {
        Button {
            saveDocument()
        } label: {
            HStack {
                if saving {
                    ProgressView()
                        .tint(.white)
                }
                else {
                    Image(systemName:"square.and.arrow.down")
                    Text("保存扫描")
                }
            }
            .frame(maxWidth:.infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .cornerRadius(14)
        }
        .padding(.horizontal)
        .padding(.bottom,15)
        .disabled(saving || isSmartEnhancing || pages.isEmpty)
    }

    private func applyCropResult(
        _ result:CropResult,
        at index:Int
    ) {
        guard pages.indices.contains(index) else {
            showCropSheet = false
            return
        }

        var page = pages[index]
        // 保存用户最终确认的四角，之后再次调整时从当前裁切位置开始。
        page.detectedCorners = result.corners
        page.suggestedCropCorners = nil
        page.smartEnhancementSeed = nil
        let preview = filteredImage(
            result.image,
            filter:page.filter
        )

        do {
            try page.replaceStoredImages(
                original:result.sourceImage,
                adjusted:result.image,
                preview:preview
            )
        }
        catch {
            print("裁切结果临时保存失败:", error)
            page.originalImage = result.sourceImage
            page.adjustedImage = result.image
            page.previewImage = preview
        }

        pages[index] = page
        // 裁切会改变页面几何位置，旧 OCR 坐标不再有效。
        recognizedResults[index] = nil
        recognizedTexts[index] = nil
        manuallyRecognizedPageIDs.remove(page.id)
        showCropSheet = false

        if page.filter == .smart {
            enqueueSmartEnhancement(for:page.id)
        }
    }

    private func applyFilter(
        _ filter:ScanPageFilter,
        at index:Int
    ) {
        guard pages.indices.contains(index) else { return }

        var page = pages[index]
        page.filter = filter
        let rendered = filteredImage(
            page.fullResolutionAdjustedImage(),
            filter:filter
        )

        do {
            try page.replaceStoredPreview(rendered)
        }
        catch {
            print("滤镜结果临时保存失败:", error)
            page.previewImage = rendered
        }

        pages[index] = page

        if filter == .smart {
            enqueueSmartEnhancement(for:page.id)
        }
    }

    private func filteredImage(
        _ image:UIImage,
        filter:ScanPageFilter
    )->UIImage {
        DocumentImageFilter.apply(
            filter,
            to:image
        )
    }

    private var isSmartEnhancing:Bool {
        activeEnhancementPageID != nil
            || !pendingEnhancementPageIDs.isEmpty
    }

    private var enhancementBanner:some View {
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

    private func scheduleInitialSmartEnhancement() {
        guard !didScheduleInitialEnhancement else { return }
        didScheduleInitialEnhancement = true

        for page in pages where page.filter == .smart
                && page.detectedCorners != nil {
            enqueueSmartEnhancement(for:page.id)
        }
    }

    private func enqueueSmartEnhancement(for pageID:UUID) {
        guard viewIsActive,
              pages.contains(where:{
                  $0.id == pageID && $0.filter == .smart
              }),
              activeEnhancementPageID != pageID,
              !pendingEnhancementPageIDs.contains(pageID) else {
            return
        }

        pendingEnhancementPageIDs.append(pageID)
        beginEnhancementBannerDelayIfNeeded()
        processNextSmartEnhancement()
    }

    private func processNextSmartEnhancement() {
        guard viewIsActive,
              activeEnhancementPageID == nil else {
            return
        }

        while !pendingEnhancementPageIDs.isEmpty {
            let pageID = pendingEnhancementPageIDs.removeFirst()

            guard let index = pages.firstIndex(where:{
                $0.id == pageID && $0.filter == .smart
            }) else {
                continue
            }

            activeEnhancementPageID = pageID
            let sourceImage = pages[index]
                .fullResolutionAdjustedImage()
            let baselineSeed = pages[index].smartEnhancementSeed

            SmartEnhancementPipeline.process(
                rgbImage:sourceImage,
                pageNumber:index + 1,
                baselineSeed:baselineSeed
            ) { output in
                guard viewIsActive,
                      activeEnhancementPageID == pageID else {
                    return
                }

                if let currentIndex = pages.firstIndex(where:{
                    $0.id == pageID && $0.filter == .smart
                }) {
                    var page = pages[currentIndex]

                    do {
                        try page.replaceStoredPreview(output.image)
                    }
                    catch {
                        print("智能增强结果临时保存失败:", error)
                        page.previewImage = output.image
                    }

                    pages[currentIndex] = page

                    if !manuallyRecognizedPageIDs.contains(pageID),
                       let result = output.ocrResult {
                        let normalized = result.withPageNumber(
                            currentIndex + 1
                        )
                        recognizedResults[currentIndex] = normalized
                        recognizedTexts[currentIndex] = normalized.plainText
                    }
                }

                activeEnhancementPageID = nil
                processNextSmartEnhancement()
                finishEnhancementBannerIfNeeded()
            }

            return
        }

        finishEnhancementBannerIfNeeded()
    }

    private func beginEnhancementBannerDelayIfNeeded() {
        guard enhancementBannerToken == nil else { return }

        let token = UUID()
        enhancementBannerToken = token

        DispatchQueue.main.asyncAfter(deadline:.now() + 0.4) {
            guard enhancementBannerToken == token,
                  isSmartEnhancing else {
                return
            }

            enhancementBannerShownAt = Date()
            withAnimation(.easeInOut(duration:0.2)) {
                showEnhancementBanner = true
            }
        }
    }

    private func finishEnhancementBannerIfNeeded() {
        guard !isSmartEnhancing else { return }

        let token = enhancementBannerToken
        let elapsed = enhancementBannerShownAt.map {
            Date().timeIntervalSince($0)
        } ?? 0.6
        let delay = showEnhancementBanner
            ? max(0, 0.6 - elapsed)
            : 0

        DispatchQueue.main.asyncAfter(deadline:.now() + delay) {
            guard enhancementBannerToken == token,
                  !isSmartEnhancing else {
                return
            }

            withAnimation(.easeInOut(duration:0.2)) {
                showEnhancementBanner = false
            }
            enhancementBannerShownAt = nil
            enhancementBannerToken = nil
        }
    }

    private func saveDocument() {
        guard !pages.isEmpty else { return }
        saving = true

        let fileManager = FileManager.default
        let folderIdentifier = UUID().uuidString
        let folderURL = ScanManager.documentFolderURL(
            for:folderIdentifier
        )

        do {
            try fileManager.createDirectory(
                at:folderURL,
                withIntermediateDirectories:true
            )

            for index in pages.indices {
                let originalURL = folderURL.appendingPathComponent(
                    "original_\(index + 1).jpg"
                )
                let adjustedURL = folderURL.appendingPathComponent(
                    "adjusted_\(index + 1).jpg"
                )
                let displayURL = folderURL.appendingPathComponent(
                    "\(index + 1).jpg"
                )

                try pages[index].writeFullResolutionImages(
                    originalURL:originalURL,
                    adjustedURL:adjustedURL,
                    previewURL:displayURL
                )

                if let recognizedText = recognizedTexts[index] {
                    let textURL = folderURL.appendingPathComponent(
                        "recognized_\(index + 1).txt"
                    )

                    try recognizedText.write(
                        to:textURL,
                        atomically:true,
                        encoding:.utf8
                    )
                }

                if let result = recognizedResults[index] {
                    let structuredURL = OCRStorage.fileURL(
                        in:folderURL,
                        pageNumber:index + 1
                    )

                    try OCRStorage.write(
                        result.withPageNumber(index + 1),
                        to:structuredURL
                    )
                }
            }


            let metadata = pages.indices.map { index in
                ScanPageMetadata(
                    pageNumber:index + 1,
                    corners:pages[index].detectedCorners,
                    filter:pages[index].filter
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let metadataData = try encoder.encode(metadata)
            let metadataURL = folderURL.appendingPathComponent(
                "scan_metadata.json"
            )

            try metadataData.write(
                to:metadataURL,
                options:.atomic
            )

            try createRecord(
                folderIdentifier:folderIdentifier
            )
        }
        catch {
            print("保存失败:", error)

            if fileManager.fileExists(atPath:folderURL.path) {
                do {
                    try fileManager.removeItem(at:folderURL)
                }
                catch {
                    print("清理未完成扫描文件失败:", error)
                }
            }

            saving = false
        }
    }

    private func createRecord(
        folderIdentifier:String
    ) throws {
        let context = PersistenceController.shared.container.viewContext
        let document = ScanEntity(context:context)
        document.id = UUID()
        document.title = L10n.text("扫描文档")
        document.folderPath = folderIdentifier
        document.createdAt = Date()

        do {
            try context.save()
            ScanManager.shared.loadDocuments()
            OCRIndexManager.shared.enqueueNewDocument(document)
            removeTemporaryPageFiles()
            saving = false
            dismiss()
        }
        catch {
            context.rollback()
            throw error
        }
    }


    private func discardTemporaryPagesAndDismiss(){
        removeTemporaryPageFiles()
        dismiss()
    }


    private func removeTemporaryPageFiles(){
        for page in pages {
            page.removeTemporaryFiles()
        }
    }
}
