import DesignSystem
import JellyfinKit
import PreviewSupport
import SwiftUI

struct HomeView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @State var model: HomeModel
    @Namespace private var zoom
    @Binding var path: [LibraryRoute]
    @State private var didRefresh = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.xxl) {
                    ForEach(model.shelves) { shelf in
                        ShelfSection(shelf.title, items: shelf.albums) { album in
                            AlbumLink(
                                album: album,
                                context: shelf.kind.rawValue,
                                onRemoveFromRecents: shelf.kind == .recentlyPlayed
                                    ? { withAnimation(theme.motion.smooth) { model.removeFromRecentlyPlayed(album.id) } }
                                    : nil
                            )
                        }
                    }
                }
                .padding(.vertical, theme.spacing.lg)
            }
            .overlay { overlay }
            .themedBackground()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Wavetile")
                        .font(theme.typography.wordmark)
                        .foregroundStyle(theme.palette.accent)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .tabRootChrome()
            .libraryDestinations(zoom: zoom)
            .refreshable { await model.load() }
            .task {
                // Local shelves are already on screen; refresh from the server once per session.
                guard !didRefresh else { return }
                didRefresh = true
                await model.load()
                if DebugFlags.openFirstAlbum, let shelf = model.shelves.first,
                   let album = shelf.albums.dropFirst(DebugFlags.albumIndex).first {
                    path = [.album(AlbumRoute(album: album, sourceID: "\(shelf.kind.rawValue)-\(album.id)"))]
                }
            }
        }
        .enableInjection()
    }

    @ViewBuilder private var overlay: some View {
        if model.isLoading {
            LoadingMark()
        } else if let error = model.errorMessage {
            EmptyState("Nothing Here Yet", glyph: .album, message: error) {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(.glass)
            }
        }
    }
}

#Preview {
    let app = AppModel.preview()
    if case let .signedIn(signedIn) = app.phase {
        HomeView(model: HomeModel(previewShelves: [
            .init(kind: .recentlyPlayed, albums: Array(Fixtures.albums.prefix(6))),
            .init(kind: .mostPlayed, albums: Fixtures.albums.reversed()),
            .init(kind: .recentlyAdded, albums: Array(Fixtures.albums.suffix(5))),
        ]), path: .constant([]))
        .environment(signedIn.library)
    }
}
