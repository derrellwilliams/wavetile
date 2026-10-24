import DesignSystem
import Library
import Persistence
import SwiftUI

/// Artist page: full-bleed artist photo, name, then albums.
struct ArtistDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    let artistID: String
    let name: String
    @State private var albums: [AlbumRecord] = []
    /// Resolved once; reading the database from `body` would run on every render.
    @State private var imageTag: String??

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
            }
            .padding(.bottom, theme.spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        // Full-bleed art: no dimming/blur band under the navigation bar.
        .scrollEdgeEffectHidden(true, for: .top)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FavoriteButton(itemID: artistID)
            }
        }
        .task {
            if imageTag == nil { imageTag = .some(try? store.database.artist(id: artistID)?.imageTag) }
            do {
                for try await value in store.observe(store.database.albums(artistID: artistID)) { albums = value }
            } catch {}
        }
        .enableInjection()
    }
}
