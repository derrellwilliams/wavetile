import Foundation
import GRDB

// Jellyfin builds an item's ID from its file path, so renaming or moving a folder (a tagger
// tidying up, a new mount point, a library added again) gives the same album new IDs. A complete
// sync then prunes the old ones, which used to strand album downloads: the files stayed on the
// phone with nothing pointing at them, and the album page couldn't load. An album download now
// moves to the album's new ID and downloads again, but only when exactly one album matches; one
// that can't be matched says so on its page.

public extension LibraryDatabase {
    /// Stale album downloads (see `isStaleAlbumDownload`) move to the album's new ID, with its
    /// current songs queued (the old song rows are gone, so their files can't be matched to
    /// anything and are let go). The new album is the only one with the same title and album
    /// artist. Run after a complete sync. Returns how many moved, the songs to download, and the
    /// files nothing uses any more.
    func repairAlbumDownloads() async throws -> (moved: Int, queued: [String], orphanedFiles: [String]) {
        try await pool.write { db in
            // Same rule as the page: an album downloaded during or since the last sync is left
            // alone (the sync may have listed albums before it existed), as is everything when the
            // mirror has no songs.
            let stale = try DownloadCollectionRecord.fetchAll(db, sql: "SELECT * FROM downloadCollection WHERE id IN (\(Self.staleAlbumDownloads))")
            var moved = 0
            var queued: [String] = []
            for download in stale {
                guard let album = try Self.currentAlbum(for: download, in: db) else { continue }
                let trackIDs = try String.fetchAll(db, sql: """
                    SELECT id FROM track WHERE albumID = ? ORDER BY discNumber, trackNumber, sortTitle
                    """, arguments: [album.id])
                guard !trackIDs.isEmpty else { continue }
                // A download the listener paused stays paused under its new ID: every song still to
                // come is paused (one paused through a playlist that shares it doesn't count). One
                // that already exists under the new ID keeps its own state.
                var paused = false
                if try !DownloadCollectionRecord.exists(db, key: album.id) {
                    try DownloadCollectionRecord(
                        id: album.id, kind: .album, name: album.title, subtitle: album.artistName,
                        imageTag: album.imageTag, addedAt: download.addedAt
                    ).insert(db)
                    let states = try String.fetchAll(db, sql: """
                        SELECT t.state FROM downloadMembership m JOIN downloadedTrack t ON t.trackID = m.trackID
                        WHERE m.collectionID = ? AND t.state != 'done'
                        """, arguments: [download.id])
                    paused = !states.isEmpty && states.allSatisfy { $0 == "paused" }
                }
                for trackID in trackIDs where try Self.addToDownload(collectionID: album.id, trackID: trackID, paused: paused, in: db) {
                    queued.append(trackID)
                }
                // Its memberships go with it (cascade); songs only it held become orphans below.
                _ = try download.delete(db)
                moved += 1
            }
            return (moved, queued, try Self.deleteOrphans(db))
        }
    }

    /// True when a downloaded album's ID isn't in the library and a complete sync that began after
    /// the download didn't see it: the album was moved or removed on the server, and the download
    /// couldn't be moved to it. Never a guess: an album downloaded during or since the last sync
    /// (its album pass may have run before the album existed) says false.
    func isStaleAlbumDownload(id: String) throws -> Bool {
        try pool.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS (\(Self.staleAlbumDownloads) AND d.id = ?)", arguments: [id]) ?? false
        }
    }

    /// Album downloads that are stale (see `isStaleAlbumDownload`), as a query on `d`.
    internal static let staleAlbumDownloads = """
        SELECT d.id FROM downloadCollection d
        WHERE d.kind = 'album'
          AND NOT EXISTS (SELECT 1 FROM album a WHERE a.id = d.id)
          AND EXISTS (SELECT 1 FROM track)
          AND d.addedAt < (SELECT lastStarted FROM syncState WHERE lastStarted IS NOT NULL)
        """

    /// The only album with the download's title and album artist (ignoring case and accents).
    private static func currentAlbum(for download: DownloadCollectionRecord, in db: Database) throws -> AlbumRecord? {
        let title = fold(download.name), artist = fold(download.subtitle)
        // NOCASE narrows by title (it folds ASCII only); the folded comparison decides.
        let found = try AlbumRecord.filter(sql: "title = ? COLLATE NOCASE", arguments: [download.name]).fetchAll(db)
            .filter { fold($0.title) == title && fold($0.artistName) == artist }
        return found.count == 1 ? found[0] : nil
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
