import DesignSystem
import Library
import Persistence
import SwiftUI

struct LibraryView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Namespace private var zoom
    @State private var recentlyAdded: [AlbumRecord] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(LibrarySection.allCases, id: \.self) { section in
                        NavigationLink(value: LibraryRoute.section(section)) {
                            HStack(spacing: theme.spacing.md) {
                                section.glyph.image
                                    .foregroundStyle(theme.palette.accent)
                                    .frame(width: 28)
                                Text(section.title)
                                    .font(theme.typography.sectionHeader)
                                    .foregroundStyle(theme.palette.textPrimary)
                                Spacer()
                                Glyph.chevron.image
                                    .resizable()
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(theme.palette.textSecondary)
                            }
                            .padding(.vertical, theme.spacing.md + 2)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(theme.palette.separator).padding(.leading, 28 + theme.spacing.md)
                    }

                    syncStatus

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
            }
            .themedBackground()
            .markRefreshable { await store.syncNow() }
            .navigationTitle("Library")
            .tabRootChrome()
            .libraryDestinations(zoom: zoom)
            .task {
                do {
                    for try await albums in store.observe(store.database.albums(sort: .recentlyAdded)) {
                        recentlyAdded = Array(albums.prefix(12))
                    }
                } catch {}
            }
        }
        .enableInjection()
    }

    @ViewBuilder private var syncStatus: some View {
        if let status = store.statusText {
            HStack(spacing: theme.spacing.sm) {
                ProgressView().controlSize(.small)
                Text(status)
            }
            .font(theme.typography.caption)
            .foregroundStyle(theme.palette.textSecondary)
            .padding(.top, theme.spacing.sm)
        } else if let error = store.syncError {
            Label(error, glyph: .warning)
                .font(theme.typography.caption)
                .foregroundStyle(theme.palette.textSecondary)
                .padding(.top, theme.spacing.sm)
        }
    }
}
