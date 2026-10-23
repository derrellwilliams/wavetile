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
}
