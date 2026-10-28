import SwiftUI

/// Every visual decision in the app flows from a `Theme`.
///
/// To rebrand: edit `Theme.dark` below, or add a new static theme and pick it in
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
        /// The faint accent wash behind tinted buttons, and the deeper one while pressed.
        public var tint: Color { accent.opacity(0.12) }
        /// Switch "on" color. Neutral gray in both themes: a tan or near-black tint would hide
        /// the knob or read as off.
        public var toggle = Color(hex: 0x6E6E73)
        public var tintPressed: Color { accent.opacity(0.2) }
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
        /// Bold text-face heading: the Now Playing title, the welcome greeting, About sheet sections.
        public var headline: Font
        /// Larger reading text: the Now Playing artist, the About sheet, a detail page's artist or show.
        public var lead: Font
        public var code: Font
        /// Letter-spacing for large display titles: big type reads loose, so it's tightened.
        /// (Body text stays at 0; system fonts do this automatically, custom faces don't.)
        public var displayTracking: CGFloat = -0.5
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
        public var shelfTileWidth: CGFloat = 148
        /// Leading thumbnail in track rows.
        public var rowThumbnail: CGFloat = 44
        public var miniPlayerThumbnail: CGFloat = 36
        public var shadowRadius: CGFloat = 12
        public var shadowOpacity: Double = 0.18
    }
}

// MARK: - Built-in themes

public extension Theme {
    /// Default brand: #1A1A1A canvas, light tan (#ECE4D2) type, logo, icons and controls,
    /// Stack Sans Notch for the logo and titles, Familjen Grotesk for text.
    /// The id stays "wavetile" so existing saved theme choices still resolve.
    static let dark = Theme(
        id: "wavetile",
        name: "Dark",
        palette: .init(
            accent: Color(hex: 0xECE4D2),
            background: Color(hex: 0x1A1A1A),
            surface: Color(hex: 0x262626),
            textPrimary: Color(hex: 0xECE4D2),
            textSecondary: Color(hex: 0xECE4D2).opacity(0.6),
            separator: .white.opacity(0.12),
            artworkPlaceholder: [Color(hex: 0x2E2E2E), Color(hex: 0x222222)]
        ),
        typography: .init(
            // Logo: fixed size (a mark, not text). 30pt is the largest that sits cleanly in the 44pt bar.
            wordmark: BrandFont.font(fixedSize: 32, weight: .bold, family: BrandFont.displayFamily),
            largeTitle: BrandFont.display(.largeTitle),
            title: BrandFont.display(.title2),
            sectionHeader: BrandFont.font(.title3, weight: .semibold),
            body: BrandFont.font(.body),
            itemTitle: BrandFont.font(.subheadline, weight: .medium),
            itemSubtitle: BrandFont.font(.subheadline),
            caption: BrandFont.font(.caption),
            headline: BrandFont.font(.title2, weight: .bold),
            lead: BrandFont.font(.title3),
            code: .system(.largeTitle, design: .monospaced).weight(.semibold)
        ),
        spacing: .init(),
        radius: .init(),
        artwork: .init(),
        motion: .standard,
        colorScheme: .dark
    )

    /// Light: the Dark theme inverted. Tan (#ECE4D2) canvas with #1A1A1A type, logo, icons and
    /// controls; same fonts, spacing and motion.
    static let light: Theme = {
        var theme = Theme.dark
        theme.id = "light"
        theme.name = "Light"
        theme.palette.accent = Color(hex: 0x1A1A1A)
        theme.palette.background = Color(hex: 0xECE4D2)
        theme.palette.surface = Color(hex: 0xE0D7C3)
        theme.palette.textPrimary = Color(hex: 0x1A1A1A)
        theme.palette.textSecondary = Color(hex: 0x262626).opacity(0.6)
        theme.palette.separator = .black.opacity(0.12)
        theme.palette.artworkPlaceholder = [Color(hex: 0xD9CFB9), Color(hex: 0xE3DAC6)]
        theme.colorScheme = .light
        return theme
    }()

    static let all: [Theme] = [.dark, .light]
}

public extension EnvironmentValues {
    @Entry var theme: Theme = .dark
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
