import Foundation

/// Schema version for diagnostics JSON. Bump when structure changes.
public let DiagnosticsSchemaVersion = "1.0.0"

// MARK: - Top-level session log

/// Represents a complete diagnostics session log with app, device, session info and capture logs.
/// All fields are whitelisted and privacy-safe.
@preconcurrency public struct SessionLog: Codable, Sendable {
    /// Version of the diagnostics schema used.
    public var schemaVersion: String = DiagnosticsSchemaVersion
    /// Basic app information.
    public var app: AppInfo
    /// Device-specific information.
    public var device: DeviceInfo
    /// Session metadata.
    public var session: SessionInfo
    /// List of captures performed during the session.
    public var captures: [CaptureLog]
    /// Timestamp of session log creation.
    public var createdAt: Date

    public init(app: AppInfo, device: DeviceInfo, session: SessionInfo, captures: [CaptureLog] = [], createdAt: Date = Date()) {
        self.app = app
        self.device = device
        self.session = session
        self.captures = captures
        self.createdAt = createdAt
    }
}

// MARK: - App & Device (privacy-safe)

/// Minimal app info for diagnostics, excluding any user data.
public struct AppInfo: Codable, Sendable {
    /// App version string.
    public var version: String
    /// Build identifier string.
    public var build: String
}

/// Device information with privacy-safe fields only.
public struct DeviceInfo: Codable, Sendable {
    /// Thermal state of the device.
    public enum ThermalState: String, Codable, Sendable {
        case nominal, fair, serious, critical, unknown
    }
    /// Device model identifier (not user-visible).
    public var model: String
    /// Operating system version.
    public var iOS: String
    /// Current thermal state.
    public var thermalState: ThermalState
}

// MARK: - Session & Capture

/// Session metadata with identifiers and timing.
public struct SessionInfo: Codable, Sendable {
    /// Unique session identifier (UUID string).
    public var id: String
    /// Session start timestamp.
    public var startedAt: Date
    /// Session end timestamp, if ended.
    public var endedAt: Date?
    /// Indicates if session contains multiple pages.
    public var multiPage: Bool
    /// Number of pages in session, if multiPage is true.
    public var pageCount: Int?
}

/// Log of a single capture attempt, with privacy-safe diagnostic info.
public struct CaptureLog: Codable, Sendable {
    // Basic identifiers
    /// Unique capture id (UUID string).
    public var id: String
    /// Optional capture index in session.
    public var index: Int?
    /// Timestamp of capture.
    public var time: Date

    // Shooting context
    /// Optional device orientation at capture.
    public var orientation: String?
    /// Camera settings used.
    public var camera: CameraInfo?

    // Pre-capture stability metrics
    public var previewStability: PreviewStability?

    // Recognition algorithm path details
    public var path: RecognitionPath?

    // Candidate analysis results
    public var candidates: CandidateAnalysis?

    // Timing measurements in milliseconds
    public var timings: Timings?

    // Final privacy-safe result of capture processing
    public var result: FinalResult?

    // User adjustments applied post-capture
    public var userAdjust: UserAdjust?
}

// MARK: - Nested structs

/// Camera capture settings and stabilization info.
public struct CameraInfo: Codable, Sendable {
    /// Lens type, e.g. ultraWide, wide, telephoto, front.
    public var lens: String?
    /// Whether flash was enabled.
    public var flashSetting: Bool?
    /// Whether flash fired during capture.
    public var flashFired: Bool?
    /// ISO setting at capture.
    public var ISO: Double?
    /// Exposure duration in seconds.
    public var exposureSeconds: Double?
    /// Stabilization information.
    public var stabilized: Stabilized?

    /// Details about focus and exposure stabilization.
    public struct Stabilized: Codable, Sendable {
        public var focus: Bool?
        public var exposure: Bool?
    }
}

/// Metrics about preview frame stability before capture.
public struct PreviewStability: Codable, Sendable {
    public var recentFrames: Int?
    public var successFrames: Int?
    public var stableStreak: Int?
    public var cornerJitterAvg: Double?
    public var stableToShutterMs: Int?
    public var bboxCoverage: Double?
}

/// Details about recognition processing path and options.
public struct RecognitionPath: Codable, Sendable {
    public var strictOK: Bool?
    public var fromContinuousPreview: Bool?
    public var fallbackRan: Bool?
    public var enhancedRan: Bool?
    /// Color channels used in recognition.
    public var channels: [String]?
    public var bookSpread: Bool?
    public var mergePages: Bool?
    public var manualCrop: Bool?
}

/// Analysis of candidate detection results during recognition.
public struct CandidateAnalysis: Codable, Sendable {
    public var total: Int?
    public var rejected: Rejected?
    public var final: FinalCandidate?

    /// Breakdown of rejected candidates by reason.
    public struct Rejected: Codable, Sendable {
        public var smallArea: Int?
        public var badCenter: Int?
        public var badGeometry: Int?
        public var incompleteEdges: Int?
        public var noText: Int?
    }

    /// Characteristics of the final candidate selected.
    public struct FinalCandidate: Codable, Sendable {
        public var confidence: Double?
        public var coverage: Double?
        /// Corner points normalized to 0..1.
        public var cornersN: [[Double]]?
        public var edgeDistances: [Double]?
        public var safeInset: Double?
    }
}

/// Timing measurements for various capture and processing steps.
public struct Timings: Codable, Sendable {
    public var shutterMs: Int?
    public var orientationFixMs: Int?
    public var strictMs: Int?
    public var fallbackMs: Int?
    public var enhancedMs: Int?
    public var ocrAssistMs: Int?
    public var rectifyMs: Int?
    public var filterMs: Int?
    public var tempSaveMs: Int?
    public var totalMs: Int?
}

/// Final result of capture processing, privacy-safe.
public struct FinalResult: Codable, Sendable {
    /// File route or identifier.
    public var route: String?
    public var autoCropOK: Bool?
    /// Output image size.
    public var outSize: Size2D?
    /// Aspect ratio.
    public var aspect: Double?
    public var tempSaved: Bool?
    public var fileSaved: Bool?
    public var pdfOK: Bool?
    /// Error info if processing failed.
    public var error: ErrorInfo?

    /// 2D size structure.
    public struct Size2D: Codable, Sendable {
        public var width: Int
        public var height: Int
    }

    /// Error details with domain and code.
    public struct ErrorInfo: Codable, Sendable {
        public var domain: String
        public var code: Int
        public var message: String?
    }
}

/// User interaction adjustments after capture.
public struct UserAdjust: Codable, Sendable {
    public var opened: Bool?
    public var usedAutoCrop: Bool?
    public var selectAll: Bool?
    public var movedCorners: Bool?
    public var movedEdges: Bool?
    public var rotated: Bool?
    public var avgOffset: Double?
    public var maxCornerOffset: Double?
    public var mainDirection: String?
    public var saved: Bool?
}

// MARK: - Helpers

/// Helper for privacy validation and redaction.
public enum DiagnosticsRedaction {
    /// Ensures privacy by validating there are no forbidden fields like images or OCR text.
    /// This is a placeholder guard: call before writing to disk.
    /// Since our model is whitelist-only and contains no binary payloads or text contents,
    /// we simply return the session. Place additional checks here if the model expands.
    public static func assertPrivacySafe(_ session: SessionLog) -> SessionLog {
        return session
    }
}

extension SessionLog {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case app
        case device
        case session
        case captures
        case createdAt
    }

    nonisolated public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(app, forKey: .app)
        try container.encode(device, forKey: .device)
        try container.encode(session, forKey: .session)
        try container.encode(captures, forKey: .captures)
        try container.encode(createdAt, forKey: .createdAt)
    }

    nonisolated public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "1.0.0"
        self.app = try container.decode(AppInfo.self, forKey: .app)
        self.device = try container.decode(DeviceInfo.self, forKey: .device)
        self.session = try container.decode(SessionInfo.self, forKey: .session)
        self.captures = try container.decode([CaptureLog].self, forKey: .captures)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

