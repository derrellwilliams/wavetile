import Foundation
import GRDB
import Testing
@testable import Persistence

/// Guards query speed on a large library (50k tracks, 5k albums, 2k artists).
/// Budgets are generous for CI/simulator variance; the printed timings are the real signal.
@Suite(.serialized)
struct LibraryPerformanceTests {
    static let trackCount = 50_000
    static let albumCount = 5_000
    static let artistCount = 2_000

    static let database: LibraryDatabase = {
        let db = try! LibraryDatabase.temporary()
        let words = ["night", "river", "glass", "echo", "summer", "static", "velvet", "north", "paper", "gold", "ghost", "neon"]
        try! db.pool.write { db in
            for a in 0 ..< artistCount {
                try ArtistRecord(id: "ar\(a)", name: "Artist \(a)", sortName: "artist \(a)", imageTag: nil, generation: 1).insert(db)
            }
            for a in 0 ..< albumCount {
                try AlbumRecord(
                    id: "al\(a)", title: "\(words[a % words.count].capitalized) \(a)", sortTitle: "\(words[a % words.count]) \(a)",
                    artistName: "Artist \(a % artistCount)", artistID: "ar\(a % artistCount)", year: 1960 + a % 60,
                    imageTag: nil, dateAdded: Date(timeIntervalSince1970: Double(a) * 3600), generation: 1
                ).insert(db)
                try AlbumGenreRecord(albumID: "al\(a)", genre: ["Rock", "Jazz", "Hip-Hop", "Folk", "Electronic"][a % 5]).insert(db)
            }
            for t in 0 ..< trackCount {
                let title = "\(words[t % words.count].capitalized) \(words[(t / 7) % words.count]) \(t)"
                try TrackRecord(
                    id: "t\(t)", title: title, sortTitle: title.lowercased(), albumID: "al\(t % albumCount)", albumTitle: "Album \(t % albumCount)",
                    artistName: "Artist \(t % artistCount)", albumArtistName: "Artist \(t % artistCount)", trackNumber: t % 12 + 1, discNumber: 1,
                    durationMs: 200_000, playCount: t % 17 == 0 ? t % 40 : 0, isFavorite: t % 50 == 0,
                    lastPlayed: t % 13 == 0 ? Date(timeIntervalSince1970: Double(t) * 60) : nil, dateAdded: nil, container: "flac", generation: 1
                ).insert(db)
            }
        }
        return db
    }()

    func measure(_ label: String, budget: Duration, _ work: () throws -> Void) rethrows {
        let elapsed = try ContinuousClock().measure(work)
        print("⏱ \(label): \(elapsed.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1))))")
        #expect(elapsed < budget, "\(label) took \(elapsed), budget \(budget)")
    }

    @Test func searchIsInteractive() throws {
        let db = Self.database
        try measure("search 'vel'", budget: .milliseconds(50)) { _ = try db.search("vel") }
        try measure("search 'echo riv'", budget: .milliseconds(50)) { _ = try db.search("echo riv") }
        #expect(try !db.search("velvet").tracks.isEmpty)
    }

    @Test func homeShelvesAreFast() throws {
        let db = Self.database
        try measure("recently played albums", budget: .milliseconds(100)) { _ = try db.recentlyPlayedAlbums() }
        try measure("most played albums", budget: .milliseconds(100)) { _ = try db.mostPlayedAlbums() }
        try measure("recently added albums", budget: .milliseconds(20)) { _ = try db.recentlyAddedAlbums() }
    }

    @Test func browseQueriesAreFast() async throws {
        let db = Self.database
        try await measureFirst("all 50k songs", db.allTracks(), budget: .milliseconds(1000))
        try measure("album tracks", budget: .milliseconds(10)) { _ = try db.tracks(albumID: "al42") }
        try await measureFirst("albums by genre", db.albums(genre: "Jazz"), budget: .milliseconds(100))
        try await measureFirst("all artists", db.artists(), budget: .milliseconds(100))
    }

    /// Times how long an observation takes to deliver its first value.
    func measureFirst<T: Sendable>(_ label: String, _ observation: ValueObservation<ValueReducers.Fetch<T>>, budget: Duration) async throws {
        let db = Self.database
        let start = ContinuousClock.now
        for try await _ in observation.values(in: db.pool) { break }
        let elapsed = ContinuousClock.now - start
        print("⏱ \(label): \(elapsed.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1))))")
        #expect(elapsed < budget, "\(label) took \(elapsed), budget \(budget)")
    }
}
