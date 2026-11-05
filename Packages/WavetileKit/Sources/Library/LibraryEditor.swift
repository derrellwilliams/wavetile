import Foundation
import GRDB
import JellyfinKit
import Persistence

/// Edits the user's library on the server (favorites, playlists, collections) and mirrors each
/// change into the local database so screens update immediately.
public struct LibraryEditor: Sendable {
    private let session: ServerSession
    private let client: JellyfinAPI.JellyfinClient
    private let database: LibraryDatabase
    private let sync: LibrarySync

    public init(session: ServerSession, token: String, auth: AuthService, database: LibraryDatabase, sync: LibrarySync) {
        self.session = session
        self.client = auth.makeClient(for: session.serverURL, token: token)
        self.database = database
        self.sync = sync
    }

    // MARK: Favorites

    /// Optimistic: flips the local flag first, reverts if the server call fails.
    public func setFavorite(itemID: String, _ isFavorite: Bool) async throws {
        try await database.setFavorite(itemID: itemID, isFavorite)
        do {
            if isFavorite {
                _ = try await client.send(Paths.markFavoriteItem(itemID: itemID, userID: session.userID))
            } else {
                _ = try await client.send(Paths.unmarkFavoriteItem(itemID: itemID, userID: session.userID))
            }
        } catch {
            try? await database.setFavorite(itemID: itemID, !isFavorite)
            throw error
        }
    }

    // MARK: Playlists (song-based)

    @discardableResult
    public func createPlaylist(name: String, trackIDs: [String] = []) async throws -> String? {
        let body = CreatePlaylistDto(ids: trackIDs, isPublic: false, mediaType: .audio, name: name, userID: session.userID)
        let result = try await client.send(Paths.createPlaylist(body)).value
        if let id = result.id { try await sync.refreshPlaylist(id: id) }
        return result.id
    }

    public func renamePlaylist(id: String, to name: String) async throws {
        try await client.send(Paths.updatePlaylist(playlistID: id, UpdatePlaylistDto(name: name)))
        try await sync.refreshPlaylist(id: id)
    }

    public func deletePlaylist(id: String) async throws {
        try await client.send(Paths.deleteItem(itemID: id))
        _ = try await database.pool.write { try PlaylistRecord.deleteOne($0, key: id) }
    }

    public func addToPlaylist(id: String, trackIDs: [String]) async throws {
        guard !trackIDs.isEmpty else { return }
        try await client.send(Paths.addItemToPlaylist(playlistID: id, parameters: .init(ids: trackIDs, userID: session.userID)))
        try await sync.refreshPlaylist(id: id)
    }

    /// Removes specific entries (by Jellyfin entry ID, so duplicates are handled correctly).
    public func removeFromPlaylist(id: String, entryIDs: [String]) async throws {
        guard !entryIDs.isEmpty else { return }
        try await client.send(Paths.removeItemFromPlaylist(playlistID: id, entryIDs: entryIDs))
        try await sync.refreshPlaylist(id: id)
    }

    public func movePlaylistEntry(id: String, entryID: String, to newIndex: Int) async throws {
        try await client.send(Paths.moveItem(playlistID: id, itemID: entryID, newIndex: newIndex))
        try await sync.refreshPlaylist(id: id)
    }

    // MARK: Collections (album-based)

    @discardableResult
    public func createCollection(name: String, albumIDs: [String] = []) async throws -> String? {
        let params = Paths.CreateCollectionParameters(name: name, ids: albumIDs.isEmpty ? nil : albumIDs, isLocked: false)
        let result = try await client.send(Paths.createCollection(parameters: params)).value
        if let id = result.id { try await sync.refreshCollection(id: id) }
        return result.id
    }

    /// Renames a collection and returns its ID afterwards. Collections have no rename call, so an
    /// admin's rename reads the full item, changes the name and saves it back (as Jellyfin's
    /// metadata editor does). Other accounts can't edit items: only a refused save (403) falls back
    /// to recreating the collection under the new name, which gives it a new ID.
    @discardableResult
    public func renameCollection(id: String, to name: String) async throws -> String {
        var item = try await client.send(Paths.getItem(itemID: id, userID: session.userID)).value
        item.name = name
        do {
            try await client.send(Paths.updateItem(itemID: id, item))
        } catch let error where isForbidden(error) {
            return try await recreateCollection(id: id, name: name, image: item.imageTags?["Primary"])
        }
        try await sync.refreshCollection(id: id)
        return id
    }

    /// Neither copy could be deleted after a collection was recreated under its new name, so both
    /// are now on the server.
    public struct DuplicateCollectionError: Error {}

    /// Recreating would drop the collection's cover image, which only an admin can upload again,
    /// so the rename isn't attempted.
    public struct RenameWouldLoseCoverError: Error {}

    /// A new collection with the same items in the same order, then the old one deleted. Every
    /// item is copied, not only albums, and the list comes from the server rather than the local
    /// mirror, so nothing added elsewhere is lost. A collection with a cover image isn't recreated
    /// (`RenameWouldLoseCoverError`). If the old one can't be deleted, the new one is removed again;
    /// only if that fails too are there two copies (`DuplicateCollectionError`).
    private func recreateCollection(id: String, name: String, image: String?) async throws -> String {
        guard image == nil else { throw RenameWouldLoseCoverError() }
        var params = Paths.GetItemsParameters()
        params.userID = session.userID
        params.parentID = id
        let children = try await client.send(Paths.getItems(parameters: params)).value.items ?? []
        let itemIDs = children.compactMap(\.id)
        let create = Paths.CreateCollectionParameters(name: name, ids: itemIDs.isEmpty ? nil : itemIDs, isLocked: false)
        guard let newID = try await client.send(Paths.createCollection(parameters: create)).value.id else {
            throw URLError(.badServerResponse)
        }
        do {
            try await client.send(Paths.deleteItem(itemID: id))
        } catch {
            do { try await client.send(Paths.deleteItem(itemID: newID)) } catch { throw DuplicateCollectionError() }
            throw error
        }
        let old = try await database.pool.read { try CollectionRecord.fetchOne($0, key: id) }
        let albumIDs = children.filter { $0.type == .musicAlbum }.compactMap(\.id)
        // Swap the local copy over now, so the open page can follow even if the read below fails;
        // the read (or the next sync) then fills in the server's details.
        try await database.pool.write { db in
            try CollectionRecord.deleteOne(db, key: id)
            try CollectionRecord(
                id: newID, name: name, sortName: SortKey.make(name), imageTag: nil,
                albumCount: albumIDs.count, generation: old?.generation ?? 0
            ).insert(db)
            for (position, albumID) in albumIDs.enumerated() {
                try CollectionAlbumRecord(collectionID: newID, albumID: albumID, position: position).insert(db)
            }
            // A downloaded collection's download moves with it, or the next sync would find
            // nothing under the old ID and delete its songs.
            if var download = try DownloadCollectionRecord.fetchOne(db, key: id) {
                download.id = newID
                download.name = name
                try download.insert(db)
                try db.execute(sql: "UPDATE downloadMembership SET collectionID = ? WHERE collectionID = ?", arguments: [newID, id])
                try DownloadCollectionRecord.deleteOne(db, key: id)
            }
        }
        try? await sync.refreshCollection(id: newID)
        return newID
    }

    public func deleteCollection(id: String) async throws {
        try await client.send(Paths.deleteItem(itemID: id))
        _ = try await database.pool.write { try CollectionRecord.deleteOne($0, key: id) }
    }

    public func addToCollection(id: String, albumIDs: [String]) async throws {
        guard !albumIDs.isEmpty else { return }
        try await client.send(Paths.addToCollection(collectionID: id, ids: albumIDs))
        try await sync.refreshCollection(id: id)
    }

    public func removeFromCollection(id: String, albumIDs: [String]) async throws {
        guard !albumIDs.isEmpty else { return }
        try await client.send(Paths.removeFromCollection(collectionID: id, ids: albumIDs))
        try await sync.refreshCollection(id: id)
    }

    // MARK: Cover images (playlists and collections)

    public enum CoverOwner: Sendable { case playlist, collection }

    /// Uploads a JPEG as the item's primary image on the server, replacing any it had. Jellyfin
    /// takes the image base64-encoded in the body. Some servers only let admins change images.
    public func setCoverImage(itemID: String, jpeg: Data, owner: CoverOwner) async throws {
        var request = Paths.setItemImage(itemID: itemID, imageType: ImageType.primary.rawValue, jpeg.base64EncodedData())
        request.headers = ["Content-Type": "image/jpeg"]
        try await client.send(request)
        try await refresh(itemID, owner)
    }

    /// Deletes the item's primary image, so Wavetile falls back to its generated cover.
    public func removeCoverImage(itemID: String, owner: CoverOwner) async throws {
        try await client.send(Paths.deleteItemImage(itemID: itemID, imageType: ImageType.primary.rawValue))
        try await refresh(itemID, owner)
    }

    private func refresh(_ itemID: String, _ owner: CoverOwner) async throws {
        switch owner {
        case .playlist: try await sync.refreshPlaylist(id: itemID)
        case .collection: try await sync.refreshCollection(id: itemID)
        }
    }
}
