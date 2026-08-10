import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @State private var exportText: String = ""
    @State private var isExporting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("诊断日志") {
                Button {
                    exportDiagnostics()
                } label: {
                    if isExporting {
                        Label("正在导出…", systemImage: "arrow.down.circle")
                    } else {
                        Label("导出最近 14 天（JSON）", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .disabled(isExporting)

                Button(role: .destructive) {
                    clearDiagnostics()
                } label: {
                    Label("清空诊断日志", systemImage: "trash")
                }
            }

            if !exportText.isEmpty {
                Section("预览（前 10KB）") {
                    ScrollView {
                        Text(String(exportText.prefix(10_000)))
                            .font(.footnote)
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                    }
                    .frame(minHeight: 160)
                }

                Section {
                    Button {
                        shareExport()
                    } label: {
                        Label("系统分享导出内容", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        UIPasteboard.general.string = exportText
                    } label: {
                        Label("复制导出内容", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .navigationTitle("诊断日志")
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func exportDiagnostics() {
        isExporting = true
        DiagnosticsStore.shared.exportRecentSessions(days: 14) { result in
            DispatchQueue.main.async {
                isExporting = false
                switch result {
                case .success(let data):
                    exportText = String(data: data, encoding: .utf8) ?? ""
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func clearDiagnostics() {
        DiagnosticsStore.shared.clearAll { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    exportText = ""
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func shareExport() {
        guard !exportText.isEmpty else { return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("AoiScan-Diagnostics.json")
        do {
            try exportText.write(to: tmp, atomically: true, encoding: .utf8)
            presentShareSheet(url: tmp)
        } catch {
            errorMessage = L10n.format(
                "无法写出分享文件：%@",
                error.localizedDescription
            )
        }
    }

    private func presentShareSheet(url: URL) {
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

#Preview {
    NavigationView {
        DiagnosticsView()
    }
}
