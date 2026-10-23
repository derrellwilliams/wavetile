import DesignSystem
import Foundation
import JellyfinKit

/// Deterministic sample data so every screen can be previewed and hot-reloaded without a server.
public enum Fixtures {
    public static let session = ServerSession(
        serverURL: URL(string: "https://music.example.com")!,
        serverID: "preview-server",
        serverName: "Home Server",
        userID: "preview-user",
        userName: "Derrell"
    )

    public static let albums: [AlbumSummary] = [
        ("In Rainbows", "Radiohead", 2007),
        ("Blonde", "Frank Ocean", 2016),
        ("Currents", "Tame Impala", 2015),
        ("To Pimp a Butterfly", "Kendrick Lamar", 2015),
        ("Random Access Memories", "Daft Punk", 2013),
        ("Vespertine", "Björk", 2001),
        ("Kid A", "Radiohead", 2000),
        ("Punisher", "Phoebe Bridgers", 2020),
        ("Since I Left You", "The Avalanches", 2000),
        ("Madvillainy", "Madvillain", 2004),
    ].enumerated().map { index, album in
        AlbumSummary(id: "album-\(index)", title: album.0, artist: album.1, year: album.2, playCount: 40 - index * 3)
    }

    public static let tracks: [TrackSummary] = [
        ("15 Step", 237), ("Bodysnatchers", 242), ("Nude", 255), ("Weird Fishes/Arpeggi", 318),
        ("All I Need", 228), ("Faust Arp", 129), ("Reckoner", 290), ("House of Cards", 328),
        ("Jigsaw Falling into Place", 249), ("Videotape", 279),
    ].enumerated().map { index, track in
        TrackSummary(id: "track-\(index)", title: track.0, artist: "Radiohead", trackNumber: index + 1, discNumber: 1, duration: .seconds(track.1))
    }

    /// Placeholder art keyed to the album so the same album always gets the same colors.
    public static func artwork(for album: AlbumSummary) -> ArtworkSource {
        .placeholder(seed: albums.firstIndex(of: album) ?? album.id.count)
    }
}
