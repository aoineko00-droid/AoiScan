//
//  ScannerViewController.swift
//  AoiScan
//

import UIKit
import AVFoundation
import Vision
import ImageIO
import CoreImage



protocol ScannerViewControllerDelegate: AnyObject {
    
    func scannerDidFinish(
        pages: [ScanPage]
    )
    
}




class ScannerViewController:
UIViewController,
AVCapturePhotoCaptureDelegate,
AVCaptureVideoDataOutputSampleBufferDelegate {
    
    
    
    weak var delegate:
    ScannerViewControllerDelegate?
    
    
    
    
    // MARK: Camera
    
    
    private let session =
    AVCaptureSession()


    private let sessionQueue =
    DispatchQueue(
        label:"aoi.scan.camera.session",
        qos:.userInitiated
    )
    
    
    private let previewLayer =
    AVCaptureVideoPreviewLayer()
    
    
    private let photoOutput =
    AVCapturePhotoOutput()


    private var cameraDevice:
    AVCaptureDevice?
    
    
    private let videoOutput =
    AVCaptureVideoDataOutput()


    private let videoDetectionQueue =
    DispatchQueue(
        label:"aoi.scan.video.detection",
        qos:.utility
    )


    private let previewSnapshotQueue =
    DispatchQueue(
        label:"aoi.scan.capture.preview",
        qos:.userInitiated
    )


    private let captureBufferQueue = DispatchQueue(
        label:"aoi.scan.capture.buffer",
        qos:.userInitiated
    )


    private let captureFrameBuffer = CaptureFrameBuffer()


    private var frozenCaptureBuffer:CaptureBufferSnapshot?


    private let captureBufferSchedulingLock = NSLock()


    private var captureBufferAnalysisPending = false


    private let previewFrameLock = NSLock()


    private var latestPreviewPixelBuffer:CVPixelBuffer?


    private var latestPreviewOrientation:
    CGImagePropertyOrientation = .right


    private let previewCIContext = CIContext(
        options:[.cacheIntermediates:false]
    )


    // 只在 videoDetectionQueue 中读写。
    private var visionImageOrientation:
    CGImagePropertyOrientation = .right


    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        frozenCaptureBuffer = nil
        captureBufferQueue.async { [weak self] in
            self?.captureFrameBuffer.handleMemoryPressure()
        }
    }
    
    
    
    
    // MARK: Vision
    
    
    private let boxLayer =
    CAShapeLayer()
    
    
    private var lastDetectionTime =
    Date.distantPast


    // 以下追踪状态只在 videoDetectionQueue 中读写。
    private var recentDocumentCorners:[ScanCorners] = []


    private var missedDetectionFrames = 0


    // 以下两项只在主线程读写。
    private var stableDocumentCorners:ScanCorners?


    private var stableDocumentStability:CaptureCornerStability?


    private var captureReferenceCorners:ScanCorners?


    private var captureReferenceStability:CaptureCornerStability?


    private let focusExposureWaitLimit:
    TimeInterval = 0.25


    private let focusExposurePollInterval:
    TimeInterval = 0.05
    
    
    
    
    
    // MARK: Scan Mode
    
    
    private var isMultiPage =
    false
    
    
    private var scannedPages:
    [ScanPage] = []


    private var isProcessingPhoto =
    false


    private var didHandOffPages =
    false


    private var isDiscardingSession =
    false
    
    
    
    
    // MARK: Flash
    
    
    // MARK: Flash
    
    private var flashMode =
    RecognitionSettings.defaultFlashMode
    
    
    private var isCameraReady =
    false
    
    private var sessionConfigured =
    false


    private var delayedStartWorkItem:
    DispatchWorkItem?


    private var isViewVisible =
    false


    private var currentCaptureRotationAngle:
    CGFloat = 90


    private var lastValidDeviceOrientation:
    UIDeviceOrientation?


    private var rotationCoordinator:
    AVCaptureDevice.RotationCoordinator?


    private var previewRotationObservation:
    NSKeyValueObservation?


    private var captureRotationObservation:
    NSKeyValueObservation?


    private var pendingCameraAlert:(
        title:String,
        message:String,
        showsSettings:Bool
    )?
    
    
    
    
    // MARK: UI
    
    
    private let captureButton =
    UIButton(type:.system)


    private let captureActivityIndicator =
    UIActivityIndicatorView(style:.medium)
    
    
    private let flashButton =
    UIButton(type:.system)


    private let doneButton =
    UIButton(type:.system)
    
    
    private let modeControl =
    UISegmentedControl(
        items:[
            L10n.text("单页"),
            L10n.text("多页")
        ]
    )


    private let guidanceLabel = UILabel()


    private var lastGuidanceMessage = ""


    private let processingOverlay = UIView()


    private let capturedImageView = UIImageView()


    private let processingCard = UIVisualEffectView(
        effect:UIBlurEffect(style:.systemMaterialDark)
    )


    private let processingIcon = UIImageView()


    private let processingTitleLabel = UILabel()


    private let processingDetailLabel = UILabel()


    private let processingIndicator = UIActivityIndicatorView(
        style:.medium
    )


    private var processingMessageWorkItems:[DispatchWorkItem] = []


    // 以下状态只在主线程读写，用于防止较慢的预览帧覆盖正式照片。
    private var activeCaptureFeedbackID:UUID?


    private var didReceiveFormalPhoto = false


    private var captureFeedbackStartedAt:CFTimeInterval?
    
    
    
    
    
    
    override func viewDidLoad(){
        
        
        super.viewDidLoad()
        
        
        view.backgroundColor =
            .black
        
        
        setupPreviewLayer()

        setupUI()

        setCameraControlsAvailable(false)

        requestCameraAuthorization()

        NotificationCenter.default.addObserver(
            self,
            selector:#selector(applicationDidBecomeActive),
            name:UIApplication.didBecomeActiveNotification,
            object:nil
        )

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        rememberDeviceOrientationIfValid(
            UIDevice.current.orientation
        )

        NotificationCenter.default.addObserver(
            self,
            selector:#selector(deviceOrientationDidChange),
            name:UIDevice.orientationDidChangeNotification,
            object:nil
        )
        
        
    }


    deinit {
        delayedStartWorkItem?.cancel()
        previewRotationObservation?.invalidate()
        captureRotationObservation?.invalidate()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.removeObserver(self)
    }
    
    
    
    
    
    
    override func viewDidLayoutSubviews(){
        
        
        super.viewDidLayoutSubviews()
        
        
        previewLayer.frame =
        view.bounds


        updateCameraOrientation()
        
        
    }
    
    
    
    
    
    
    override func viewDidAppear(
        _ animated: Bool
    ){
        
        super.viewDidAppear(animated)


        isViewVisible = true

        presentPendingCameraAlertIfNeeded()

        scheduleCameraStart(after:0.5)
        
    }
    
    
    
    
    
    
    override func viewWillDisappear(
        _ animated: Bool
    ){
        
        super.viewWillDisappear(animated)


        isViewVisible = false
        cancelScheduledCameraStart()
        isCameraReady = false
        setCameraControlsAvailable(false)


        if !didHandOffPages {
            isDiscardingSession = true
            isProcessingPhoto = false
            captureActivityIndicator.stopAnimating()
            discardScannedPages()
        }

        frozenCaptureBuffer = nil
        captureBufferQueue.async { [weak self] in
            self?.captureFrameBuffer.resumeAndClear()
        }


        stopCamera()
        
        
    }
    
    
    
    
    
    
    // MARK: Camera Start Stop


    private func scheduleCameraStart(
        after delay:TimeInterval
    ){

        cancelScheduledCameraStart()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isViewVisible else {
                return
            }

            self.delayedStartWorkItem = nil
            self.startCamera()
        }

        delayedStartWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline:.now() + delay,
            execute:workItem
        )
    }


    private func cancelScheduledCameraStart(){
        delayedStartWorkItem?.cancel()
        delayedStartWorkItem = nil
    }
    
    
    private func startCamera(){

        sessionQueue.async { [weak self] in
            guard let self,
                  self.sessionConfigured else {
                return
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            let isRunning = self.session.isRunning

            DispatchQueue.main.async {
                guard self.isViewVisible else {
                    return
                }

                self.isCameraReady = isRunning
                self.setCameraControlsAvailable(isRunning)

                if isRunning {
                    print("📷 相机准备完成")
                }
            }
        }
    }
    
    
    
    
    
    
    private func stopCamera(){

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    
    
    
    
    
    // MARK: Camera Setup
    
    
    private func setupPreviewLayer(){

        previewLayer.session = session
        // 完整显示相机的 4:3 画面，不再为铺满长屏而裁掉左右两侧。
        // 竖屏会自然呈现 3:4，横屏会自然呈现 4:3；黑色留白区域
        // 同时用于承载顶部和底部控制按钮。
        previewLayer.videoGravity = .resizeAspect

        view.layer.insertSublayer(
            previewLayer,
            at:0
        )

        boxLayer.strokeColor = UIColor.systemGreen.cgColor
        boxLayer.fillColor = UIColor.clear.cgColor
        boxLayer.lineWidth = 3

        // 后台继续识别纸张，但拍摄界面不显示识别框。
        boxLayer.isHidden = true
        view.layer.addSublayer(boxLayer)
    }


    private func requestCameraAuthorization(){

        switch AVCaptureDevice.authorizationStatus(
            for:.video
        ) {

        case .authorized:
            configureCameraSession()

        case .notDetermined:
            AVCaptureDevice.requestAccess(
                for:.video
            ) { [weak self] granted in

                guard let self else {
                    return
                }

                if granted {
                    self.configureCameraSession()
                }
                else {
                    self.queueCameraAlert(
                        title:L10n.text("无法使用相机"),
                        message:L10n.text("请在系统设置中允许 AoiScan 使用相机。"),
                        showsSettings:true
                    )
                }
            }

        case .denied, .restricted:
            queueCameraAlert(
                title:L10n.text("无法使用相机"),
                message:L10n.text("请在系统设置中允许 AoiScan 使用相机。"),
                showsSettings:true
            )

        @unknown default:
            queueCameraAlert(
                title:L10n.text("相机不可用"),
                message:L10n.text("当前无法取得相机权限。"),
                showsSettings:false
            )
        }
    }


    @objc
    private func applicationDidBecomeActive(){

        guard AVCaptureDevice.authorizationStatus(
            for:.video
        ) == .authorized else {
            return
        }

        configureCameraSession()

        if isViewVisible {
            scheduleCameraStart(after:0.1)
        }
    }


    @objc
    private func deviceOrientationDidChange(){
        guard rememberDeviceOrientationIfValid(
            UIDevice.current.orientation
        ) else {
            return
        }

        updateCameraOrientation()
    }


    private func configureCameraSession(){

        sessionQueue.async { [weak self] in
            guard let self,
                  !self.sessionConfigured else {
                return
            }

            do {
                try self.performCameraConfiguration()

                DispatchQueue.main.async {
                    self.configureRotationCoordinatorIfNeeded()
                    self.updateCameraOrientation()

                    if self.isViewVisible {
                        self.scheduleCameraStart(after:0)
                    }
                }
            }
            catch {
                self.queueCameraAlert(
                    title:L10n.text("相机启动失败"),
                    message:error.localizedDescription,
                    showsSettings:false
                )
            }
        }
    }


    private func performCameraConfiguration() throws {

        var addedInput:AVCaptureDeviceInput?
        var addedPhotoOutput = false
        var addedVideoOutput = false
        var configurationSucceeded = false

        session.beginConfiguration()

        defer {
            if !configurationSucceeded {
                if addedVideoOutput {
                    session.removeOutput(videoOutput)
                }
                if addedPhotoOutput {
                    session.removeOutput(photoOutput)
                }
                if let addedInput {
                    session.removeInput(addedInput)
                }

                videoOutput.setSampleBufferDelegate(
                    nil,
                    queue:nil
                )
            }

            session.commitConfiguration()
        }

        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for:.video,
            position:.back
        ) else {
            throw ScannerCameraError.cameraUnavailable
        }

        configureCameraDevice(camera)

        let input = try AVCaptureDeviceInput(
            device:camera
        )

        guard session.canAddInput(input) else {
            throw ScannerCameraError.cannotAddInput
        }
        session.addInput(input)
        addedInput = input

        guard session.canAddOutput(photoOutput) else {
            throw ScannerCameraError.cannotAddPhotoOutput
        }
        session.addOutput(photoOutput)
        addedPhotoOutput = true
        photoOutput.maxPhotoQualityPrioritization = .quality

        // 低频读取预览帧，只在后台判断纸张是否连续稳定。
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(
            self,
            queue:videoDetectionQueue
        )

        guard session.canAddOutput(videoOutput) else {
            throw ScannerCameraError.cannotAddVideoOutput
        }
        session.addOutput(videoOutput)
        addedVideoOutput = true

        cameraDevice = camera
        sessionConfigured = true
        configurationSucceeded = true
    }


    private func queueCameraAlert(
        title:String,
        message:String,
        showsSettings:Bool
    ){

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.pendingCameraAlert = (
                title:title,
                message:message,
                showsSettings:showsSettings
            )
            self.presentPendingCameraAlertIfNeeded()
        }
    }


    private func presentPendingCameraAlertIfNeeded(){

        guard isViewVisible,
              presentedViewController == nil,
              let pendingCameraAlert else {
            return
        }

        self.pendingCameraAlert = nil

        let alert = UIAlertController(
            title:pendingCameraAlert.title,
            message:pendingCameraAlert.message,
            preferredStyle:.alert
        )

        alert.addAction(
            UIAlertAction(
                title:L10n.text("取消"),
                style:.cancel
            )
        )

        if pendingCameraAlert.showsSettings,
           let settingsURL = URL(
            string:UIApplication.openSettingsURLString
           ) {

            alert.addAction(
                UIAlertAction(
                    title:L10n.text("前往设置"),
                    style:.default
                ) { _ in
                    UIApplication.shared.open(settingsURL)
                }
            )
        }

        present(
            alert,
            animated:true
        )
    }


    private func setCameraControlsAvailable(
        _ available:Bool
    ){

        if available {
            setCaptureEnabled(true)
        }
        else {
            captureButton.isEnabled = false
            captureButton.alpha = 0.55
            modeControl.isEnabled = false
            modeControl.alpha = 0.6
            captureActivityIndicator.stopAnimating()
        }

        flashButton.isEnabled = available
        flashButton.alpha = available ? 1 : 0.5
    }


    private func configureRotationCoordinatorIfNeeded(){
        guard rotationCoordinator == nil,
              let cameraDevice else {
            return
        }

        let coordinator = AVCaptureDevice.RotationCoordinator(
            device:cameraDevice,
            previewLayer:previewLayer
        )
        rotationCoordinator = coordinator

        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options:[.initial, .new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateCameraOrientation()
            }
        }

        captureRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options:[.initial, .new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateCameraOrientation()
            }
        }
    }


    private func updateCameraOrientation(){
        let previewRotationAngle:CGFloat
        let captureRotationAngle:CGFloat

        if let lastValidDeviceOrientation,
                let deviceRotationAngle = deviceRotationAngle(
                    for:lastValidDeviceOrientation
                ) {
            previewRotationAngle = deviceRotationAngle
            captureRotationAngle = deviceRotationAngle
        }
        else if let rotationCoordinator {
            previewRotationAngle = normalizedRotationAngle(
                rotationCoordinator
                    .videoRotationAngleForHorizonLevelPreview
            )
            captureRotationAngle = normalizedRotationAngle(
                rotationCoordinator
                    .videoRotationAngleForHorizonLevelCapture
            )
        }
        else {
            let fallbackAngle = interfaceRotationAngle()
            previewRotationAngle = fallbackAngle
            captureRotationAngle = fallbackAngle
        }

        let orientationChanged = angularDistance(
            currentCaptureRotationAngle,
            captureRotationAngle
        ) > 1
        currentCaptureRotationAngle = captureRotationAngle

        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(
            previewRotationAngle
           ) {
            connection.videoRotationAngle = previewRotationAngle
        }

        if orientationChanged {
            stableDocumentCorners = nil
            stableDocumentStability = nil
            captureReferenceCorners = nil
            captureReferenceStability = nil
            frozenCaptureBuffer = nil
            captureBufferQueue.async { [weak self] in
                self?.captureFrameBuffer.resumeAndClear()
            }
        }

        let visionOrientation = visionOrientation(
            for:captureRotationAngle
        )

        videoDetectionQueue.async {
            guard self.visionImageOrientation
                    != visionOrientation else {
                return
            }

            self.visionImageOrientation = visionOrientation
            self.recentDocumentCorners.removeAll()
            self.missedDetectionFrames = 0
            self.lastDetectionTime = .distantPast
        }
    }


    @discardableResult
    private func rememberDeviceOrientationIfValid(
        _ orientation:UIDeviceOrientation
    )->Bool {
        guard deviceRotationAngle(for:orientation) != nil else {
            return false
        }

        lastValidDeviceOrientation = orientation
        return true
    }


    private func deviceRotationAngle(
        for orientation:UIDeviceOrientation
    )->CGFloat? {
        switch orientation {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            return 0
        case .landscapeRight:
            return 180
        default:
            return nil
        }
    }


    private func interfaceRotationAngle()->CGFloat {
        let interfaceOrientation = view.window?
            .windowScene?
            .interfaceOrientation ?? .portrait

        switch interfaceOrientation {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            return 0
        case .landscapeRight:
            return 180
        default:
            return 90
        }
    }


    private func normalizedRotationAngle(
        _ angle:CGFloat
    )->CGFloat {
        let normalized = angle.truncatingRemainder(
            dividingBy:360
        )

        return normalized >= 0
            ? normalized
            : normalized + 360
    }


    private func angularDistance(
        _ first:CGFloat,
        _ second:CGFloat
    )->CGFloat {
        let difference = abs(
            normalizedRotationAngle(first)
                - normalizedRotationAngle(second)
        )

        return min(difference, 360 - difference)
    }


    private func visionOrientation(
        for rotationAngle:CGFloat
    )->CGImagePropertyOrientation {
        let normalized = normalizedRotationAngle(
            rotationAngle
        )

        switch normalized {
        case 45..<135:
            return .right
        case 135..<225:
            return .down
        case 225..<315:
            return .left
        default:
            return .up
        }
    }


    private func configureCameraDevice(
        _ camera:AVCaptureDevice
    ){


        do {


            try camera.lockForConfiguration()


            defer {

                camera.unlockForConfiguration()

            }


            let center = CGPoint(
                x:0.5,
                y:0.5
            )


            if camera.isFocusPointOfInterestSupported {

                camera.focusPointOfInterest = center

            }


            if camera.isFocusModeSupported(
                .continuousAutoFocus
            ){

                camera.focusMode =
                    .continuousAutoFocus

            }


            if camera.isSmoothAutoFocusSupported {

                camera.isSmoothAutoFocusEnabled =
                true

            }


            if camera.isExposurePointOfInterestSupported {

                camera.exposurePointOfInterest = center

            }


            if camera.isExposureModeSupported(
                .continuousAutoExposure
            ){

                camera.exposureMode =
                    .continuousAutoExposure

            }


            camera.isSubjectAreaChangeMonitoringEnabled =
            true


            // 常亮灯保持关闭；拍照闪光由当前关闭/自动/开启模式控制。
            if camera.hasTorch {
                camera.torchMode = .off
            }


        }
        catch {

            print(
                "相机对焦和曝光配置失败:",
                error
            )

        }


    }
    // MARK: UI
    
    
    private func setupUI(){
        
        
        // MARK: 拍摄按钮
        
        captureButton.translatesAutoresizingMaskIntoConstraints =
        false
        
        
        captureButton.backgroundColor =
            .white
        
        
        captureButton.layer.cornerRadius =
        40
        
        
        captureButton.addTarget(
            self,
            action:#selector(capture),
            for:.touchUpInside
        )
        
        
        view.addSubview(
            captureButton
        )


        captureActivityIndicator.translatesAutoresizingMaskIntoConstraints =
        false


        captureActivityIndicator.color =
            .darkGray


        captureActivityIndicator.hidesWhenStopped =
        true


        captureButton.addSubview(
            captureActivityIndicator
        )


        NSLayoutConstraint.activate([


            captureActivityIndicator.centerXAnchor.constraint(
                equalTo:captureButton.centerXAnchor
            ),


            captureActivityIndicator.centerYAnchor.constraint(
                equalTo:captureButton.centerYAnchor
            )


        ])


        NSLayoutConstraint.activate([
            
            
            captureButton.centerXAnchor.constraint(
                equalTo:view.centerXAnchor
            ),
            
            
            captureButton.bottomAnchor.constraint(
                equalTo:view.safeAreaLayoutGuide.bottomAnchor,
                constant:-35
            ),
            
            
            captureButton.widthAnchor.constraint(
                equalToConstant:80
            ),
            
            
            captureButton.heightAnchor.constraint(
                equalToConstant:80
            )
            
            
        ])




        // MARK: 多页完成按钮

        doneButton.translatesAutoresizingMaskIntoConstraints =
        false


        doneButton.backgroundColor =
        .systemBlue


        doneButton.setTitleColor(
            .white,
            for:.normal
        )


        doneButton.titleLabel?.font =
        .systemFont(
            ofSize:16,
            weight:.semibold
        )


        doneButton.layer.cornerRadius =
        20


        doneButton.isHidden =
        true


        doneButton.isEnabled =
        false


        doneButton.alpha =
        0.5


        doneButton.setTitle(
            L10n.format("完成 (%@)", "0"),
            for:.normal
        )


        doneButton.addTarget(
            self,
            action:#selector(finishMultiPageScan),
            for:.touchUpInside
        )


        view.addSubview(
            doneButton
        )


        NSLayoutConstraint.activate([


            doneButton.trailingAnchor.constraint(
                equalTo:view.safeAreaLayoutGuide.trailingAnchor,
                constant:-20
            ),


            doneButton.centerYAnchor.constraint(
                equalTo:captureButton.centerYAnchor
            ),


            doneButton.widthAnchor.constraint(
                equalToConstant:92
            ),


            doneButton.heightAnchor.constraint(
                equalToConstant:40
            )


        ])
        
        
        
        
        // MARK: 单页 / 多页
        
        modeControl.translatesAutoresizingMaskIntoConstraints =
        false
        
        
        modeControl.selectedSegmentIndex =
        0
        
        
        modeControl.addTarget(
            self,
            action:#selector(changeMode),
            for:.valueChanged
        )
        
        
        view.addSubview(
            modeControl
        )
        
        
        NSLayoutConstraint.activate([
            
            
            modeControl.centerXAnchor.constraint(
                equalTo:view.centerXAnchor
            ),
            
            
            modeControl.bottomAnchor.constraint(
                equalTo:captureButton.topAnchor,
                constant:-20
            )
            
            
        ])
        
        
        
        
        // MARK: 闪光灯
        
        flashButton.translatesAutoresizingMaskIntoConstraints =
        false
        
        
        flashButton.tintColor =
            .white
        
        
        updateFlashIcon()
        
        
        flashButton.addTarget(
            self,
            action:#selector(toggleFlash),
            for:.touchUpInside
        )
        
        
        view.addSubview(
            flashButton
        )
        
        
        NSLayoutConstraint.activate([
            
            
            flashButton.trailingAnchor.constraint(
                equalTo:view.trailingAnchor,
                constant:-30
            ),
            
            
            flashButton.topAnchor.constraint(
                equalTo:view.safeAreaLayoutGuide.topAnchor,
                constant:20
            ),
            
            
            flashButton.widthAnchor.constraint(
                equalToConstant:50
            ),
            
            
            flashButton.heightAnchor.constraint(
                equalToConstant:40
            )
            
            
        ])


        // MARK: 拍摄引导

        guidanceLabel.translatesAutoresizingMaskIntoConstraints = false
        guidanceLabel.textColor = .white
        guidanceLabel.font = .systemFont(
            ofSize:14,
            weight:.semibold
        )
        guidanceLabel.textAlignment = .center
        guidanceLabel.numberOfLines = 2
        guidanceLabel.backgroundColor = UIColor.black.withAlphaComponent(
            0.58
        )
        guidanceLabel.layer.cornerRadius = 12
        guidanceLabel.layer.masksToBounds = true
        guidanceLabel.text = L10n.text(
            "将纸张或书页放在画面中央"
        )
        guidanceLabel.isHidden =
            !RecognitionSettings.captureGuidanceEnabled

        view.addSubview(guidanceLabel)

        NSLayoutConstraint.activate([
            guidanceLabel.topAnchor.constraint(
                equalTo:view.safeAreaLayoutGuide.topAnchor,
                constant:72
            ),
            guidanceLabel.centerXAnchor.constraint(
                equalTo:view.centerXAnchor
            ),
            guidanceLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo:view.leadingAnchor,
                constant:32
            ),
            guidanceLabel.trailingAnchor.constraint(
                lessThanOrEqualTo:view.trailingAnchor,
                constant:-32
            ),
            guidanceLabel.heightAnchor.constraint(
                greaterThanOrEqualToConstant:38
            )
        ])


        // MARK: 拍摄完成过渡层

        processingOverlay.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.backgroundColor = .black
        processingOverlay.alpha = 0
        processingOverlay.isHidden = true
        view.addSubview(processingOverlay)

        capturedImageView.translatesAutoresizingMaskIntoConstraints = false
        capturedImageView.contentMode = .scaleAspectFill
        capturedImageView.clipsToBounds = true
        processingOverlay.addSubview(capturedImageView)

        let dimView = UIView()
        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        processingOverlay.addSubview(dimView)

        processingCard.translatesAutoresizingMaskIntoConstraints = false
        processingCard.layer.cornerRadius = 20
        processingCard.layer.masksToBounds = true
        processingOverlay.addSubview(processingCard)

        processingIcon.translatesAutoresizingMaskIntoConstraints = false
        processingIcon.tintColor = .systemGreen
        processingIcon.contentMode = .scaleAspectFit
        processingCard.contentView.addSubview(processingIcon)

        processingTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        processingTitleLabel.textColor = .white
        processingTitleLabel.font = .systemFont(ofSize:19, weight:.semibold)
        processingTitleLabel.textAlignment = .center
        processingCard.contentView.addSubview(processingTitleLabel)

        processingDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        processingDetailLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        processingDetailLabel.font = .systemFont(ofSize:14, weight:.regular)
        processingDetailLabel.textAlignment = .center
        processingDetailLabel.numberOfLines = 2
        processingCard.contentView.addSubview(processingDetailLabel)

        processingIndicator.translatesAutoresizingMaskIntoConstraints = false
        processingIndicator.color = .white
        processingIndicator.hidesWhenStopped = true
        processingCard.contentView.addSubview(processingIndicator)

        NSLayoutConstraint.activate([
            processingOverlay.leadingAnchor.constraint(equalTo:view.leadingAnchor),
            processingOverlay.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            processingOverlay.topAnchor.constraint(equalTo:view.topAnchor),
            processingOverlay.bottomAnchor.constraint(equalTo:view.bottomAnchor),
            capturedImageView.leadingAnchor.constraint(equalTo:processingOverlay.leadingAnchor),
            capturedImageView.trailingAnchor.constraint(equalTo:processingOverlay.trailingAnchor),
            capturedImageView.topAnchor.constraint(equalTo:processingOverlay.topAnchor),
            capturedImageView.bottomAnchor.constraint(equalTo:processingOverlay.bottomAnchor),
            dimView.leadingAnchor.constraint(equalTo:processingOverlay.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo:processingOverlay.trailingAnchor),
            dimView.topAnchor.constraint(equalTo:processingOverlay.topAnchor),
            dimView.bottomAnchor.constraint(equalTo:processingOverlay.bottomAnchor),
            processingCard.centerXAnchor.constraint(equalTo:processingOverlay.centerXAnchor),
            processingCard.centerYAnchor.constraint(equalTo:processingOverlay.centerYAnchor),
            processingCard.leadingAnchor.constraint(greaterThanOrEqualTo:processingOverlay.leadingAnchor, constant:36),
            processingCard.trailingAnchor.constraint(lessThanOrEqualTo:processingOverlay.trailingAnchor, constant:-36),
            processingCard.widthAnchor.constraint(lessThanOrEqualToConstant:330),
            processingIcon.topAnchor.constraint(equalTo:processingCard.contentView.topAnchor, constant:22),
            processingIcon.centerXAnchor.constraint(equalTo:processingCard.contentView.centerXAnchor),
            processingIcon.widthAnchor.constraint(equalToConstant:38),
            processingIcon.heightAnchor.constraint(equalToConstant:38),
            processingTitleLabel.topAnchor.constraint(equalTo:processingIcon.bottomAnchor, constant:12),
            processingTitleLabel.leadingAnchor.constraint(equalTo:processingCard.contentView.leadingAnchor, constant:24),
            processingTitleLabel.trailingAnchor.constraint(equalTo:processingCard.contentView.trailingAnchor, constant:-24),
            processingDetailLabel.topAnchor.constraint(equalTo:processingTitleLabel.bottomAnchor, constant:7),
            processingDetailLabel.leadingAnchor.constraint(equalTo:processingCard.contentView.leadingAnchor, constant:22),
            processingDetailLabel.trailingAnchor.constraint(equalTo:processingCard.contentView.trailingAnchor, constant:-22),
            processingIndicator.topAnchor.constraint(equalTo:processingDetailLabel.bottomAnchor, constant:14),
            processingIndicator.centerXAnchor.constraint(equalTo:processingCard.contentView.centerXAnchor),
            processingIndicator.bottomAnchor.constraint(equalTo:processingCard.contentView.bottomAnchor, constant:-20)
        ])

        view.bringSubviewToFront(processingOverlay)
        
        
    }


    private func showImmediateCapturedTransition(
        image:UIImage,
        pageNumber:Int,
        feedbackID:UUID
    ) {
        guard activeCaptureFeedbackID == feedbackID,
              !didReceiveFormalPhoto else {
            return
        }

        processingMessageWorkItems.forEach { $0.cancel() }
        processingMessageWorkItems.removeAll()

        capturedImageView.image = image
        processingIcon.image = UIImage(systemName:"checkmark.circle.fill")
        processingIcon.tintColor = .systemGreen
        processingTitleLabel.text = isMultiPage
            ? L10n.format("第 %@ 页已拍摄", String(pageNumber))
            : L10n.text("已拍摄")
        processingDetailLabel.text = L10n.text("正在获取高清原图…")
        processingIndicator.stopAnimating()
        processingOverlay.isHidden = false

        UIView.animate(withDuration:0.08) {
            self.processingOverlay.alpha = 1
        }

        if let startedAt = captureFeedbackStartedAt {
            let milliseconds = Int(
                ((CACurrentMediaTime() - startedAt) * 1_000).rounded()
            )
            RecognitionLogStore.shared.add(
                category:"拍摄反馈",
                message:"已显示即时预览",
                details:"快门后 \(milliseconds) 毫秒，来源 相机预览帧"
            )
        }
    }


    private func showCapturedTransition(
        image:UIImage,
        pageNumber:Int
    ) {
        didReceiveFormalPhoto = true
        processingMessageWorkItems.forEach { $0.cancel() }
        processingMessageWorkItems.removeAll()

        processingOverlay.isHidden = false
        if processingOverlay.alpha == 0 {
            processingOverlay.alpha = 1
        }

        UIView.transition(
            with:capturedImageView,
            duration:0.14,
            options:[.transitionCrossDissolve, .allowAnimatedContent]
        ) {
            self.capturedImageView.image = image
        }

        processingIcon.image = UIImage(systemName:"doc.viewfinder")
        processingIcon.tintColor = .white
        processingTitleLabel.text = L10n.text("画面智能处理中…")
        processingDetailLabel.text = L10n.text(
            "正在校正纸张并优化文字清晰度"
        )
        processingIndicator.startAnimating()

        scheduleProcessingMessage(
            after:1.25,
            title:"正在检查文字清晰度…",
            detail:"正在选择更清晰且安全的扫描结果"
        )
        scheduleProcessingMessage(
            after:2.75,
            title:"正在生成扫描预览…",
            detail:"复杂页面可能需要多一点时间"
        )
    }


    private func scheduleProcessingMessage(
        after delay:TimeInterval,
        title:String,
        detail:String
    ) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.processingOverlay.isHidden else { return }
            self.processingIcon.image = UIImage(systemName:"doc.viewfinder")
            self.processingIcon.tintColor = .white
            self.processingTitleLabel.text = L10n.text(title)
            self.processingDetailLabel.text = L10n.text(detail)
            self.processingIndicator.startAnimating()
        }
        processingMessageWorkItems.append(workItem)
        DispatchQueue.main.asyncAfter(
            deadline:.now() + delay,
            execute:workItem
        )
    }


    private func hideCapturedTransition(
        completion:(()->Void)? = nil
    ) {
        processingMessageWorkItems.forEach { $0.cancel() }
        processingMessageWorkItems.removeAll()
        UIView.animate(
            withDuration:0.20,
            animations:{ self.processingOverlay.alpha = 0 },
            completion:{ _ in
                self.processingIndicator.stopAnimating()
                self.processingOverlay.isHidden = true
                self.capturedImageView.image = nil
                self.activeCaptureFeedbackID = nil
                self.didReceiveFormalPhoto = false
                self.captureFeedbackStartedAt = nil
                completion?()
            }
        )
    }
    
    
    
    
    
    
    // MARK: Vision Detection
    
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ){
        if !isProcessingPhoto,
           let previewBuffer = CMSampleBufferGetImageBuffer(
            sampleBuffer
        ) {
            previewFrameLock.lock()
            latestPreviewPixelBuffer = previewBuffer
            latestPreviewOrientation = visionImageOrientation
            previewFrameLock.unlock()

            let bufferedCorners = recentDocumentCorners.last
            let referenceCorners = recentDocumentCorners.isEmpty
                ? nil : averagedCorners(recentDocumentCorners)
            let bufferedOrientation = visionImageOrientation

            captureBufferSchedulingLock.lock()
            let canScheduleBufferAnalysis = !captureBufferAnalysisPending
            if canScheduleBufferAnalysis {
                captureBufferAnalysisPending = true
            }
            captureBufferSchedulingLock.unlock()

            if canScheduleBufferAnalysis {
                captureBufferQueue.async { [weak self] in
                    guard let self else { return }
                    self.captureFrameBuffer.offer(
                        pixelBuffer:previewBuffer,
                        orientation:bufferedOrientation,
                        corners:bufferedCorners,
                        referenceCorners:referenceCorners
                    )
                    self.captureBufferSchedulingLock.lock()
                    self.captureBufferAnalysisPending = false
                    self.captureBufferSchedulingLock.unlock()
                }
            }
        }

        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) >= 0.15 else {
            return
        }
        lastDetectionTime = now

        guard let buffer = CMSampleBufferGetImageBuffer(
            sampleBuffer
        ) else {
            return
        }

        let brightness = averageLuma(in:buffer)

        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.55
        request.maximumObservations = 6
        request.minimumAspectRatio = 0.12
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.10
        request.quadratureTolerance = 32

        let handler = VNImageRequestHandler(
            cvPixelBuffer:buffer,
            orientation:visionImageOrientation,
            options:[:]
        )

        do {
            try handler.perform([request])

            let observations = request.results ?? []
            let trackingReference = recentDocumentCorners.count >= 2
                ? averagedCorners(recentDocumentCorners)
                : nil
            guard let rectangle = DocumentRectangleSelector.best(
                in:observations,
                preferredCorners:trackingReference
            ) else {
                let largestCandidate = observations.max {
                    let firstArea = $0.boundingBox.width
                        * $0.boundingBox.height
                    let secondArea = $1.boundingBox.width
                        * $1.boundingBox.height
                    return firstArea < secondArea
                }

                recordMissingDocumentFrame(
                    brightness:brightness,
                    candidateCorners:largestCandidate.map {
                        DocumentRectangleSelector.corners(
                            from:$0
                        )
                    }
                )
                return
            }

            let corners = DocumentRectangleSelector.corners(
                from:rectangle
            )
            recordDocumentFrame(
                corners,
                brightness:brightness
            )
        }
        catch {
            recordMissingDocumentFrame(
                brightness:brightness,
                candidateCorners:nil
            )
        }
    }


    private func recordDocumentFrame(
        _ corners:ScanCorners,
        brightness:CGFloat
    ){
        missedDetectionFrames = 0


        // 参考 WeScan 的连续帧漏斗：如果新结果突然跳到另一处，
        // 重新开始积累，避免把不同物体的四角平均在一起。
        if !recentDocumentCorners.isEmpty {

            let currentAverage = averagedCorners(
                recentDocumentCorners
            )

            if maximumCornerDistance(
                corners,
                currentAverage
            ) > 0.075 {

                recentDocumentCorners.removeAll()

            }

        }


        recentDocumentCorners.append(corners)

        if recentDocumentCorners.count > 8 {
            recentDocumentCorners.removeFirst(
                recentDocumentCorners.count - 8
            )
        }

        let average = averagedCorners(recentDocumentCorners)
        let stabilityWindow = recentDocumentCorners.suffix(5)
        let averageJitter = stabilityWindow.isEmpty
            ? CGFloat.greatestFiniteMagnitude
            : stabilityWindow.reduce(CGFloat.zero) {
                $0 + maximumCornerDistance($1, average)
            } / CGFloat(stabilityWindow.count)
        let isStable = stabilityWindow.count == 5
            && stabilityWindow.allSatisfy {
                maximumCornerDistance($0, average) <= 0.018
            }
            && quadrilateralArea(average) >= 0.12
        let recentFrameCount = recentDocumentCorners.count
        let stableFrameCount = stabilityWindow.count

        DispatchQueue.main.async {
            self.stableDocumentCorners = isStable ? average : nil
            self.stableDocumentStability = isStable
                ? CaptureCornerStability(
                    recentFrameCount:recentFrameCount,
                    stableFrameCount:stableFrameCount,
                    averageCornerJitter:averageJitter
                )
                : nil
            self.updateGuidance(
                corners:average,
                isStable:isStable,
                brightness:brightness
            )
        }
    }


    private func recordMissingDocumentFrame(
        brightness:CGFloat,
        candidateCorners:ScanCorners?
    ){
        missedDetectionFrames += 1

        guard missedDetectionFrames >= 3 else {
            return
        }

        recentDocumentCorners.removeAll()

        DispatchQueue.main.async {
            self.stableDocumentCorners = nil
            self.stableDocumentStability = nil
            self.boxLayer.path = nil
            self.updateGuidance(
                corners:candidateCorners,
                isStable:false,
                brightness:brightness
            )
        }
    }


    private func averageLuma(
        in pixelBuffer:CVPixelBuffer
    )->CGFloat {
        CVPixelBufferLockBaseAddress(
            pixelBuffer,
            .readOnly
        )

        defer {
            CVPixelBufferUnlockBaseAddress(
                pixelBuffer,
                .readOnly
            )
        }

        let isPlanar = CVPixelBufferIsPlanar(pixelBuffer)
        let width = isPlanar
            ? CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            : CVPixelBufferGetWidth(pixelBuffer)
        let height = isPlanar
            ? CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            : CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = isPlanar
            ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            : CVPixelBufferGetBytesPerRow(pixelBuffer)
        let baseAddress = isPlanar
            ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
            : CVPixelBufferGetBaseAddress(pixelBuffer)

        guard width > 0,
              height > 0,
              let baseAddress else {
            return 128
        }

        let bytes = baseAddress.assumingMemoryBound(
            to:UInt8.self
        )
        let horizontalStep = max(width / 24, 1)
        let verticalStep = max(height / 24, 1)
        var sum = 0
        var count = 0

        for y in stride(
            from:verticalStep / 2,
            to:height,
            by:verticalStep
        ) {
            for x in stride(
                from:horizontalStep / 2,
                to:width,
                by:horizontalStep
            ) {
                sum += Int(bytes[y * bytesPerRow + x])
                count += 1
            }
        }

        guard count > 0 else {
            return 128
        }

        return CGFloat(sum) / CGFloat(count)
    }


    private func updateGuidance(
        corners:ScanCorners?,
        isStable:Bool,
        brightness:CGFloat
    ){
        guard RecognitionSettings.captureGuidanceEnabled else {
            guidanceLabel.isHidden = true
            return
        }

        guidanceLabel.isHidden = false

        let message:String

        if brightness < 48 {
            message = flashMode != .off
                ? L10n.text("光线较暗，闪光灯会辅助拍摄")
                : L10n.text("光线较暗，建议开启闪光灯")
        }
        else if let corners {
            let area = quadrilateralArea(corners)

            if area < 0.18 {
                message = L10n.text("请靠近并对准单页纸张")
            }
            else if perspectiveIsStrong(corners) {
                message = L10n.text("请尽量让手机与纸面保持平行")
            }
            else if isStable {
                message = L10n.text("已对准，可以拍摄")
            }
            else {
                message = L10n.text("请保持稳定")
            }
        }
        else {
            message = L10n.text("将纸张或书页放在画面中央")
        }

        guard message != lastGuidanceMessage else {
            return
        }

        lastGuidanceMessage = message
        guidanceLabel.text = "  \(message)  "
    }


    private func perspectiveIsStrong(
        _ corners:ScanCorners
    )->Bool {
        func length(
            _ first:CGPoint,
            _ second:CGPoint
        )->CGFloat {
            hypot(
                first.x - second.x,
                first.y - second.y
            )
        }

        let top = length(corners.topLeft, corners.topRight)
        let bottom = length(
            corners.bottomLeft,
            corners.bottomRight
        )
        let left = length(corners.topLeft, corners.bottomLeft)
        let right = length(corners.topRight, corners.bottomRight)
        let horizontalRatio = max(top, bottom)
            / max(min(top, bottom), 0.0001)
        let verticalRatio = max(left, right)
            / max(min(left, right), 0.0001)

        return horizontalRatio > 1.75
            || verticalRatio > 1.75
    }


    private func averagedCorners(
        _ corners:[ScanCorners]
    )->ScanCorners {
        let divisor = CGFloat(max(corners.count, 1))

        func average(
            _ keyPath:KeyPath<ScanCorners,CGPoint>
        )->CGPoint {
            corners.reduce(CGPoint.zero) { partial, item in
                let point = item[keyPath:keyPath]
                return CGPoint(
                    x:partial.x + point.x,
                    y:partial.y + point.y
                )
            }
            .applying(
                CGAffineTransform(
                    scaleX:1 / divisor,
                    y:1 / divisor
                )
            )
        }

        return ScanCorners(
            topLeft:average(\.topLeft),
            topRight:average(\.topRight),
            bottomRight:average(\.bottomRight),
            bottomLeft:average(\.bottomLeft)
        )
    }


    private func maximumCornerDistance(
        _ first:ScanCorners,
        _ second:ScanCorners
    )->CGFloat {
        [
            hypot(
                first.topLeft.x - second.topLeft.x,
                first.topLeft.y - second.topLeft.y
            ),
            hypot(
                first.topRight.x - second.topRight.x,
                first.topRight.y - second.topRight.y
            ),
            hypot(
                first.bottomRight.x - second.bottomRight.x,
                first.bottomRight.y - second.bottomRight.y
            ),
            hypot(
                first.bottomLeft.x - second.bottomLeft.x,
                first.bottomLeft.y - second.bottomLeft.y
            )
        ]
        .max() ?? .greatestFiniteMagnitude
    }


    private func quadrilateralArea(
        _ corners:ScanCorners
    )->CGFloat {

        let points = [
            corners.topLeft,
            corners.topRight,
            corners.bottomRight,
            corners.bottomLeft
        ]

        var sum:CGFloat = 0

        for index in points.indices {

            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y
                - next.x * points[index].y

        }

        return abs(sum) / 2
    }


    private func drawDocumentCorners(
        _ corners:ScanCorners,
        isStable:Bool
    ){
        func previewPoint(_ point:CGPoint)->CGPoint {
            previewLayer.layerPointConverted(
                fromCaptureDevicePoint:point
            )
        }

        let path = UIBezierPath()
        path.move(to:previewPoint(corners.topLeft))
        path.addLine(to:previewPoint(corners.topRight))
        path.addLine(to:previewPoint(corners.bottomRight))
        path.addLine(to:previewPoint(corners.bottomLeft))
        path.close()

        boxLayer.strokeColor = (
            isStable ? UIColor.systemGreen : UIColor.systemYellow
        ).cgColor
        boxLayer.path = path.cgPath
    }


    private func resetDocumentTracking(){
        stableDocumentCorners = nil
        stableDocumentStability = nil
        captureReferenceCorners = nil
        captureReferenceStability = nil
        boxLayer.path = nil
        lastGuidanceMessage = ""
        updateGuidance(
            corners:nil,
            isStable:false,
            brightness:128
        )
        frozenCaptureBuffer = nil
        captureBufferQueue.async { [weak self] in
            self?.captureFrameBuffer.resumeAndClear()
        }

        videoDetectionQueue.async {
            self.recentDocumentCorners.removeAll()
            self.missedDetectionFrames = 0
            self.lastDetectionTime = .distantPast
        }
    }
    
    
    
    
    
    
    // MARK: Capture
    
    
    @objc
    private func capture(){
        
        
        guard isCameraReady,
              !isProcessingPhoto
        else {
            
            print("⚠️ Session未运行")
            
            return
            
        }


        setCaptureEnabled(
            false
        )


        beginImmediateCaptureFeedback()


        waitForFocusAndExposure(
            startedAt:CACurrentMediaTime()
        )


    }


    private func beginImmediateCaptureFeedback(){
        let feedbackID = UUID()
        activeCaptureFeedbackID = feedbackID
        didReceiveFormalPhoto = false
        captureFeedbackStartedAt = CACurrentMediaTime()
        let pageNumber = scannedPages.count + 1

        previewFrameLock.lock()
        let pixelBuffer = latestPreviewPixelBuffer
        let orientation = latestPreviewOrientation
        previewFrameLock.unlock()

        guard let pixelBuffer else {
            RecognitionLogStore.shared.add(
                level:"警告",
                category:"拍摄反馈",
                message:"没有可用于即时预览的相机帧"
            )
            return
        }

        previewSnapshotQueue.async { [weak self] in
            guard let self,
                  let image = self.makePreviewSnapshot(
                    from:pixelBuffer,
                    orientation:orientation
                  ) else {
                return
            }

            DispatchQueue.main.async {
                self.showImmediateCapturedTransition(
                    image:image,
                    pageNumber:pageNumber,
                    feedbackID:feedbackID
                )
            }
        }
    }


    private func makePreviewSnapshot(
        from pixelBuffer:CVPixelBuffer,
        orientation:CGImagePropertyOrientation
    )->UIImage? {
        let orientedImage = CIImage(cvPixelBuffer:pixelBuffer)
            .oriented(forExifOrientation:Int32(orientation.rawValue))
        let maximumPreviewDimension:CGFloat = 1_600
        let longestDimension = max(
            orientedImage.extent.width,
            orientedImage.extent.height
        )
        let scale = min(
            1,
            maximumPreviewDimension / max(longestDimension, 1)
        )
        let previewImage = orientedImage.transformed(
            by:CGAffineTransform(scaleX:scale, y:scale)
        )

        guard let cgImage = previewCIContext.createCGImage(
            previewImage,
            from:previewImage.extent
        ) else {
            return nil
        }

        return UIImage(cgImage:cgImage)
    }


    private func waitForFocusAndExposure(
        startedAt:CFTimeInterval
    ){


        guard isProcessingPhoto else {

            return

        }


        let isAdjusting =
            cameraDevice?.isAdjustingFocus == true
            || cameraDevice?.isAdjustingExposure == true


        let hasTimedOut =
            CACurrentMediaTime() - startedAt
            >= focusExposureWaitLimit


        if !isAdjusting || hasTimedOut {

            performPhotoCapture(
                focusExposureTimedOut:hasTimedOut
            )
            return

        }


        DispatchQueue.main.asyncAfter(
            deadline:.now() + focusExposurePollInterval
        ){

            self.waitForFocusAndExposure(
                startedAt:startedAt
            )

        }


    }


    private func performPhotoCapture(
        focusExposureTimedOut:Bool
    ){


        // 快门前读取一次相机的实际重力方向，避免横竖屏切换后沿用旧角度。
        updateCameraOrientation()


        captureReferenceCorners =
        stableDocumentCorners


        captureReferenceStability =
        stableDocumentStability


        frozenCaptureBuffer = captureFrameBuffer.freeze()


        RecognitionLogStore.shared.add(
            category:"拍摄",
            message:captureReferenceCorners == nil
                ? "拍摄前没有取得连续稳定的纸张定位"
                : "拍摄前已取得连续稳定的纸张定位",
            details:L10n.format(
                "模式 %@，闪光灯 %@，对焦曝光 %@，方向 %@，拍摄旋转 %d°",
                L10n.text(isMultiPage ? "多页" : "单页"),
                flashMode.title,
                L10n.text(
                    focusExposureTimedOut
                        ? "等待 250 毫秒后拍摄"
                        : "已稳定"
                ),
                L10n.text("自动"),
                Int(currentCaptureRotationAngle.rounded())
            )
        )


        let settings =
        AVCapturePhotoSettings()


        settings.photoQualityPrioritization =
            .quality


        settings.flashMode = flashMode.captureMode


        if let connection = photoOutput.connection(
            with:.video
        ),
           connection.isVideoRotationAngleSupported(
            currentCaptureRotationAngle
           ) {
            connection.videoRotationAngle =
            currentCaptureRotationAngle
        }


        photoOutput.capturePhoto(
            with:settings,
            delegate:self
        )


    }
    
    
    
    
    
    
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ){


        if let error {

            print(
                "拍摄失败:",
                error
            )

            RecognitionLogStore.shared.add(
                level:"警告",
                category:"相机",
                message:"拍摄失败",
                details:error.localizedDescription
            )

            DispatchQueue.main.async {
                self.frozenCaptureBuffer = nil
                self.captureBufferQueue.async {
                    self.captureFrameBuffer.resumeAndClear()
                }
                self.hideCapturedTransition {
                    self.setCaptureEnabled(true)
                }
            }

            return

        }
        
        
        guard
            
            let data =
                photo.fileDataRepresentation(),
            
                let image =
                UIImage(
                    data:data
                )
                
        else {

            RecognitionLogStore.shared.add(
                level:"警告",
                category:"相机",
                message:"无法读取拍摄图片数据"
            )

            DispatchQueue.main.async {
                self.frozenCaptureBuffer = nil
                self.captureBufferQueue.async {
                    self.captureFrameBuffer.resumeAndClear()
                }
                self.hideCapturedTransition {
                    self.setCaptureEnabled(true)
                }
            }
            
            return
            
        }


        recordFlashResult(for:photo)

        let pageNumber = isMultiPage ? scannedPages.count + 1 : 1
        let snapshot = frozenCaptureBuffer ?? CaptureBufferSnapshot(
            frames:[],
            frozenAt:Date(),
            diagnosticsOnly:true
        )
        let fusionFeasibility = FrameFusionFeasibilityAnalyzer.analyze(
            snapshot:snapshot
        )
        FrameFusionDiagnostics.record(
            result:fusionFeasibility,
            pageNumber:pageNumber
        )
        let selection = BestFrameSelector.select(
            formalPhoto:image,
            formalCorners:captureReferenceCorners,
            snapshot:snapshot
        )
        CaptureBufferDiagnostics.record(
            result:selection,
            pageNumber:pageNumber
        )
        let selectedImage = selection.image
        let selectedCorners:ScanCorners?
        let selectedCornerStability:CaptureCornerStability?
        switch selection.source {
        case .formalPhoto:
            // A formal high-resolution photo may only carry the genuinely
            // stable pre-capture corners. Ordinary buffered-frame corners are
            // never allowed to influence its crop.
            selectedCorners = captureReferenceCorners
            selectedCornerStability = captureReferenceStability
        case .bufferedFrame:
            selectedCorners = selection.corners
            selectedCornerStability = nil
        }

        frozenCaptureBuffer = nil
        captureBufferQueue.async { [weak self] in
            self?.captureFrameBuffer.releaseFrozenFrames()
        }

        DispatchQueue.main.async {
            self.showCapturedTransition(
                image:selectedImage,
                pageNumber:self.scannedPages.count + 1
            )
        }
        
        
        if isMultiPage {


            print(
                "📸 多页拍摄完成，开始扫描处理"
            )


            ScanProcessor.shared.process(
                image:selectedImage,
                preferredCorners:selectedCorners,
                preferredCornerStability:selectedCornerStability,
                pageNumber:scannedPages.count + 1
            ){ processedPages in


                DispatchQueue.main.async {


                    guard !self.isDiscardingSession else {
                        for page in processedPages {
                            page.removeTemporaryFiles()
                        }
                        return
                    }


                    self.scannedPages.append(
                        contentsOf:processedPages
                    )


                    self.resetDocumentTracking()


                    self.updateMultiPageUI()


                    self.hideCapturedTransition {
                        self.setCaptureEnabled(true)
                    }


                    print(
                        "✅ 多页扫描，当前页数:",
                        self.scannedPages.count
                    )


                }


            }
            
            
        }
        else {
            
            
            print(
                "📸 拍摄完成，开始扫描处理"
            )
            
            
            ScanProcessor.shared.process(
                image:selectedImage,
                preferredCorners:selectedCorners,
                preferredCornerStability:selectedCornerStability,
                pageNumber:1
            ){ processedPages in
                
                
                print(
                    "✅ 扫描处理完成"
                )
                
                
                DispatchQueue.main.async {


                    guard !self.isDiscardingSession else {
                        for page in processedPages {
                            page.removeTemporaryFiles()
                        }
                        return
                    }


                    self.resetDocumentTracking()
                    
                    
                    guard let delegate = self.delegate else {
                        self.hideCapturedTransition {
                            self.setCaptureEnabled(true)
                        }
                        for page in processedPages {
                            page.removeTemporaryFiles()
                        }
                        return
                    }


                    self.didHandOffPages = true

                    // Keep the captured-photo transition fully visible until
                    // SwiftUI replaces the camera with ScanPreviewView. Hiding
                    // it first briefly exposes the live camera again.
                    self.processingMessageWorkItems.forEach { $0.cancel() }
                    self.processingMessageWorkItems.removeAll()
                    self.processingIcon.image = UIImage(
                        systemName:"doc.text.magnifyingglass"
                    )
                    self.processingIcon.tintColor = .white
                    self.processingTitleLabel.text = L10n.text(
                        "正在打开扫描预览…"
                    )
                    self.processingDetailLabel.text = L10n.text(
                        "扫描结果已准备完成"
                    )
                    self.processingIndicator.startAnimating()

                    delegate.scannerDidFinish(
                        pages:processedPages
                    )
                    
                    
                }
                
                
            }
            
            
        }
        
        
    }


    private func recordFlashResult(
        for photo:AVCapturePhoto
    ){
        let capturedFlashMode = flashMode
        let didFire:Bool?

        if let exif = photo.metadata[
            kCGImagePropertyExifDictionary as String
        ] as? [String:Any],
           let flashValue = exif[
            kCGImagePropertyExifFlash as String
           ] as? NSNumber {
            didFire = flashValue.intValue & 1 == 1
        }
        else {
            didFire = nil
        }

        let details = L10n.format(
            "模式 %@，实际触发 %@",
            capturedFlashMode.title,
            didFire.map {
                L10n.text($0 ? "是" : "否")
            } ?? L10n.text("未知")
        )

        RecognitionLogStore.shared.add(
            category:"闪光灯",
            message:"拍摄闪光灯结果",
            details:details
        )

        DiagnosticsCollector.shared.recordEvent(
            category:"闪光灯",
            message:"拍摄闪光灯结果",
            details:details
        )
    }
    // MARK: Mode


    @objc
    private func changeMode(){
        
        
        isMultiPage =
        modeControl.selectedSegmentIndex == 1
        
        
        if isMultiPage {

            discardScannedPages()

            doneButton.isHidden = false

            updateMultiPageUI()
            
            print("进入多页扫描")
            
        }
        else {

            discardScannedPages()

            doneButton.isHidden = true
            
            print("进入单页扫描")
            
        }
        
        
    }



    @objc
    private func finishMultiPageScan(){


        guard isMultiPage,
              !isProcessingPhoto,
              !scannedPages.isEmpty
        else {

            return

        }


        captureButton.isEnabled =
        false


        doneButton.isEnabled =
        false


        stopCamera()


        guard let delegate else {
            return
        }


        didHandOffPages = true


        delegate.scannerDidFinish(
            pages:scannedPages
        )


    }



    private func discardScannedPages(){

        for page in scannedPages {
            page.removeTemporaryFiles()
        }

        scannedPages.removeAll()
    }



    private func updateMultiPageUI(){


        let count =
        scannedPages.count


        doneButton.setTitle(
            L10n.format(
                "完成 (%@)",
                String(count)
            ),
            for:.normal
        )


        doneButton.isEnabled =
        count > 0 && !isProcessingPhoto


        doneButton.alpha =
        doneButton.isEnabled ? 1 : 0.5


    }



    private func setCaptureEnabled(
        _ enabled:Bool
    ){


        isProcessingPhoto =
        !enabled


        captureButton.isEnabled =
        enabled


        captureButton.alpha =
        enabled ? 1 : 0.55


        let modeCanChange =
        enabled && scannedPages.isEmpty


        modeControl.isEnabled =
        modeCanChange


        modeControl.alpha =
        modeCanChange ? 1 : 0.6


        flashButton.isEnabled = enabled
        flashButton.alpha = enabled ? 1 : 0.5


        if enabled {

            captureActivityIndicator.stopAnimating()

        }
        else {

            captureActivityIndicator.startAnimating()

        }


        if isMultiPage {

            updateMultiPageUI()

        }


    }



    // MARK: Flash


    @objc
    private func toggleFlash(){
        flashMode = flashMode.next
        updateFlashIcon()
    }

    private func updateFlashIcon(){
        flashButton.setImage(
            UIImage(systemName:flashMode.symbolName),
            for:.normal
        )
        flashButton.accessibilityLabel = L10n.format(
            "闪光灯：%@",
            flashMode.title
        )
    }
    
    
}


private enum ScannerCameraError:LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddPhotoOutput
    case cannotAddVideoOutput

    var errorDescription:String? {
        switch self {
        case .cameraUnavailable:
            return L10n.text("没有找到可用的后置相机。")
        case .cannotAddInput:
            return L10n.text("无法连接后置相机。")
        case .cannotAddPhotoOutput:
            return L10n.text("无法创建拍照输出。")
        case .cannotAddVideoOutput:
            return L10n.text("无法创建纸张识别预览。")
        }
    }
}
