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
    @State private var promptedManualCropPages:Set<UUID> = []

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
                        initialTexts:recognizedTexts
                    ) { pageIndex, text in
                        recognizedTexts[pageIndex] = text
                        currentPage = pageIndex
                    }
                }
            }
        }
        .onAppear {
            presentManualCropIfNeeded()
        }
        .onChange(of:currentPage) { _, _ in
            presentManualCropIfNeeded()
        }
        .onDisappear {
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
        .disabled(saving || pages.isEmpty)
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
        showCropSheet = false
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
