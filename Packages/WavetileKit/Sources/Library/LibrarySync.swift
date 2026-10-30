import Foundation
import GRDB
import JellyfinKit
import Persistence

/// Mirrors the user's Jellyfin music library into `LibraryDatabase`.
///
/// Full sync, paged, each page written in its own transaction so the UI fills in while it runs.
/// Only new or changed rows are written, so a sync of an unchanged library touches nothing.
/// Rows not seen in a completed pass are deleted, but only for an entity type whose pass saw
/// every item the server reported, so a flaky page can never wipe tracks.
public actor LibrarySync {
    public struct Progress: Sendable, Equatable {
        public enum Phase: String, Sendable {
            case artists, albums, tracks, playlists, collections, finishing
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
        // IDs seen per table, for passes that saw every item.
        var complete: [String: Set<String>] = [:]

        complete[ArtistRecord.databaseTableName] = try await syncArtists(generation, progress)
        complete[AlbumRecord.databaseTableName] = try await syncAlbums(generation, progress)
        complete[TrackRecord.databaseTableName] = try await syncTracks(generation, progress)
        complete[PlaylistRecord.databaseTableName] = try await syncPlaylists(generation, progress)
        complete[CollectionRecord.databaseTableName] = try await syncCollections(generation, progress)

        progress(.init(phase: .finishing, completed: 0, total: nil))
        let tables = complete
        try await database.pool.write { db in
            for (table, seen) in tables {
                try LibraryDatabase.prune(table, keeping: seen, in: db)
            }
            try SyncStateRecord(generation: generation, lastCompleted: Date()).upsert(db)
        }
    }

    // MARK: - Entity passes (each returns the IDs it saw, or nil if it missed some)

    private func syncArtists(_ generation: Int, _ progress: (Progress) -> Void) async throws -> Set<String>? {
        try await paged(phase: .artists, pageSize: 500, progress: progress) { start, limit in
            var params = Paths.GetAlbumArtistsParameters()
            params.userID = session.userID
            params.startIndex = start
            params.limit = limit
            params.fields = [.sortName]
            params.sortBy = [.sortName]
            params.enableUserData = true
            return try await client.send(Paths.getAlbumArtists(parameters: params)).value
        } write: { db, items in
            let records = items.compactMap { item -> ArtistRecord? in
                guard let id = item.id else { return nil }
                let name = item.name ?? "Unknown Artist"
                return ArtistRecord(
                    id: id, name: name, sortName: SortKey.make(item.sortName ?? name),
                    imageTag: item.imageTags?["Primary"], isFavorite: item.userData?.isFavorite ?? false,
                    generation: generation
                )
            }
            try ArtistRecord.upsertChanged(records, in: db)
        }
    }

    private func syncAlbums(_ generation: Int, _ progress: (Progress) -> Void) async throws -> Set<String>? {
        try await paged(phase: .albums, pageSize: 500, progress: progress) { start, limit in
            try await items(of: .musicAlbum, start: start, limit: limit, fields: [.genres, .dateCreated, .sortName])
        } write: { db, items in
            var records: [AlbumRecord] = []
            var genres: [String: Set<String>] = [:]
            for item in items {
                guard let id = item.id else { continue }
                let title = item.name ?? "Unknown Album"
                records.append(AlbumRecord(
                    id: id,
                    title: title,
                    sortTitle: SortKey.make(item.sortName ?? title),
                    artistName: item.albumArtist ?? item.artists?.first ?? "Unknown Artist",
                    artistID: item.albumArtists?.first?.id,
                    year: item.productionYear,
                    imageTag: item.imageTags?["Primary"],
                    dateAdded: item.dateCreated,
                    isFavorite: item.userData?.isFavorite ?? false,
                    generation: generation
                ))
                genres[id] = Set((item.genres ?? []).flatMap(GenreTag.split))
            }
            try AlbumRecord.upsertChanged(records, in: db)
            // Rewrite an album's genres only when they changed.
            var stored: [String: Set<String>] = [:]
            for row in try AlbumGenreRecord.filter(Array(genres.keys).contains(Column("albumID"))).fetchAll(db) {
                stored[row.albumID, default: []].insert(row.genre)
            }
            for (id, tags) in genres where stored[id, default: []] != tags {
                try AlbumGenreRecord.filter(Column("albumID") == id).deleteAll(db)
                for genre in tags { try AlbumGenreRecord(albumID: id, genre: genre).insert(db) }
            }
        }
    }

    private func syncTracks(_ generation: Int, _ progress: (Progress) -> Void) async throws -> Set<String>? {
        try await paged(phase: .tracks, pageSize: 1000, progress: progress) { start, limit in
            try await items(of: .audio, start: start, limit: limit, fields: [.dateCreated, .sortName])
        } write: { db, items in
            try TrackRecord.upsertChanged(items.compactMap { TrackRecord(item: $0, generation: generation) }, in: db)
        }
    }

    private func syncPlaylists(_ generation: Int, _ progress: (Progress) -> Void) async throws -> Set<String>? {
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
        let seen = Set(playlists.compactMap(\.id))

        for (index, playlist) in playlists.enumerated() {
            progress(.init(phase: .playlists, completed: index, total: playlists.count))
            try await writePlaylist(playlist, generation: generation)
        }
        return seen.count >= total ? seen : nil
    }

    private func writePlaylist(_ playlist: BaseItemDto, generation: Int) async throws {
        guard let id = playlist.id else { return }
        let entries = try await playlistEntries(id)
        let rows = entries.enumerated().compactMap { position, entry in
            entry.id.map { PlaylistEntryRecord(playlistID: id, position: position, trackID: $0, entryID: entry.playlistItemID) }
        }
        try await database.pool.write { db in
            try PlaylistRecord.upsertChanged([PlaylistRecord(
                id: id,
                name: playlist.name ?? "Untitled Playlist",
                imageTag: playlist.imageTags?["Primary"],
                trackCount: entries.count,
                durationMs: entries.compactMap { $0.runTimeTicks.map { $0 / 10_000 } }.reduce(0, +),
                generation: generation
            )], in: db)
            let request = PlaylistEntryRecord.filter(Column("playlistID") == id)
            guard try request.order(Column("position")).fetchAll(db) != rows else { return }
            try request.deleteAll(db)
            for row in rows { try row.insert(db) }
        }
    }

    /// Collections (BoxSets) that hold albums. Empty ones are kept so new collections show up.
    private func syncCollections(_ generation: Int, _ progress: (Progress) -> Void) async throws -> Set<String>? {
        var params = Paths.GetItemsParameters()
        params.userID = session.userID
        params.isRecursive = true
        params.includeItemTypes = [.boxSet]
        params.fields = [.childCount, .sortName]
        params.sortBy = [.sortName]
        let page = try await client.send(Paths.getItems(parameters: params)).value
        let collections = page.items ?? []
        var seen = Set<String>()
        for (index, collection) in collections.enumerated() {
            progress(.init(phase: .collections, completed: index, total: collections.count))
            if try await writeCollection(collection, generation: generation), let id = collection.id { seen.insert(id) }
        }
        // Movie/TV collections were skipped (and deleted), so count every listed collection.
        return collections.count >= (page.totalRecordCount ?? 0) ? seen : nil
    }

    /// Returns false for collections that aren't music (and so aren't kept).
    @discardableResult
    private func writeCollection(_ collection: BaseItemDto, generation: Int) async throws -> Bool {
        guard let id = collection.id else { return false }
        var params = Paths.GetItemsParameters()
        params.userID = session.userID
        params.parentID = id
        params.fields = [.sortName]
        let children = try await client.send(Paths.getItems(parameters: params)).value.items ?? []
        let albums = children.filter { $0.type == .musicAlbum }
        // Skip movie/TV collections: keep only empty ones or ones that contain albums.
        guard children.isEmpty || !albums.isEmpty else {
            _ = try await database.pool.write { try CollectionRecord.deleteOne($0, key: id) }
            return false
        }
        let name = collection.name ?? "Untitled Collection"
        let rows = albums.enumerated().compactMap { position, album in
            album.id.map { CollectionAlbumRecord(collectionID: id, albumID: $0, position: position) }
        }
        try await database.pool.write { db in
            try CollectionRecord.upsertChanged([CollectionRecord(
                id: id, name: name, sortName: SortKey.make(collection.sortName ?? name),
                imageTag: collection.imageTags?["Primary"], albumCount: albums.count, generation: generation
            )], in: db)
            let request = CollectionAlbumRecord.filter(Column("collectionID") == id)
            guard try request.order(Column("position")).fetchAll(db) != rows else { return }
            try request.deleteAll(db)
            for row in rows { try row.insert(db) }
        }
        return true
    }

    // MARK: - Targeted refreshes (after edits)

    private var currentGeneration: Int {
        (try? database.syncState()?.generation) ?? 0
    }

    /// Re-reads one playlist from the server into the database.
    public func refreshPlaylist(id: String) async throws {
        let item = try await client.send(Paths.getItem(itemID: id, userID: session.userID)).value
        try await writePlaylist(item, generation: currentGeneration)
    }

    /// Re-reads one collection from the server into the database.
    public func refreshCollection(id: String) async throws {
        let item = try await client.send(Paths.getItem(itemID: id, userID: session.userID)).value
        try await writeCollection(item, generation: currentGeneration)
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
    /// Returns the IDs seen when they cover the server's reported total, else nil.
    private func paged(
        phase: Progress.Phase,
        pageSize: Int,
        progress: (Progress) -> Void,
        fetch: (_ start: Int, _ limit: Int) async throws -> BaseItemDtoQueryResult,
        write: @escaping @Sendable (Database, [BaseItemDto]) throws -> Void
    ) async throws -> Set<String>? {
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
        return seen.count >= (total ?? 0) ? seen : nil
    }
}

extension TrackRecord {
    init?(item: BaseItemDto, generation: Int) {
        guard let id = item.id else { return nil }
        let title = item.name ?? "Unknown Track"
        self.init(
            id: id,
            title: title,
            // Not item.sortName: for tracks Jellyfin makes it "disc - track - title" (track order).
            sortTitle: SortKey.make(title),
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
        normalizationGain = item.normalizationGain.map(Double.init)
        albumImageTag = item.albumPrimaryImageTag
    }
}
