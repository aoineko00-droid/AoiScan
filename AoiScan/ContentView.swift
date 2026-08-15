//
//  ContentView.swift
//  AoiScan
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers


struct ContentView:View {
    @ObservedObject private var manager = ScanManager.shared

    @State private var showScanner = false
    @State private var showPreview = false
    @State private var previewPages:[ScanPage] = []

    @State private var renameTarget:ScanEntity?
    @State private var newName = ""
    @State private var searchText = ""
    @State private var searchQuery = ""
    @State private var activeFolderID:UUID?

    @State private var isEditingDocuments = false
    @State private var selectedDocumentIDs:Set<UUID> = []
    @State private var showDeleteConfirmation = false
    @State private var mergeSheet:MergeSheetState?
    @State private var shareItem:BatchShareItem?
    @State private var showShareFormatDialog = false
    @State private var pendingShareDocumentIDs:Set<UUID> = []
    @State private var isPerformingBatchAction = false
    @State private var batchActionTitle = ""
    @State private var batchErrorMessage:String?
    @State private var folderEditor:FolderEditorState?
    @State private var documentDeleteTarget:ScanEntity?
    @State private var folderDeleteTarget:ScanFolderEntity?
    @State private var showMoveSheet = false
    @State private var showPDFImporter = false

    @FocusState private var searchFieldFocused:Bool

    var body:some View {
        NavigationStack {
            VStack(spacing:0) {
                header
                searchBar
                documentContent

                if isEditingDocuments {
                    ScanBatchActionBar(
                        selectedCount:selectedDocumentIDs.count,
                        onShare:shareSelectedDocuments,
                        onMerge:presentMergeSheet,
                        onMove:{ showMoveSheet = true },
                        onDelete:{
                            showDeleteConfirmation = true
                        }
                    )
                }
                else {
                    ScanButton {
                        searchFieldFocused = false
                        previewPages.removeAll()
                        showPreview = false
                        showScanner = true
                    }
                    .padding(.bottom,40)
                }
            }
            .toolbar(.hidden, for:.navigationBar)
            .task(id:searchText) {
                await updateSearchQuery()
            }
            .onChange(of:searchText) { _,_ in
                if isEditingDocuments {
                    selectedDocumentIDs.removeAll()
                }
            }
            .ignoresSafeArea(.keyboard, edges:.bottom)
        }
        .overlay {
            if isPerformingBatchAction {
                batchProgressOverlay
            }
        }
        .sheet(isPresented:$showScanner) {
            if showPreview {
                ScanPreviewView(
                    pages:previewPages,
                    destinationFolderID:activeFolderID
                )
            }
            else {
                CameraScannerView(
                    pages:$previewPages,
                    showPreview:$showPreview
                )
            }
        }
        .sheet(item:$shareItem) { item in
            ShareSheet(activityItems:item.urls)
        }
        .sheet(item:$mergeSheet) { state in
            ScanMergeView(
                items:state.items,
                initialName:state.initialName
            ) { orderedIDs,title,originalDisposition in
                mergeSheet = nil
                mergeDocuments(
                    orderedIDs:orderedIDs,
                    title:title,
                    deleteOriginals:originalDisposition == .delete
                )
            }
        }
        .sheet(item:$folderEditor) { editor in
            FolderNameEditor(
                title:editor.isCreating
                    ? L10n.text("新建文件夹")
                    : L10n.text("重命名文件夹"),
                initialName:editor.initialName,
                confirmationTitle:editor.isCreating
                    ? L10n.text("新建")
                    : L10n.text("保存")
            ) { name in
                if let folderID = editor.folderID,
                   let folder = manager.folder(withID:folderID) {
                    try manager.renameFolder(folder, newName:name)
                }
                else {
                    _ = try manager.createFolder(named:name)
                }
            }
        }
        .sheet(isPresented:$showMoveSheet) {
            MoveDocumentsSheet(
                folders:folderChoices,
                currentFolderID:activeFolderID,
                onCreateFolder:{ name in
                    let folder = try manager.createFolder(named:name)
                    return folderChoice(folder)
                },
                onMove:{ folderID in
                    try manager.moveDocuments(
                        selectedDocuments,
                        to:folderID
                    )
                    exitEditingMode()
                }
            )
        }
        .fileImporter(
            isPresented:$showPDFImporter,
            allowedContentTypes:[.pdf],
            allowsMultipleSelection:true
        ) { result in
            handlePDFSelection(result)
        }
        .confirmationDialog(
            L10n.text("分享格式"),
            isPresented:$showShareFormatDialog,
            titleVisibility:.visible
        ) {
            Button(L10n.text("分享为 PDF")) {
                sharePendingDocuments(as:.pdf)
            }
            Button(L10n.text("分享为 JPG")) {
                sharePendingDocuments(as:.jpg)
            }
            Button(L10n.text("取消"), role:.cancel) {
                pendingShareDocumentIDs.removeAll()
            }
        }
        .alert(
            L10n.text("重命名"),
            isPresented:Binding(
                get:{ renameTarget != nil },
                set:{ if !$0 { renameTarget = nil } }
            )
        ) {
            TextField(L10n.text("文件名称"), text:$newName)

            Button(L10n.text("保存")) {
                if let target = renameTarget {
                    manager.renameDocument(target, newName:newName)
                }
                renameTarget = nil
            }

            Button(L10n.text("取消"), role:.cancel) {
                renameTarget = nil
            }
        }
        .alert(
            L10n.text("删除扫描文件"),
            isPresented:Binding(
                get:{ documentDeleteTarget != nil },
                set:{ if !$0 { documentDeleteTarget = nil } }
            )
        ) {
            Button(L10n.text("取消"), role:.cancel) {
                documentDeleteTarget = nil
            }
            Button(L10n.text("删除"), role:.destructive) {
                deleteTargetDocument()
            }
        } message: {
            Text(documentDeleteMessage)
        }
        .alert(
            L10n.text("批量删除"),
            isPresented:$showDeleteConfirmation
        ) {
            Button(L10n.text("取消"), role:.cancel) {}
            Button(L10n.text("删除"), role:.destructive) {
                deleteSelectedDocuments()
            }
        } message: {
            Text(
                L10n.format(
                    "确定删除选中的 %@ 个扫描文件吗？此操作无法撤销。",
                    NSNumber(value:selectedDocumentIDs.count)
                )
            )
        }
        .alert(
            L10n.text("文件操作失败"),
            isPresented:Binding(
                get:{ batchErrorMessage != nil },
                set:{ if !$0 { batchErrorMessage = nil } }
            )
        ) {
            Button(L10n.text("好"), role:.cancel) {
                batchErrorMessage = nil
            }
        } message: {
            Text(batchErrorMessage ?? "")
        }
        .alert(
            L10n.text("删除文件夹"),
            isPresented:Binding(
                get:{ folderDeleteTarget != nil },
                set:{ if !$0 { folderDeleteTarget = nil } }
            )
        ) {
            Button(L10n.text("取消"), role:.cancel) {
                folderDeleteTarget = nil
            }
            Button(L10n.text("删除"), role:.destructive) {
                deleteTargetFolder()
            }
        } message: {
            Text(folderDeleteMessage)
        }
    }

    private var header:some View {
        HStack(alignment:.center) {
            if isEditingDocuments {
                Button(
                    allVisibleDocumentsSelected
                        ? L10n.text("取消全选")
                        : L10n.text("全选")
                ) {
                    toggleSelectAllVisibleDocuments()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(filteredDocuments.isEmpty)

                Spacer()

                Button(L10n.text("取消")) {
                    exitEditingMode()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            else {
                if activeFolderID != nil {
                    Button {
                        leaveActiveFolder()
                    } label: {
                        Image(systemName:"chevron.left")
                            .font(.system(size:20, weight:.semibold))
                            .foregroundStyle(.primary)
                            .frame(width:36, height:44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(activeFolder?.title ?? L10n.text("文件夹"))
                        .font(.system(size:27, weight:.bold))
                        .lineLimit(1)
                }
                else {
                    Text("AoiScan")
                        .font(.system(size:34, weight:.bold))
                }

                Spacer()

                Menu {
                    if activeFolderID == nil {
                        Button {
                            presentCreateFolder()
                        } label: {
                            Label(
                                L10n.text("新建文件夹"),
                                systemImage:"folder.badge.plus"
                            )
                        }
                    }

                    Button {
                        showPDFImporter = true
                    } label: {
                        Label(
                            L10n.text("导入 PDF"),
                            systemImage:"doc.badge.plus"
                        )
                    }
                } label: {
                    Image(systemName:"plus")
                        .font(.system(size:21, weight:.medium))
                        .foregroundStyle(.primary)
                        .frame(width:44, height:44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    searchFieldFocused = false
                    selectedDocumentIDs.removeAll()
                    withAnimation(.easeInOut(duration:0.18)) {
                        isEditingDocuments = true
                    }
                } label: {
                    Image(systemName:"line.3.horizontal")
                        .font(.system(size:21, weight:.medium))
                        .foregroundStyle(.primary)
                        .frame(width:44, height:44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(baseDocuments.isEmpty)
                .accessibilityLabel(L10n.text("编辑"))

                if activeFolderID == nil {
                    NavigationLink {
                        AppSettingsView()
                            .toolbar(.visible, for:.navigationBar)
                    } label: {
                        Image(systemName:"gearshape")
                            .font(.system(size:21, weight:.medium))
                            .foregroundStyle(.primary)
                            .frame(width:44, height:44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            searchFieldFocused = false
                        }
                    )
                }
            }
        }
        .frame(minHeight:44)
        .padding(.leading,20)
        .padding(.trailing,12)
        .padding(.top,6)
        .padding(.bottom,6)
    }

    private var searchBar:some View {
        HStack(spacing:10) {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(
                    L10n.text("搜索文件名或扫描文字"),
                    text:$searchText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFieldFocused)
                .onSubmit {
                    searchFieldFocused = false
                }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchQuery = ""
                    } label: {
                        Image(systemName:"xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal,14)
            .frame(height:42)
            .background(Color(.secondarySystemBackground))
            .clipShape(
                RoundedRectangle(
                    cornerRadius:12,
                    style:.continuous
                )
            )

            if searchFieldFocused {
                Button(L10n.text("取消")) {
                    searchText = ""
                    searchQuery = ""
                    searchFieldFocused = false
                }
                .foregroundStyle(.blue)
                .buttonStyle(.plain)
                .transition(
                    .opacity.combined(with:.move(edge:.trailing))
                )
            }
        }
        .padding(.horizontal,20)
        .padding(.top,4)
        .padding(.bottom,8)
        .animation(
            .easeInOut(duration:0.18),
            value:searchFieldFocused
        )
    }

    @ViewBuilder
    private var documentContent:some View {
        if visibleFolders.isEmpty && filteredDocuments.isEmpty {
            Spacer()
            if searchQuery.isEmpty {
                VStack(spacing:10) {
                    Image(
                        systemName:activeFolderID == nil
                            ? "doc.text.image"
                            : "folder"
                    )
                    .font(.system(size:38))
                    .foregroundStyle(.secondary)

                    Text(
                        activeFolderID == nil
                            ? L10n.text("暂无扫描文档")
                            : L10n.text("该文件夹中暂无文件")
                    )
                    .foregroundStyle(.secondary)
                }
            }
            else {
                ContentUnavailableView.search(text:searchText)
            }
            Spacer()
        }
        else {
            List {
                if !isEditingDocuments && !visibleFolders.isEmpty {
                    Section(L10n.text("文件夹")) {
                        ForEach(visibleFolders, id:\.id) { folder in
                            Button {
                                enterFolder(folder)
                            } label: {
                                folderLabel(folder)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(
                                edge:.trailing,
                                allowsFullSwipe:false
                            ) {
                                Button {
                                    presentRenameFolder(folder)
                                } label: {
                                    Label(
                                        L10n.text("重命名"),
                                        systemImage:"pencil"
                                    )
                                }
                                .tint(.blue)

                                Button(role:.destructive) {
                                    folderDeleteTarget = folder
                                } label: {
                                    Label(
                                        L10n.text("删除"),
                                        systemImage:"trash"
                                    )
                                }
                            }
                        }
                    }
                }

                if !filteredDocuments.isEmpty {
                    Section(
                        activeFolderID == nil
                            ? L10n.text("扫描文件")
                            : ""
                    ) {
                ForEach(filteredDocuments, id:\.id) { document in
                    if isEditingDocuments {
                        Button {
                            toggleSelection(for:document)
                        } label: {
                            HStack(spacing:12) {
                                Image(
                                    systemName:isSelected(document)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .font(.system(size:22, weight:.medium))
                                .foregroundStyle(
                                    isSelected(document)
                                        ? Color.blue
                                        : Color.secondary
                                )

                                documentLabel(document)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(
                            isSelected(document)
                                ? L10n.text("已选中")
                                : L10n.text("未选中")
                        )
                    }
                    else {
                        NavigationLink {
                            ScanDetailView(document:document)
                        } label: {
                            documentLabel(document)
                        }
                        .swipeActions(
                            edge:.trailing,
                            allowsFullSwipe:false
                        ) {
                            Button {
                                renameTarget = document
                                newName = document.title ?? ""
                            } label: {
                                Label(
                                    L10n.text("重命名"),
                                    systemImage:"pencil"
                                )
                            }
                            .tint(.blue)

                            Button(role:.destructive) {
                                documentDeleteTarget = document
                            } label: {
                                Label(
                                    L10n.text("删除"),
                                    systemImage:"trash"
                                )
                            }
                        }
                    }
                }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func folderLabel(_ folder:ScanFolderEntity)->some View {
        HStack(spacing:13) {
            Image(systemName:"folder.fill")
                .font(.system(size:24))
                .foregroundStyle(.blue)
                .frame(width:32)

            VStack(alignment:.leading, spacing:4) {
                Text(folder.title ?? L10n.text("未命名文件夹"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(
                    L10n.format(
                        "%@ 个文件",
                        NSNumber(value:manager.documentCount(in:folder))
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName:"chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical,7)
        .contentShape(Rectangle())
    }

    private func documentLabel(_ document:ScanEntity)->some View {
        HStack(spacing:12) {
            ScanDocumentThumbnailView(
                folderURL:manager.folderURL(
                    for:document,
                    migrateIfNeeded:false
                )
            )

            VStack(alignment:.leading, spacing:6) {
                Text(document.title ?? L10n.text("未命名文档"))
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let date = document.createdAt {
                    Text(
                        date,
                        format:.dateTime
                            .year()
                            .month()
                            .day()
                            .hour()
                            .minute()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if activeFolderID == nil,
                   !searchQuery.isEmpty,
                   let folderTitle = document.parentFolder?.title {
                    Label(folderTitle, systemImage:"folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth:.infinity, alignment:.leading)
        }
        .padding(.vertical,6)
        .frame(maxWidth:.infinity, alignment:.leading)
    }

    private var batchProgressOverlay:some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing:12) {
                ProgressView()
                Text(batchActionTitle)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal,28)
            .padding(.vertical,22)
            .background(.regularMaterial)
            .clipShape(
                RoundedRectangle(
                    cornerRadius:16,
                    style:.continuous
                )
            )
        }
    }

    private var activeFolder:ScanFolderEntity? {
        manager.folder(withID:activeFolderID)
    }

    private var baseDocuments:[ScanEntity] {
        if let activeFolderID {
            return manager.documents.filter {
                $0.parentFolder?.id == activeFolderID
            }
        }

        if !searchQuery.trimmingCharacters(
            in:.whitespacesAndNewlines
        ).isEmpty {
            return manager.documents
        }

        return manager.documents.filter { $0.parentFolder == nil }
    }

    private var filteredDocuments:[ScanEntity] {
        let query = searchQuery.trimmingCharacters(
            in:.whitespacesAndNewlines
        )

        guard !query.isEmpty else {
            return baseDocuments
        }

        return baseDocuments.filter { document in
            let titleMatches = (document.title ?? "")
                .localizedCaseInsensitiveContains(query)
            let textMatches = (document.searchableText ?? "")
                .localizedCaseInsensitiveContains(query)
            return titleMatches || textMatches
        }
    }

    private var visibleFolders:[ScanFolderEntity] {
        guard activeFolderID == nil,
              !isEditingDocuments else {
            return []
        }
        let query = searchQuery.trimmingCharacters(
            in:.whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            return manager.folders
        }
        return manager.folders.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var folderChoices:[ScanFolderChoice] {
        manager.folders.map(folderChoice)
    }

    private var selectedDocuments:[ScanEntity] {
        manager.documents.filter { document in
            guard let id = document.id else { return false }
            return selectedDocumentIDs.contains(id)
        }
    }

    private var allVisibleDocumentsSelected:Bool {
        let visibleIDs = filteredDocuments.compactMap(\.id)
        return !visibleIDs.isEmpty
            && visibleIDs.allSatisfy(selectedDocumentIDs.contains)
    }

    private func toggleSelectAllVisibleDocuments() {
        let visibleIDs = Set(filteredDocuments.compactMap(\.id))

        if allVisibleDocumentsSelected {
            selectedDocumentIDs.subtract(visibleIDs)
        }
        else {
            selectedDocumentIDs.formUnion(visibleIDs)
        }
    }

    private func toggleSelection(for document:ScanEntity) {
        guard let id = document.id else { return }

        if selectedDocumentIDs.contains(id) {
            selectedDocumentIDs.remove(id)
        }
        else {
            selectedDocumentIDs.insert(id)
        }
    }

    private func isSelected(_ document:ScanEntity)->Bool {
        guard let id = document.id else { return false }
        return selectedDocumentIDs.contains(id)
    }

    private func folderChoice(
        _ folder:ScanFolderEntity
    )->ScanFolderChoice {
        ScanFolderChoice(
            id:folder.id ?? UUID(),
            title:folder.title ?? L10n.text("未命名文件夹"),
            documentCount:manager.documentCount(in:folder)
        )
    }

    private func enterFolder(_ folder:ScanFolderEntity) {
        guard let id = folder.id else { return }
        searchText = ""
        searchQuery = ""
        searchFieldFocused = false
        selectedDocumentIDs.removeAll()
        withAnimation(.easeInOut(duration:0.18)) {
            activeFolderID = id
        }
    }

    private func leaveActiveFolder() {
        searchText = ""
        searchQuery = ""
        searchFieldFocused = false
        selectedDocumentIDs.removeAll()
        withAnimation(.easeInOut(duration:0.18)) {
            activeFolderID = nil
        }
    }

    private func presentCreateFolder() {
        folderEditor = FolderEditorState(
            folderID:nil,
            initialName:""
        )
    }

    private func presentRenameFolder(
        _ folder:ScanFolderEntity
    ) {
        folderEditor = FolderEditorState(
            folderID:folder.id,
            initialName:folder.title ?? ""
        )
    }

    private var folderDeleteMessage:String {
        guard let folderDeleteTarget else { return "" }
        let count = manager.documentCount(in:folderDeleteTarget)
        return L10n.format(
            "删除文件夹后，其中的 %@ 个扫描文件将移回根目录。",
            NSNumber(value:count)
        )
    }

    private var documentDeleteMessage:String {
        guard let documentDeleteTarget else { return "" }
        return L10n.format(
            "确定删除“%@”吗？此操作无法撤销。",
            (documentDeleteTarget.title
                ?? L10n.text("未命名文档")) as NSString
        )
    }

    private func deleteTargetDocument() {
        guard let document = documentDeleteTarget else { return }
        documentDeleteTarget = nil

        do {
            try manager.deleteDocuments([document])
        }
        catch {
            finishBatchAction(error:error)
        }
    }

    private func deleteTargetFolder() {
        guard let folder = folderDeleteTarget else { return }
        do {
            try manager.deleteFolder(folder)
            folderDeleteTarget = nil
        }
        catch {
            folderDeleteTarget = nil
            finishBatchAction(error:error)
        }
    }

    private func handlePDFSelection(
        _ selection:Result<[URL],Error>
    ) {
        switch selection {
        case .success(let urls):
            importPDFs(urls)
        case .failure(let error):
            let cocoaError = error as NSError
            guard cocoaError.code != CocoaError.userCancelled.rawValue else {
                return
            }
            finishBatchAction(error:error)
        }
    }

    private func importPDFs(_ urls:[URL]) {
        guard !urls.isEmpty else { return }
        let destinationFolderID = activeFolderID
        beginBatchAction(L10n.text("正在导入 PDF…"))

        Task {
            do {
                let results = try await Task.detached(
                    priority:.userInitiated
                ) {
                    try PDFImportService.importPDFs(
                        from:urls,
                        progress:{ _ in }
                    )
                }.value

                do {
                    try await MainActor.run { () throws->Void in
                        try manager.registerImportedPDFs(
                            results,
                            parentFolderID:destinationFolderID
                        )
                    }
                }
                catch {
                    await Task.detached(priority:.utility) {
                        PDFImportService.removeImportedFiles(results)
                    }.value
                    throw error
                }

                await MainActor.run {
                    finishBatchAction()
                }
            }
            catch {
                await MainActor.run {
                    finishBatchAction(error:error)
                }
            }
        }
    }

    private func exitEditingMode() {
        selectedDocumentIDs.removeAll()
        withAnimation(.easeInOut(duration:0.18)) {
            isEditingDocuments = false
        }
    }

    private func deleteSelectedDocuments() {
        let documents = selectedDocuments
        guard !documents.isEmpty else { return }

        beginBatchAction(L10n.text("正在删除…"))

        Task { @MainActor in
            await Task.yield()

            do {
                try manager.deleteDocuments(documents)
                finishBatchAction()
                exitEditingMode()
            }
            catch {
                finishBatchAction(error:error)
            }
        }
    }

    private func shareSelectedDocuments() {
        presentShareOptions(for:selectedDocuments)
    }

    private func presentShareOptions(
        for documents:[ScanEntity]
    ) {
        pendingShareDocumentIDs = Set(documents.compactMap(\.id))
        showShareFormatDialog = !pendingShareDocumentIDs.isEmpty
    }

    private func sharePendingDocuments(
        as format:BatchShareFormat
    ) {
        let documentIDs = pendingShareDocumentIDs
        pendingShareDocumentIDs.removeAll()
        let documents = manager.documents.filter { document in
            guard let id = document.id else { return false }
            return documentIDs.contains(id)
        }
        shareDocuments(documents, as:format)
    }

    private func shareDocuments(
        _ documents:[ScanEntity],
        as format:BatchShareFormat
    ) {
        guard !documents.isEmpty else { return }

        do {
            let references = try manager.fileReferences(for:documents)
            beginBatchAction(L10n.text("正在准备分享…"))

            Task {
                do {
                    let urls = try await Task.detached(
                        priority:.userInitiated
                    ) {
                        switch format {
                        case .pdf:
                            return try references.map { reference in
                                try PDFManager.generatePDF(
                                    in:reference.folderURL,
                                    title:reference.title
                                )
                            }
                        case .jpg:
                            return try JPGExportService.exportDocuments(
                                references
                            )
                        }
                    }.value

                    await MainActor.run {
                        finishBatchAction()
                        shareItem = BatchShareItem(urls:urls)
                    }
                }
                catch {
                    await MainActor.run {
                        finishBatchAction(error:error)
                    }
                }
            }
        }
        catch {
            finishBatchAction(error:error)
        }
    }

    private func presentMergeSheet() {
        let documents = selectedDocuments
        guard documents.count >= 2 else { return }

        do {
            let references = try manager.fileReferences(for:documents)
            let items = references.map { reference in
                ScanMergeItem(
                    id:reference.id,
                    title:reference.title,
                    pageCount:PDFManager.pageCount(
                        in:reference.folderURL
                    )
                )
            }
            mergeSheet = MergeSheetState(
                items:items,
                initialName:defaultMergedDocumentName()
            )
        }
        catch {
            finishBatchAction(error:error)
        }
    }

    private func mergeDocuments(
        orderedIDs:[UUID],
        title:String,
        deleteOriginals:Bool
    ) {
        let documentsByID:[UUID:ScanEntity] = Dictionary(
            uniqueKeysWithValues:selectedDocuments.compactMap { document in
                guard let id = document.id else { return nil }
                return (id,document)
            }
        )
        let orderedDocuments = orderedIDs.compactMap { documentsByID[$0] }

        guard orderedDocuments.count >= 2 else { return }

        do {
            let references = try manager.fileReferences(
                for:orderedDocuments
            )
            let destinationFolderID = activeFolderID
            beginBatchAction(L10n.text("正在合并…"))

            Task {
                do {
                    let result = try await Task.detached(
                        priority:.userInitiated
                    ) {
                        try ScanFileOperationService.merge(
                            references,
                            title:title
                        )
                    }.value

                    do {
                        try await MainActor.run { () throws->Void in
                            try manager.registerMergedDocument(
                                result,
                                parentFolderID:destinationFolderID,
                                deletingDocumentIDs:deleteOriginals
                                    ? Set(orderedIDs)
                                    : []
                            )
                        }
                    }
                    catch {
                        try? FileManager.default.removeItem(
                            at:result.folderURL
                        )
                        throw error
                    }

                    await MainActor.run {
                        finishBatchAction()
                        exitEditingMode()
                    }
                }
                catch {
                    await MainActor.run {
                        finishBatchAction(error:error)
                    }
                }
            }
        }
        catch {
            finishBatchAction(error:error)
        }
    }

    private func beginBatchAction(_ title:String) {
        batchErrorMessage = nil
        batchActionTitle = title
        isPerformingBatchAction = true
    }

    private func finishBatchAction(error:Error? = nil) {
        isPerformingBatchAction = false
        batchActionTitle = ""
        if let error {
            batchErrorMessage = error.localizedDescription
        }
    }

    private func defaultMergedDocumentName()->String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(L10n.text("合并扫描")) \(formatter.string(from:Date()))"
    }

    private func updateSearchQuery() async {
        let trimmed = searchText.trimmingCharacters(
            in:.whitespacesAndNewlines
        )

        if trimmed.isEmpty {
            searchQuery = ""
            return
        }

        do {
            try await Task.sleep(for:.milliseconds(250))
        }
        catch {
            return
        }

        guard !Task.isCancelled else { return }
        searchQuery = trimmed
    }
}


private struct MergeSheetState:Identifiable {
    let id = UUID()
    let items:[ScanMergeItem]
    let initialName:String
}


private struct BatchShareItem:Identifiable {
    let id = UUID()
    let urls:[URL]
}


private enum BatchShareFormat:Sendable {
    case pdf
    case jpg
}



private struct FolderEditorState:Identifiable {
    let id = UUID()
    let folderID:UUID?
    let initialName:String

    var isCreating:Bool {
        folderID == nil
    }
}


#Preview {
    ContentView()
}
