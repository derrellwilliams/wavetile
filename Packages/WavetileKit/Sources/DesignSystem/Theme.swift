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
        /// The main tan (in Dark): titles and primary text. Text is only ever this or `textSecondary`,
        /// never white.
        public var textPrimary: Color
        /// The subtle tan: the main tan 60% of the way from the background, as a solid color so it
        /// reads the same over artwork and glass.
        public var textSecondary: Color
        public var separator: Color
        /// Placeholder tones for artwork that hasn't loaded yet.
        public var artworkPlaceholder: [Color]
    }

    /// One weight (Inter Regular), six sizes: 12 · 14 · 18 · 20 · 22 · 36. Hierarchy comes from size,
    /// color and the mono face, never weight. Every token scales with Dynamic Type (HIG).
    public struct Typography: Sendable, Equatable {
        public static let scale = (caption: CGFloat(12), small: CGFloat(14), body: CGFloat(18), lead: CGFloat(20), title: CGFloat(22), display: CGFloat(36))

        /// 36: screen and detail-page titles.
        public var largeTitle: Font
        /// 22: titles inside a screen (Now Playing, sheets, empty states, episodes).
        public var title: Font
        /// 20: shelf and section titles.
        public var sectionHeader: Font
        /// 20: secondary names under a title (a detail page's artist or show, the Now Playing artist).
        public var lead: Font
        /// 18: reading text, rows and buttons.
        public var body: Font
        /// 14: names under artwork and in rows.
        public var itemTitle: Font
        /// 14: the name under an item (artist, author, server) and short notes.
        public var itemSubtitle: Font
        /// 14, mono: metadata under or beside an item (counts, durations, dates, status).
        public var itemMetadata: Font
        /// 12: labels and fine print.
        public var caption: Font
        /// 36, mono: Quick Connect codes.
        public var code: Font
        /// Letter-spacing for 36pt titles: big type reads loose, so it's tightened.
        public var displayTracking: CGFloat = -0.5
        /// Extra space between wrapped lines. Inter sets lines at about 1.21× its size, so text gets
        /// 3pt more (about 1.4× at body size, set app-wide in `RootView`) and titles none (about 1.2×).
        public var textLeading: CGFloat = 3
        public var titleLeading: CGFloat = 0

        /// Metadata (years, counts, durations, times) in the mono face: `.caption` is 12, `.body` 18,
        /// anything else 14.
        public func mono(_ style: Font.TextStyle) -> Font {
            let size = switch style {
            case .caption, .caption2, .footnote: Self.scale.caption
            case .body, .callout, .headline: Self.scale.body
            default: Self.scale.small
            }
            return BrandFont.font(style, size: size, family: BrandFont.monoFamily)
        }
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
    /// Inter throughout; Geist Mono for codes.
    /// The id stays "wavetile" so existing saved theme choices still resolve.
    public static let dark = Theme(
        id: "wavetile",
        name: "Dark",
        palette: .init(
            accent: Color(hex: 0xECE4D2),
            background: Color(hex: 0x1A1A1A),
            surface: Color(hex: 0x262626),
            textPrimary: Color(hex: 0xECE4D2),
            textSecondary: Color(hex: 0x989388),
            separator: Color(hex: 0xECE4D2).opacity(0.12),
            artworkPlaceholder: [Color(hex: 0x2E2E2E), Color(hex: 0x222222)]
        ),
        typography: .init(
            largeTitle: BrandFont.font(.largeTitle, size: 36),
            title: BrandFont.font(.title2, size: 22),
            sectionHeader: BrandFont.font(.title3, size: 20),
            lead: BrandFont.font(.title3, size: 20),
            body: BrandFont.font(.body, size: 18),
            itemTitle: BrandFont.font(.subheadline, size: 14),
            itemSubtitle: BrandFont.font(.subheadline, size: 14),
            itemMetadata: BrandFont.font(.subheadline, size: 14, family: BrandFont.monoFamily),
            caption: BrandFont.font(.caption, size: 12),
            code: BrandFont.font(.largeTitle, size: 36, family: BrandFont.monoFamily)
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
        theme.palette.textSecondary = Color(hex: 0x75726B)
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

/// A text color dimmed when the view is disabled, for a default foreground style that keeps the
/// system's disabled look (a plain color would draw disabled rows at full strength).
public nonisolated struct EnabledAwareColor: ShapeStyle {
    let color: Color

    public init(_ color: Color) {
        self.color = color
    }

    public func resolve(in environment: EnvironmentValues) -> Color {
        environment.isEnabled ? color : color.opacity(0.4)
    }
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
