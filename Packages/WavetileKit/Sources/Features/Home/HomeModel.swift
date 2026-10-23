import DesignSystem
import Foundation
import JellyfinKit
import Observation
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
    private let library: LibraryClient?

    init(library: LibraryClient) {
        self.library = library
    }

    /// Preview initializer with fixed content and no network.
    init(previewShelves: [Shelf]) {
        self.library = nil
        self.shelves = previewShelves
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
        shelves = results.compactMap { kind, result in
            guard let albums = try? result.get(), !albums.isEmpty else { return nil }
            return Shelf(kind: kind, albums: albums)
        }
        let allFailed = results.allSatisfy { (try? $0.1.get()) == nil }
        errorMessage = allFailed ? "Couldn't reach your server." : (shelves.isEmpty ? "Your music library is empty." : nil)
    }
}

extension Result where Failure == any Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
