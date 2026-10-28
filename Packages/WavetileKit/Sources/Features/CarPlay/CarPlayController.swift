import CarPlay
import DesignSystem
import Persistence
import Playback
import Podcasts

/// CarPlay: tabs for Home (recently and most played), Playlists, Library (albums and artists)
/// and, when podcasts are on, Up Next. Picking something plays it and shows the system
/// Now Playing screen, which reads the same Now Playing info and remote commands as the
/// Lock Screen.
///
/// CarPlay only lists the app once Apple grants the CarPlay audio entitlement
/// (`com.apple.developer.carplay-audio`) and it's added to `App/Wavetile.entitlements`.
public final class CarPlayController {
    private let interface: CPInterfaceController
    private let app: AppModel
    private let connectivity = Connectivity()
    /// Long lists are cut off here; CarPlay limits list length while driving anyway.
    private let listLimit = 200

    public init(interface: CPInterfaceController, app: AppModel) {
        self.interface = interface
        self.app = app
    }

    public func connect() {
        interface.setRootTemplate(rootTemplate(), animated: false, completion: nil)
    }

    private var signedIn: AppModel.SignedIn? {
        if case let .signedIn(signedIn) = app.phase { return signedIn }
        return nil
    }

    private func rootTemplate() -> CPTemplate {
        guard let signedIn else {
            let template = CPListTemplate(title: "Wavetile", sections: [])
            template.emptyViewTitleVariants = ["Sign in on your iPhone"]
            template.emptyViewSubtitleVariants = ["Open Wavetile on your iPhone to connect to Jellyfin."]
            return template
        }
        var tabs = [homeTab(signedIn), playlistsTab(signedIn), libraryTab(signedIn)]
        if signedIn.podcasts.isEnabled { tabs.append(podcastsTab(signedIn)) }
        return CPTabBarTemplate(templates: tabs)
    }

    // MARK: - Tabs

    private func homeTab(_ signedIn: AppModel.SignedIn) -> CPListTemplate {
        let database = signedIn.library.database
        let recent = (try? database.recentlyPlayedAlbums(limit: 24)) ?? []
        let most = (try? database.mostPlayedAlbums(limit: 24)) ?? []
        let sections = [
            CPListSection(items: recent.map { albumItem($0, signedIn) }, header: "Recently Played", sectionIndexTitle: nil),
            CPListSection(items: most.map { albumItem($0, signedIn) }, header: "Most Played", sectionIndexTitle: nil),
        ].filter { !$0.items.isEmpty }
        let template = CPListTemplate(title: "Home", sections: sections)
        template.tabTitle = "Home"
        template.tabImage = Glyph.home.uiImage
        template.emptyViewTitleVariants = ["Nothing played yet"]
        return template
    }

    private func playlistsTab(_ signedIn: AppModel.SignedIn) -> CPListTemplate {
        let playlists = (try? signedIn.library.database.playlistList()) ?? []
        let items = playlists.prefix(listLimit).map { playlist in
            let item = CPListItem(text: playlist.name, detailText: "\(playlist.trackCount) songs")
            loadImage(item, itemID: playlist.id, tag: playlist.imageTag, signedIn)
            item.handler = { [weak self] _, completion in
                self?.play((try? signedIn.library.database.tracks(playlistID: playlist.id)) ?? [], signedIn)
                completion()
            }
            return item
        }
        let template = CPListTemplate(title: "Playlists", sections: [CPListSection(items: Array(items))])
        template.tabTitle = "Playlists"
        template.tabImage = Glyph.playlist.uiImage
        template.emptyViewTitleVariants = ["No playlists"]
        return template
    }

    private func libraryTab(_ signedIn: AppModel.SignedIn) -> CPListTemplate {
        let albums = CPListItem(text: "Albums", detailText: nil)
        albums.accessoryType = .disclosureIndicator
        albums.handler = { [weak self] _, completion in
            guard let self else { return completion() }
            let records = (try? signedIn.library.database.albumList(limit: listLimit)) ?? []
            push(CPListTemplate(title: "Albums", sections: [CPListSection(items: records.map { self.albumItem($0, signedIn) })]))
            completion()
        }
        let artists = CPListItem(text: "Artists", detailText: nil)
        artists.accessoryType = .disclosureIndicator
        artists.handler = { [weak self] _, completion in
            guard let self else { return completion() }
            let records = (try? signedIn.library.database.artistList(limit: listLimit)) ?? []
            push(CPListTemplate(title: "Artists", sections: [CPListSection(items: records.map { self.artistItem($0, signedIn) })]))
            completion()
        }
        let template = CPListTemplate(title: "Library", sections: [CPListSection(items: [albums, artists])])
        template.tabTitle = "Library"
        template.tabImage = Glyph.library.uiImage
        return template
    }

    private func podcastsTab(_ signedIn: AppModel.SignedIn) -> CPListTemplate {
        let episodes = (try? signedIn.podcasts.database.upNextShelfNow()) ?? []
        let items = episodes.map { episode in
            let item = CPListItem(text: episode.episode.title, detailText: episode.show.title)
            if let url = episode.artworkURL { loadImage(item, url: url) }
            item.handler = { [weak self] _, completion in
                signedIn.podcasts.play(episode)
                self?.showNowPlaying()
                completion()
            }
            return item
        }
        let template = CPListTemplate(title: "Up Next", sections: [CPListSection(items: items)])
        template.tabTitle = "Podcasts"
        template.tabImage = Glyph.podcasts.uiImage
        template.emptyViewTitleVariants = ["Nothing up next"]
        return template
    }

    // MARK: - Items

    /// An album opens its songs; picking one plays the album from there.
    private func albumItem(_ album: AlbumRecord, _ signedIn: AppModel.SignedIn) -> CPListItem {
        let item = CPListItem(text: album.title, detailText: album.artistName)
        item.accessoryType = .disclosureIndicator
        loadImage(item, itemID: album.id, tag: album.imageTag, signedIn)
        item.handler = { [weak self] _, completion in
            guard let self else { return completion() }
            let tracks = (try? signedIn.library.database.tracks(albumID: album.id)) ?? []
            let rows = tracks.enumerated().map { index, track in
                let row = CPListItem(text: track.title, detailText: track.artistName == album.artistName ? nil : track.artistName)
                row.handler = { [weak self] _, completion in
                    self?.play(tracks, startAt: index, signedIn)
                    completion()
                }
                return row
            }
            let shuffle = CPListItem(text: "Shuffle", detailText: nil, image: Glyph.shuffle.uiImage)
            shuffle.handler = { [weak self] _, completion in
                self?.play(tracks, shuffled: true, signedIn)
                completion()
            }
            push(CPListTemplate(title: album.title, sections: [CPListSection(items: [shuffle]), CPListSection(items: rows)]))
            completion()
        }
        return item
    }

    /// An artist opens Shuffle plus their albums.
    private func artistItem(_ artist: ArtistRecord, _ signedIn: AppModel.SignedIn) -> CPListItem {
        let item = CPListItem(text: artist.name, detailText: nil)
        item.accessoryType = .disclosureIndicator
        loadImage(item, itemID: artist.id, tag: artist.imageTag, signedIn)
        item.handler = { [weak self] _, completion in
            guard let self else { return completion() }
            let shuffle = CPListItem(text: "Shuffle", detailText: nil, image: Glyph.shuffle.uiImage)
            shuffle.handler = { [weak self] _, completion in
                self?.play((try? signedIn.library.database.tracks(artistID: artist.id)) ?? [], shuffled: true, signedIn)
                completion()
            }
            let albums = (try? signedIn.library.database.albumList(artistID: artist.id)) ?? []
            push(CPListTemplate(title: artist.name, sections: [
                CPListSection(items: [shuffle]),
                CPListSection(items: albums.map { self.albumItem($0, signedIn) }),
            ]))
            completion()
        }
        return item
    }

    // MARK: - Playback and navigation

    /// Offline, only downloaded songs are queued, as on the phone.
    private func play(_ tracks: [TrackRecord], startAt index: Int = 0, shuffled: Bool = false, _ signedIn: AppModel.SignedIn) {
        let queue = tracks.map(QueuedTrack.init)
        guard !queue.isEmpty else { return }
        if shuffled {
            signedIn.player.play(queue, shuffled: true)
        } else {
            signedIn.player.play(queue, startAt: index, online: connectivity.isOnline, downloads: signedIn.downloads)
        }
        showNowPlaying()
    }

    private func showNowPlaying() {
        guard interface.topTemplate !== CPNowPlayingTemplate.shared else { return }
        interface.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    private func push(_ template: CPTemplate) {
        interface.pushTemplate(template, animated: true, completion: nil)
    }

    private func loadImage(_ item: CPListItem, itemID: String, tag: String?, _ signedIn: AppModel.SignedIn) {
        guard let url = signedIn.library.api.imageURL(itemID: itemID, tag: tag, maxPixelWidth: 180) else { return }
        loadImage(item, url: url)
    }

    private func loadImage(_ item: CPListItem, url: URL) {
        Task {
            if let image = await ImageCaching.image(for: url) { item.setImage(image) }
        }
    }
}
