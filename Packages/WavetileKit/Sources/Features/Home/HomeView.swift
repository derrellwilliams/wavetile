import DesignSystem
import JellyfinKit
import PreviewSupport
import SwiftUI

struct HomeView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @State var model: HomeModel
    let userName: String
    @Binding var showSettings: Bool
    @Namespace private var zoom
    @State private var path: [AlbumRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.xxl) {
                    ForEach(model.shelves) { shelf in
                        ShelfSection(shelf.title, items: shelf.albums) { album in
                            let route = AlbumRoute(album: album, sourceID: "\(shelf.kind.rawValue)-\(album.id)")
                            NavigationLink(value: route) {
                                AlbumTile(title: album.title, subtitle: album.artist, artwork: model.artwork(for: album))
                                    .matchedTransitionSource(id: route.sourceID, in: zoom)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
                .padding(.vertical, theme.spacing.lg)
            }
            .overlay { overlay }
            .themedBackground()
            .reportsTabRoot()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Wavetile")
                        .font(theme.typography.wordmark)
                        .foregroundStyle(theme.palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Avatar(name: userName, size: 34)
                    }
                    .accessibilityLabel("Profile and Settings")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationDestination(for: AlbumRoute.self) { route in
                AlbumDetailView(model: model.detailModel(for: route.album))
                    .navigationTransition(.zoom(sourceID: route.sourceID, in: zoom))
            }
            .refreshable { await model.load() }
            // Root reappears after every pop, so only load the first time; pull to refresh after that.
            .task {
                guard model.shelves.isEmpty else { return }
                await model.load()
                if DebugFlags.openFirstAlbum, let shelf = model.shelves.first, let album = shelf.albums.first {
                    path = [AlbumRoute(album: album, sourceID: "\(shelf.kind.rawValue)-\(album.id)")]
                }
            }
        }
        .enableInjection()
    }

    @ViewBuilder private var overlay: some View {
        if model.isLoading {
            ProgressView()
        } else if let error = model.errorMessage {
            EmptyState("Nothing Here Yet", glyph: .album, message: error) {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(.glass)
            }
        }
    }
}

#Preview {
    HomeView(model: HomeModel(previewShelves: [
        .init(kind: .recentlyPlayed, albums: Array(Fixtures.albums.prefix(6))),
        .init(kind: .mostPlayed, albums: Fixtures.albums.reversed()),
        .init(kind: .recentlyAdded, albums: Array(Fixtures.albums.suffix(5))),
    ]), userName: "Derrell", showSettings: .constant(false))
}
