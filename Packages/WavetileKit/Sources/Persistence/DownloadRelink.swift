import Foundation
import GRDB

// Jellyfin builds an item's ID from its file path, so renaming or moving a folder (a tagger
// tidying up, a new mount point, a library added again) gives the same songs and albums new IDs.
// A complete sync then sees new items and prunes the old ones, which used to strand downloads:
// the files stayed on the phone with nothing pointing at them, and their album page couldn't
// load. Downloads follow their songs to the new IDs instead, and only on an exact match: anything
// without one clear match is left as it is.

public extension LibraryDatabase {
    /// Moves each downloaded song the sync didn't see to its new ID, keeping its file, so nothing
    /// downloads again. Runs inside the sync's write, before the prune deletes the old rows:
    /// `keptTracks` is every track ID the complete track pass saw.
    ///
    /// A song matches when its album, album artist, disc, track number and title are the same
    /// (ignoring case and accents) and the durations are within 2 s, and exactly one song on each
    /// side has that description. Returns how many moved.
    @discardableResult
    static func relinkDownloadedTracks(keptTracks: Set<String>, in db: Database) throws -> Int {
        let gone = try String.fetchAll(db, sql: "SELECT trackID FROM downloadedTrack").filter { !keptTracks.contains($0) }
        guard !gone.isEmpty else { return 0 }
        // Old rows that are still here: the prune hasn't run yet.
        let old = try TrackRecord.filter(keys: gone).fetchAll(db)
        guard !old.isEmpty else { return 0 }

        let goneByKey = Dictionary(grouping: old, by: TrackMatch.init)
        var candidates: [TrackMatch: [(id: String, durationMs: Int?)]] = [:]
        let rows = try Row.fetchCursor(db, sql: """
            SELECT id, title, albumTitle, albumArtistName, discNumber, trackNumber, durationMs FROM track
            """)
        while let row = try rows.next() {
            let id: String = row["id"]
            guard keptTracks.contains(id) else { continue }
            let key = TrackMatch(
                title: row["title"], albumTitle: row["albumTitle"], albumArtistName: row["albumArtistName"],
                discNumber: row["discNumber"], trackNumber: row["trackNumber"]
            )
            guard goneByKey[key] != nil else { continue }
            candidates[key, default: []].append((id, row["durationMs"]))
        }

        var moved = 0
        for (key, songs) in goneByKey {
            // Two old songs with one description can't be told apart; neither can two new ones.
            guard songs.count == 1, let song = songs.first,
                  let matches = candidates[key], matches.count == 1, let match = matches.first,
                  TrackMatch.durationsAgree(song.durationMs, match.durationMs)
            else { continue }
            try moveDownload(from: song.id, to: match.id, in: db)
            moved += 1
        }
        return moved
    }

    /// Album downloads whose album the library no longer has under that ID move to the album's
    /// new ID, with its current songs. Songs already moved by `relinkDownloadedTracks` keep their
    /// files; the rest are queued (the old song details are gone, so their files can't be matched
    /// to anything). The new album is the one the download's moved songs now belong to, else the
    /// only album with the same title and album artist. Run after a complete sync. Returns the
    /// songs to download and the files nothing uses any more.
    func repairAlbumDownloads() async throws -> (queued: [String], orphanedFiles: [String]) {
        try await pool.write { db in
            // A mirror with no songs says nothing about what's gone (see `syncedDownloadSource`).
            guard try !TrackRecord.limit(1).isEmpty(db) else { return ([], []) }
            let stale = try DownloadCollectionRecord.fetchAll(db, sql: """
                SELECT * FROM downloadCollection
                WHERE kind = 'album' AND id NOT IN (SELECT id FROM album)
                """)
            guard !stale.isEmpty else { return ([], []) }
            var queued: [String] = []
            for download in stale {
                guard let album = try Self.currentAlbum(for: download, in: db) else { continue }
                let trackIDs = try String.fetchAll(db, sql: """
                    SELECT id FROM track WHERE albumID = ? ORDER BY discNumber, trackNumber, sortTitle
                    """, arguments: [album.id])
                guard !trackIDs.isEmpty else { continue }
                if try !DownloadCollectionRecord.exists(db, key: album.id) {
                    try DownloadCollectionRecord(
                        id: album.id, kind: .album, name: album.title, subtitle: album.artistName,
                        imageTag: album.imageTag, addedAt: download.addedAt
                    ).insert(db)
                }
                for trackID in trackIDs {
                    try db.execute(sql: "INSERT OR IGNORE INTO downloadMembership (collectionID, trackID) VALUES (?, ?)", arguments: [album.id, trackID])
                    let existing = try DownloadedTrackRecord.fetchOne(db, key: trackID)
                    if existing == nil || existing?.state == .failed {
                        try DownloadedTrackRecord(trackID: trackID, state: .queued).upsert(db)
                        queued.append(trackID)
                    }
                }
                // Its memberships go with it (cascade); songs only it held become orphans below.
                _ = try download.delete(db)
            }
            return (queued, try Self.deleteOrphans(db))
        }
    }

    /// True when a downloaded album's ID isn't in the library and a complete sync since the
    /// download didn't see it: the album was moved or removed on the server, and the download
    /// couldn't be moved to it. Never a guess: a library that hasn't synced since says false.
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
          AND d.addedAt < (SELECT lastCompleted FROM syncState WHERE lastCompleted IS NOT NULL)
        """

    private static func currentAlbum(for download: DownloadCollectionRecord, in db: Database) throws -> AlbumRecord? {
        // Where its songs went, if they were moved to new IDs.
        let homes = try String.fetchAll(db, sql: """
            SELECT DISTINCT t.albumID FROM downloadMembership m JOIN track t ON t.id = m.trackID
            WHERE m.collectionID = ? AND t.albumID IS NOT NULL
            """, arguments: [download.id])
        if homes.count == 1, let album = try AlbumRecord.fetchOne(db, key: homes[0]) { return album }
        guard homes.isEmpty else { return nil }
        // Otherwise by title and album artist, when exactly one album has both.
        let title = TrackMatch.fold(download.name), artist = TrackMatch.fold(download.subtitle)
        let matches = try AlbumRecord.filter(sql: "title = ? COLLATE NOCASE", arguments: [download.name]).fetchAll(db)
            .filter { TrackMatch.fold($0.title) == title && TrackMatch.fold($0.artistName) == artist }
        // NOCASE only folds ASCII: try the folded comparison over every album when that missed.
        let found = matches.isEmpty
            ? try AlbumRecord.fetchAll(db).filter { TrackMatch.fold($0.title) == title && TrackMatch.fold($0.artistName) == artist }
            : matches
        return found.count == 1 ? found[0] : nil
    }

    /// Points a downloaded song's row and memberships at its new ID. If the new ID already has a
    /// finished download, that one is kept and the old row is left to the orphan sweep; otherwise
    /// the old row (and its file) takes the new ID's place.
    private static func moveDownload(from oldID: String, to newID: String, in db: Database) throws {
        if let existing = try DownloadedTrackRecord.fetchOne(db, key: newID) {
            if existing.state != .done { try existing.delete(db) }
        }
        if try !DownloadedTrackRecord.exists(db, key: newID) {
            // A transfer under the old ID finds no row when it ends and deletes its file; the
            // song is queued again under the new ID.
            try db.execute(sql: """
                UPDATE downloadedTrack SET trackID = ?,
                    state = CASE WHEN state = 'downloading' THEN 'queued' ELSE state END,
                    progress = CASE WHEN state = 'downloading' THEN 0 ELSE progress END,
                    bytes = CASE WHEN state = 'downloading' THEN 0 ELSE bytes END
                WHERE trackID = ?
                """, arguments: [newID, oldID])
        }
        try db.execute(sql: "UPDATE OR IGNORE downloadMembership SET trackID = ? WHERE trackID = ?", arguments: [newID, oldID])
        try db.execute(sql: "DELETE FROM downloadMembership WHERE trackID = ?", arguments: [oldID])
    }
}

/// What identifies a song across an ID change: its place on its album, and its title.
struct TrackMatch: Hashable {
    let title: String
    let albumTitle: String
    let albumArtistName: String
    let discNumber: Int?
    let trackNumber: Int?

    init(title: String, albumTitle: String, albumArtistName: String, discNumber: Int?, trackNumber: Int?) {
        self.title = Self.fold(title)
        self.albumTitle = Self.fold(albumTitle)
        self.albumArtistName = Self.fold(albumArtistName)
        self.discNumber = discNumber
        self.trackNumber = trackNumber
    }

    init(_ track: TrackRecord) {
        self.init(
            title: track.title, albumTitle: track.albumTitle, albumArtistName: track.albumArtistName,
            discNumber: track.discNumber, trackNumber: track.trackNumber
        )
    }

    static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The same recording, give or take a re-encode; unknown durations don't rule a match out.
    static func durationsAgree(_ a: Int?, _ b: Int?) -> Bool {
        guard let a, let b else { return true }
        return abs(a - b) <= 2000
    }
}
