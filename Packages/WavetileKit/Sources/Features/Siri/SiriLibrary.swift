import Persistence
import Playback

/// Something Siri can play by name: an album, artist or playlist from the synced library.
/// `key` ("album:<id>") is the App Intents entity identifier.
nonisolated public struct SiriMusicItem: Sendable, Hashable {
    public enum Kind: String, Sendable { case album, artist, playlist }

    public let kind: Kind
    public let id: String
    public let title: String
    public let subtitle: String?

    public var key: String { "\(kind.rawValue):\(id)" }
}

/// Library lookups and playback for the Siri intents in the app target. Everything is read
/// from the local database, so Siri works offline for downloaded music and never sends
/// what was asked for anywhere.
public extension AppModel {
    func siriSearch(_ text: String) -> [SiriMusicItem] {
        guard let database = libraryDatabase else { return [] }
        let results = (try? database.search(text, limit: 8)) ?? .init()
        let playlists = (try? database.playlists(matching: text)) ?? []
        return results.artists.map(Self.item) + results.albums.map(Self.item) + playlists.map(Self.item)
    }

    /// Names Siri should recognize without asking: recent albums, playlists and favorite artists.
    func siriSuggestions() -> [SiriMusicItem] {
        guard let database = libraryDatabase else { return [] }
        let albums = (try? database.recentlyPlayedAlbums(limit: 50)) ?? []
        let playlists = (try? database.playlistList()) ?? []
        let artists = (try? database.favoriteArtistList(limit: 50)) ?? []
        return albums.map(Self.item) + playlists.prefix(50).map(Self.item) + artists.map(Self.item)
    }

    func siriItems(keys: [String]) -> [SiriMusicItem] {
        guard let database = libraryDatabase else { return [] }
        return keys.compactMap { key in
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let kind = SiriMusicItem.Kind(rawValue: parts[0]) else { return nil }
            switch kind {
            case .album: return (try? database.album(id: parts[1])).flatMap { $0.map(Self.item) }
            case .artist: return (try? database.artist(id: parts[1])).flatMap { $0.map(Self.item) }
            case .playlist: return (try? database.playlist(id: parts[1])).flatMap { $0.map(Self.item) }
            }
        }
    }

    /// Plays an album or playlist in order, an artist shuffled. False when nothing could play.
    @discardableResult
    func playForSiri(_ key: String) -> Bool {
        guard case let .signedIn(signedIn) = phase, let item = siriItems(keys: [key]).first else { return false }
        let database = signedIn.library.database
        let tracks: [TrackRecord] = switch item.kind {
        case .album: (try? database.tracks(albumID: item.id)) ?? []
        case .artist: (try? database.tracks(artistID: item.id)) ?? []
        case .playlist: (try? database.tracks(playlistID: item.id)) ?? []
        }
        guard !tracks.isEmpty else { return false }
        let queue = tracks.map(QueuedTrack.init)
        let online = Connectivity.shared.isOnline
        // Offline, only downloaded songs can play.
        guard online || queue.contains(where: { signedIn.downloads.isDownloaded($0.trackID) }) else { return false }
        signedIn.player.play(queue, shuffled: item.kind == .artist, online: online, downloads: signedIn.downloads)
        return true
    }

    private var libraryDatabase: LibraryDatabase? {
        if case let .signedIn(signedIn) = phase { return signedIn.library.database }
        return nil
    }

    private static func item(_ album: AlbumRecord) -> SiriMusicItem {
        SiriMusicItem(kind: .album, id: album.id, title: album.title, subtitle: album.artistName)
    }

    private static func item(_ artist: ArtistRecord) -> SiriMusicItem {
        SiriMusicItem(kind: .artist, id: artist.id, title: artist.name, subtitle: "Artist")
    }

    private static func item(_ playlist: PlaylistRecord) -> SiriMusicItem {
        SiriMusicItem(kind: .playlist, id: playlist.id, title: playlist.name, subtitle: "Playlist")
    }
}
