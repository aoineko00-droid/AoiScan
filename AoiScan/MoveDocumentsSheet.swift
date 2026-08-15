//
//  MoveDocumentsSheet.swift
//  AoiScan
//

import SwiftUI


struct ScanFolderChoice:Identifiable,Hashable,Sendable {
    let id:UUID
    let title:String
    let documentCount:Int
}


private enum MoveDestination:Hashable {
    case root
    case folder(UUID)
}


struct MoveDocumentsSheet:View {
    @Environment(\.dismiss) private var dismiss

    @State private var folders:[ScanFolderChoice]
    @State private var destination:MoveDestination?
    @State private var showCreateFolder = false
    @State private var errorMessage:String?

    let currentFolderID:UUID?
    let onCreateFolder:(String) throws->ScanFolderChoice
    let onMove:(UUID?) throws->Void

    init(
        folders:[ScanFolderChoice],
        currentFolderID:UUID?,
        onCreateFolder:@escaping (String) throws->ScanFolderChoice,
        onMove:@escaping (UUID?) throws->Void
    ) {
        _folders = State(initialValue:folders)
        self.currentFolderID = currentFolderID
        self.onCreateFolder = onCreateFolder
        self.onMove = onMove
    }

    var body:some View {
        NavigationStack {
            VStack(spacing:0) {
                List {
                    destinationRow(
                        title:L10n.text("根目录"),
                        subtitle:nil,
                        destination:.root,
                        disabled:currentFolderID == nil
                    )

                    ForEach(folders) { folder in
                        destinationRow(
                            title:folder.title,
                            subtitle:L10n.format(
                                "%@ 个文件",
                                NSNumber(value:folder.documentCount)
                            ),
                            destination:.folder(folder.id),
                            disabled:folder.id == currentFolderID
                        )
                    }
                }
                .listStyle(.plain)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal,20)
                        .padding(.top,8)
                }

                HStack(spacing:12) {
                    Button {
                        showCreateFolder = true
                    } label: {
                        Label(
                            L10n.text("新建文件夹"),
                            systemImage:"folder.badge.plus"
                        )
                        .frame(maxWidth:.infinity)
                        .frame(height:46)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        move()
                    } label: {
                        Text(L10n.text("移动"))
                            .frame(maxWidth:.infinity)
                            .frame(height:46)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(destination == nil)
                }
                .padding(16)
                .background(.bar)
                .overlay(alignment:.top) {
                    Divider()
                }
            }
            .navigationTitle(L10n.text("移动到"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button(L10n.text("取消")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented:$showCreateFolder) {
            FolderNameEditor(
                title:L10n.text("新建文件夹"),
                confirmationTitle:L10n.text("新建")
            ) { name in
                let folder = try onCreateFolder(name)
                folders.append(folder)
                folders.sort {
                    $0.title.localizedStandardCompare($1.title)
                        == .orderedAscending
                }
                destination = .folder(folder.id)
            }
        }
    }

    private func destinationRow(
        title:String,
        subtitle:String?,
        destination rowDestination:MoveDestination,
        disabled:Bool
    )->some View {
        Button {
            guard !disabled else { return }
            destination = rowDestination
            errorMessage = nil
        } label: {
            HStack(spacing:12) {
                Image(
                    systemName:destination == rowDestination
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.system(size:21, weight:.medium))
                .foregroundStyle(
                    disabled
                        ? Color.secondary.opacity(0.45)
                        : Color.blue
                )

                VStack(alignment:.leading, spacing:3) {
                    Text(title)
                        .foregroundStyle(
                            disabled ? Color.secondary : Color.primary
                        )
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func move() {
        guard let destination else { return }
        let folderID:UUID?

        switch destination {
        case .root:
            folderID = nil
        case .folder(let id):
            folderID = id
        }

        do {
            try onMove(folderID)
            dismiss()
        }
        catch {
            errorMessage = error.localizedDescription
        }
    }
}
