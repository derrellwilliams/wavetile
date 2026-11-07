import DesignSystem
import Podcasts
import SwiftUI

/// A tile on the Podcasts tab's Recommended for You shelf: opens the show to preview and follow it. The
/// subtitle says why it's suggested, and Not Interested keeps it from coming back.
struct RecommendedShowLink: View {
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(\.zoomNamespace) private var zoom
    let show: RecommendedShow

    private var sourceID: String { "recommended-\(show.directoryID)" }

    var body: some View {
        NavigationLink(value: PodcastRoute.show(route)) {
            ShowTile(title: show.title, subtitle: show.reason, artworkURL: show.artworkURL)
                .zoomSource(sourceID, in: zoom)
        }
        .buttonStyle(.pressable)
        .contextMenu {
            Button("Not Interested", glyph: .close) { podcasts.dismissRecommendation(show) }
        }
    }

    private var route: ShowRoute {
        var route = ShowRoute(feedURL: show.feedURL, title: show.title, author: show.author, artworkURL: show.artworkURL)
        route.sourceID = sourceID
        return route
    }
}
