AoiScan 速度收敛与色温诊断版

本目录中的 diff 以 AoiScan-instant-capture-feedback-work 为基线，记录本次修改。

本次目标：
1. 普通页面不再默认进入恢复和第二次精确 OCR。
2. 密集文字页面直接保留已测量的基础智能版本。
3. 强问题候选先通过低成本图像预检，未达到收益门槛时在 OCR 前早停。
4. 色温模块只检测和写入诊断日志，不对白平衡或扫描图片做修改。
5. 保留快门后的即时预览及原有扫描、裁切、OCR、导出结构。

新增文件：
- AoiScan/EnhancementPreflightAnalyzer.swift
- AoiScan/ColorTemperatureModels.swift
- AoiScan/ColorTemperatureAnalyzer.swift
- AoiScan/ColorTemperatureDiagnostics.swift

验证：
- 使用 iPhoneOS SDK 完成 Swift 全量编译和链接。
- 为避开当前机器缺失 Simulator runtime 导致的资源编译错误，验证命令仅临时排除了 Assets.xcassets；项目文件和资源没有被删除或改写。


本次新增：Capture Buffer + Best Frame Selection（第一阶段）

目标：
1. 拍摄前低频缓存最近 5 个相机帧，不改变相机界面和拍摄流程。
2. 快门时冻结缓存，并与正式高质量照片比较上、中、下三段清晰度、曝光和四角稳定度。
3. 正式照片始终为默认结果；缓存帧只有在分辨率足够、整体明显更清晰且任何区域均不退化时才允许替换。
4. 缓存帧分辨率不足时仍可提供稳定的纸张四角，但不会降低最终图片分辨率。
5. 每次选择结果写入“Capture Buffer”诊断日志，便于判断后续是否值得升级区域级融合。

新增文件：
- AoiScan/CaptureBufferModels.swift
- AoiScan/CaptureFrameQualityAnalyzer.swift
- AoiScan/CaptureFrameBuffer.swift
- AoiScan/BestFrameSelector.swift
- AoiScan/CaptureBufferDiagnostics.swift

修改文件：
- AoiScan/ScannerViewController.swift

性能保护：
- 同一时间最多分析一个缓存帧，避免相机帧在后台队列积压。
- 设备方向改变、扫描完成或相机退出时立即清空缓存。
- 不修改即时预览、OCR、DocumentBlock、智能增强、裁切和导出逻辑。

验证：
- 使用 iPhoneOS SDK 完成全量 Swift 编译与链接，结果 BUILD SUCCEEDED。


两批实测日志后的裁切安全修复：

1. 修复 cornerJitter 缺失时被当作“完全稳定”的问题；缺少稳定度现在直接不可用。
2. 正式照片不再从普通缓存帧补充裁切四角。
3. ScannerViewController 增加第二层保护：正式照片只允许携带真正稳定的 captureReferenceCorners。
4. 只有真正选中缓存图片时，才使用对应缓存图片自己的四角。
5. 当前 960x1280 缓存帧分辨率不足时，在正式照片质量分析前早停，消除约 128～148ms 无效比较。
6. Capture Buffer 日志现在分别记录分辨率、稳定度、曝光和清晰度失败原因。

修改文件：
- AoiScan/BestFrameSelector.swift
- AoiScan/CaptureBufferModels.swift
- AoiScan/CaptureBufferDiagnostics.swift
- AoiScan/ScannerViewController.swift

验证：
- 使用 iPhoneOS SDK 全量编译与链接，结果 BUILD SUCCEEDED。
