//
//  FolderNameEditor.swift
//  AoiScan
//

import SwiftUI


struct FolderNameEditor:View {
    @Environment(\.dismiss) private var dismiss

    @State private var name:String
    @State private var errorMessage:String?

    let title:String
    let confirmationTitle:String
    let onSave:(String) throws->Void

    init(
        title:String,
        initialName:String = "",
        confirmationTitle:String,
        onSave:@escaping (String) throws->Void
    ) {
        self.title = title
        self.confirmationTitle = confirmationTitle
        self.onSave = onSave
        _name = State(initialValue:initialName)
    }

    var body:some View {
        NavigationStack {
            Form {
                TextField(
                    L10n.text("文件夹名称"),
                    text:$name
                )
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(save)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button(L10n.text("取消")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement:.confirmationAction) {
                    Button(confirmationTitle, action:save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var trimmedName:String {
        name.trimmingCharacters(in:.whitespacesAndNewlines)
    }

    private func save() {
        do {
            try onSave(trimmedName)
            dismiss()
        }
        catch {
            errorMessage = error.localizedDescription
        }
    }
}
