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

    private(set) var shelves: [Shelf] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Called with the Recently Played albums after each load (feeds the widget).
    @ObservationIgnored var onRecentlyPlayed: (([AlbumSummary]) -> Void)?
    private let library: LibraryClient?
    private let database: LibraryDatabase?

    /// Shelves are computed from the local database synchronously, so Home is populated on the
    /// first frame (and offline); `load()` then refreshes them from the server.
    init(library: LibraryClient, database: LibraryDatabase? = nil) {
        self.library = library
        self.database = database
        loadLocal()
    }

    /// Preview initializer with fixed content and no network.
    init(previewShelves: [Shelf]) {
        self.library = nil
        self.database = nil
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
        shelves = results.compactMap { kind, result in
            if let albums = try? result.get() {
                return albums.isEmpty ? nil : Shelf(kind: kind, albums: albums)
            }
            return previous[kind]
        }
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
