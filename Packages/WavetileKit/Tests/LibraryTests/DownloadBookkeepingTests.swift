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

    @Test func fileExtensionFollowsMimeType() {
        func response(_ mime: String) -> URLResponse {
            URLResponse(url: URL(string: "https://x/Audio/1/universal")!, mimeType: mime, expectedContentLength: 0, textEncodingName: nil)
        }
        #expect(DownloadManager.fileExtension(for: response("audio/flac")) == "flac")
        #expect(DownloadManager.fileExtension(for: response("audio/mpeg")) == "mp3")
        #expect(DownloadManager.fileExtension(for: response("audio/mp4")) == "m4a")
    }
}
