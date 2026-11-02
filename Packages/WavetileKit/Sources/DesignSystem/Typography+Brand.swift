import CoreText
import SwiftUI
import UIKit

/// Brand typefaces, bundled in `Resources/Fonts` (SIL OFL 1.1, see the OFL files).
///
/// `family` is Inter, Regular only, so every weight resolves to it; `monoFamily` is Geist Mono
/// Regular (there's no Inter Mono). One weight throughout keeps the type even.
/// To change a font: drop new .ttf/.otf files in `Resources/Fonts` and update the family name.
public enum BrandFont {
    public static let family = "Inter"
    public static let monoFamily = "Geist Mono"
    /// PostScript names, for fixed faces (the wordmark, screen titles, Home's feed).
    public static let regularName = "Inter-Regular"
    public static let monoName = "GeistMono-Regular"

    /// Registers bundled fonts with the process. Packages can't use `UIAppFonts`, so this
    /// runs once at launch (`RootView` calls it); repeated calls are no-ops.
    public static func register() {
        _ = registration
    }

    private static let registration: Void = {
        let urls = (Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.module.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Brand font that scales with Dynamic Type relative to `style`. `size` overrides the style's default size.
    /// One weight only (Regular), so there's no weight parameter.
    public static func font(_ style: Font.TextStyle, size: CGFloat? = nil, family: String = family) -> Font {
        .custom(family, size: size ?? defaultSize(style), relativeTo: style)
    }

    /// Fixed-size brand font for graphics that must fit a shape (logo, avatars, badges), not body text.
    public static func font(fixedSize size: CGFloat, family: String = family) -> Font {
        .custom(family, fixedSize: size)
    }

    /// UIKit equivalent for appearance proxies (navigation bar titles).
    public static func uiFont(_ style: UIFont.TextStyle, weight: UIFont.Weight, family: String = family) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        let base = UIFont(descriptor: descriptor, size: UIFont.preferredFont(forTextStyle: style, compatibleWith: .init(preferredContentSizeCategory: .large)).pointSize)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    /// Navigation bar titles can't be styled from SwiftUI, so use the appearance proxy. The
    /// proxy is set once, so the color resolves per bar from its interface style (which follows
    /// the selected theme), and switching Dark/Light in Settings recolors titles at once.
    public static func applyNavigationBarAppearance() {
        _ = textSizeObserver
        let dark = UIColor(Theme.dark.palette.textPrimary), light = UIColor(Theme.light.palette.textPrimary)
        let darkSubtle = UIColor(Theme.dark.palette.textSecondary), lightSubtle = UIColor(Theme.light.palette.textSecondary)
        applyNavigationBarAppearance(
            textColor: UIColor { $0.userInterfaceStyle == .light ? light : dark },
            subtleColor: UIColor { $0.userInterfaceStyle == .light ? lightSubtle : darkSubtle }
        )
    }

    public static func applyNavigationBarAppearance(textColor: UIColor, subtleColor: UIColor) {
        // Screen titles (Music, Podcasts, Downloaded, Search) in Inter Regular 36, scaling with
        // Dynamic Type; negative kerning on them (size-specific tracking), a lighter touch inline.
        let largeTitle = UIFont(name: regularName, size: 36).map { UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: $0) }
            ?? uiFont(.largeTitle, weight: .regular)
        // The bar has no title insets, so a taller line adds room above and below the title (a
        // taller line puts all its extra room above the text; the offset lifts it back to the middle).
        let spacing = NSMutableParagraphStyle()
        spacing.minimumLineHeight = largeTitle.lineHeight + largeTitlePadding * 2
        spacing.maximumLineHeight = spacing.minimumLineHeight
        largeTitleAttributes = [
            .font: largeTitle, .foregroundColor: textColor, .kern: Theme.dark.typography.displayTracking,
            .paragraphStyle: spacing, .baselineOffset: largeTitlePadding,
        ]
        titleAttributes = [.font: uiFont(.headline, weight: .regular), .foregroundColor: textColor]
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = largeTitleAttributes
        bar.titleTextAttributes = titleAttributes
        // Tab bar labels: the system's own small size, in Inter; the subtle tan, the main tan when selected.
        if let label = UIFont(name: regularName, size: 10) {
            let item = UITabBarItem.appearance()
            item.setTitleTextAttributes([.font: label, .foregroundColor: subtleColor], for: .normal)
            item.setTitleTextAttributes([.font: label, .foregroundColor: textColor], for: .selected)
            UITabBar.appearance().unselectedItemTintColor = subtleColor
            // The floating tab bar reads its labels from the bar's appearance, not the item proxy.
            let tabs = UITabBarAppearance()
            tabs.configureWithDefaultBackground()
            for layout in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
                layout.normal.titleTextAttributes = [.font: label, .foregroundColor: subtleColor]
                layout.normal.iconColor = subtleColor
                layout.selected.titleTextAttributes = [.font: label, .foregroundColor: textColor]
                layout.selected.iconColor = textColor
            }
            UITabBar.appearance().standardAppearance = tabs
            UITabBar.appearance().scrollEdgeAppearance = tabs
        }
    }

    /// Extra room above and below the large screen titles.
    static let largeTitlePadding: CGFloat = 12

    /// Re-applies the bar fonts when Text Size changes: they're scaled once when built, so they'd
    /// otherwise keep the launch size. Bars pick them up as they next lay out (`TintedSystemBack`).
    private static let textSizeObserver: any NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main
    ) { _ in
        MainActor.assumeIsolated { applyNavigationBarAppearance() }
    }

    /// The bar title attributes, for appearances SwiftUI makes per bar (which ignore the proxy).
    public private(set) static var largeTitleAttributes: [NSAttributedString.Key: Any] = [:]
    public private(set) static var titleAttributes: [NSAttributedString.Key: Any] = [:]

    /// Each text style's size on the type scale (`Theme.Typography.scale`) at the standard
    /// ("Large") content size category, so even a bare style lands on one of the seven sizes.
    private static func defaultSize(_ style: Font.TextStyle) -> CGFloat {
        let scale = Theme.Typography.scale
        switch style {
        case .largeTitle: return scale.display
        case .title, .title2: return scale.title
        case .title3: return scale.lead
        case .headline, .body, .callout: return scale.body
        case .subheadline, .footnote: return scale.small
        case .caption, .caption2: return scale.caption
        @unknown default: return scale.body
        }
    }
}
