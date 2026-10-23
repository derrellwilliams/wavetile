import Foundation

/// Lightweight, UI-ready album model decoupled from the generated `BaseItemDto`.
public struct AlbumSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var artist: String
    public var year: Int?
    public var imageTag: String?
    public var playCount: Int

    public init(id: String, title: String, artist: String, year: Int? = nil, imageTag: String? = nil, playCount: Int = 0) {
        self.id = id
        self.title = title
        self.artist = artist
        self.year = year
        self.imageTag = imageTag
        self.playCount = playCount
    }
}

/// A track as shown in album and playlist lists.
public struct TrackSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var artist: String
    public var trackNumber: Int?
    public var discNumber: Int?
    public var duration: Duration?

    public init(id: String, title: String, artist: String, trackNumber: Int? = nil, discNumber: Int? = nil, duration: Duration? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.duration = duration
    }
}

/// Typed, read-only library queries for an authenticated session.
///
/// Milestone 2 hits the API directly; milestone 3 puts a GRDB cache in front of it.
public struct LibraryClient: Sendable {
    public let session: ServerSession
    let client: JellyfinAPI.JellyfinClient
    let identity: ClientIdentity
    let token: String

    public init(session: ServerSession, token: String, auth: AuthService) {
        self.session = session
        self.client = auth.makeClient(for: session.serverURL, token: token)
        self.identity = auth.identity
        self.token = token
    }

    /// Newest albums added to the library.
    public func recentlyAdded(limit: Int = 24) async throws -> [AlbumSummary] {
        let params = Paths.GetItemsParameters(
            userID: session.userID,
            limit: limit,
            isRecursive: true,
            sortOrder: [.descending],
            includeItemTypes: [.musicAlbum],
            sortBy: [.dateCreated]
        )
        return try await client.send(Paths.getItems(parameters: params)).value.items?.compactMap(AlbumSummary.init(album:)) ?? []
    }

    /// Albums ordered by the most recent play of any of their tracks.
    /// Jellyfin records plays on tracks, not albums, so this derives albums from track history.
    public func recentlyPlayed(limit: Int = 24) async throws -> [AlbumSummary] {
        let tracks = try await playedTracks(sortBy: .datePlayed, limit: limit * 8)
        var seen = Set<String>()
        return tracks.compactMap { track -> AlbumSummary? in
            guard let album = AlbumSummary(track: track), seen.insert(album.id).inserted else { return nil }
            return album
        }
        .prefix(limit)
        .map(\.self)
    }

    /// Albums ranked by the summed play counts of their tracks.
    public func mostPlayed(limit: Int = 24) async throws -> [AlbumSummary] {
        let tracks = try await playedTracks(sortBy: .playCount, limit: 500)
        var albums: [String: AlbumSummary] = [:]
        for track in tracks {
            guard var album = AlbumSummary(track: track) else { continue }
            album.playCount = (albums[album.id]?.playCount ?? 0) + (track.userData?.playCount ?? 0)
            albums[album.id] = album
        }
        return albums.values
            .sorted { ($0.playCount, $1.title) > ($1.playCount, $0.title) }
            .prefix(limit)
            .map(\.self)
    }

    /// Tracks on an album in disc/track order.
    public func albumTracks(albumID: String) async throws -> [TrackSummary] {
        let params = Paths.GetItemsParameters(
            userID: session.userID,
            isRecursive: true,
            parentID: albumID,
            includeItemTypes: [.audio],
            sortBy: [.parentIndexNumber, .indexNumber, .sortName]
        )
        return try await client.send(Paths.getItems(parameters: params)).value.items?.compactMap(TrackSummary.init(item:)) ?? []
    }

    private func playedTracks(sortBy: ItemSortBy, limit: Int) async throws -> [BaseItemDto] {
        let params = Paths.GetItemsParameters(
            userID: session.userID,
            limit: limit,
            isRecursive: true,
            sortOrder: [.descending],
            includeItemTypes: [.audio],
            filters: [.isPlayed],
            sortBy: [sortBy]
        )
        return try await client.send(Paths.getItems(parameters: params)).value.items ?? []
    }

    /// Jellyfin image endpoints are unauthenticated, so no token goes in the URL.
    /// `tag` makes the URL change when artwork changes, which keeps image caches correct.
    public func imageURL(itemID: String, tag: String?, maxPixelWidth: Int) -> URL? {
        let params = Paths.GetItemImageParameters(maxWidth: maxPixelWidth, quality: 90, tag: tag)
        return client.url(with: Paths.getItemImage(itemID: itemID, imageType: "Primary", parameters: params))
    }
}

extension AlbumSummary {
    init?(album item: BaseItemDto) {
        guard let id = item.id else { return nil }
        self.init(
            id: id,
            title: item.name ?? "Unknown Album",
            artist: item.albumArtist ?? item.artists?.first ?? "Unknown Artist",
            year: item.productionYear,
            imageTag: item.imageTags?["Primary"]
        )
    }

    init?(track item: BaseItemDto) {
        guard let id = item.albumID else { return nil }
        self.init(
            id: id,
            title: item.album ?? "Unknown Album",
            artist: item.albumArtist ?? item.artists?.first ?? "Unknown Artist",
            year: item.productionYear,
            imageTag: item.albumPrimaryImageTag
        )
    }
}

extension TrackSummary {
    init?(item: BaseItemDto) {
        guard let id = item.id else { return nil }
        self.init(
            id: id,
            title: item.name ?? "Unknown Track",
            artist: item.artists?.joined(separator: ", ") ?? item.albumArtist ?? "Unknown Artist",
            trackNumber: item.indexNumber,
            discNumber: item.parentIndexNumber,
            // Jellyfin ticks are 100ns.
            duration: item.runTimeTicks.map { .milliseconds($0 / 10_000) }
        )
    }
}
