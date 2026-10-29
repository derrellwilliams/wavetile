import DesignSystem
import JellyfinKit
import Persistence
import Playback
import PreviewSupport
import SwiftUI

struct AlbumDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @Environment(LibraryActions.self) private var actions
    @Environment(LibraryStore.self) private var store
    @State var model: AlbumDetailModel
    /// The release date, fetched when the page opens (it isn't synced).
    @State private var details: ItemDetails?
    @State private var moreByArtist: [AlbumRecord] = []

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.xl) {
                VStack(spacing: theme.spacing.md) {
                    ArtworkHero(artwork: model.artwork)
                    header
                    playButtons
                }
                trackList
                releaseDate
                if !moreByArtist.isEmpty {
                    ShelfSection("More by \(model.album.artist)", items: moreByArtist) { album in
                        AlbumLink(album: album.summary, context: "more-by")
                    }
                }
            }
            .padding(.bottom, theme.spacing.xxl)
        }
        // Full-bleed art: no bar background or blur band under the navigation bar.
        .detailPageChrome()
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
                    Button("Start Radio", glyph: .radio) { actions.startRadio(from: model.album.id, store: store, player: player) }
                } label: {
                    Label("More", glyph: .more)
                }
            }
        }
        .task {
            let loaded = try? await store.api.details(itemID: model.album.id)
            withAnimation(theme.motion.smooth) { details = loaded }
        }
        .task {
            guard let artistID = model.artistID else { return }
            do {
                for try await albums in store.observe(store.database.albums(artistID: artistID)) {
                    moreByArtist = albums.filter { $0.id != model.album.id }
                }
            } catch { Log.observationFailed(error) }
        }
        .task {
            await model.load()
            if DebugFlags.autoplay, !player.hasQueue { player.play(queue()) }
            if DebugFlags.autodownload { downloads.download(album: model.album, trackIDs: model.tracks.map(\.id)) }
        }
        .enableInjection()
    }

    private var header: some View {
        DetailHeader(model.album.title, metadata: metadata) { artistName }
    }

    /// Play and Shuffle side by side, as in Apple Music.
    private var playButtons: some View {
        HStack(spacing: theme.spacing.md) {
            PrimaryButton("Play", glyph: .play) { player.play(queue()) }
            PrimaryButton("Shuffle", glyph: .shuffle) { player.play(queue(), shuffled: true) }
        }
        .disabled(model.tracks.isEmpty)
        .padding(.horizontal, theme.spacing.screenInset)
    }

    /// Taps through to the artist when the album's artist is known locally.
    @ViewBuilder private var artistName: some View {
        if let artistID = model.artistID {
            NavigationLink(value: LibraryRoute.artist(id: artistID, name: model.album.artist)) {
                DetailSubtitle(model.album.artist)
            }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the artist")
        } else {
            DetailSubtitle(model.album.artist)
        }
    }

    /// The full release date, as Apple Music shows under the track list.
    @ViewBuilder private var releaseDate: some View {
        if let date = details?.premiereDate {
            // Jellyfin stores release dates at midnight UTC; local time would show the day before.
            Text(date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt)))
                .font(theme.typography.itemSubtitle)
                .foregroundStyle(theme.palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.spacing.screenInset)
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
            LoadingMark().padding(theme.spacing.xxl)
        } else if let error = model.errorMessage {
            EmptyState("Something Went Wrong", glyph: .warning, message: error) {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(.tinted)
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
                        PlayableRow(trackID: track.id, index: model.tracks.firstIndex(of: track) ?? 0, tracks: queue, showsMore: true) {
                            TrackRow(
                                title: track.title,
                                subtitle: track.artist == model.album.artist ? nil : track.artist,
                                duration: track.duration,
                                leading: .number(model.number(for: track, in: disc.tracks)),
                                isPlaying: player.current?.trackID == track.id,
                                isDownloaded: downloads.isDownloaded(track.id)
                            )
                            .padding(.leading, theme.spacing.screenInset)
                            .padding(.vertical, theme.spacing.md)
                        }
                        // The ⋯ tap area is wider than its glyph; this lines the glyph up with the inset.
                        .padding(.trailing, theme.spacing.screenInset - 12)
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
