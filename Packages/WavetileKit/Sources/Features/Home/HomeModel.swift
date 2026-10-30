import DesignSystem
import Foundation
import JellyfinKit
import Library
import Observation
import Persistence
import PreviewSupport

@Observable
final class HomeModel {
    struct Shelf: Identifiable {
        enum Kind: String { case recentlyPlayed, mostPlayed, recentlyAdded }
        let kind: Kind
        var albums: [AlbumSummary]
        var id: Kind { kind }

        var title: String {
            switch kind {
            case .recentlyPlayed: "Recently Played"
            case .mostPlayed: "Most Played"
            case .recentlyAdded: "Recently Added"
            }
        }
    }

    /// A genre's shelf of random albums (shown while there's little play history).
    struct GenreShelf: Identifiable {
        let genre: String
        let albums: [AlbumSummary]
        var id: String { genre }
    }

    struct Spotlight {
        let artistID: String
        let name: String
        let albums: [AlbumSummary]
    }

    private(set) var shelves: [Shelf] = []
    // Discovery shelves come from the local library alone, so Home has something to offer
    // before there's any play history. Random picks are reshuffled on pull to refresh.
    private(set) var stats: LibraryStats?
    private(set) var genreShelves: [GenreShelf] = []
    private(set) var playlists: [PlaylistRecord] = []
    private(set) var rediscover: [AlbumSummary] = []
    private(set) var spotlight: Spotlight?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Called with the Recently Played albums after each load (feeds the widget).
    @ObservationIgnored var onRecentlyPlayed: (([AlbumSummary]) -> Void)?
    private let library: LibraryClient?
    private let database: LibraryDatabase?
    /// Albums the user removed from Recently Played. Local only: Jellyfin's play history and
    /// counts are untouched, and playing the album again brings it back.
    private var hiddenRecents: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenRecents), forKey: hiddenRecentsKey) }
    }
    @ObservationIgnored private let hiddenRecentsKey: String

    /// Shelves are computed from the local database synchronously, so Home is populated on the
    /// first frame (and offline); `load()` then refreshes them from the server.
    init(library: LibraryClient, database: LibraryDatabase? = nil, userID: String = "") {
        self.library = library
        self.database = database
        hiddenRecentsKey = "hiddenRecentlyPlayed.\(userID)"
        hiddenRecents = Set(UserDefaults.standard.stringArray(forKey: hiddenRecentsKey) ?? [])
        loadLocal()
    }

    /// Little play history yet: Home leads with the welcome card, genres and playlists.
    var isNewListener: Bool {
        (shelves.first { $0.kind == .recentlyPlayed }?.albums.count ?? 0) < 6
    }

    func removeFromRecentlyPlayed(_ albumID: String) {
        hiddenRecents.insert(albumID)
        applyHiddenRecents()
        onRecentlyPlayed?(shelves.first { $0.kind == .recentlyPlayed }?.albums ?? [])
    }

    /// Playing an album again un-hides it; the next load shows it at the front.
    func albumStartedPlaying(_ albumID: String?) {
        guard let albumID, hiddenRecents.contains(albumID) else { return }
        hiddenRecents.remove(albumID)
    }

    private func applyHiddenRecents() {
        if DebugFlags.freshHome { shelves.removeAll { $0.kind != .recentlyAdded } }
        guard let index = shelves.firstIndex(where: { $0.kind == .recentlyPlayed }) else { return }
        shelves[index].albums.removeAll { hiddenRecents.contains($0.id) }
        if shelves[index].albums.isEmpty { shelves.remove(at: index) }
    }

    /// Preview initializer with fixed content and no network.
    init(previewShelves: [Shelf]) {
        self.library = nil
        self.database = nil
        self.hiddenRecentsKey = ""
        self.hiddenRecents = []
        self.shelves = previewShelves
    }

    private func loadLocal() {
        guard let database else { return }
        let local: [(Shelf.Kind, [AlbumRecord])] = [
            (.recentlyPlayed, (try? database.recentlyPlayedAlbums()) ?? []),
            (.mostPlayed, (try? database.mostPlayedAlbums()) ?? []),
            (.recentlyAdded, (try? database.recentlyAddedAlbums()) ?? []),
        ]
        shelves = local.compactMap { kind, albums in
            albums.isEmpty ? nil : Shelf(kind: kind, albums: albums.map(\.summary))
        }
        applyHiddenRecents()
        loadDiscovery()
    }

    /// Recomputes the discovery shelves, picking new random albums, genres and artist.
    func loadDiscovery() {
        guard let database else { return }
        stats = try? database.libraryStats()
        let genres = ((try? database.topGenres(limit: 6)) ?? []).shuffled().prefix(2)
        genreShelves = genres.compactMap { genre in
            let albums = (try? database.randomAlbums(genre: genre.genre)) ?? []
            return albums.count < 4 ? nil : GenreShelf(genre: genre.genre, albums: albums.map(\.summary))
        }
        playlists = (try? database.playlistsByName()) ?? []
        rediscover = ((try? database.randomAlbums()) ?? []).map(\.summary)
        spotlight = (try? database.spotlightArtist()).flatMap { found in
            found.map { Spotlight(artistID: $0.artist.id, name: $0.artist.name, albums: $0.albums.map(\.summary)) }
        }
    }

    /// After a library sync: fills discovery if it was empty (first launch) without reshuffling
    /// what's already on screen, and refetches shelves that came back empty mid-sync.
    func librarySynced() async {
        if (stats?.albums ?? 0) == 0 { loadDiscovery() }
        if shelves.isEmpty { await load() }
    }

    func load() async {
        guard let library else { return }
        isLoading = shelves.isEmpty
        defer { isLoading = false }
        // Fetch shelves in parallel; one failing shelf shouldn't blank the screen.
        async let played = await Result { try await library.recentlyPlayed() }
        async let most = await Result { try await library.mostPlayed() }
        async let added = await Result { try await library.recentlyAdded() }
        let results: [(Shelf.Kind, Result<[AlbumSummary], any Error>)] = [
            (.recentlyPlayed, await played),
            (.mostPlayed, await most),
            (.recentlyAdded, await added),
        ]
        // Server results win; a shelf that failed keeps its local version.
        let previous = Dictionary(uniqueKeysWithValues: shelves.map { ($0.kind, $0) })
        // Play history can name albums outside the synced music library (other libraries, removed
        // albums); keep only ones here. Before the first sync there's nothing to check against.
        let serverIDs = results.flatMap { (try? $0.1.get())?.map(\.id) ?? [] }
        let synced = (try? database?.isEmpty()) == false ? try? database?.albumIDs(in: serverIDs) : nil
        shelves = results.compactMap { kind, result in
            if var albums = try? result.get() {
                if let synced { albums.removeAll { !synced.contains($0.id) } }
                return albums.isEmpty ? nil : Shelf(kind: kind, albums: albums)
            }
            return previous[kind]
        }
        applyHiddenRecents()
        if let recent = shelves.first(where: { $0.kind == .recentlyPlayed }) { onRecentlyPlayed?(recent.albums) }
        let allFailed = results.allSatisfy { (try? $0.1.get()) == nil }
        errorMessage = if !shelves.isEmpty {
            nil
        } else if allFailed {
            "Couldn't reach your server. Your downloads are in the Downloaded tab."
        } else {
            "Your music library is empty."
        }
    }
}

extension Result where Failure == any Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
