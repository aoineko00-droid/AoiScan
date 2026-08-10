import Foundation

public final class DiagnosticsCollector: @unchecked Sendable {
    public static let shared = DiagnosticsCollector()

    private let queue = DispatchQueue(label: "diagnostics.collector", qos: .utility)

    // Current in-memory session under construction
    private var currentSession: SessionLog?

    private init() {}

    // MARK: - Session lifecycle

    /// Begin a new diagnostics session. Typically called when entering scan flow.
    /// - Parameters:
    ///   - sessionID: Identifier for the session. Default is a new UUID string.
    ///   - appVersion: Version of the app.
    ///   - build: Build identifier.
    ///   - deviceModel: Model identifier of the device.
    ///   - iOSVersion: Operating system version.
    ///   - thermalState: Thermal state of the device. Default is `.unknown`.
    ///   - multiPage: Whether the session includes multiple pages.
    public func beginSession(
        sessionID: String = UUID().uuidString,
        appVersion: String,
        build: String,
        deviceModel: String,
        iOSVersion: String,
        thermalState: DeviceInfo.ThermalState = .unknown,
        multiPage: Bool
    ) {
        queue.async {
            let app = AppInfo(version: appVersion, build: build)
            let device = DeviceInfo(model: deviceModel, iOS: iOSVersion, thermalState: thermalState)
            let session = SessionInfo(id: sessionID, startedAt: Date(), endedAt: nil, multiPage: multiPage, pageCount: nil)
            self.currentSession = SessionLog(app: app, device: device, session: session, captures: [], createdAt: Date())
        }
    }

    /// End the current session and persist it.
    /// - Parameters:
    ///   - pageCount: Optional page count to record in the session.
    ///   - completion: Optional completion handler called with the result of saving.
    public func endSession(pageCount: Int? = nil, completion: ((Result<URL, Error>) -> Void)? = nil) {
        queue.async {
            guard var session = self.currentSession else {
                completion?(.failure(NSError(domain: "Diagnostics", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active session"])))
                return
            }
            session.session.pageCount = pageCount
            session.session.endedAt = Date()
            self.currentSession = nil
            DiagnosticsStore.shared.saveSession(session, completion: completion)
        }
    }

    // MARK: - Capture events

    /// Record a capture event in the current session.
    /// - Parameter capture: The capture log to record.
    public func recordCapture(_ capture: CaptureLog) {
        queue.async {
            guard var session = self.currentSession else { return }
            session.captures.append(capture)
            self.currentSession = session
        }
    }

    /// Convenience builder for common capture info.
    /// - Parameters:
    ///   - id: Identifier for the capture. Default is a new UUID string.
    ///   - index: Optional index of the capture.
    ///   - time: Timestamp of the capture. Default is current date.
    ///   - orientation: Optional orientation string.
    ///   - camera: Optional camera info.
    ///   - previewStability: Optional preview stability info.
    ///   - path: Optional recognition path info.
    ///   - candidates: Optional candidate analysis.
    ///   - timings: Optional timing information.
    ///   - result: Optional final result.
    ///   - userAdjust: Optional user adjustment info.
    /// - Returns: A new CaptureLog instance.
    public func makeCapture(
        id: String = UUID().uuidString,
        index: Int? = nil,
        time: Date = Date(),
        orientation: String? = nil,
        camera: CameraInfo? = nil,
        previewStability: PreviewStability? = nil,
        path: RecognitionPath? = nil,
        candidates: CandidateAnalysis? = nil,
        timings: Timings? = nil,
        result: FinalResult? = nil,
        userAdjust: UserAdjust? = nil
    ) -> CaptureLog {
        return CaptureLog(
            id: id,
            index: index,
            time: time,
            orientation: orientation,
            camera: camera,
            previewStability: previewStability,
            path: path,
            candidates: candidates,
            timings: timings,
            result: result,
            userAdjust: userAdjust
        )
    }

    // MARK: - One-off event logging (minimal)
    /// Records a lightweight diagnostics event without requiring a prior beginSession.
    /// This creates a minimal session containing a single capture with provided details.
    public func recordEvent(category: String, message: String, details: String? = nil) {
        // Fetch potentially main-actor-associated values outside the background queue
        let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let iOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceModel: String = {
            var systemInfo = utsname()
            uname(&systemInfo)
            let mirror = Mirror(reflecting: systemInfo.machine)
            return mirror.children.reduce("") { id, element in
                guard let v = element.value as? Int8, v != 0 else { return id }
                return id + String(UnicodeScalar(UInt8(v)))
            }
        }()

        queue.async {
            let app = AppInfo(version: appVersion, build: build)
            let device = DeviceInfo(model: deviceModel, iOS: iOSVersion, thermalState: .unknown)
            let session = SessionInfo(id: UUID().uuidString, startedAt: Date(), endedAt: Date(), multiPage: false, pageCount: nil)

            var cap = CaptureLog(
                id: UUID().uuidString,
                index: nil,
                time: Date(),
                orientation: nil,
                camera: nil,
                previewStability: nil,
                path: nil,
                candidates: nil,
                timings: nil,
                result: nil,
                userAdjust: nil
            )
            cap.result = FinalResult(
                route: "event:\(category)",
                autoCropOK: nil,
                outSize: nil,
                aspect: nil,
                tempSaved: nil,
                fileSaved: nil,
                pdfOK: nil,
                error: FinalResult.ErrorInfo(domain: message, code: 0, message: details)
            )

            let sessionLog = SessionLog(app: app, device: device, session: session, captures: [cap], createdAt: Date())
            DiagnosticsStore.shared.saveSession(sessionLog, completion: nil)
        }
    }
}
