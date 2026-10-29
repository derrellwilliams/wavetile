import DesignSystem
import Persistence
import SwiftUI

/// Top of Home while there's little play history: library size and a nudge to start listening.
struct WelcomeCard: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PodcastsStore.self) private var podcasts
    let userName: String
    let stats: LibraryStats
    /// Bumped once after the first frame so the hand waves.
    @State private var waves = 0
    /// Home reappears often (tab switches, returning from a page); the hand waves only the first time each launch.
    private static var hasWaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            HStack(spacing: theme.spacing.sm) {
                hand
                Text("Hi, \(greetingName)!")
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.palette.textPrimary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hi, \(greetingName)!")
            .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                Text("You have \(songCount) in your library. Start listening and Wavetile tunes itself to your taste.")
                // Podcasts are opt-in; point to the switch until they're on (always with -freshHome).
                if !podcasts.isEnabled || DebugFlags.freshHome {
                    Text("Into podcasts? Turn them on from your profile.")
                }
            }
            // The artist bio's style: body size, secondary color.
            .font(theme.typography.body)
            .foregroundStyle(theme.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing.lg)
        .background(theme.palette.surface, in: .rect(cornerRadius: theme.radius.card))
        .padding(.horizontal, theme.spacing.screenInset)
        .task {
            guard !reduceMotion, !Self.hasWaved else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            Self.hasWaved = true
            waves += 1
        }
    }

    /// A wave from the wrist, easing out to rest.
    private var hand: some View {
        Glyph.wave.image
            .resizable()
            .frame(width: 28, height: 28)
            .foregroundStyle(theme.palette.accent)
            .keyframeAnimator(initialValue: 0.0, trigger: waves) { content, angle in
                content.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.3, y: 0.85))
            } keyframes: { _ in
                // Three rounds of back and forth, the last one tapering off.
                KeyframeTrack {
                    CubicKeyframe(14, duration: 0.2)
                    CubicKeyframe(-8, duration: 0.22)
                    CubicKeyframe(14, duration: 0.22)
                    CubicKeyframe(-8, duration: 0.22)
                    CubicKeyframe(14, duration: 0.22)
                    CubicKeyframe(-8, duration: 0.22)
                    CubicKeyframe(14, duration: 0.22)
                    CubicKeyframe(-8, duration: 0.22)
                    CubicKeyframe(10, duration: 0.22)
                    CubicKeyframe(-4, duration: 0.22)
                    SpringKeyframe(0, duration: 0.4, spring: .smooth)
                }
            }
    }

    /// The username with its first letter capitalized ("slimscrawny" → "Slimscrawny"); the rest is left as typed.
    private var greetingName: String {
        userName.prefix(1).uppercased() + userName.dropFirst()
    }

    private var songCount: String {
        "\(stats.tracks.formatted()) song\(stats.tracks == 1 ? "" : "s")"
    }
}

/// Playlist tile for Home shelves.
struct PlaylistLink: View {
    @Environment(LibraryStore.self) private var store
    let playlist: PlaylistRecord

    var body: some View {
        NavigationLink(value: LibraryRoute.playlist(playlist)) {
            AlbumTile(
                title: playlist.name,
                subtitle: "\(playlist.trackCount) song\(playlist.trackCount == 1 ? "" : "s")",
                artwork: store.artwork(itemID: playlist.id, tag: playlist.imageTag, maxPixelWidth: 480)
            )
        }
        .buttonStyle(.pressable)
    }
}

/// One artist and their albums, at the bottom of Home. A new artist is picked each launch
/// and on pull to refresh.
struct ArtistSpotlightShelf: View {
    @Environment(\.theme) private var theme
    let spotlight: HomeModel.Spotlight

    var body: some View {
        ShelfSection(items: spotlight.albums) {
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text("Artist Spotlight")
                    .font(theme.typography.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.palette.accent)
                Text(spotlight.name)
                    .font(theme.typography.sectionHeader)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        } tile: { album in
            AlbumLink(album: album, context: "spotlight")
        }
    }
}
