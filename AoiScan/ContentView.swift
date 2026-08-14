//
//  ContentView.swift
//  AoiScan
//

import SwiftUI
import CoreData


struct ContentView: View {
    
    
    @ObservedObject
    var manager = ScanManager.shared
    
    
    @State private var showScanner = false
    
    
    @State private var showPreview = false
    
    
    @State private var previewPages:[ScanPage] = []
    
    
    @State private var shareURL: URL?
    
    
    @State private var showShare = false
    
    
    @State private var renameTarget: ScanEntity?
    
    
    @State private var newName = ""


    @State private var searchText = ""


    @State private var searchQuery = ""


    @FocusState private var searchFieldFocused:Bool
    
    
    
    
    var body: some View {
        
        
        NavigationStack {
            
            
            VStack(spacing:0) {


                HStack(alignment:.center) {


                    Text("AoiScan")
                        .font(
                            .system(
                                size:34,
                                weight:.bold,
                                design:.default
                            )
                        )


                    Spacer()


                    NavigationLink {

                        AppSettingsView()
                            .toolbar(
                                .visible,
                                for:.navigationBar
                            )

                    } label: {

                        Image(
                            systemName:"gearshape"
                        )
                        .font(
                            .system(
                                size:21,
                                weight:.medium
                            )
                        )
                        .foregroundStyle(.primary)
                        .frame(
                            width:44,
                            height:44
                        )
                        .contentShape(
                            Rectangle()
                        )

                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            searchFieldFocused = false
                        }
                    )


                }
                .padding(.leading,20)
                .padding(.trailing,12)
                .padding(.top,6)
                .padding(.bottom,6)


                HStack(spacing:10) {

                    HStack(spacing:10) {

                        Image(systemName:"magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField(
                            "搜索文件名或扫描文字",
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
                                Image(
                                    systemName:"xmark.circle.fill"
                                )
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)

                        }

                    }
                    .padding(.horizontal,14)
                    .frame(height:42)
                    .background(
                        Color(.secondarySystemBackground)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius:12,
                            style:.continuous
                        )
                    )

                    if searchFieldFocused {

                        Button("取消") {
                            searchText = ""
                            searchQuery = ""
                            searchFieldFocused = false
                        }
                        .foregroundStyle(.blue)
                        .buttonStyle(.plain)
                        .transition(
                            .opacity.combined(
                                with:.move(edge:.trailing)
                            )
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
                
                
                if manager.documents.isEmpty {
                    
                    Spacer()
                    
                    Text("暂无扫描文档")
                        .foregroundColor(.gray)
                    
                    Spacer()

                } else if filteredDocuments.isEmpty {

                    Spacer()

                    ContentUnavailableView.search(
                        text:searchText
                    )

                    Spacer()
                    
                } else {
                    
                    List {
                        
                        ForEach(
                            filteredDocuments,
                            id:\.id
                        ) { document in
                            
                            
                            NavigationLink {
                                
                                ScanDetailView(
                                    document: document
                                )
                                
                            } label: {
                                
                                VStack(
                                    alignment:.leading,
                                    spacing:6
                                ) {
                                    
                                    Text(
                                        document.title
                                        ?? L10n.text("未命名文档")
                                    )
                                    .font(.headline)
                                    
                                    
                                    if let date =
                                        document.createdAt {
                                        
                                        Text(
                                            date,
                                            format:
                                                .dateTime
                                                .year()
                                                .month()
                                                .day()
                                                .hour()
                                                .minute()
                                        )
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        
                                    }
                                    
                                }
                                .padding(.vertical,8)
                                
                            }
                            
                            
                            .swipeActions(
                                edge:.trailing
                            ) {
                                
                                Button(
                                    role:.destructive
                                ) {
                                    
                                    manager.deleteDocument(
                                        document
                                    )
                                    
                                } label:{
                                    
                                    Label(
                                        "删除",
                                        systemImage:"trash"
                                    )
                                    
                                }
                                
                            }
                            
                            
                            .swipeActions(
                                edge:.leading
                            ) {
                                
                                Button {
                                    
                                    generatePDF(
                                        document
                                    )
                                    
                                } label:{
                                    
                                    Label(
                                        "分享PDF",
                                        systemImage:
                                            "square.and.arrow.up"
                                    )
                                    
                                }
                                .tint(.green)
                                
                                
                                Button {
                                    
                                    renameTarget =
                                    document
                                    
                                    newName =
                                    document.title ?? ""
                                    
                                } label:{
                                    
                                    Label(
                                        "重命名",
                                        systemImage:"pencil"
                                    )
                                    
                                }
                                .tint(.blue)
                                
                                
                            }
                            
                            
                        }
                        
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.interactively)
                    
                }
                
                
                ScanButton {

                    searchFieldFocused = false
                    
                    // 每次打开扫描前重置
                    
                    previewPages.removeAll()
                    
                    showPreview = false
                    
                    showScanner = true
                    
                }
                .padding(.bottom,40)
                
                
            }
            .toolbar(
                .hidden,
                for:.navigationBar
            )
            .task(id:searchText) {
                await updateSearchQuery()
            }
            .ignoresSafeArea(
                .keyboard,
                edges:.bottom
            )
            
            
        }
        
        
        // MARK: 扫描 + 预览统一管理
        
        .sheet(
            isPresented:
                $showScanner
        ) {
            
            
            if showPreview {
                
                
                ScanPreviewView(
                    pages:
                        previewPages
                )
                
                
            }
            else {
                
                
                CameraScannerView(
                    pages:
                        $previewPages,
                    
                    showPreview:
                        $showPreview
                )
                
                
            }
            
            
        }
        
        
        // MARK: 分享
        
        .sheet(
            isPresented:
                $showShare
        ) {
            
            if let url =
                shareURL {
                
                ShareSheet(
                    activityItems:[
                        url
                    ]
                )
                
            }
            
        }
        
        
        // MARK: 重命名
        
        .alert(
            "重命名",
            isPresented:
                Binding(
                    get:{
                        renameTarget != nil
                    },
                    set:{
                        if !$0 {
                            renameTarget = nil
                        }
                    }
                )
        ) {
            
            
            TextField(
                "文件名称",
                text:
                    $newName
            )
            
            
            Button("保存") {
                
                
                if let target =
                    renameTarget {
                    
                    manager.renameDocument(
                        target,
                        newName:
                            newName
                    )
                    
                }
                
                
                renameTarget = nil
                
                
            }
            
            
            Button(
                "取消",
                role:.cancel
            ) {
                
                renameTarget = nil
                
            }
            
            
        }
        
        
    }


    private var filteredDocuments:[ScanEntity] {

        let query = searchQuery.trimmingCharacters(
            in:.whitespacesAndNewlines
        )

        guard !query.isEmpty else {
            return manager.documents
        }

        return manager.documents.filter { document in

            let titleMatches = (document.title ?? "")
                .localizedCaseInsensitiveContains(query)

            let textMatches = (document.searchableText ?? "")
                .localizedCaseInsensitiveContains(query)

            return titleMatches || textMatches

        }

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
            try await Task.sleep(
                for:.milliseconds(250)
            )
        }
        catch {
            return
        }

        guard !Task.isCancelled else {
            return
        }

        searchQuery = trimmed

    }
    
    
    
    
    private func generatePDF(
        _ document: ScanEntity
    ) {
        
        print(
            "生成PDF:",
            document.title ?? ""
        )
        
    }
    
    
}



#Preview {
    
    ContentView()
    
}


