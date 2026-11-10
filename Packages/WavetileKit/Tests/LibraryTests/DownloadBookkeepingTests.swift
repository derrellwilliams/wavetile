import Foundation
import GRDB
import Testing
@testable import Downloads
@testable import Persistence

struct DownloadBookkeepingTests {
    let album = DownloadCollectionRecord(id: "album", kind: .album, name: "In Rainbows", subtitle: "Radiohead", imageTag: nil)
    let playlist = DownloadCollectionRecord(id: "pl", kind: .playlist, name: "Mix", subtitle: "Playlist", imageTag: nil)

    func finish(_ db: LibraryDatabase, _ trackID: String) async throws {
        try await db.updateDownload(trackID: trackID) {
            $0.state = .done
            $0.fileName = "\(trackID).flac"
            $0.bytes = 1000
            $0.progress = 1
        }
    }

    @Test func pauseSurvivesRecoveryAndPreservesFinishedSongs() async throws {
        let db = try LibraryDatabase.temporary()
        _ = try await db.requestDownload(album, trackIDs: ["done", "pending"])
        _ = try await db.requestDownload(playlist, trackIDs: ["pending"])
        try await finish(db, "done")
        try await db.setDownloadPaused(collectionID: album.id, paused: true)
        #expect(try db.pendingDownloads().isEmpty)
        #expect(try await db.requeueFailedDownloads().isEmpty)
        #expect(db.downloadedFileName(trackID: "done") == "done.flac")
        let status = try db.downloadStatusNow(collectionID: album.id)
        #expect(status.paused == 1)
        #expect(!status.isInProgress)
        #expect(try db.downloadStatusNow(collectionID: playlist.id).paused == 1)
        try await db.setDownloadPaused(collectionID: album.id, paused: false)
        #expect(try db.pendingDownloads().map(\.trackID) == ["pending"])
    }

    @Test func requestQueuesOnlyMissingTracks() async throws {
        let db = try LibraryDatabase.temporary()
        #expect(try await db.requestDownload(album, trackIDs: ["t1", "t2"]) == ["t1", "t2"])
        try await finish(db, "t1")
        // t1 is already downloaded, t2 already queued: nothing new to fetch.
        #expect(try await db.requestDownload(playlist, trackIDs: ["t1", "t2"]).isEmpty)
    }

    @Test func sharedTracksSurviveRemovingOneCollection() async throws {
        let db = try LibraryDatabase.temporary()
        _ = try await db.requestDownload(album, trackIDs: ["t1", "t2"])
        _ = try await db.requestDownload(playlist, trackIDs: ["t2", "t3"])
        for id in ["t1", "t2", "t3"] { try await finish(db, id) }

        let removed = try await db.removeDownload(collectionID: "album")
        #expect(removed == ["t1.flac"])
        #expect(db.downloadedFileName(trackID: "t2") == "t2.flac")
        #expect(db.downloadedFileName(trackID: "t1") == nil)
    }

    @Test func playlistSyncAddsAndPrunes() async throws {
        let db = try LibraryDatabase.temporary()
        _ = try await db.requestDownload(playlist, trackIDs: ["t1", "t2"])
        for id in ["t1", "t2"] { try await finish(db, id) }

        let (added, orphaned) = try await db.syncDownloadedPlaylist(id: "pl", trackIDs: ["t2", "t3"])
        #expect(added == ["t3"])
        #expect(orphaned == ["t1.flac"])
    }

    @Test func statusAggregatesProgress() async throws {
        let db = try LibraryDatabase.temporary()
        _ = try await db.requestDownload(album, trackIDs: ["t1", "t2"])
        try await finish(db, "t1")
        try await db.updateDownload(trackID: "t2") {
            $0.state = .downloading
            $0.progress = 0.5
        }
        var status = DownloadStatus.none
        for try await value in db.downloadStatus(collectionID: "album").values(in: db.pool) {
            status = value
            break
        }
        #expect(status.total == 2)
        #expect(status.done == 1)
        #expect(status.isInProgress)
        #expect(abs(status.progress - 0.75) < 0.001)
    }

    @Test func missingFilesGoBackInTheQueue() async throws {
        let db = try LibraryDatabase.temporary()
        _ = try await db.requestDownload(album, trackIDs: ["t1", "t2"])
        for id in ["t1", "t2"] { try await finish(db, id) }
        #expect(try db.finishedDownloads().map(\.trackID).sorted() == ["t1", "t2"])

        try await db.requeueDownloads(trackIDs: ["t1"])
        #expect(db.downloadedFileName(trackID: "t1") == nil)
        #expect(db.downloadedFileName(trackID: "t2") == "t2.flac")
        #expect(try db.pendingDownloads().map(\.trackID) == ["t1"])
        #expect(try db.downloadedTrackIDsNow() == ["t2"])
        // The membership stays, so the album still counts t1 as wanted and a later pass fetches it.
        #expect(try await db.requestDownload(album, trackIDs: ["t1", "t2"]).isEmpty)
    }

    /// The stand-in used when the real database won't open must say so, so downloads stay off against it.
    @Test func onlyTheStandInDatabaseIsMarkedTemporary() throws {
        #expect(try LibraryDatabase.temporary().isTemporary)
        let path = FileManager.default.temporaryDirectory.appending(path: "real-\(UUID().uuidString).sqlite").path(percentEncoded: false)
        #expect(try LibraryDatabase(path: path).isTemporary == false)
    }

    /// Sign-out deletes the stand-in's files (they hold the cached library); a real database is never touched.
    @Test func signOutRemovesOnlyTheStandInFiles() throws {
        let standIn = try LibraryDatabase.temporary()
        let standInPath = standIn.pool.path
        #expect(FileManager.default.fileExists(atPath: standInPath))
        standIn.deleteStandInFiles()
        #expect(!FileManager.default.fileExists(atPath: standInPath))

        let path = FileManager.default.temporaryDirectory.appending(path: "real-\(UUID().uuidString).sqlite").path(percentEncoded: false)
        let real = try LibraryDatabase(path: path)
        real.deleteStandInFiles()
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func songDownloadSizeIsCapped() {
        #expect(!DownloadManager.exceedsLimit(written: 400 * 1024 * 1024))
        #expect(DownloadManager.exceedsLimit(written: DownloadManager.maxBytes + 1))
    }

    @Test func rejectsEmptyAndNonAudioBodies() {
        func response(_ mime: String?) -> URLResponse {
            URLResponse(url: URL(string: "https://x/Audio/1/universal")!, mimeType: mime, expectedContentLength: 0, textEncodingName: nil)
        }
        #expect(DownloadManager.looksLikeAudio(response("audio/flac"), bytes: 10))
        #expect(DownloadManager.looksLikeAudio(response("application/octet-stream"), bytes: 10))
        #expect(DownloadManager.looksLikeAudio(response(nil), bytes: 10))
        #expect(!DownloadManager.looksLikeAudio(response("audio/flac"), bytes: 0))
        #expect(!DownloadManager.looksLikeAudio(response("text/html; charset=utf-8"), bytes: 500))
        #expect(!DownloadManager.looksLikeAudio(response("application/json"), bytes: 500))
        #expect(!DownloadManager.looksLikeAudio(response("application/xhtml+xml"), bytes: 500))
    }

    @Test func fileExtensionFollowsMimeType() {
        func response(_ mime: String) -> URLResponse {
            URLResponse(url: URL(string: "https://x/Audio/1/universal")!, mimeType: mime, expectedContentLength: 0, textEncodingName: nil)
        }
        #expect(DownloadManager.fileExtension(for: response("audio/flac")) == "flac")
        #expect(DownloadManager.fileExtension(for: response("audio/mpeg")) == "mp3")
        #expect(DownloadManager.fileExtension(for: response("audio/mp4")) == "m4a")
    }
}
