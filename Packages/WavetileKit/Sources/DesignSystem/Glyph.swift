import SwiftUI

/// App iconography: Phosphor Bold (https://phosphoricons.com), bundled as 24pt template vectors
/// in `Resources/Icons.xcassets`.
///
/// Views use semantic names (`.library`), never asset names, so swapping an icon or the whole
/// set is a one-line change here. To add one: put its Phosphor name in `scripts/fetch-icons.sh`,
/// run the script, and add a case.
public enum Glyph: String, CaseIterable, Sendable {
    case home = "house"
    case library = "stack"
    case downloads = "box-arrow-down"
    case search = "magnifying-glass"
    case profile = "user-circle"
    case playlist
    case artist = "microphone-stage"
    case album = "vinyl-record"
    case song = "music-note"
    case genre = "guitar"
    case waveform
    case warning
    case lockOpen = "lock-open"
    case lock
    case copy
    case check
    case play
    case pause
    case next = "skip-forward"
    case previous = "skip-back"
    case settings = "gear-six"
    case signOut = "sign-out"
    case appearance = "palette"
    case server = "hard-drives"
    case address = "globe"
    case close = "x"
    case shuffle
    case sort = "sort-ascending"
    case chevron = "caret-right"
    case `repeat`
    case repeatOne = "repeat-once"
    case queue
    case dismiss = "caret-down"
    case airplay = "speaker-hifi"
    case more = "dots-three"
    case addToQueue = "list-plus"
    case playNext = "arrow-bend-down-right"
    case downloaded = "check-circle"
    case offline = "cloud-slash"
    case trash
    case download = "download-simple"
    case favorite = "heart"
    case favoriteFilled = "heart-fill"
    case collection = "squares-four"
    case add = "plus"
    case edit = "pencil-simple"
    case user

    /// 24pt template image; tints with `foregroundStyle`. Add `.resizable()` for other sizes.
    /// Decorative: VoiceOver skips it (otherwise it reads asset names like "magnifying-glass").
    /// Meaning comes from the surrounding `Label`, button title, or an explicit accessibility label.
    public var image: Image {
        Image(decorative: rawValue, bundle: .module)
    }

    /// The glyph with an accessibility label, for icon-only controls.
    public func image(label: String) -> Image {
        Image(rawValue, bundle: .module, label: Text(label))
    }

    /// The glyph with its color baked in, for places that recolor template images on their own
    /// (the glass tab bar forces its item colors and ignores `.tint` and appearance proxies).
    /// Decorative like `image`; pair it with a title.
    public func image(color: Color) -> Image {
        guard let base = UIImage(named: rawValue, in: .module, with: nil) else { return image }
        return Image(uiImage: base.withTintColor(UIColor(color), renderingMode: .alwaysOriginal))
    }
}

public extension Label where Title == Text, Icon == Image {
    /// `Label("Library", glyph: .library)`: the Phosphor equivalent of `Label(_:systemImage:)`.
    init(_ title: String, glyph: Glyph) {
        // Labeled icon so `.labelStyle(.iconOnly)` buttons still have a VoiceOver name.
        self.init { Text(title) } icon: { glyph.image(label: title) }
    }
}

public extension Button where Label == SwiftUI.Label<Text, Image> {
    /// `Button("Settings", glyph: .profile) { ... }`: the Phosphor equivalent of `Button(_:systemImage:action:)`.
    init(_ title: String, glyph: Glyph, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, glyph: glyph) }
    }
}

/// White title with a tan (accent) icon, for text buttons like "New Playlist" and "Sign Out".
public struct TintedIconLabelStyle: LabelStyle {
    @Environment(\.theme) private var theme

    public func makeBody(configuration: Configuration) -> some View {
        SwiftUI.Label {
            configuration.title.foregroundStyle(theme.palette.textPrimary)
        } icon: {
            configuration.icon.foregroundStyle(theme.palette.accent)
        }
    }
}

public extension LabelStyle where Self == TintedIconLabelStyle {
    static var tintedIcon: TintedIconLabelStyle { .init() }
}

/// Icon-only button at an arbitrary size (Phosphor assets are 24pt templates).
/// Keeps a 44pt minimum hit target and an accessibility label.
public struct GlyphButton: View {
    private let title: String
    private let glyph: Glyph
    private let size: CGFloat
    private let action: () -> Void

    public init(_ title: String, glyph: Glyph, size: CGFloat = 24, action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            glyph.image
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(title)
    }
}

/// Empty and error states with a large Phosphor glyph (replaces `ContentUnavailableView(_:systemImage:)`).
public struct EmptyState<Actions: View>: View {
    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 48
    private let title: String
    private let glyph: Glyph
    private let message: String?
    private let actions: Actions

    public init(_ title: String, glyph: Glyph, message: String? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.glyph = glyph
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        ContentUnavailableView {
            SwiftUI.Label {
                // System copy, so the text face; Stack Sans Notch is for screen and content titles.
                Text(title).font(BrandFont.font(.title2, weight: .bold))
            } icon: {
                glyph.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: glyphSize, height: glyphSize)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        } description: {
            if let message {
                Text(message).font(theme.typography.body)
            }
        } actions: {
            actions
        }
    }
}

public extension View {
    /// Gentle opacity pulse for "live" indicators (now playing, waiting). Off with Reduce Motion.
    func pulsing(_ active: Bool = true) -> some View {
        modifier(Pulsing(active: active))
    }
}

private struct Pulsing: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.phaseAnimator([1.0, 0.35]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            content
        }
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 20) {
            ForEach(Glyph.allCases, id: \.self) { glyph in
                VStack(spacing: 6) {
                    glyph.image
                    Text(String(describing: glyph)).font(.caption2)
                }
            }
        }
        .padding()
    }
}
