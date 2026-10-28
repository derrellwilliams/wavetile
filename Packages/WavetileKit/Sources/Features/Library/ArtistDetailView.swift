import DesignSystem
import JellyfinKit
import Library
import Persistence
import Playback
import SwiftUI

/// Artist page: full-bleed artist photo, name, Play and Shuffle, the start of the bio, then
/// albums and similar artists from the same library.
struct ArtistDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @Environment(Connectivity.self) private var connectivity
    @Environment(LibraryActions.self) private var actions
    let artistID: String
    let name: String
    @State private var albums: [AlbumRecord] = []
    /// Resolved once; reading the database from `body` would run on every render.
    @State private var imageTag: String??
    /// The bio, fetched when the page opens (it isn't synced).
    @State private var details: ItemDetails?
    @State private var showAbout = false
    @State private var similar: [ArtistRecord] = []

    private var artwork: ArtworkSource {
        store.artwork(itemID: artistID, tag: imageTag ?? nil, maxPixelWidth: 1320)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                VStack(spacing: theme.spacing.md) {
                    ArtworkHero(artwork: artwork)
                    Text(name)
                        .font(theme.typography.largeTitle)
                        .tracking(theme.typography.displayTracking)
                        .foregroundStyle(theme.palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, theme.spacing.screenInset)
                        .frame(maxWidth: .infinity)
                    playButtons
                    // The start of the bio; Read More opens the whole thing in a sheet.
                    if let overview = details?.overview {
                        ExpandableText(overview) { showAbout = true }
                            .padding(.horizontal, theme.spacing.screenInset)
                            .padding(.top, theme.spacing.sm)
                            .transition(.opacity)
                    }
                }

                if !albums.isEmpty {
                    Text("Albums")
                        .font(theme.typography.sectionHeader)
                        .foregroundStyle(theme.palette.textPrimary)
                        .padding(.horizontal, theme.spacing.screenInset)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: theme.artwork.shelfTileWidth - 8), spacing: theme.spacing.lg)],
                        alignment: .leading,
                        spacing: theme.spacing.xl
                    ) {
                        ForEach(albums) { album in
                            AlbumLink(album: album.summary, context: "artist")
                        }
                    }
                    .padding(.horizontal, theme.spacing.screenInset)
                }

                if !similar.isEmpty {
                    ShelfSection("Similar Artists", items: similar) { artist in
                        SimilarArtistLink(artist: artist)
                    }
                }
            }
            .padding(.bottom, theme.spacing.xxl)
        }
        // Full-bleed art: no bar background or blur band under the navigation bar.
        .detailPageChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FavoriteButton(itemID: artistID)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Start Radio", glyph: .radio) { actions.startRadio(from: artistID, store: store, player: player) }
                } label: {
                    Label("More", glyph: .more)
                }
            }
        }
        .sheet(isPresented: $showAbout) {
            if let overview = details?.overview {
                AboutSheet(sections: [.init(title: name, text: overview)])
            }
        }
        .task {
            if imageTag == nil { imageTag = .some(try? store.database.artist(id: artistID)?.imageTag) }
            do {
                for try await value in store.observe(store.database.albums(artistID: artistID)) { albums = value }
            } catch { Log.observationFailed(error) }
        }
        .task {
            let loaded = try? await store.api.details(itemID: artistID)
            withAnimation(theme.motion.smooth) { details = loaded }
        }
        .task {
            // Only artists in the synced library, so each one opens a full page.
            guard let ids = try? await store.api.similarArtists(artistID: artistID),
                  let artists = try? store.database.artists(ids: ids) else { return }
            withAnimation(theme.motion.smooth) { similar = artists }
        }
        .enableInjection()
    }

    /// Play and Shuffle across every album, as on the album page.
    private var playButtons: some View {
        HStack(spacing: theme.spacing.md) {
            PrimaryButton("Play", glyph: .play) { play(shuffled: false) }
            PrimaryButton("Shuffle", glyph: .shuffle) { play(shuffled: true) }
        }
        .disabled(albums.isEmpty)
        .padding(.horizontal, theme.spacing.screenInset)
    }

    /// Read on tap, so a large discography costs nothing until it's played.
    /// Offline, only downloaded songs are queued.
    private func play(shuffled: Bool) {
        guard var queue = try? store.database.tracks(artistID: artistID).map(QueuedTrack.init) else { return }
        if !connectivity.isOnline { queue = queue.filter { downloads.isDownloaded($0.trackID) } }
        player.play(queue, shuffled: shuffled)
    }
}

/// A round artist photo and name, for the Similar Artists shelf.
private struct SimilarArtistLink: View {
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    let artist: ArtistRecord

    var body: some View {
        NavigationLink(value: LibraryRoute.artist(id: artist.id, name: artist.name)) {
            VStack(spacing: theme.spacing.sm) {
                ArtworkView(store.artwork(itemID: artist.id, tag: artist.imageTag, maxPixelWidth: 480))
                    .clipShape(.circle)
                Text(artist.name)
                    .font(theme.typography.itemTitle)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.pressable)
    }
}
