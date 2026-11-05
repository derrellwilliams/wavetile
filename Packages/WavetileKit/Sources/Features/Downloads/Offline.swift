import DesignSystem
import SwiftUI

/// Offline, the app says so once, shows what still plays, and keeps actions that need the server
/// from failing after a tap:
/// - `OfflineNotice` under every main tab's title;
/// - `offlineDimmed(available:)` on album, playlist and collection tiles (song rows dim in
///   `PlayableRow`);
/// - `requiresServer()` on actions that change the library on the server;
/// - Home's Downloaded row (`HomeView`).

/// Under a main tab's title while music can't stream: no network, or the server is out of reach.
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

    private var message: String? {
        if !connectivity.hasNetwork {
            return podcasts ? "You're offline. Downloaded episodes still play." : "You're offline. Downloaded music still plays."
        }
        if !connectivity.serverReachable, !podcasts { return "Can't reach your server. Downloaded music still plays." }
        return nil
    }

    var body: some View {
        if let message {
            Label(message, glyph: .offline)
            .font(theme.typography.itemSubtitle)
            .foregroundStyle(theme.palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Offline, dims an album, playlist or collection with nothing downloaded. It stays tappable:
    /// its page still lists what it holds, and a song that can't play says why.
    func offlineDimmed(available: Bool) -> some View {
        modifier(OfflineDim(available: available))
    }

    /// Disables an action that changes the library on the server (favorite, add to playlist,
    /// rename, delete, covers, Start Radio) while it can't be reached, instead of letting it fail.
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
        let dimmed = !connectivity.isOnline && !available
        content
            .opacity(dimmed ? theme.unavailableOpacity : 1)
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
        content.disabled(!connectivity.isOnline)
    }
}
