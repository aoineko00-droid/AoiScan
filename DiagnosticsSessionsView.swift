import SwiftUI

struct DiagnosticsSessionsView: View {
    @State private var sessions: [SessionLog] = []
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("正在载入诊断会话…")
                }
            } else if sessions.isEmpty {
                ContentUnavailableView(
                    "暂无诊断会话",
                    systemImage: "shippingbox",
                    description: Text("完成一次扫描流程后，这里会显示会话级诊断日志。")
                )
            } else {
                ForEach(sessions, id: \ .session.id) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(sessionTitle(s))
                                .font(.subheadline).bold()
                            Spacer()
                            Text(s.createdAt, style: .date)
                            Text(s.createdAt, style: .time)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Text(
                                L10n.format(
                                    "会话 ID: %@",
                                    s.session.id
                                )
                            )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if let count = s.session.pageCount {
                                Text(
                                    L10n.format(
                                        "页数: %@",
                                        String(count)
                                    )
                                )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let details = eventDetails(s),
                           !details.isEmpty {
                            Text(details)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("诊断日志（Session）")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("刷新") { load() }
                Button("复制") { copyDiagnostics() }
                Button("清空", role: .destructive) { clear() }
            }
        }
        .onAppear { load() }
        .overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
    }

    private func sessionTitle(_ session:SessionLog)->String {
        guard let result = session.captures.first?.result,
              let route = result.route,
              route.hasPrefix("event:") else {
            return L10n.text(
                session.session.multiPage
                    ? "多页会话"
                    : "单页会话"
            )
        }

        let category = String(route.dropFirst("event:".count))
        let message = result.error?.domain ?? ""
        return message.isEmpty
            ? category
            : "\(category) · \(message)"
    }

    private func eventDetails(_ session:SessionLog)->String? {
        guard let result = session.captures.first?.result,
              result.route?.hasPrefix("event:") == true else {
            return nil
        }

        return result.error?.message
    }

    private func load() {
        isLoading = true
        message = nil
        DiagnosticsStore.shared.loadRecentSessions { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let items):
                    sessions = items
                case .failure(let error):
                    sessions = []
                    message = L10n.format(
                        "载入失败：%@",
                        error.localizedDescription
                    )
                }
            }
        }
    }

    private func copyDiagnostics() {
        message = nil
        DiagnosticsStore.shared.exportRecentSessions { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        UIPasteboard.general.string = text
                        message = L10n.text("已复制诊断信息。")
                    } else {
                        message = L10n.text(
                            "复制失败：编码为文本时出错。"
                        )
                    }
                case .failure(let error):
                    message = L10n.format(
                        "复制失败：%@",
                        error.localizedDescription
                    )
                }
            }
        }
    }

    private func clear() {
        message = nil
        DiagnosticsStore.shared.clearAll { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    sessions = []
                    message = L10n.text("已清空诊断日志。")
                case .failure(let error):
                    message = L10n.format(
                        "清空失败：%@",
                        error.localizedDescription
                    )
                }
            }
        }
    }
}
