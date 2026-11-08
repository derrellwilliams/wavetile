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
        var reconciling = false
        var lastProgressWrite: [String: Double] = [:]
        var lastByteWrite: [String: Int64] = [:]
        /// Automatic retries so far per track, this launch.
        var retries: [String: Int] = [:]
        /// The settings of the last enqueue, for retries that start a fresh request.
        var quality: Quality = .high
        var allowCellular = true
    }

    /// A dropped transfer is retried this many times (resuming where it stopped when it can).
    static let maxRetries = 3

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
        await enqueue(needed, quality: quality, allowCellular: allowCellular)
    }

    public func pause(collectionID: String) async throws {
        try await database.setDownloadPaused(collectionID: collectionID, paused: true)
        await cancelTasks(notIn: try database.pendingDownloads().map(\.trackID))
    }

    public func resume(collectionID: String, quality: Quality, allowCellular: Bool) async throws {
        try await database.setDownloadPaused(collectionID: collectionID, paused: false)
        await resumePending(quality: quality, allowCellular: allowCellular)
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

    /// Keeps downloaded playlists, collections and Favorites matching the library after a sync.
    public func syncPlaylists(quality: Quality, allowCellular: Bool) async {
        guard let downloads = try? database.syncedDownloads() else { return }
        for download in downloads {
            await sync(download, quality: quality, allowCellular: allowCellular)
        }
    }

    /// Brings the Favorites download up to date (after a heart changes), if there is one.
    public func syncFavorites(quality: Quality, allowCellular: Bool) async {
        guard let download = try? await database.pool.read({ try DownloadCollectionRecord.fetchOne($0, key: DownloadCollectionRecord.favoritesID) }) else { return }
        await sync(download, quality: quality, allowCellular: allowCellular)
    }

    private func sync(_ download: DownloadCollectionRecord, quality: Quality, allowCellular: Bool) async {
        // A playlist or collection that's gone (deleted here, or on the server) takes its
        // download with it, rather than leaving an empty one behind.
        // A failed read isn't "gone": only a successful lookup that finds nothing removes the download.
        let sourceExists: Bool
        do {
            sourceExists = switch download.kind {
            case .playlist: try database.playlist(id: download.id) != nil
            case .collection: try database.collection(id: download.id) != nil
            case .favorites, .album: true
            }
        } catch {
            return
        }
        guard sourceExists else {
            try? await remove(collectionID: download.id)
            return
        }
        let trackIDs: [String]? = switch download.kind {
        case .playlist: try? database.tracks(playlistID: download.id).map(\.id)
        case .collection: try? database.trackIDs(collectionID: download.id)
        case .favorites: try? database.favoritesDownloadTrackIDs()
        case .album: nil
        }
        guard let trackIDs,
              let (added, orphans) = try? await database.syncDownloadedPlaylist(id: download.id, trackIDs: trackIDs) else { return }
        await enqueue(added, quality: quality, allowCellular: allowCellular)
        deleteFiles(orphans)
    }

    /// Restarts queued downloads that have no running task (e.g. after the app was killed), and
    /// gives failed ones another go.
    public func resumePending(quality: Quality, allowCellular: Bool, retryFailed: Bool = true) async {
        guard state.withLock({ state in
            guard !state.reconciling else { return false }
            state.reconciling = true
            return true
        }) else { return }
        defer { state.withLock { $0.reconciling = false } }
        let running = Set(await session.allTasks.filter { $0.state == .running || $0.state == .suspended }.compactMap(\.taskDescription))
        await requeueMissingFiles()
        if retryFailed { _ = try? await database.requeueFailedDownloads() }
        let pending = (try? database.pendingDownloads().map(\.trackID)) ?? []
        await enqueue(pending.filter { !running.contains($0) }, quality: quality, allowCellular: allowCellular)
    }

    /// A download marked done whose file is gone would show as downloaded and count as playable
    /// offline, yet not play. Put it back in the queue instead.
    private func requeueMissingFiles() async {
        // An unreachable folder (not the files) means nothing can be said about them.
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)),
              let finished = try? database.finishedDownloads() else { return }
        let missing = finished.filter { record in
            guard let name = record.fileName else { return true }
            return !FileManager.default.fileExists(atPath: directory.appending(path: name).path(percentEncoded: false))
        }
        guard !missing.isEmpty else { return }
        log.error("\(missing.count, privacy: .public) finished downloads lost their file; queueing them again")
        try? await database.requeueDownloads(trackIDs: missing.map(\.trackID))
    }

    /// Security: the system carries a background transfer over to a new network on its own,
    /// token and all, so transfers from a plain-HTTP server stop here and wait for
    /// `resumePending` to restart them once the server has proved itself (see `ServerIdentity`).
    public func networkChanged() async {
        guard library.session.serverURL.scheme?.lowercased() == "http" else { return }
        for task in await session.allTasks { task.cancel() }
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

    private func enqueue(_ trackIDs: [String], quality: Quality, allowCellular: Bool) async {
        guard !trackIDs.isEmpty, await ServerIdentity.shared.confirmToken(to: library.session.serverURL) else { return }
        state.withLock {
            $0.quality = quality
            $0.allowCellular = allowCellular
        }
        let running = Set(await session.allTasks.filter { $0.state == .running || $0.state == .suspended }.compactMap(\.taskDescription))
        let pending = Set((try? database.pendingDownloads().map(\.trackID)) ?? [])
        for trackID in trackIDs where pending.contains(trackID) && !running.contains(trackID) {
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

    /// The track's file in the download folder. Security: the ID and extension come from the server,
    /// so only letters, digits and `-` are kept; a hostile ID like `../x` can't leave the folder.
    static func fileName(trackID: String, response: URLResponse?) -> String {
        let safe = { (text: String) in text.filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" } }
        let id = safe(trackID)
        return "\(id.isEmpty ? "track" : id).\(safe(fileExtension(for: response)).prefix(8))"
    }

    /// Rejects an empty body and text, JSON, XML or HTML responses; anything else (including
    /// `application/octet-stream`, which some servers use for audio) is left to the player.
    public static func looksLikeAudio(_ response: URLResponse?, bytes: Int64) -> Bool {
        guard bytes > 0 else { return false }
        let type = response?.mimeType?.lowercased() ?? ""
        return !(type.hasPrefix("text/") || type.contains("json") || type.contains("xml") || type.contains("html"))
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
            guard progress - last >= 0.05 || totalBytesWritten - (state.lastByteWrite[trackID] ?? 0) >= 262_144 else { return false }
            state.lastByteWrite[trackID] = totalBytesWritten
            state.lastProgressWrite[trackID] = progress
            return true
        }
        guard shouldWrite else { return }
        Task {
            try? await database.updateDownload(trackID: trackID) {
                guard $0.state == .queued || $0.state == .downloading else { return }
                $0.state = .downloading
                $0.bytes = totalBytesWritten
                $0.progress = progress
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let trackID = downloadTask.taskDescription else { return }
        if redirectedOffOrigin(downloadTask) {
            stopAfterOffOriginRedirect(trackID)
            return
        }
        if let http = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            if http.statusCode == 401 {
                Task { await library.checkAuthentication() }
            }
            markFailed(trackID, "Server returned \(http.statusCode)")
            return
        }
        // A proxy's login page or an error body saved as "music" would show as downloaded and fail to play.
        let received = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard Self.looksLikeAudio(downloadTask.response, bytes: received) else {
            markFailed(trackID, "The server didn't send audio")
            return
        }
        // The temp file is deleted when this method returns, so move it synchronously.
        let name = Self.fileName(trackID: trackID, response: downloadTask.response)
        let destination = directory.appending(path: name)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            try (destination as NSURL).setResourceValue(FileProtectionType.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
            let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            state.withLock { _ = $0.lastProgressWrite.removeValue(forKey: trackID) }
            state.withLock { _ = $0.retries.removeValue(forKey: trackID) }
            Task { [directory] in
                let wanted = (try? await database.updateDownload(trackID: trackID) {
                    $0.state = .done
                    $0.fileName = name
                    $0.bytes = bytes
                    $0.progress = 1
                    $0.error = nil
                }) ?? true
                // Its collection was removed while this finished: don't leave the file behind.
                if !wanted { try? FileManager.default.removeItem(at: directory.appending(path: name)) }
            }
        } catch {
            markFailed(trackID, error.localizedDescription)
        }
    }

    // Security: a background session follows redirects on its own and never asks its delegate
    // (so `RedirectGuard` can't run here), and the request carries the token in a header. The
    // check below runs afterwards: a download that ended on another origin stops the queue, so a
    // misbehaving server or proxy exposes the token to one request, not every track and retry.
    private func redirectedOffOrigin(_ task: URLSessionTask) -> Bool {
        RedirectGuard.leftOrigin(requested: task.originalRequest?.url, ended: task.currentRequest?.url ?? task.response?.url)
    }

    private func stopAfterOffOriginRedirect(_ trackID: String) {
        log.error("Download of \(trackID, privacy: .public) was redirected to another host; stopping all downloads")
        let message = "The server redirected this download to another host, so downloads were stopped to protect your sign-in."
        Task {
            for task in await session.allTasks { task.cancel() }
            for pending in (try? database.pendingDownloads()) ?? [] { markFailed(pending.trackID, message) }
            markFailed(trackID, message)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let trackID = task.taskDescription else { return }
        if (error as? URLError)?.code == .cancelled { return }
        if redirectedOffOrigin(task) {
            stopAfterOffOriginRedirect(trackID)
            return
        }
        log.error("Download failed for \(trackID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        let attempt = state.withLock { state -> Int in
            let attempt = (state.retries[trackID] ?? 0) + 1
            state.retries[trackID] = attempt
            return attempt
        }
        guard attempt <= Self.maxRetries else {
            markFailed(trackID, error.localizedDescription)
            return
        }
        // Resume from where it stopped when the server allows it; otherwise start over.
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task {
            try? await Task.sleep(for: .seconds(pow(2, Double(attempt))))
            guard (try? database.pendingDownloads().contains { $0.trackID == trackID }) == true else { return }
            // Resume data carries the original request, Authorization header included.
            guard await ServerIdentity.shared.confirmToken(to: library.session.serverURL) else { return }
            if let resumeData {
                let retry = self.session.downloadTask(withResumeData: resumeData)
                retry.taskDescription = trackID
                retry.resume()
            } else {
                let (quality, cellular) = state.withLock { ($0.quality, $0.allowCellular) }
                await enqueue([trackID], quality: quality, allowCellular: cellular)
            }
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // If the app delegate hasn't handed over its handler yet, it's called on arrival instead.
        let completion = BackgroundSessionEvents.finished(identifier)
        DispatchQueue.main.async { completion?() }
    }

    private func markFailed(_ trackID: String, _ message: String) {
        Task {
            try? await database.updateDownload(trackID: trackID) {
                guard $0.state != .paused && $0.state != .done else { return }
                $0.state = .failed
                $0.error = message
            }
        }
    }
}

/// Holds the completion handler iOS passes to the app delegate when it relaunches the app to
/// deliver background transfer events. The matching `DownloadManager` calls it when done.
public enum BackgroundSessionEvents {
    private struct Events {
        var handlers: [String: @Sendable () -> Void] = [:]
        /// Sessions whose events finished before the app delegate stored a handler. Sessions are
        /// created at launch, so on a background relaunch their events can finish first.
        var finishedEarly: Set<String> = []
    }

    private static let events = OSAllocatedUnfairLock(initialState: Events())

    public static func store(_ identifier: String, completion: @escaping @Sendable () -> Void) {
        let alreadyFinished = events.withLock { events in
            if events.finishedEarly.remove(identifier) != nil { return true }
            events.handlers[identifier] = completion
            return false
        }
        if alreadyFinished { DispatchQueue.main.async { completion() } }
    }

    /// The session's events are delivered: returns the stored handler to call, or records that
    /// they finished so a handler stored later is called right away.
    public static func finished(_ identifier: String) -> (@Sendable () -> Void)? {
        events.withLock { events in
            if let handler = events.handlers.removeValue(forKey: identifier) { return handler }
            events.finishedEarly.insert(identifier)
            return nil
        }
    }
}
