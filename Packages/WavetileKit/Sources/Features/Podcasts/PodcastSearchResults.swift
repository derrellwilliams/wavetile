import DesignSystem
import Podcasts
import SwiftUI

/// Search's Podcasts filter: your shows and episodes (instant, offline), then Apple Podcasts
/// directory results.
///
/// Privacy: only text typed under this filter goes to Apple, after typing pauses. Music
/// searches never leave the device.
struct PodcastSearchResults: View {
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(\.pushPodcastRoute) private var push
    let text: String
    @State private var local = PodcastDatabase.SearchResults()
    @State private var directory: [DirectoryShow] = []
    @State private var isSearching = false
    @State private var directoryError: String?
    @State private var showAddFeed = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Text that is itself a feed link.
    private var pastedFeed: URL? {
        guard trimmed.contains("/") || trimmed.hasPrefix("feed:"), !trimmed.contains(" "),
              let url = URL(string: trimmed), url.host() != nil
        else { return nil }
        return PodcastNetwork.secure(url)
    }

    var body: some View {
        List {
            if let feed = pastedFeed {
                Section {
                    Button {
                        push(.show(ShowRoute(feedURL: feed, title: feed.host() ?? "Podcast", author: "", artworkURL: nil)))
                    } label: {
                        Label("Open Feed Link", glyph: .feed)
                            .labelStyle(.tintedIcon)
                            .font(theme.typography.body.weight(.semibold))
                    }
                    .listRowBackground(Color.clear)
                }
            }
            if !local.shows.isEmpty {
                Section("Your Shows") {
                    ForEach(local.shows) { show in
                        NavigationLink(value: PodcastRoute.show(ShowRoute(show))) {
                            TrackRow(title: show.title, subtitle: show.author, leading: .artwork(.unsized(show.artworkURL, maxPixelWidth: 168)))
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            if !local.episodes.isEmpty {
                Section("Episodes") {
                    ForEach(local.episodes) { item in
                        EpisodeRow(item: item)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            if !directory.isEmpty {
                Section("Apple Podcasts") {
                    ForEach(directory) { show in
                        if let route = ShowRoute(show) {
                            NavigationLink(value: PodcastRoute.show(route)) {
                                TrackRow(
                                    title: show.title,
                                    subtitle: [show.author, show.genre].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "),
                                    leading: .artwork(.unsized(show.artworkURL, maxPixelWidth: 168))
                                )
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            } else if isSearching {
                HStack {
                    Spacer()
                    LoadingMark()
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .overlay { emptyState }
        .sheet(isPresented: $showAddFeed) { AddFeedSheet() }
        .task(id: trimmed) {
            local = (try? podcasts.database.search(trimmed)) ?? .init()
            directory = []
            directoryError = nil
            guard trimmed.count >= 2, pastedFeed == nil else { return }
            // Debounce: Apple allows about 20 searches a minute per device.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                directory = try await podcasts.directory.search(trimmed)
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { directoryError = "Couldn't reach Apple Podcasts." }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if trimmed.isEmpty {
            EmptyState("Search Podcasts", glyph: .podcasts, message: "Find shows on Apple Podcasts, or search the shows you follow.") {
                Button("Add by Link") { showAddFeed = true }
                    .buttonStyle(.glass)
            }
        } else if !isSearching, local.isEmpty, directory.isEmpty, pastedFeed == nil {
            EmptyState("No Results", glyph: .search, message: directoryError ?? "No podcasts match “\(trimmed)”.")
        }
    }
}
