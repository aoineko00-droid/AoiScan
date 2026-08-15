//
//  AppSettingsView.swift
//  AoiScan
//

import SwiftUI
import UIKit


struct AppSettingsView:View {

    @AppStorage(AppLanguage.storageKey)
    private var appLanguage = AppLanguage.simplifiedChinese.rawValue

    @State private var languageSelection =
        AppLanguage.current.rawValue

    @State private var pendingLanguage:String?

    @State private var showLanguageConfirmation = false

    @AppStorage("recognition.smallDocumentFallback")
    private var smallDocumentFallbackEnabled = true

    @AppStorage("recognition.captureGuidance")
    private var captureGuidanceEnabled = true

    @AppStorage(CameraFlashMode.storageKey)
    private var defaultFlashMode = CameraFlashMode.off.rawValue

    @AppStorage(OCRIndexManager.automaticIndexingKey)
    private var automaticTextIndexEnabled = true

    @ObservedObject
    private var logStore = RecognitionLogStore.shared

    @ObservedObject
    private var ocrIndexManager = OCRIndexManager.shared

    @ObservedObject
    private var scanManager = ScanManager.shared


    var body:some View {
        Form {
            Section("语言") {
                Picker(
                    "界面语言",
                    selection:$languageSelection
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(
                    "选择新语言后，点击“确定”将重新载入 AoiScan 并返回主页面。系统分享菜单、键盘和权限弹窗仍跟随 iOS 的语言设置。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("拍摄") {
                Picker(
                    "默认闪光灯",
                    selection:$defaultFlashMode
                ) {
                    ForEach(CameraFlashMode.allCases) { mode in
                        Label(
                            mode.title,
                            systemImage:mode.symbolName
                        )
                        .tag(mode.rawValue)
                    }
                }

                Text(
                    "默认为关闭；自动模式会根据环境亮度决定是否闪光。拍摄页面的临时修改只影响当前扫描。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("扫描识别") {
                Toggle(
                    "书页与小文档识别",
                    isOn:$smallDocumentFallbackEnabled
                )

                Text(
                    "普通纸张严格识别失败后，再尝试增强低对比度书页或彩色文档；明确识别到摊开的左右书页时，会忽略中缝并合并为一个完整裁切范围。不会降低普通扫描的识别标准。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Toggle(
                    "拍摄引导提示",
                    isOn:$captureGuidanceEnabled
                )

                Text(
                    "根据纸张大小、拍摄角度、稳定程度和环境亮度给出文字提示，不显示识别框。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("文字与搜索") {
                Toggle(
                    "自动建立文字索引",
                    isOn:$automaticTextIndexEnabled
                )

                Text(
                    "扫描保存后在本机识别文字，用于搜索扫描件。图片和识别文字不会上传。关闭后仍可在扫描详情中手动识别。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button {
                    ocrIndexManager.indexExistingDocuments(
                        scanManager.documents
                    )
                } label: {
                    Label(
                        "为已有扫描件建立索引",
                        systemImage:"text.magnifyingglass"
                    )
                }
                .disabled(
                    !automaticTextIndexEnabled
                        || ocrIndexManager.isIndexing
                        || scanManager.documents.isEmpty
                )

                if ocrIndexManager.batchTotal > 0 {
                    VStack(alignment:.leading, spacing:8) {
                        ProgressView(
                            value:Double(
                                ocrIndexManager.batchCompleted
                            ),
                            total:Double(
                                ocrIndexManager.batchTotal
                            )
                        )

                        Text(
                            ocrIndexManager.batchCompleted
                                >= ocrIndexManager.batchTotal
                            ? L10n.text("已有扫描件索引已完成")
                            : L10n.format(
                                "正在处理 %@ / %@",
                                String(ocrIndexManager.batchCompleted),
                                String(ocrIndexManager.batchTotal)
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section("诊断") {
                NavigationLink {
                    DiagnosticsSessionsView()
                } label: {
                    HStack {
                        Label(
                            "诊断日志（Session）",
                            systemImage:"shippingbox"
                        )

                        Spacer()
                    }
                }

                NavigationLink {
                    RecognitionLogView()
                } label: {
                    HStack {
                        Label(
                            "识别日志",
                            systemImage:"doc.text.magnifyingglass"
                        )

                        Spacer()

                        Text("\(logStore.entries.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Text(
                    "日志只记录识别方式、候选数量、纸张面积和失败原因，不保存扫描图片或识别出的文字内容。最多保留 250 条。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("隐私声明") {
                Label(
                    "所有功能均在本机完成",
                    systemImage:"lock.shield"
                )

                Text(
                    "AoiScan 不连接服务器。扫描图片、文字识别、文档搜索和文件保存均在设备本地完成，不会上传扫描内容、识别文字或文件名。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text(
                    "部分中国区 iOS 设备可能在首次使用系统键盘时显示“无线数据”授权。选择“不允许”不会影响扫描、文字识别、搜索、重命名或 PDF 生成。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text(
                    "诊断日志仅保存识别流程和错误信息，不包含扫描图片或识别文字。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of:languageSelection) { _, newValue in
            guard newValue != appLanguage else { return }
            pendingLanguage = newValue
            showLanguageConfirmation = true
        }
        .alert(
            L10n.text("切换界面语言"),
            isPresented:$showLanguageConfirmation
        ) {
            Button(L10n.text("取消"), role:.cancel) {
                languageSelection = appLanguage
                pendingLanguage = nil
            }

            Button(L10n.text("确定")) {
                guard let pendingLanguage else { return }
                self.pendingLanguage = nil
                appLanguage = pendingLanguage
            }
        } message: {
            Text(
                L10n.text(
                    "确定切换界面语言吗？AoiScan 将重新载入并返回主页面。"
                )
            )
        }
        .onChange(
            of:automaticTextIndexEnabled
        ) { _, enabled in
            ocrIndexManager.automaticSettingDidChange(
                enabled:enabled
            )
        }
    }
}


struct RecognitionLogView:View {

    @ObservedObject
    private var logStore = RecognitionLogStore.shared

    @State private var showShareSheet = false
    @State private var showClearConfirmation = false
    @State private var showCopiedConfirmation = false


    var body:some View {
        Group {
            if logStore.entries.isEmpty {
                ContentUnavailableView(
                    "暂无识别日志",
                    systemImage:"doc.text.magnifyingglass",
                    description:Text(
                        "完成一次拍摄后，这里会显示识别过程和结果。"
                    )
                )
            }
            else {
                List(logStore.entries) { entry in
                    VStack(alignment:.leading, spacing:6) {
                        HStack(spacing:8) {
                            Text(L10n.text(entry.category))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    entry.level == "警告"
                                    ? Color.orange
                                    : Color.blue
                                )

                            Spacer()

                            Text(
                                entry.date,
                                format:.dateTime
                                    .month()
                                    .day()
                                    .hour()
                                    .minute()
                                    .second()
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Text(L10n.text(entry.message))
                            .font(.subheadline)

                        if let details = entry.details,
                           !details.isEmpty {
                            Text(details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical,4)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("识别日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement:.topBarTrailing) {
                Button {
                    UIPasteboard.general.string =
                        logStore.exportedText()
                    showCopiedConfirmation = true
                } label: {
                    Image(systemName:"doc.on.doc")
                }
                .disabled(logStore.entries.isEmpty)

                Menu {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label(
                            "分享日志",
                            systemImage:"square.and.arrow.up"
                        )
                    }

                    Button(role:.destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label(
                            "清空日志",
                            systemImage:"trash"
                        )
                    }
                } label: {
                    Image(systemName:"ellipsis.circle")
                }
                .disabled(logStore.entries.isEmpty)
            }
        }
        .sheet(isPresented:$showShareSheet) {
            ShareSheet(
                activityItems:[
                    logStore.exportedText()
                ]
            )
        }
        .confirmationDialog(
            "确定清空全部识别日志？",
            isPresented:$showClearConfirmation,
            titleVisibility:.visible
        ) {
            Button("清空日志", role:.destructive) {
                logStore.clear()
            }

            Button("取消", role:.cancel) {}
        }
        .alert(
            "已复制",
            isPresented:$showCopiedConfirmation
        ) {
            Button("好", role:.cancel) {}
        } message: {
            Text("识别日志已复制到剪贴板。")
        }
    }
}
