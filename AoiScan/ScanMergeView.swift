//
//  ScanMergeView.swift
//  AoiScan
//

import SwiftUI


struct ScanMergeItem:Identifiable,Hashable {
    let id:UUID
    let title:String
    let pageCount:Int
}


enum ScanMergeOriginalDisposition:String,CaseIterable,Identifiable,Sendable {
    case keep
    case delete

    var id:String { rawValue }

    var title:String {
        switch self {
        case .keep:
            return L10n.text("保留")
        case .delete:
            return L10n.text("删除")
        }
    }
}


struct ScanMergeView:View {
    @Environment(\.dismiss) private var dismiss

    @State private var items:[ScanMergeItem]
    @State private var documentName:String
    @State private var originalDisposition:ScanMergeOriginalDisposition = .keep

    let onMerge:([UUID],String,ScanMergeOriginalDisposition)->Void

    init(
        items:[ScanMergeItem],
        initialName:String,
        onMerge:@escaping (
            [UUID],
            String,
            ScanMergeOriginalDisposition
        )->Void
    ) {
        _items = State(initialValue:items)
        _documentName = State(initialValue:initialName)
        self.onMerge = onMerge
    }

    var body:some View {
        NavigationStack {
            List {
                Section(L10n.text("新文件名称")) {
                    TextField(
                        L10n.text("文件名称"),
                        text:$documentName
                    )
                    .textInputAutocapitalization(.sentences)
                }

                Section {
                    ForEach(items) { item in
                        HStack(spacing:12) {
                            Image(systemName:"doc.text.image")
                                .foregroundStyle(.blue)

                            VStack(alignment:.leading, spacing:3) {
                                Text(item.title)
                                    .lineLimit(1)

                                Text(
                                    L10n.format(
                                        "%@ 页",
                                        NSNumber(value:item.pageCount)
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical,3)
                    }
                    .onMove { source,destination in
                        items.move(
                            fromOffsets:source,
                            toOffset:destination
                        )
                    }
                } header: {
                    Text(L10n.text("合并顺序"))
                } footer: {
                    Text(
                        L10n.format(
                            "合并后共 %@ 页",
                            NSNumber(value:totalPageCount)
                        )
                    )
                }

                Section(L10n.text("合并后原文件")) {
                    Picker(
                        L10n.text("合并后原文件"),
                        selection:$originalDisposition
                    ) {
                        ForEach(ScanMergeOriginalDisposition.allCases) {
                            disposition in
                            Text(disposition.title)
                                .tag(disposition)
                        }
                    }
                    .pickerStyle(.segmented)

                    if originalDisposition == .delete {
                        Text(
                            L10n.text(
                                "合并成功后，将删除参与合并的原扫描文件。"
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L10n.text("合并扫描文件"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button(L10n.text("取消")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement:.confirmationAction) {
                    Button(L10n.text("合并")) {
                        let name = trimmedName
                        let orderedIDs = items.map(\.id)
                        dismiss()
                        onMerge(
                            orderedIDs,
                            name,
                            originalDisposition
                        )
                    }
                    .disabled(items.count < 2 || trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName:String {
        documentName.trimmingCharacters(
            in:.whitespacesAndNewlines
        )
    }

    private var totalPageCount:Int {
        items.reduce(0) { $0 + $1.pageCount }
    }
}
