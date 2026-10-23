import SwiftUI

/// Every visual decision in the app flows from a `Theme`.
///
/// To rebrand: edit `Theme.wavetile` below, or add a new static theme and pick it in
/// Settings → Appearance. Views read tokens via `@Environment(\.theme)`; they never
/// hard-code colors, fonts, spacing, radii, or animations.
public struct Theme: Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var palette: Palette
    public var typography: Typography
    public var spacing: Spacing
    public var radius: Radius
    public var artwork: Artwork
    public var motion: Motion
    /// Forced appearance. `nil` follows the system light/dark setting.
    public var colorScheme: ColorScheme?

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public struct Palette: Sendable, Equatable {
        /// Brand color: tint for controls, selection, progress.
        public var accent: Color
        public var background: Color
        public var surface: Color
        public var textPrimary: Color
        public var textSecondary: Color
        public var separator: Color
        /// Placeholder tones for artwork that hasn't loaded yet.
        public var artworkPlaceholder: [Color]
    }

    /// Built on Dynamic Type text styles so every token scales with the user's text size (HIG).
    public struct Typography: Sendable, Equatable {
        /// Centered wordmark in the Home navigation bar.
        public var wordmark: Font
        public var largeTitle: Font
        public var title: Font
        public var sectionHeader: Font
        public var body: Font
        public var itemTitle: Font
        public var itemSubtitle: Font
        public var caption: Font
        public var nowPlayingTitle: Font
        public var nowPlayingSubtitle: Font
        public var code: Font
    }

    public struct Spacing: Sendable, Equatable {
        public var xxs: CGFloat = 2
        public var xs: CGFloat = 4
        public var sm: CGFloat = 8
        public var md: CGFloat = 12
        public var lg: CGFloat = 16
        public var xl: CGFloat = 24
        public var xxl: CGFloat = 32
        /// Leading/trailing inset for scrolling content (matches system list margins).
        public var screenInset: CGFloat = 20
    }

    public struct Radius: Sendable, Equatable {
        public var small: CGFloat = 6
        /// Album art corner radius. 0 = square covers.
        public var artwork: CGFloat = 0
        public var card: CGFloat = 16
        public var sheet: CGFloat = 28
    }

    public struct Artwork: Sendable, Equatable {
        /// Width of album tiles in horizontal shelves.
        public var shelfTileWidth: CGFloat = 156
        /// Leading thumbnail in track rows.
        public var rowThumbnail: CGFloat = 44
        public var miniPlayerThumbnail: CGFloat = 36
        public var shadowRadius: CGFloat = 12
        public var shadowOpacity: Double = 0.18
    }
}

// MARK: - Built-in themes

public extension Theme {
    /// Default brand: near-black canvas, white type, Familjen Grotesk throughout.
    static let wavetile = Theme(
        id: "wavetile",
        name: "Wavetile",
        palette: .init(
            accent: Color(hex: 0xE00909),
            background: Color(hex: 0x151515),
            surface: Color(hex: 0x222222),
            textPrimary: .white,
            textSecondary: .white.opacity(0.6),
            separator: .white.opacity(0.12),
            artworkPlaceholder: [Color(hex: 0x2A2A2A), Color(hex: 0x1E1E1E)]
        ),
        typography: .init(
            wordmark: BrandFont.font(.title2, weight: .bold),
            largeTitle: BrandFont.font(.largeTitle, weight: .bold),
            title: BrandFont.font(.title2, weight: .bold),
            sectionHeader: BrandFont.font(.title3, weight: .semibold),
            body: BrandFont.font(.body),
            itemTitle: BrandFont.font(.subheadline, weight: .medium),
            itemSubtitle: BrandFont.font(.subheadline),
            caption: BrandFont.font(.caption),
            nowPlayingTitle: BrandFont.font(.title2, weight: .bold),
            nowPlayingSubtitle: BrandFont.font(.title3),
            code: .system(.largeTitle, design: .monospaced).weight(.semibold)
        ),
        spacing: .init(),
        radius: .init(),
        artwork: .init(),
        motion: .standard,
        colorScheme: .dark
    )

    /// Alternate theme to prove tokens are swappable; tweak or delete freely.
    static let midnight: Theme = {
        var theme = Theme.wavetile
        theme.id = "midnight"
        theme.name = "Midnight"
        theme.palette.accent = Color(red: 0.45, green: 0.55, blue: 1.0)
        theme.palette.background = Color(hex: 0x0B0E1A)
        theme.palette.surface = Color(hex: 0x161B2E)
        theme.typography.wordmark = .system(.title2, design: .rounded).bold()
        theme.typography.largeTitle = .system(.largeTitle, design: .rounded).bold()
        theme.typography.title = .system(.title2, design: .rounded).bold()
        theme.typography.sectionHeader = .system(.title3, design: .rounded).weight(.semibold)
        theme.typography.nowPlayingTitle = .system(.title2, design: .rounded).weight(.heavy)
        theme.radius.artwork = 16
        theme.motion = .playful
        return theme
    }()

    static let all: [Theme] = [.wavetile, .midnight]
}

public extension EnvironmentValues {
    @Entry var theme: Theme = .wavetile
}

public extension Color {
    /// `Color(hex: 0x151515)`: sRGB from a 24-bit hex literal, matching design-tool values.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

public extension View {
    /// Fills the screen with the theme background behind scrolling content, lists and forms.
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}

private struct ThemedBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.palette.background.ignoresSafeArea())
    }
}
