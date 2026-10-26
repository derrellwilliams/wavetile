import DesignSystem
import Podcasts
import SwiftUI

/// Every podcast destination, shared by the Podcasts, Search and Downloaded stacks.
enum PodcastRoute: Hashable {
    case show(ShowRoute)
    case episode(id: String)
    case list(EpisodeList)
    case shows
    case topShows
}

/// Enough to draw a show's header immediately, before its feed loads.
struct ShowRoute: Hashable {
    var feedURL: URL
    var title: String
    var author: String
    var artworkURL: URL?

    init(feedURL: URL, title: String, author: String, artworkURL: URL?) {
        self.feedURL = feedURL
        self.title = title
        self.author = author
        self.artworkURL = artworkURL
    }

    init(_ show: ShowRecord) {
        self.init(feedURL: show.feedURL, title: show.title, author: show.author, artworkURL: show.artworkURL)
    }

    init?(_ show: DirectoryShow) {
        guard let feedURL = show.feedURL else { return nil }
        self.init(feedURL: feedURL, title: show.title, author: show.author, artworkURL: show.artworkURL)
    }
}

enum EpisodeList: String, CaseIterable, Hashable {
    case latest, saved, downloaded, history

    var title: String {
        switch self {
        case .latest: "Latest Episodes"
        case .saved: "Saved"
        case .downloaded: "Downloaded"
        case .history: "Recently Played"
        }
    }

    var glyph: Glyph {
        switch self {
        case .latest: .podcasts
        case .saved: .save
        case .downloaded: .downloads
        case .history: .history
        }
    }
}

extension EnvironmentValues {
    /// Jumps to Search with the Podcasts filter selected.
    @Entry var openPodcastSearch: () -> Void = {}
    /// Pushes a podcast route on the current tab's stack (menus can't hold a NavigationLink).
    @Entry var pushPodcastRoute: (PodcastRoute) -> Void = { _ in }
}

extension View {
    /// Registers `PodcastRoute` destinations on a tab's root screen. `push` appends to the
    /// stack's path so menus anywhere in it can navigate.
    func podcastDestinations(push: @escaping (PodcastRoute) -> Void) -> some View {
        environment(\.pushPodcastRoute, push)
            .navigationDestination(for: PodcastRoute.self) { route in
                PodcastDestination(route: route)
                    .environment(\.pushPodcastRoute, push)
            }
    }
}

private struct PodcastDestination: View {
    let route: PodcastRoute

    var body: some View {
        switch route {
        case let .show(show):
            ShowDetailView(route: show)
        case let .episode(id):
            EpisodeDetailView(episodeID: id)
        case let .list(list):
            EpisodeListView(list: list)
        case .shows:
            AllShowsView()
        case .topShows:
            TopShowsView()
        }
    }
}

/// Display formatting shared by episode rows, cards and detail pages.
enum EpisodeFormat {
    /// "1h 5m", "42m", "30s".
    static func length(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    /// What the play pill says: "45m", "12m left", "Played".
    static func status(_ episode: EpisodeRecord) -> String {
        if episode.isPlayed { return "Played" }
        if episode.isInProgress, let remaining = episode.remaining { return "\(length(remaining)) left" }
        return episode.duration.map(length) ?? "Play"
    }

    /// "Today", "Yesterday", "Tuesday", "Oct 5", "Oct 5, 2024".
    static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
