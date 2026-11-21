import DesignSystem
import SwiftUI

/// What plays offline is always marked: downloaded songs, albums, playlists and collections carry
/// a download mark online and off (`TrackRow`, `AlbumTile`). On top of that:
/// - no network (certain): `OfflineNotice`, `offlineDimmed(available:)` on tiles (song rows dim in
///   `PlayableRow`), `requiresServer()` on actions that change the library on the server, and
///   Home's Downloaded row first;
/// - the server failed a request (see `Connectivity`): `OfflineNotice` with Retry and Home's
///   Downloaded row, no dimming. Server actions still run, and say so if they fail.

/// Under a main tab's title while music can't stream: no network, or the server failed a request.
/// Draws nothing when online, so it takes no room. Put `animatesConnectivity()` on its container
/// so it slides in and out.
struct OfflineNotice: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(Connectivity.self) private var connectivity
    /// Space below it, for stacks without spacing of their own; nothing while online.
    var gap: CGFloat = 0
    /// The Podcasts tab: episodes stream from their feeds, not the server, so only a lost network
    /// stops them.
    var podcasts = false

    @State private var retrying = false

    private var message: String? {
        if !connectivity.hasNetwork {
            return podcasts ? "You're offline. Downloaded episodes still play." : "You're offline. Downloaded music still plays."
        }
        if serverDown { return "Can't reach your server. Downloaded music still plays." }
        return nil
    }

    private var serverDown: Bool { connectivity.hasNetwork && !connectivity.serverReachable && !podcasts }

    var body: some View {
        if let message {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                Label(message, glyph: .offline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // It also retries by itself; this is for not waiting.
                if serverDown {
                    Button("Retry") {
                        retrying = true
                        Task {
                            await connectivity.recheck()
                            retrying = false
                        }
                    }
                    .foregroundStyle(theme.palette.accent)
                    .disabled(retrying)
                }
            }
            .font(theme.typography.itemSubtitle)
            .foregroundStyle(theme.palette.textSecondary)
            .padding(.horizontal, theme.spacing.screenInset)
            .padding(.bottom, gap)
            // Drops in from the top and leaves the same way.
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
    }
}

extension View {
    /// Animates the notice and dimming when the connection changes.
    func animatesConnectivity() -> some View {
        modifier(ConnectivityAnimation())
    }

    /// With no network, dims an album, playlist or collection with nothing downloaded. It stays tappable:
    /// its page still lists what it holds, and a song that can't play says why.
    func offlineDimmed(available: Bool) -> some View {
        modifier(OfflineDim(available: available))
    }

    /// Disables an action that changes the library on the server (favorite, add to playlist,
    /// rename, delete, covers, Start Radio) with no network, instead of letting it fail. A server
    /// that's only failing requests doesn't disable it: the action runs and says if it fails.
    func requiresServer() -> some View {
        modifier(RequiresServer())
    }
}

private struct ConnectivityAnimation: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(Connectivity.self) private var connectivity

    func body(content: Content) -> some View {
        content.animation(theme.motion.smooth, value: connectivity.isOnline)
    }
}

private struct OfflineDim: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(Connectivity.self) private var connectivity
    let available: Bool

    func body(content: Content) -> some View {
        let dimmed = !connectivity.hasNetwork && !available
        content
            // Animated here as well as by the container: a tile a lazy stack builds mid-change
            // can miss the container's animation and keep a stale dim until it's rebuilt. Scoped
            // to the opacity, so the tile's other updates (artwork, badges) don't animate with it.
            .animation(theme.motion.smooth) { $0.opacity(dimmed ? theme.unavailableOpacity : 1) }
            .modifier(DimmedHint(isDimmed: dimmed))
    }
}

/// "Not downloaded" for VoiceOver while dimmed; otherwise leaves the tile's own hint alone.
private struct DimmedHint: ViewModifier {
    let isDimmed: Bool

    func body(content: Content) -> some View {
        if isDimmed { content.accessibilityHint("Not downloaded") } else { content }
    }
}

private struct RequiresServer: ViewModifier {
    @Environment(Connectivity.self) private var connectivity

    func body(content: Content) -> some View {
        content.disabled(!connectivity.hasNetwork)
    }
}
