//
//  ScannerViewController.swift
//  AoiScan
//

import UIKit
import AVFoundation
import Vision



protocol ScannerViewControllerDelegate: AnyObject {
    
    func scannerDidFinish(
        pages: [ScanPage]
    )
    
}




private enum CaptureOrientationMode:CaseIterable {
    case automatic
    case portrait
    case landscapeTopLeft
    case landscapeTopRight

    var title:String {
        switch self {
        case .automatic:
            return "自动"
        case .portrait:
            return "竖屏"
        case .landscapeTopLeft:
            return "横屏（手机顶部朝左）"
        case .landscapeTopRight:
            return "横屏（手机顶部朝右）"
        }
    }

    var shortTitle:String {
        switch self {
        case .automatic:
            return "自动"
        case .portrait:
            return "竖屏"
        case .landscapeTopLeft, .landscapeTopRight:
            return "横屏"
        }
    }

    var symbolName:String {
        switch self {
        case .automatic:
            return "arrow.triangle.2.circlepath.camera"
        case .portrait:
            return "rectangle.portrait"
        case .landscapeTopLeft:
            return "rectangle"
        case .landscapeTopRight:
            return "rectangle"
        }
    }

    var fixedRotationAngle:CGFloat? {
        switch self {
        case .automatic:
            return nil
        case .portrait:
            return 90
        case .landscapeTopLeft:
            return 0
        case .landscapeTopRight:
            return 180
        }
    }
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


    // 只在 videoDetectionQueue 中读写。
    private var visionImageOrientation:
    CGImagePropertyOrientation = .right
    
    
    
    
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


    private var captureReferenceCorners:ScanCorners?


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
    
    private var flashOn =
    RecognitionSettings.defaultFlashEnabled
    
    
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


    private var captureOrientationMode:
    CaptureOrientationMode = .automatic


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


    private let orientationButton =
    UIButton(type:.system)


    private let doneButton =
    UIButton(type:.system)
    
    
    private let modeControl =
    UISegmentedControl(
        items:[
            "单页",
            "多页"
        ]
    )


    private let guidanceLabel = UILabel()


    private var lastGuidanceMessage = ""
    
    
    
    
    
    
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
        previewLayer.videoGravity = .resizeAspectFill

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
                        title:"无法使用相机",
                        message:"请在系统设置中允许 AoiScan 使用相机。",
                        showsSettings:true
                    )
                }
            }

        case .denied, .restricted:
            queueCameraAlert(
                title:"无法使用相机",
                message:"请在系统设置中允许 AoiScan 使用相机。",
                showsSettings:true
            )

        @unknown default:
            queueCameraAlert(
                title:"相机不可用",
                message:"当前无法取得相机权限。",
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
        ),
              captureOrientationMode == .automatic else {
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
                    title:"相机启动失败",
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
                title:"取消",
                style:.cancel
            )
        )

        if pendingCameraAlert.showsSettings,
           let settingsURL = URL(
            string:UIApplication.openSettingsURLString
           ) {

            alert.addAction(
                UIAlertAction(
                    title:"前往设置",
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
        orientationButton.isEnabled = available
        orientationButton.alpha = available ? 1 : 0.5
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

        if let fixedRotationAngle =
            captureOrientationMode.fixedRotationAngle {
            previewRotationAngle = fixedRotationAngle
            captureRotationAngle = fixedRotationAngle
        }
        else if let lastValidDeviceOrientation,
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
            captureReferenceCorners = nil
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


            // 常亮灯保持关闭；拍照闪光仍由 flashOn 控制，默认开启。
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


        // MARK: 拍摄方向

        orientationButton.translatesAutoresizingMaskIntoConstraints = false
        orientationButton.tintColor = .white
        orientationButton.setTitleColor(
            .white,
            for:.normal
        )
        orientationButton.titleLabel?.font = .systemFont(
            ofSize:13,
            weight:.semibold
        )
        orientationButton.backgroundColor = UIColor.black.withAlphaComponent(
            0.48
        )
        orientationButton.layer.cornerRadius = 18
        orientationButton.showsMenuAsPrimaryAction = true
        updateOrientationMenu()

        view.addSubview(orientationButton)

        NSLayoutConstraint.activate([
            orientationButton.leadingAnchor.constraint(
                equalTo:view.leadingAnchor,
                constant:20
            ),
            orientationButton.topAnchor.constraint(
                equalTo:view.safeAreaLayoutGuide.topAnchor,
                constant:20
            ),
            orientationButton.widthAnchor.constraint(
                equalToConstant:82
            ),
            orientationButton.heightAnchor.constraint(
                equalToConstant:40
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
            "完成 (0)",
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
        guidanceLabel.text = "将纸张或书页放在画面中央"
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
        
        
    }
    
    
    
    
    
    
    // MARK: Vision Detection
    
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ){
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
        let isStable = stabilityWindow.count == 5
            && stabilityWindow.allSatisfy {
                maximumCornerDistance($0, average) <= 0.018
            }
            && quadrilateralArea(average) >= 0.12

        DispatchQueue.main.async {
            self.stableDocumentCorners = isStable ? average : nil
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
            message = flashOn
                ? "光线较暗，闪光灯会辅助拍摄"
                : "光线较暗，建议开启闪光灯"
        }
        else if let corners {
            let area = quadrilateralArea(corners)

            if area < 0.18 {
                message = "请靠近并对准单页纸张"
            }
            else if perspectiveIsStrong(corners) {
                message = "请尽量让手机与纸面保持平行"
            }
            else if isStable {
                message = "已对准，可以拍摄"
            }
            else {
                message = "请保持稳定"
            }
        }
        else {
            message = "将纸张或书页放在画面中央"
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
        captureReferenceCorners = nil
        boxLayer.path = nil
        lastGuidanceMessage = ""
        updateGuidance(
            corners:nil,
            isStable:false,
            brightness:128
        )

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


        waitForFocusAndExposure(
            startedAt:CACurrentMediaTime()
        )


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


        RecognitionLogStore.shared.add(
            category:"拍摄",
            message:captureReferenceCorners == nil
                ? "拍摄前没有取得连续稳定的纸张定位"
                : "拍摄前已取得连续稳定的纸张定位",
            details:
                "模式 \(isMultiPage ? "多页" : "单页")，闪光灯 \(flashOn ? "开启" : "关闭")，对焦曝光 \(focusExposureTimedOut ? "等待 250 毫秒后拍摄" : "已稳定")，方向 \(captureOrientationMode.title)，拍摄旋转 \(Int(currentCaptureRotationAngle.rounded()))°"
        )


        let settings =
        AVCapturePhotoSettings()


        settings.photoQualityPrioritization =
            .quality


        settings.flashMode =
        flashOn
        ? .on
        : .off


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
                self.setCaptureEnabled(true)
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
                self.setCaptureEnabled(true)
            }
            
            return
            
        }
        
        
        if isMultiPage {


            print(
                "📸 多页拍摄完成，开始扫描处理"
            )


            ScanProcessor.shared.process(
                image:image,
                preferredCorners:captureReferenceCorners
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


                    self.setCaptureEnabled(
                        true
                    )


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
                image:image,
                preferredCorners:captureReferenceCorners
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
                    
                    
                    self.setCaptureEnabled(
                        true
                    )


                    guard let delegate = self.delegate else {
                        for page in processedPages {
                            page.removeTemporaryFiles()
                        }
                        return
                    }


                    self.didHandOffPages = true


                    delegate.scannerDidFinish(
                        pages:processedPages
                    )
                    
                    
                }
                
                
            }
            
            
        }
        
        
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
            "完成 (\(count))",
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


        orientationButton.isEnabled = enabled
        orientationButton.alpha = enabled ? 1 : 0.5


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
        
        
        flashOn.toggle()
        
        
        updateFlashIcon()
        
        
    }
    private func updateFlashIcon(){
        
        
        flashButton.setImage(
            
            UIImage(
                systemName:
                    flashOn
                ? "bolt.fill"
                : "bolt.slash"
            ),
            
            for:.normal
            
        )
        
        
    }


    private func updateOrientationMenu(){
        let actions = CaptureOrientationMode.allCases.map { mode in
            UIAction(
                title:mode.title,
                image:UIImage(systemName:mode.symbolName),
                state:mode == captureOrientationMode ? .on : .off
            ) { [weak self] _ in
                self?.selectCaptureOrientation(mode)
            }
        }

        orientationButton.menu = UIMenu(
            title:"拍摄方向",
            children:actions
        )

        orientationButton.setImage(
            UIImage(systemName:captureOrientationMode.symbolName),
            for:.normal
        )
        orientationButton.setTitle(
            " \(captureOrientationMode.shortTitle)",
            for:.normal
        )
        orientationButton.accessibilityLabel =
            "拍摄方向：\(captureOrientationMode.title)"
    }


    private func selectCaptureOrientation(
        _ mode:CaptureOrientationMode
    ){
        guard captureOrientationMode != mode else {
            return
        }

        captureOrientationMode = mode
        updateOrientationMenu()
        updateCameraOrientation()

        RecognitionLogStore.shared.add(
            category:"拍摄方向",
            message:"已切换拍摄方向",
            details:mode.title
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
            return "没有找到可用的后置相机。"
        case .cannotAddInput:
            return "无法连接后置相机。"
        case .cannotAddPhotoOutput:
            return "无法创建拍照输出。"
        case .cannotAddVideoOutput:
            return "无法创建纸张识别预览。"
        }
    }
}
