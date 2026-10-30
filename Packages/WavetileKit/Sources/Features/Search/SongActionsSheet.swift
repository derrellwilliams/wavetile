import DesignSystem
import JellyfinKit
import Persistence
import Playback
import SwiftUI

/// What a song's ⋯ button and long press both offer beyond the standard queue actions:
/// play it, or jump to its album or artist (nil when the song isn't linked to a synced album).
struct SongMenu {
    let play: () -> Void
    private let routes: Routes

    /// Rows build a menu on every render; the routes need a database read, so they're resolved
    /// once, when the menu or sheet first asks for them.
    private final class Routes {
        let resolve: () -> (album: LibraryRoute?, artist: LibraryRoute?)
        lazy var value = resolve()
        init(_ resolve: @escaping () -> (album: LibraryRoute?, artist: LibraryRoute?)) { self.resolve = resolve }
    }

    init(play: @escaping () -> Void, routes: @escaping () -> (album: LibraryRoute?, artist: LibraryRoute?)) {
        self.play = play
        self.routes = Routes(routes)
    }

    var album: LibraryRoute? { routes.value.album }
    var artist: LibraryRoute? { routes.value.artist }
}

/// The ⋯ sheet for a song (search results, Library → Songs). Same actions as the row's long press.
struct SongActionsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pushLibraryRoute) private var push
    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryActions.self) private var actions
    @Environment(LibraryStore.self) private var store
    let track: TrackRecord
    let artwork: ArtworkSource
    let menu: SongMenu

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            HStack(spacing: theme.spacing.md) {
                ArtworkView(artwork)
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text(track.title)
                        .font(theme.typography.itemTitle)
                        .foregroundStyle(theme.palette.textPrimary)
                    Text("\(track.artistName) · \(track.albumTitle)")
                        .font(theme.typography.itemSubtitle)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .lineLimit(2)
            }
            .accessibilityElement(children: .combine)

            ScrollView {
                VStack(spacing: 0) {
                    action("Play", glyph: .play, perform: menu.play)
                    if let album = menu.album { action("Go to Album", glyph: .album) { push(album) } }
                    if let artist = menu.artist { action("Go to Artist", glyph: .artist) { push(artist) } }
                    Divider().overlay(theme.palette.separator)
                    action("Play Next", glyph: .playNext) { player.playNext([QueuedTrack(track).requeued()]) }
                    action("Add to Queue", glyph: .queue) { player.addToQueue([QueuedTrack(track).requeued()]) }
                    action("Start Radio", glyph: .radio) { actions.startRadio(from: track.id, store: store, player: player) }
                    Divider().overlay(theme.palette.separator)
                    action("Add to Playlist", glyph: .addToQueue) {
                        // Opens from the presenter's onDismiss, the moment this sheet is gone.
                        actions.pendingPlaylistTrackIDs = [track.id]
                    }
                    action("Favorite", glyph: .favorite) {
                        actions.favorite(track.id, store: store)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(theme.spacing.screenInset)
        .padding(.top, theme.spacing.sm)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Dismisses first so navigation and Now Playing happen on the screen underneath.
    private func action(_ title: String, glyph: Glyph, perform: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            perform()
        } label: {
            Label(title, glyph: glyph)
                .labelStyle(.tintedIcon)
                .font(theme.typography.body)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

extension LibraryStore {
    /// The song's album page, or nil when the song isn't linked to an album.
    func artistRoute(albumID: String) -> LibraryRoute? {
        guard let album = try? database.album(id: albumID), let artistID = album.artistID else { return nil }
        return .artist(id: artistID, name: album.artistName)
    }

    func songMenu(for track: TrackRecord, source: String, play: @escaping () -> Void) -> SongMenu {
        SongMenu(play: play) { [self] in
            // One album read serves both routes. The artist is the album artist: tracks don't
            // store their own artist ID.
            let record = albumRecord(for: track)
            let album = track.albumID.map { albumID in
                LibraryRoute.album(AlbumRoute(
                    album: record?.summary ?? AlbumSummary(id: albumID, title: track.albumTitle, artist: track.albumArtistName),
                    sourceID: "\(source)-track-\(track.id)"
                ))
            }
            let artist = record.flatMap { record in record.artistID.map { LibraryRoute.artist(id: $0, name: record.artistName) } }
            return (album, artist)
        }
    }

    private func albumRecord(for track: TrackRecord) -> AlbumRecord? {
        track.albumID.flatMap { try? database.album(id: $0) }
    }
}
