import Foundation
import GRDB
import JellyfinKit
import Persistence

/// Mirrors the user's Jellyfin music library into `LibraryDatabase`.
///
/// Full sync, paged, each page written in its own transaction so the UI fills in while it runs.
/// Rows not seen in a completed pass are deleted, but only for an entity type whose pass saw
/// every item the server reported, so a flaky page can never wipe tracks.
public actor LibrarySync {
    public struct Progress: Sendable, Equatable {
        public enum Phase: String, Sendable {
            case artists, albums, tracks, playlists, finishing
        }

        public var phase: Phase
        public var completed: Int
        public var total: Int?
    }

    private let session: ServerSession
    private let client: JellyfinAPI.JellyfinClient
    private let database: LibraryDatabase
    private var isRunning = false

    public init(session: ServerSession, token: String, auth: AuthService, database: LibraryDatabase) {
        self.session = session
        self.client = auth.makeClient(for: session.serverURL, token: token)
        self.database = database
    }

    /// True when the library has never synced or the last sync is older than `maxAge`.
    public func needsSync(maxAge: TimeInterval = 60 * 60) throws -> Bool {
        guard let state = try database.syncState(), let last = state.lastCompleted else { return true }
        return Date().timeIntervalSince(last) > maxAge
    }

    /// Runs a full sync. Concurrent calls while one is running return immediately.
    public func run(progress: @Sendable (Progress) -> Void = { _ in }) async throws {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let generation = (try database.syncState()?.generation ?? 0) + 1
        var complete: Set<String> = []

        if try await syncArtists(generation, progress) { complete.insert(ArtistRecord.databaseTableName) }
        if try await syncAlbums(generation, progress) { complete.insert(AlbumRecord.databaseTableName) }
        if try await syncTracks(generation, progress) { complete.insert(TrackRecord.databaseTableName) }
        if try await syncPlaylists(generation, progress) { complete.insert(PlaylistRecord.databaseTableName) }

        progress(.init(phase: .finishing, completed: 0, total: nil))
        let tables = complete
        try await database.pool.write { db in
            for table in tables {
                try db.execute(sql: "DELETE FROM \(table) WHERE generation < ?", arguments: [generation])
            }
            try SyncStateRecord(generation: generation, lastCompleted: Date()).upsert(db)
        }
    }

    // MARK: - Entity passes (each returns true if it saw every item)

    private func syncArtists(_ generation: Int, _ progress: (Progress) -> Void) async throws -> Bool {
        try await paged(phase: .artists, pageSize: 500, progress: progress) { start, limit in
            var params = Paths.GetAlbumArtistsParameters()
            params.userID = session.userID
            params.startIndex = start
            params.limit = limit
            params.fields = [.sortName]
            params.sortBy = [.sortName]
            params.enableUserData = false
            return try await client.send(Paths.getAlbumArtists(parameters: params)).value
        } write: { db, items in
            for item in items {
                guard let id = item.id else { continue }
                let name = item.name ?? "Unknown Artist"
                try ArtistRecord(
                    id: id, name: name, sortName: SortKey.make(item.sortName ?? name),
                    imageTag: item.imageTags?["Primary"], generation: generation
                ).upsert(db)
            }
        }
    }

    private func syncAlbums(_ generation: Int, _ progress: (Progress) -> Void) async throws -> Bool {
        try await paged(phase: .albums, pageSize: 500, progress: progress) { start, limit in
            try await items(of: .musicAlbum, start: start, limit: limit, fields: [.genres, .dateCreated, .sortName])
        } write: { db, items in
            for item in items {
                guard let id = item.id else { continue }
                let title = item.name ?? "Unknown Album"
                try AlbumRecord(
                    id: id,
                    title: title,
                    sortTitle: SortKey.make(item.sortName ?? title),
                    artistName: item.albumArtist ?? item.artists?.first ?? "Unknown Artist",
                    artistID: item.albumArtists?.first?.id,
                    year: item.productionYear,
                    imageTag: item.imageTags?["Primary"],
                    dateAdded: item.dateCreated,
                    generation: generation
                ).upsert(db)
                try AlbumGenreRecord.filter(Column("albumID") == id).deleteAll(db)
                for genre in Set(item.genres ?? []) where !genre.isEmpty {
                    try AlbumGenreRecord(albumID: id, genre: genre).insert(db)
                }
            }
        }
    }

    private func syncTracks(_ generation: Int, _ progress: (Progress) -> Void) async throws -> Bool {
        try await paged(phase: .tracks, pageSize: 1000, progress: progress) { start, limit in
            try await items(of: .audio, start: start, limit: limit, fields: [.dateCreated, .sortName])
        } write: { db, items in
            for item in items {
                guard let record = TrackRecord(item: item, generation: generation) else { continue }
                try record.upsert(db)
            }
        }
    }

    private func syncPlaylists(_ generation: Int, _ progress: (Progress) -> Void) async throws -> Bool {
        // Playlists are few; fetch the list, then each playlist's entries.
        var playlists: [BaseItemDto] = []
        var total = 0
        repeat {
            var params = Paths.GetItemsParameters()
            params.userID = session.userID
            params.startIndex = playlists.count
            params.limit = 200
            params.isRecursive = true
            params.includeItemTypes = [.playlist]
            params.mediaTypes = [.audio]
            params.fields = [.childCount, .sortName]
            params.sortBy = [.sortName]
            let page = try await client.send(Paths.getItems(parameters: params)).value
            let items = page.items ?? []
            playlists.append(contentsOf: items)
            total = page.totalRecordCount ?? playlists.count
            if items.isEmpty { break }
        } while playlists.count < total
        let complete = Set(playlists.compactMap(\.id)).count >= total

        for (index, playlist) in playlists.enumerated() {
            progress(.init(phase: .playlists, completed: index, total: playlists.count))
            guard let id = playlist.id else { continue }
            let entries = try await playlistEntries(id)
            try await database.pool.write { db in
                try PlaylistRecord(
                    id: id,
                    name: playlist.name ?? "Untitled Playlist",
                    imageTag: playlist.imageTags?["Primary"],
                    trackCount: entries.count,
                    durationMs: entries.compactMap { $0.runTimeTicks.map { $0 / 10_000 } }.reduce(0, +),
                    generation: generation
                ).upsert(db)
                try PlaylistEntryRecord.filter(Column("playlistID") == id).deleteAll(db)
                for (position, entry) in entries.enumerated() {
                    guard let trackID = entry.id else { continue }
                    try PlaylistEntryRecord(playlistID: id, position: position, trackID: trackID, entryID: entry.playlistItemID).insert(db)
                }
            }
        }
        return complete
    }

    private func playlistEntries(_ playlistID: String) async throws -> [BaseItemDto] {
        var entries: [BaseItemDto] = []
        while true {
            var params = Paths.GetPlaylistItemsParameters()
            params.userID = session.userID
            params.startIndex = entries.count
            params.limit = 500
            params.enableImages = false
            let page = try await client.send(Paths.getPlaylistItems(playlistID: playlistID, parameters: params)).value
            let items = page.items ?? []
            entries.append(contentsOf: items)
            if items.isEmpty || entries.count >= (page.totalRecordCount ?? 0) { return entries }
        }
    }

    // MARK: - Helpers

    private func items(of kind: BaseItemKind, start: Int, limit: Int, fields: [ItemFields]) async throws -> BaseItemDtoQueryResult {
        var params = Paths.GetItemsParameters()
        params.userID = session.userID
        params.startIndex = start
        params.limit = limit
        params.isRecursive = true
        params.includeItemTypes = [kind]
        params.fields = fields
        // Stable order so pages don't overlap or skip while paging.
        params.sortBy = [.sortName]
        params.sortOrder = [.ascending]
        params.enableUserData = true
        params.enableImages = true
        params.imageTypeLimit = 1
        return try await client.send(Paths.getItems(parameters: params)).value
    }

    /// Pages through a query, writing each page in one transaction.
    /// Returns true when the unique IDs seen cover the server's reported total.
    private func paged(
        phase: Progress.Phase,
        pageSize: Int,
        progress: (Progress) -> Void,
        fetch: (_ start: Int, _ limit: Int) async throws -> BaseItemDtoQueryResult,
        write: @escaping @Sendable (Database, [BaseItemDto]) throws -> Void
    ) async throws -> Bool {
        var seen = Set<String>()
        var start = 0
        var total: Int?
        while true {
            try Task.checkCancellation()
            let page = try await fetch(start, pageSize)
            let items = page.items ?? []
            total = page.totalRecordCount ?? total
            try await database.pool.write { db in try write(db, items) }
            seen.formUnion(items.compactMap(\.id))
            start += items.count
            progress(.init(phase: phase, completed: start, total: total))
            if items.isEmpty || start >= (total ?? 0) { break }
        }
        return seen.count >= (total ?? 0)
    }
}

extension TrackRecord {
    init?(item: BaseItemDto, generation: Int) {
        guard let id = item.id else { return nil }
        let title = item.name ?? "Unknown Track"
        self.init(
            id: id,
            title: title,
            sortTitle: SortKey.make(item.sortName ?? title),
            albumID: item.albumID,
            albumTitle: item.album ?? "",
            artistName: item.artists?.joined(separator: ", ") ?? item.albumArtist ?? "Unknown Artist",
            albumArtistName: item.albumArtist ?? item.artists?.first ?? "Unknown Artist",
            trackNumber: item.indexNumber,
            discNumber: item.parentIndexNumber,
            // Jellyfin ticks are 100ns.
            durationMs: item.runTimeTicks.map { $0 / 10_000 },
            playCount: item.userData?.playCount ?? 0,
            isFavorite: item.userData?.isFavorite ?? false,
            lastPlayed: item.userData?.lastPlayedDate,
            dateAdded: item.dateCreated,
            container: item.container,
            generation: generation
        )
    }
}
