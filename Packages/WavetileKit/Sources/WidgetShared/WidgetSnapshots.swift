import Foundation

/// Shared container between the app and its widget extension.
public enum AppGroup {
    public static let identifier = "group.com.derrellwilliams.wavetile"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

public enum WidgetKind {
    public static let nowPlaying = "NowPlaying"
    public static let recentlyPlayed = "RecentlyPlayed"
}

/// What the Now Playing widget shows. Written by the app on track/play-state changes.
public struct NowPlayingSnapshot: Codable, Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumID: String?
    public var isPlaying: Bool
    /// File name of a small JPEG in the app group container (widgets can't load URLs).
    public var artworkFile: String?
    public var updatedAt: Date

    public init(title: String, artist: String, album: String, albumID: String?, isPlaying: Bool, artworkFile: String?, updatedAt: Date = Date()) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumID = albumID
        self.isPlaying = isPlaying
        self.artworkFile = artworkFile
        self.updatedAt = updatedAt
    }
}

public struct RecentAlbumSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var artist: String
    public var artworkFile: String?

    public init(id: String, title: String, artist: String, artworkFile: String?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkFile = artworkFile
    }
}

/// JSON + artwork files in the app group. Small, synchronous, and safe to call from widgets.
public enum WidgetStore {
    private static let nowPlayingFile = "now-playing.json"
    private static let recentsFile = "recently-played.json"

    public static func loadNowPlaying() -> NowPlayingSnapshot? { load(nowPlayingFile) }
    public static func saveNowPlaying(_ snapshot: NowPlayingSnapshot?) { save(snapshot, to: nowPlayingFile) }

    public static func loadRecents() -> [RecentAlbumSnapshot] { load(recentsFile) ?? [] }
    public static func saveRecents(_ albums: [RecentAlbumSnapshot]) { save(albums, to: recentsFile) }

    public static func artworkURL(_ name: String) -> URL? {
        AppGroup.containerURL?.appending(path: "Artwork/\(name)")
    }

    /// Stores already-downscaled JPEG data; returns the file name to reference in a snapshot.
    public static func saveArtwork(_ data: Data, id: String) -> String? {
        guard let directory = AppGroup.containerURL?.appending(path: "Artwork", directoryHint: .isDirectory) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(id.filter { $0.isLetter || $0.isNumber }).jpg"
        do {
            try data.write(to: directory.appending(path: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Removes everything (sign out): widgets fall back to their empty state.
    public static func clear() {
        guard let root = AppGroup.containerURL else { return }
        for name in [nowPlayingFile, recentsFile, "Artwork"] {
            try? FileManager.default.removeItem(at: root.appending(path: name))
        }
    }

    private static func load<T: Decodable>(_ name: String) -> T? {
        guard let url = AppGroup.containerURL?.appending(path: name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T?, to name: String) {
        guard let url = AppGroup.containerURL?.appending(path: name) else { return }
        guard let value else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

/// Deep links the widgets open: `wavetile://album/<id>`, `wavetile://now-playing`.
public enum WidgetLink {
    public static func album(_ id: String) -> URL { URL(string: "wavetile://album/\(id)")! }
    public static let nowPlaying = URL(string: "wavetile://now-playing")!
}
