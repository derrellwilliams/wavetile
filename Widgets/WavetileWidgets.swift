import DesignSystem
import SwiftUI
import WidgetKit
import WidgetShared

@main
struct WavetileWidgets: WidgetBundle {
    init() {
        // Widgets render in this extension's process, so the brand fonts must be registered here too.
        BrandFont.register()
    }

    var body: some Widget {
        NowPlayingWidget()
        RecentlyPlayedWidget()
        DownloadLiveActivity()
    }
}

/// Loads a small artwork JPEG from the app group (widgets can't fetch URLs at render time).
func widgetArtwork(_ file: String?) -> Image? {
    guard let file, let url = WidgetStore.artworkURL(file), let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
    return Image(uiImage: image)
}

/// Square artwork with the brand placeholder.
struct WidgetArtwork: View {
    let file: String?

    var body: some View {
        Color(hex: 0x2E2E2E)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = widgetArtwork(file) {
                    image.resizable().scaledToFill()
                } else {
                    Glyph.song.image.foregroundStyle(.white.opacity(0.4))
                }
            }
            .clipped()
    }
}
