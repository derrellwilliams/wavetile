import DesignSystem
import Library
import Persistence
import SwiftUI

/// The Music tab (the Jellyfin library): browse sections and Recently Added.
struct LibraryView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Namespace private var zoom
    @State private var path = NavigationPath()
    @State private var recentlyAdded: [AlbumRecord] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(LibrarySection.allCases, id: \.self) { section in
                        NavigationLink(value: LibraryRoute.section(section)) {
                            LinkRow(title: section.title, glyph: section.glyph)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(theme.palette.separator).padding(.leading, 28 + theme.spacing.md)
                    }

                    LibrarySyncStatus()

                    if !recentlyAdded.isEmpty {
                        Text("Recently Added")
                            .font(theme.typography.sectionHeader)
                            .foregroundStyle(theme.palette.textPrimary)
                            .padding(.top, theme.spacing.xl)
                            .padding(.bottom, theme.spacing.md)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: theme.artwork.shelfTileWidth - 8), spacing: theme.spacing.lg)],
                            alignment: .leading,
                            spacing: theme.spacing.xl
                        ) {
                            ForEach(recentlyAdded) { album in
                                AlbumLink(album: album.summary, context: "library-recent")
                            }
                        }
                    }
                }
                .padding(.horizontal, theme.spacing.screenInset)
                .padding(.bottom, theme.spacing.xxl)
                // The sync line fading in or out moves Recently Added smoothly, not in a jump.
                // Keyed on isSyncing (flips twice a sync), not the progress count, which changes
                // every page and would redraw this whole tab.
                .animation(theme.motion.smooth, value: store.isSyncing)
                .animation(theme.motion.smooth, value: store.syncError)
            }
            .themedBackground()
            .markRefreshable { await store.syncNow() }
            .navigationTitle("Music")
            .tabRootChrome()
            .libraryDestinations(zoom: zoom) { path.append($0) }
            .task {
                do {
                    for try await albums in store.observe(store.database.recentlyAddedAlbums(limit: 12)) {
                        recentlyAdded = albums
                    }
                } catch { Log.observationFailed(error) }
            }
        }
        .enableInjection()
    }
}

/// The sync progress line. Its own view so per-page progress redraws only this line.
private struct LibrarySyncStatus: View {
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store

    var body: some View {
        if let status = store.statusText {
            HStack(spacing: theme.spacing.sm) {
                ProgressView().controlSize(.small)
                Text(status)
            }
            .font(theme.typography.caption)
            .foregroundStyle(theme.palette.textSecondary)
            .padding(.top, theme.spacing.sm)
            .transition(.opacity)
        } else if let error = store.syncError {
            Label(error, glyph: .warning)
                .font(theme.typography.caption)
                .foregroundStyle(theme.palette.textSecondary)
                .padding(.top, theme.spacing.sm)
                .transition(.opacity)
        }
    }
}
