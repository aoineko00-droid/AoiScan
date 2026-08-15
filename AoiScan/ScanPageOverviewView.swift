//
//  ScanPageOverviewView.swift
//  AoiScan
//

import SwiftUI
import UIKit


struct ScanPageOverviewItem:Identifiable {
    let pageNumber:Int
    let image:UIImage

    var id:Int { pageNumber }
}


struct ScanPageOverviewView:View {
    let currentPageNumber:Int
    let originalOrder:[Int]
    let onSelect:(Int)->Void
    let onCommit:([Int]) async throws->Void

    @State private var items:[ScanPageOverviewItem]
    @State private var errorMessage:String?
    @State private var isSaving = false

    @Environment(\.dismiss)
    private var dismiss

    init(
        items:[ScanPageOverviewItem],
        currentPageNumber:Int,
        onSelect:@escaping (Int)->Void,
        onCommit:@escaping ([Int]) async throws->Void
    ) {
        self.currentPageNumber = currentPageNumber
        self.originalOrder = items.map(\.pageNumber)
        self.onSelect = onSelect
        self.onCommit = onCommit
        _items = State(initialValue:items)
    }

    var body:some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns:[
                        GridItem(
                            .adaptive(minimum:140, maximum:220),
                            spacing:14
                        )
                    ],
                    spacing:16
                ) {
                    ForEach(
                        Array(items.enumerated()),
                        id:\.element.id
                    ) { index,item in
                        pageCard(
                            item,
                            displayPageNumber:index + 1
                        )
                            .draggable(String(item.pageNumber)) {
                                dragPreview(item)
                            }
                            .dropDestination(for:String.self) {
                                values,_ in
                                guard let value = values.first,
                                      let sourcePage = Int(value) else {
                                    return false
                                }
                                return movePage(
                                    sourcePage,
                                    before:item.pageNumber
                                )
                            }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(
                L10n.format(
                    "全部页面（%@）",
                    NSNumber(value:items.count)
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button(L10n.text("取消")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement:.topBarTrailing) {
                    Button {
                        Task {
                            await commitOrder()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        else {
                            Text(L10n.text("完成"))
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .alert(
                L10n.text("页面操作失败"),
                isPresented:Binding(
                    get:{ errorMessage != nil },
                    set:{ if !$0 { errorMessage = nil } }
                )
            ) {
                Button(L10n.text("好"), role:.cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func pageCard(
        _ item:ScanPageOverviewItem,
        displayPageNumber:Int
    )->some View {
        Button {
            onSelect(item.pageNumber)
            dismiss()
        } label: {
            VStack(spacing:8) {
                Image(uiImage:item.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth:.infinity)
                    .frame(height:180)
                    .background(Color.white)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius:10,
                            style:.continuous
                        )
                    )

                HStack(spacing:6) {
                    Text(
                        L10n.format(
                            "第 %@ 页",
                            NSNumber(value:displayPageNumber)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.primary)

                    Spacer(minLength:0)

                    Image(systemName:"line.3.horizontal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(8)
            .background(Color(.secondarySystemBackground))
            .clipShape(
                RoundedRectangle(cornerRadius:12, style:.continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius:12, style:.continuous)
                    .stroke(
                        item.pageNumber == currentPageNumber
                            ? Color.blue
                            : Color.primary.opacity(0.08),
                        lineWidth:item.pageNumber == currentPageNumber
                            ? 2
                            : 0.5
                    )
            }
            .shadow(
                color:Color.black.opacity(0.05),
                radius:5,
                x:0,
                y:2
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.text("长按并拖动可调整顺序"))
    }

    private func dragPreview(
        _ item:ScanPageOverviewItem
    )->some View {
        Image(uiImage:item.image)
            .resizable()
            .scaledToFit()
            .frame(width:110, height:145)
            .background(Color.white)
            .clipShape(
                RoundedRectangle(cornerRadius:10, style:.continuous)
            )
            .shadow(radius:8)
    }

    private func movePage(
        _ sourcePage:Int,
        before targetPage:Int
    )->Bool {
        guard sourcePage != targetPage,
              let sourceIndex = items.firstIndex(
                where:{ $0.pageNumber == sourcePage }
              ),
              items.contains(where:{ $0.pageNumber == targetPage }) else {
            return false
        }

        let movedItem = items.remove(at:sourceIndex)
        guard let targetIndex = items.firstIndex(
            where:{ $0.pageNumber == targetPage }
        ) else {
            items.insert(movedItem, at:sourceIndex)
            return false
        }

        withAnimation(.easeInOut(duration:0.2)) {
            items.insert(movedItem, at:targetIndex)
        }
        UIImpactFeedbackGenerator(style:.light).impactOccurred()
        return true
    }

    private func commitOrder() async {
        let order = items.map(\.pageNumber)
        guard order != originalOrder else {
            dismiss()
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await onCommit(order)
            dismiss()
        }
        catch {
            errorMessage = error.localizedDescription
        }
    }
}
