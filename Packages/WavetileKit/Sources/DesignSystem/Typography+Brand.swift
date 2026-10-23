import CoreText
import SwiftUI
import UIKit

/// The brand typeface, bundled in `Resources/Fonts` (SIL OFL 1.1, see OFL.txt).
///
/// To change the app font: drop new .ttf/.otf files in `Resources/Fonts` and update `family`.
public enum BrandFont {
    public static let family = "Familjen Grotesk"

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

    /// Brand font that scales with Dynamic Type relative to `style`.
    public static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom(family, size: defaultSize(style), relativeTo: style).weight(weight)
    }

    /// Fixed-size brand font for graphics that must fit a shape (avatars, badges), not body text.
    public static func font(fixedSize size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(family, fixedSize: size).weight(weight)
    }

    /// UIKit equivalent for appearance proxies (navigation bar titles).
    public static func uiFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        let base = UIFont(descriptor: descriptor, size: UIFont.preferredFont(forTextStyle: style, compatibleWith: .init(preferredContentSizeCategory: .large)).pointSize)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    /// Navigation bar titles can't be styled from SwiftUI, so use the appearance proxy.
    public static func applyNavigationBarAppearance(textColor: UIColor) {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: uiFont(.largeTitle, weight: .bold), .foregroundColor: textColor]
        bar.titleTextAttributes = [.font: uiFont(.headline, weight: .semibold), .foregroundColor: textColor]
    }

    /// Apple's default point sizes at the standard ("Large") content size category.
    private static func defaultSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}
