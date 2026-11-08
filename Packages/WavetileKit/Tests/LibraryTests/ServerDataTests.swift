import Foundation
import GRDB
import Testing
@testable import Library
@testable import Persistence
import JellyfinKit

/// The server's data is untrusted and often incomplete: untagged files, empty arrays, blank
/// names, nonsense durations, hostile search text. None of it may crash, corrupt the cache or
/// show a blank row.
struct ServerDataTests {
    func item(_ id: String? = "x", _ configure: (inout BaseItemDto) -> Void = { _ in }) -> BaseItemDto {
        var item = BaseItemDto()
        item.id = id
        configure(&item)
        return item
    }

    func trackRecord(_ configure: (inout BaseItemDto) -> Void = { _ in }) throws -> TrackRecord {
        try #require(TrackRecord(item: item("x", configure), generation: 1))
    }

    // MARK: Tracks

    @Test func itemsWithoutAnIDAreSkipped() {
        #expect(TrackRecord(item: item(nil), generation: 1) == nil)
        #expect(AlbumRecord(item: item(nil), generation: 1) == nil)
        #expect(ArtistRecord(item: item(nil), generation: 1) == nil)
    }

    @Test func bareTrackGetsPlaceholders() throws {
        let track = try trackRecord()
        #expect(track.title == "Unknown Track")
        #expect(track.artistName == "Unknown Artist")
        #expect(track.albumArtistName == "Unknown Artist")
        #expect(track.albumTitle == "")
        #expect(track.durationMs == nil)
        #expect(track.playCount == 0)
        #expect(track.isFavorite == false)
    }

    @Test func blankNamesFallBackLikeMissingOnes() throws {
        let track = try trackRecord { $0.name = "   \n"; $0.artists = []; $0.albumArtist = "" }
        #expect(track.title == "Unknown Track")
        #expect(track.sortTitle == SortKey.make("Unknown Track"))
        #expect(track.artistName == "Unknown Artist", "an empty artist list is not an empty artist name")
        #expect(track.albumArtistName == "Unknown Artist")
    }

    @Test func artistFallbacksFollowTheBestAvailableName() throws {
        let onlyAlbumArtist = try trackRecord { $0.albumArtist = "Band" }
        #expect(onlyAlbumArtist.artistName == "Band")
        #expect(onlyAlbumArtist.albumArtistName == "Band")

        let onlyArtists = try trackRecord { $0.artists = ["", "First", "Second"] }
        #expect(onlyArtists.artistName == "First, Second")
        #expect(onlyArtists.albumArtistName == "First")

        let both = try trackRecord { $0.artists = ["Guest"]; $0.albumArtist = "Band" }
        #expect(both.artistName == "Guest")
        #expect(both.albumArtistName == "Band")
    }

    @Test func trackSortsByItsTitleNotTheServersSortName() throws {
        let track = try trackRecord { $0.name = "The Song"; $0.sortName = "01 - 02 - The Song" }
        #expect(track.sortTitle == "song")
    }

    @Test func durationsAreClampedAndNeverTrap() throws {
        #expect(try trackRecord { $0.runTimeTicks = 1_800_000_000 }.durationMs == 180_000)
        #expect(try trackRecord { $0.runTimeTicks = 0 }.durationMs == 0)
        #expect(try trackRecord { $0.runTimeTicks = -5_000_000_000 }.durationMs == 0, "negative is bad data")
        #expect(try trackRecord { $0.runTimeTicks = Int.max }.durationMs == ServerDuration.maxMs)
        #expect(try trackRecord { $0.runTimeTicks = Int.min }.durationMs == 0)
    }

    @Test func aHostilePlaylistCannotOverflowItsTotalDuration() {
        let entries = (0..<100_000).compactMap { _ in ServerDuration.milliseconds(ticks: Int.max) }
        #expect(entries.reduce(0, +) == entries.count * ServerDuration.maxMs, "sum is exact; plain `+` would have trapped on raw values")
    }

    @Test func negativePlayCountsAreDropped() throws {
        #expect(try trackRecord { $0.userData = UserItemDataDto(key: "", playCount: -3) }.playCount == 0)
        #expect(try trackRecord { $0.userData = UserItemDataDto(isFavorite: true, key: "", playCount: 12) }.playCount == 12)
    }

    @Test func gainAndAlbumArtCarryOver() throws {
        let track = try trackRecord { $0.normalizationGain = -6.5; $0.albumPrimaryImageTag = "tag1" }
        #expect(track.normalizationGain == -6.5)
        #expect(track.albumImageTag == "tag1")
    }

    @Test func oddTextIsKeptAndSearchable() throws {
        let long = String(repeating: "x", count: 10_000)
        let db = try LibraryDatabase.temporary()
        let records = try [
            trackRecord { $0.id = "t1"; $0.name = "🎵 Ünïcode ♪" },
            trackRecord { $0.id = "t2"; $0.name = long },
            trackRecord { $0.id = "t3"; $0.name = "日本語のタイトル" },
        ]
        _ = try db.pool.write { db in try TrackRecord.upsertChanged(records, in: db) }

        #expect(try db.search("unic").tracks.map(\.id) == ["t1"], "diacritics fold, emoji are ignored")
        let stored = try db.pool.read { try TrackRecord.fetchOne($0, key: "t2") }
        #expect(stored?.title == long, "long titles are stored whole")
        #expect(try db.search("日本").tracks.map(\.id) == ["t3"])
    }

    // MARK: Albums and artists

    @Test func bareAlbumGetsPlaceholders() throws {
        let album = try #require(AlbumRecord(item: item(), generation: 1))
        #expect(album.title == "Unknown Album")
        #expect(album.artistName == "Unknown Artist")
        #expect(album.artistID == nil)
        #expect(album.isFavorite == false)
    }

    @Test func albumArtistFallsBackToTheFirstRealArtist() throws {
        let album = try #require(AlbumRecord(item: item { $0.albumArtist = " "; $0.artists = ["", "Solo", "Other"] }, generation: 1))
        #expect(album.artistName == "Solo")
        let withID = try #require(AlbumRecord(item: item { $0.albumArtists = [NameIDPair(id: "ar1", name: "Band")] }, generation: 1))
        #expect(withID.artistID == "ar1")
        let empty = try #require(AlbumRecord(item: item { $0.albumArtists = [] }, generation: 1))
        #expect(empty.artistID == nil)
    }

    @Test func albumSortsByBlankSafeSortName() throws {
        let album = try #require(AlbumRecord(item: item { $0.name = "The Album"; $0.sortName = "  " }, generation: 1))
        #expect(album.sortTitle == "album")
        let named = try #require(AlbumRecord(item: item { $0.name = "Album"; $0.sortName = "Zed" }, generation: 1))
        #expect(named.sortTitle == "zed")
    }

    @Test func genreTagsAreSplitAndCleaned() {
        let tags = AlbumRecord.genreTags(["Electronic, Classical", "Punk;Rock", "lbl:ANTI-", " ", "", "Hip-Hop/Rap", "R&B", ",,,"])
        #expect(tags == ["Electronic", "Classical", "Punk", "Rock", "Hip-Hop", "Rap", "R&B"])
        #expect(AlbumRecord.genreTags(nil).isEmpty)
        #expect(AlbumRecord.genreTags([]).isEmpty)
    }

    @Test func bareArtistGetsPlaceholders() throws {
        let artist = try #require(ArtistRecord(item: item(), generation: 1))
        #expect(artist.name == "Unknown Artist")
        #expect(artist.sortName == "unknown artist")
        let article = try #require(ArtistRecord(item: item { $0.name = "The Band"; $0.sortName = "" }, generation: 1))
        #expect(article.sortName == "band")
    }

    // MARK: Sort keys

    @Test func sortKeysSurviveOddText() {
        #expect(SortKey.make("") == "")
        #expect(SortKey.make("   ") == "")
        #expect(SortKey.make("The") == "the", "a title that is only an article keeps it")
        #expect(SortKey.make("The  Beatles") == "beatles", "two spaces leave no leading space")
        #expect(SortKey.make("An  Album") == "album")
        #expect(SortKey.make("Beyonce\u{301}") == SortKey.make("Beyoncé"), "composed and decomposed sort together")
        #expect(SortKey.make("ＡＢＣ") == "abc", "full-width letters fold")
        #expect(SortKey.make(String(repeating: "z", count: 100_000)).count == 100_000)
    }

    @Test func sectionsPutNonLatinAndEmptyUnderHash() {
        #expect(SortKey.section("") == "#")
        #expect(SortKey.section("日本") == "#")
        #expect(SortKey.section("😀") == "#")
        #expect(SortKey.section("émile") == "#")
        #expect(SortKey.section("abba") == "A")
    }

    // MARK: Writes

    @Test func duplicateIDsInOnePageLeaveOneRow() throws {
        let db = try LibraryDatabase.temporary()
        let records = try [trackRecord { $0.id = "t1"; $0.name = "First" }, trackRecord { $0.id = "t1"; $0.name = "Second" }]
        _ = try db.pool.write { db in try TrackRecord.upsertChanged(records, in: db) }
        let rows = try db.pool.read { try TrackRecord.fetchAll($0) }
        #expect(rows.count == 1)
        #expect(try db.search("second").tracks.count == 1)
        #expect(try db.search("first").isEmpty, "search matches the stored row, not the overwritten one")
    }

    @Test func anUnchangedPageWritesNothing() throws {
        let db = try LibraryDatabase.temporary()
        let records = try [trackRecord { $0.id = "t1"; $0.name = "A" }, trackRecord { $0.id = "t2"; $0.name = "B" }]
        let first = try db.pool.write { db in try TrackRecord.upsertChanged(records, in: db) }
        let second = try db.pool.write { db in try TrackRecord.upsertChanged(records, in: db) }
        #expect(first == ["t1", "t2"])
        #expect(second.isEmpty)
    }

    @Test func pruneHandlesHostileIDs() throws {
        let db = try LibraryDatabase.temporary()
        let hostile = ["a'b", "'; DROP TABLE track; --", "\"quoted\"", "50%_off", "日本", "😀"]
        let records = try (hostile + ["gone"]).map { id in try trackRecord { $0.id = id; $0.name = "Song \(id.count)" } }
        _ = try db.pool.write { db in try TrackRecord.upsertChanged(records, in: db) }

        try db.pool.write { db in try LibraryDatabase.prune("track", keeping: Set(hostile), in: db) }
        let ids = try db.pool.read { try String.fetchAll($0, sql: "SELECT id FROM track") }
        #expect(Set(ids) == Set(hostile))
        #expect(try db.search("song").tracks.count == hostile.count, "search index followed the deletes")
    }

    // MARK: Search input

    @Test func hostileSearchTextNeverThrowsOrTouchesData() throws {
        let db = try LibraryDatabase.temporary()
        _ = try db.pool.write { db in
            try TrackRecord.upsertChanged([try self.trackRecord { $0.id = "t1"; $0.name = "Nude" }], in: db)
        }
        let inputs = [
            "\"", "\"\"", "*", "**", "NEAR(", "NEAR(a b)", "AND", "OR NOT", "a AND", "a:b", "title:nude", "^", "-", "(", ")", "((",
            "'", "\\", "%", "_", "\n", "\t", " ", "'; DROP TABLE track; --", "' OR 1=1 --", "🎵", "日本", String(repeating: "a", count: 10_000),
            String(repeating: "(", count: 1_000),
        ]
        for input in inputs {
            _ = try db.search(input)
        }
        #expect(try db.search("nude").tracks.map(\.id) == ["t1"])
    }
}
