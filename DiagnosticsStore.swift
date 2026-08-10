import Foundation
import UniformTypeIdentifiers

/// A thread-safe local diagnostics storage that saves, loads, exports, and clears diagnostic session logs.
/// It retains sessions only for 14 days to limit disk usage.
/// All file I/O operations are performed asynchronously on a background queue to avoid blocking the main thread.
public final class DiagnosticsStore: @unchecked Sendable {
    /// Shared singleton instance for easy access.
    public static let shared = DiagnosticsStore()

    /// Background queue dedicated to file I/O operations.
    private let ioQueue = DispatchQueue(label: "diagnostics.store.io", qos: .utility)
    /// File manager instance for file system interactions.
    private let fileManager = FileManager()
    /// Directory URL where session files are stored.
    private let directoryURL: URL
    /// Time interval to keep session files (14 days).
    private let keepInterval: TimeInterval = 14 * 24 * 3600 // 14 days

    /// Private initializer to enforce singleton usage.
    private init() {
        // Locate the Application Support directory for the current user domain.
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Append "Diagnostics" subdirectory for storing session files.
        let dir = base.appendingPathComponent("Diagnostics", conformingTo: .directory)
        self.directoryURL = dir
        // Ensure directory exists and clean up old files on initialization.
        ioQueue.async { [weak self] in
            // Best-effort directory creation at startup; saveSession will retry with full error handling.
            try? self?.ensureDirectory()
            self?.cleanupOldFiles()
        }
    }

    // MARK: - Public API

    /// Saves a diagnostic session asynchronously.
    /// - Parameters:
    ///   - session: The session log to save.
    ///   - completion: Optional completion handler with success or failure result containing the file URL or error.
    public func saveSession(_ session: SessionLog, completion: ((Result<URL, Error>) -> Void)? = nil) {
        let safe = DiagnosticsRedaction.assertPrivacySafe(session)
        ioQueue.async {
            do {
                try self.ensureDirectory()
                let url = self.fileURL(for: safe)
                let data = try JSONEncoder().withISO8601().encode(safe)
                try data.write(to: url, options: [.atomic])
                self.cleanupOldFiles()
                completion?(.success(url))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    /// Loads the most recent diagnostic sessions asynchronously.
    /// - Parameters:
    ///   - limit: Maximum number of sessions to load. Defaults to 20.
    ///   - completion: Completion handler with success result containing array of sessions or failure error.
    public func loadRecentSessions(limit: Int = 20, completion: @escaping (Result<[SessionLog], Error>) -> Void) {
        ioQueue.async {
            do {
                let urls = try self.sortedSessionFiles().prefix(limit)
                let decoder = JSONDecoder().withISO8601()
                let sessions: [SessionLog] = try urls.compactMap { url in
                    let data = try Data(contentsOf: url)
                    return try decoder.decode(SessionLog.self, from: data)
                }
                completion(.success(sessions))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Exports all sessions from the last specified number of days as JSON data asynchronously.
    /// - Parameters:
    ///   - days: Number of days to look back for sessions. Defaults to 14.
    ///   - completion: Completion handler with success result containing exported JSON data or failure error.
    public func exportRecentSessions(days: Int = 14, completion: @escaping (Result<Data, Error>) -> Void) {
        ioQueue.async {
            do {
                let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 3600))
                let decoder = JSONDecoder().withISO8601()
                let sessions: [SessionLog] = try self.sortedSessionFiles().compactMap { url in
                    let attrs = try self.fileManager.attributesOfItem(atPath: url.path)
                    let date = (attrs[.modificationDate] as? Date) ?? Date.distantPast
                    guard date >= cutoff else { return nil }
                    let data = try Data(contentsOf: url)
                    return try decoder.decode(SessionLog.self, from: data)
                }
                let export = try JSONEncoder().withISO8601(pretty: true).encode(sessions)
                completion(.success(export))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Clears all stored diagnostic sessions asynchronously.
    /// - Parameter completion: Optional completion handler with success or failure result.
    public func clearAll(completion: ((Result<Void, Error>) -> Void)? = nil) {
        ioQueue.async {
            do {
                if self.fileManager.fileExists(atPath: self.directoryURL.path) {
                    let urls = try self.fileManager.contentsOfDirectory(at: self.directoryURL, includingPropertiesForKeys: nil)
                    for url in urls { try? self.fileManager.removeItem(at: url) }
                }
                completion?(.success(()))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    // MARK: - Internals

    /// Ensures the diagnostics directory exists, creating it if necessary.
    /// - Throws: An error if directory creation fails.
    private func ensureDirectory() throws {
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDir) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    /// Constructs the file URL for a given session based on its unique ID.
    /// - Parameter session: The session log.
    /// - Returns: File URL where the session is stored.
    private func fileURL(for session: SessionLog) -> URL {
        let name = "session-\(session.session.id).json"
        return directoryURL.appendingPathComponent(name, conformingTo: .json)
    }

    /// Returns all stored session files sorted by modification date descending.
    /// - Throws: An error if directory reading fails.
    /// - Returns: Sorted array of session file URLs.
    private func sortedSessionFiles() throws -> [URL] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey])
        return urls.filter { $0.pathExtension == "json" }.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return l > r
        }
    }

    /// Removes session files older than the retention interval (14 days).
    private func cleanupOldFiles() {
        let cutoff = Date().addingTimeInterval(-keepInterval)
        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in urls where url.pathExtension == "json" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            if modified < cutoff {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}

// MARK: - JSON helpers

private extension JSONEncoder {
    /// Configures the JSONEncoder to use ISO8601 date encoding strategy.
    /// - Parameter pretty: Whether to pretty-print the JSON output.
    /// - Returns: Configured JSONEncoder instance.
    func withISO8601(pretty: Bool = false) -> JSONEncoder {
        dateEncodingStrategy = .iso8601
        if pretty { outputFormatting = [.prettyPrinted, .withoutEscapingSlashes] }
        return self
    }
}

private extension JSONDecoder {
    /// Configures the JSONDecoder to use ISO8601 date decoding strategy.
    /// - Returns: Configured JSONDecoder instance.
    func withISO8601() -> JSONDecoder {
        dateDecodingStrategy = .iso8601
        return self
    }
}

