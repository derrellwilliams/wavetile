import DesignSystem
import JellyfinKit
import Playback
import PreviewSupport
import SwiftUI

struct AlbumDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @Environment(LibraryActions.self) private var actions
    @State var model: AlbumDetailModel

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.xl) {
                VStack(spacing: theme.spacing.md) {
                    ArtworkHero(artwork: model.artwork)
                    header
                }
                trackList
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
                DownloadButton(collectionID: model.album.id) {
                    downloads.download(album: model.album, trackIDs: model.tracks.map(\.id))
                }
                .disabled(model.tracks.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                FavoriteButton(itemID: model.album.id)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add to Playlist", glyph: .addToQueue) { actions.addToPlaylist(model.tracks.map(\.id)) }
                        .disabled(model.tracks.isEmpty)
                    Button("Add to Collection", glyph: .collection) { actions.addToCollection([model.album.id]) }
                    Divider()
                    Button("Play Next", glyph: .playNext) { player.playNext(queue()) }
                        .disabled(model.tracks.isEmpty)
                    Button("Add to Queue", glyph: .queue) { player.addToQueue(queue()) }
                        .disabled(model.tracks.isEmpty)
                } label: {
                    Label("More", glyph: .more)
                }
            }
        }
        .task {
            await model.load()
            if DebugFlags.autoplay, !player.hasQueue { player.play(queue()) }
            if DebugFlags.autodownload { downloads.download(album: model.album, trackIDs: model.tracks.map(\.id)) }
        }
        .enableInjection()
    }

    private var header: some View {
        VStack(spacing: theme.spacing.xs) {
            Text(model.album.title)
                .font(theme.typography.largeTitle)
                .tracking(theme.typography.displayTracking)
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            artistName
            Text(metadata)
                // One point up from caption (12pt), still scaling with Dynamic Type.
                .font(BrandFont.font(.footnote))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .padding(.horizontal, theme.spacing.screenInset)
    }

    /// Taps through to the artist when the album's artist is known locally.
    @ViewBuilder private var artistName: some View {
        // Stack Sans Notch, matching the title on the artist page it opens.
        let label = Text(model.album.artist)
            .font(BrandFont.display(.title3))
            .tracking(theme.typography.displayTracking)
            .foregroundStyle(theme.palette.textPrimary)
        if let artistID = model.artistID {
            NavigationLink(value: LibraryRoute.artist(id: artistID, name: model.album.artist)) { label }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the artist")
        } else {
            label
        }
    }

    private func queue() -> [QueuedTrack] {
        model.tracks.map { QueuedTrack($0, album: model.album) }
    }

    private var metadata: String {
        var parts: [String] = []
        if let year = model.album.year { parts.append(String(year)) }
        if !model.tracks.isEmpty {
            parts.append("\(model.tracks.count) songs")
            parts.append(model.totalDuration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var trackList: some View {
        if model.isLoading {
            ProgressView().padding(theme.spacing.xxl)
        } else if let error = model.errorMessage {
            EmptyState("Something Went Wrong", glyph: .warning, message: error) {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(.glass)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.discs, id: \.number) { disc in
                    if let number = disc.number {
                        Text("Disc \(number)")
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.palette.textSecondary)
                            .padding(.horizontal, theme.spacing.screenInset)
                            .padding(.top, theme.spacing.lg)
                            .padding(.bottom, theme.spacing.xs)
                    }
                    ForEach(disc.tracks) { track in
                        PlayableRow(trackID: track.id, index: model.tracks.firstIndex(of: track) ?? 0, tracks: queue) {
                            TrackRow(
                                title: track.title,
                                subtitle: track.artist == model.album.artist ? nil : track.artist,
                                duration: track.duration,
                                leading: .number(track.trackNumber),
                                isPlaying: player.current?.trackID == track.id,
                                isDownloaded: downloads.isDownloaded(track.id)
                            )
                            .padding(.horizontal, theme.spacing.screenInset)
                            .padding(.vertical, theme.spacing.md)
                        }
                        if track.id != disc.tracks.last?.id {
                            Divider()
                                .overlay(theme.palette.separator)
                                .padding(.leading, theme.spacing.screenInset + 24 + theme.spacing.md)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(model: AlbumDetailModel(previewAlbum: Fixtures.albums[0], tracks: Fixtures.tracks))
    }
}
