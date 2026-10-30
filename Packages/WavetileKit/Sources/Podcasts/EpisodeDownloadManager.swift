import Downloads
import Foundation
import os

/// Downloads episodes with a background `URLSession`, like music downloads, but straight from
/// the podcast's host.
///
/// Security: requests carry no Jellyfin headers or cookies. Files live in a per-account folder
/// that's protected until first unlock and excluded from backups (they can be re-downloaded).
public final class EpisodeDownloadManager: NSObject, Sendable {
    public let directory: URL
    private let database: PodcastDatabase
    private let identifier: String
    private let state = OSAllocatedUnfairLock(initialState: MutableState())
    private let log = Logger(subsystem: "com.derrellwilliams.wavetile", category: "podcast-downloads")

    private struct MutableState {
        var session: URLSession?
        var lastProgressWrite: [String: Double] = [:]
    }

    public static func sessionIdentifier(serverID: String, userID: String) -> String {
        "com.derrellwilliams.wavetile.podcasts.\(serverID).\(userID)"
    }

    public init(serverID: String, userID: String, database: PodcastDatabase) throws {
        self.database = database
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
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            config.httpMaximumConnectionsPerHost = 2
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            state.session = session
            return session
        }
    }

    // MARK: - Public API

    public func download(_ episode: EpisodeRecord, automatic: Bool, allowCellular: Bool) async throws {
        guard try await database.requestDownload(episodeID: episode.id, automatic: automatic) else { return }
        enqueue(episodeID: episode.id, url: episode.audioURL, allowCellular: allowCellular)
    }

    public func remove(episodeID: String) async throws {
        for task in await session.allTasks where task.taskDescription == episodeID { task.cancel() }
        if let name = try await database.removeDownload(episodeID: episodeID) { deleteFiles([name]) }
    }

    public func removeAll() async throws {
        for task in await session.allTasks { task.cancel() }
        deleteFiles(try await database.removeAllDownloads())
    }

    public func resumePending(allowCellular: Bool) async {
        let running = Set(await session.allTasks.compactMap(\.taskDescription))
        for item in (try? database.pendingDownloads()) ?? [] where !running.contains(item.id) {
            enqueue(episodeID: item.id, url: item.episode.audioURL, allowCellular: allowCellular)
        }
    }

    public func localFile(episodeID: String) -> URL? {
        guard let name = database.downloadedFileName(episodeID: episodeID) else { return nil }
        let url = directory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    public func deleteFiles(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    /// Deletes this account's podcast downloads folder (sign out, remove all podcast data).
    public func deleteEverything() {
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Internals

    private func enqueue(episodeID: String, url: URL, allowCellular: Bool) {
        // Background transfers obey App Transport Security, so try HTTPS for http:// enclosures.
        guard let secure = PodcastNetwork.secure(url) else {
            markFailed(episodeID, FeedError.insecure.localizedDescription)
            return
        }
        var request = URLRequest(url: secure)
        request.allowsCellularAccess = allowCellular
        let task = session.downloadTask(with: request)
        task.taskDescription = episodeID
        task.resume()
    }

    private static func makeDirectory(serverID: String, userID: String) throws -> URL {
        let safe = { (id: String) in id.filter { $0.isLetter || $0.isNumber || $0 == "-" } }
        var url = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "PodcastDownloads/\(safe(serverID))-\(safe(userID))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    /// AVFoundation picks a decoder from the file extension.
    static func fileExtension(for response: URLResponse?) -> String {
        switch response?.mimeType?.lowercased() {
        case "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac", "audio/aacp": "m4a"
        case "audio/ogg", "audio/opus": "ogg"
        case "audio/wav", "audio/x-wav": "wav"
        default:
            switch response?.url?.pathExtension.lowercased() {
            case "m4a", "mp4", "aac", "m4b": "m4a"
            default: "mp3"
            }
        }
    }

    private func markFailed(_ episodeID: String, _ message: String) {
        Task {
            try? await database.updateDownload(episodeID: episodeID) {
                $0.state = .failed
                $0.error = message
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension EpisodeDownloadManager: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let episodeID = downloadTask.taskDescription else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.05
        let shouldWrite = state.withLock { state in
            let last = state.lastProgressWrite[episodeID] ?? -1
            guard progress - last >= 0.05 else { return false }
            state.lastProgressWrite[episodeID] = progress
            return true
        }
        guard shouldWrite else { return }
        Task {
            try? await database.updateDownload(episodeID: episodeID) {
                $0.state = .downloading
                $0.progress = progress
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let episodeID = downloadTask.taskDescription else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            markFailed(episodeID, "The podcast's server returned \(http.statusCode)")
            return
        }
        // The temp file is deleted when this method returns, so move it synchronously.
        let name = "\(episodeID).\(Self.fileExtension(for: downloadTask.response))"
        let destination = directory.appending(path: name)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            try (destination as NSURL).setResourceValue(FileProtectionType.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
            let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            state.withLock { _ = $0.lastProgressWrite.removeValue(forKey: episodeID) }
            Task {
                try? await database.updateDownload(episodeID: episodeID) {
                    $0.state = .done
                    $0.fileName = name
                    $0.bytes = bytes
                    $0.progress = 1
                    $0.error = nil
                }
            }
        } catch {
            markFailed(episodeID, error.localizedDescription)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let episodeID = task.taskDescription else { return }
        if (error as? URLError)?.code == .cancelled { return }
        log.error("Episode download failed for \(episodeID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        markFailed(episodeID, error.localizedDescription)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = BackgroundSessionEvents.finished(identifier)
        DispatchQueue.main.async { completion?() }
    }
}
