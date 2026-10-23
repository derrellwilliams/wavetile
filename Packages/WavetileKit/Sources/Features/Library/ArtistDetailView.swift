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

    private var artwork: ArtworkSource {
        let tag = try? store.database.artist(id: artistID)?.imageTag
        return store.artwork(itemID: artistID, tag: tag, maxPixelWidth: 1320)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                VStack(spacing: theme.spacing.md) {
                    ArtworkHero(artwork: artwork)
                    Text(name)
                        .font(theme.typography.largeTitle)
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
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                for try await value in store.observe(store.database.albums(artistID: artistID)) { albums = value }
            } catch {}
        }
        .enableInjection()
    }
}
