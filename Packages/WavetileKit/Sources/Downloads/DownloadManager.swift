import Foundation
import JellyfinKit
import os
import Persistence

/// Downloads tracks for offline listening with a background `URLSession`, so transfers
/// continue while the app is suspended and finish even if it's terminated by the system.
///
/// State lives in `LibraryDatabase` (collections → memberships → tracks), so the UI observes
/// it like any other library data. Files live in a per-account folder that is protected until
/// first unlock and excluded from backups (they can be re-downloaded).
public final class DownloadManager: NSObject, Sendable {
    public enum Quality: String, CaseIterable, Sendable {
        /// MP3 for everything (~256 kbps from Jellyfin): about a quarter the size of FLAC. The default.
        case high
        /// The original file when iOS can play it (FLAC/ALAC/MP3/AAC); otherwise 320k MP3.
        case original

        var maxBitrate: Int {
            switch self {
            case .original: 140_000_000
            // Jellyfin's MP3 encode lands at 256 kbps under this cap (verified against a 10.x server).
            case .high: 320_000
            }
        }
    }

    public let directory: URL
    private let database: LibraryDatabase
    private let library: LibraryClient
    private let identifier: String
    private let state = OSAllocatedUnfairLock(initialState: MutableState())
    private let log = Logger(subsystem: "com.derrellwilliams.wavetile", category: "downloads")

    private struct MutableState {
        var session: URLSession?
        var lastProgressWrite: [String: Double] = [:]
    }

    /// Background session identifiers must be stable across launches and unique per account.
    public static func sessionIdentifier(serverID: String, userID: String) -> String {
        "com.derrellwilliams.wavetile.downloads.\(serverID).\(userID)"
    }

    public init(serverID: String, userID: String, database: LibraryDatabase, library: LibraryClient) throws {
        self.database = database
        self.library = library
        self.identifier = Self.sessionIdentifier(serverID: serverID, userID: userID)
        self.directory = try Self.makeDirectory(serverID: serverID, userID: userID)
        super.init()
        _ = session  // Reconnect to transfers started in a previous launch.
    }

    private var session: URLSession {
        state.withLock { state in
            if let session = state.session { return session }
            let config = URLSessionConfiguration.background(withIdentifier: identifier)
            config.sessionSendsLaunchEvents = true
            config.isDiscretionary = false
            config.httpMaximumConnectionsPerHost = 3
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            state.session = session
            return session
        }
    }

    // MARK: - Public API

    public func download(_ collection: DownloadCollectionRecord, trackIDs: [String], quality: Quality, allowCellular: Bool) async throws {
        let needed = try await database.requestDownload(collection, trackIDs: trackIDs)
        enqueue(needed, quality: quality, allowCellular: allowCellular)
    }

    public func remove(collectionID: String) async throws {
        let files = try await database.removeDownload(collectionID: collectionID)
        await cancelTasks(notIn: try database.pendingDownloads().map(\.trackID))
        deleteFiles(files)
    }

    public func removeAll() async throws {
        await cancelTasks(notIn: [])
        let files = try await database.removeAllDownloads()
        deleteFiles(files)
    }

    /// Keeps downloaded playlists matching the server after a library sync.
    public func syncPlaylists(quality: Quality, allowCellular: Bool) async {
        guard let ids = try? database.downloadedPlaylistIDs() else { return }
        for id in ids {
            guard let tracks = try? database.tracks(playlistID: id) else { continue }
            guard let (added, orphans) = try? await database.syncDownloadedPlaylist(id: id, trackIDs: tracks.map(\.id)) else { continue }
            enqueue(added, quality: quality, allowCellular: allowCellular)
            deleteFiles(orphans)
        }
    }

    /// Restarts queued downloads that have no running task (e.g. after the app was killed).
    public func resumePending(quality: Quality, allowCellular: Bool) async {
        let running = Set(await session.allTasks.compactMap(\.taskDescription))
        let pending = (try? database.pendingDownloads().map(\.trackID)) ?? []
        enqueue(pending.filter { !running.contains($0) }, quality: quality, allowCellular: allowCellular)
    }

    /// Local file for a finished download, or nil. Cheap enough to call per player item.
    public func localFile(trackID: String) -> URL? {
        guard let name = database.downloadedFileName(trackID: trackID) else { return nil }
        let url = directory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// Deletes this account's download folder (sign out).
    public func deleteEverything() {
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Internals

    private func enqueue(_ trackIDs: [String], quality: Quality, allowCellular: Bool) {
        for trackID in trackIDs {
            guard let stream = library.streamRequest(trackID: trackID, maxBitrate: quality.maxBitrate) else { continue }
            var request = URLRequest(url: stream.url)
            // Header auth: the token isn't written into the URL (or the system's transfer logs).
            for (field, value) in stream.headers { request.setValue(value, forHTTPHeaderField: field) }
            request.allowsCellularAccess = allowCellular
            let task = session.downloadTask(with: request)
            task.taskDescription = trackID
            task.resume()
        }
    }

    private func cancelTasks(notIn keep: [String]) async {
        let keep = Set(keep)
        for task in await session.allTasks where !keep.contains(task.taskDescription ?? "") {
            task.cancel()
        }
    }

    private func deleteFiles(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    private static func makeDirectory(serverID: String, userID: String) throws -> URL {
        let safe = { (id: String) in id.filter { $0.isLetter || $0.isNumber || $0 == "-" } }
        var url = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Downloads/\(safe(serverID))-\(safe(userID))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    /// AVFoundation picks a decoder from the file extension, so map the served MIME type.
    static func fileExtension(for response: URLResponse?) -> String {
        switch response?.mimeType?.lowercased() {
        case "audio/flac", "audio/x-flac": "flac"
        case "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/alac": "m4a"
        case "audio/aac", "audio/aacp": "aac"
        case "audio/wav", "audio/x-wav", "audio/wave": "wav"
        case "audio/aiff", "audio/x-aiff": "aiff"
        default: response?.url?.pathExtension.isEmpty == false ? response!.url!.pathExtension : "mp3"
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let trackID = downloadTask.taskDescription else { return }
        // Transcoded streams have no length; show indeterminate-ish progress until done.
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.05
        // Throttle DB writes to ~5% steps.
        let shouldWrite = state.withLock { state in
            let last = state.lastProgressWrite[trackID] ?? -1
            guard progress - last >= 0.05 else { return false }
            state.lastProgressWrite[trackID] = progress
            return true
        }
        guard shouldWrite else { return }
        Task {
            try? await database.updateDownload(trackID: trackID) {
                $0.state = .downloading
                $0.progress = progress
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let trackID = downloadTask.taskDescription else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            markFailed(trackID, "Server returned \(http.statusCode)")
            return
        }
        // The temp file is deleted when this method returns, so move it synchronously.
        let name = "\(trackID).\(Self.fileExtension(for: downloadTask.response))"
        let destination = directory.appending(path: name)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            try (destination as NSURL).setResourceValue(FileProtectionType.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
            let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            state.withLock { _ = $0.lastProgressWrite.removeValue(forKey: trackID) }
            Task {
                try? await database.updateDownload(trackID: trackID) {
                    $0.state = .done
                    $0.fileName = name
                    $0.bytes = bytes
                    $0.progress = 1
                    $0.error = nil
                }
            }
        } catch {
            markFailed(trackID, error.localizedDescription)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let trackID = task.taskDescription else { return }
        if (error as? URLError)?.code == .cancelled { return }
        log.error("Download failed for \(trackID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        markFailed(trackID, error.localizedDescription)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = BackgroundSessionEvents.take(identifier)
        DispatchQueue.main.async { completion?() }
    }

    private func markFailed(_ trackID: String, _ message: String) {
        Task {
            try? await database.updateDownload(trackID: trackID) {
                $0.state = .failed
                $0.error = message
            }
        }
    }
}

/// Holds the completion handler iOS passes to the app delegate when it relaunches the app to
/// deliver background transfer events. The matching `DownloadManager` calls it when done.
public enum BackgroundSessionEvents {
    private static let handlers = OSAllocatedUnfairLock(initialState: [String: @Sendable () -> Void]())

    public static func store(_ identifier: String, completion: @escaping @Sendable () -> Void) {
        handlers.withLock { $0[identifier] = completion }
    }

    public static func take(_ identifier: String) -> (@Sendable () -> Void)? {
        handlers.withLock { $0.removeValue(forKey: identifier) }
    }
}
