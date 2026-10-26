import Foundation
import GRDB

/// Podcast subscriptions, episodes, listening progress, Up Next and downloads, in a database of
/// their own (one per Jellyfin user), so a music resync or a corrupt library cache never touches them.
///
/// Unlike the music library this is the source of truth for listening state (Jellyfin only
/// holds a mirror; see `PodcastSync`), so it's protected but included in device backups.
public final class PodcastDatabase: Sendable {
    public let pool: DatabasePool

    public static func open(serverID: String, userID: String) throws -> PodcastDatabase {
        let url = try directory().appending(path: "\(safe(serverID))-\(safe(userID)).sqlite")
        return try PodcastDatabase(path: url.path(percentEncoded: false))
    }

    public static func temporary() throws -> PodcastDatabase {
        let url = FileManager.default.temporaryDirectory.appending(path: "podcasts-\(UUID().uuidString).sqlite")
        return try PodcastDatabase(path: url.path(percentEncoded: false))
    }

    /// Removes the database for a session (sign out, or "Remove All Podcast Data").
    public static func delete(serverID: String, userID: String) {
        guard let directory = try? directory() else { return }
        let base = "\(safe(serverID))-\(safe(userID)).sqlite"
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: directory.appending(path: base + suffix))
        }
    }

    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        pool = try DatabasePool(path: path, configuration: config)
        try Self.migrator.migrate(pool)
    }

    private static func directory() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Podcasts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        return directory
    }

    private static func safe(_ id: String) -> String {
        id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // No erase-on-change here: this database holds user data that can't be re-synced.
        migrator.registerMigration("v1") { db in
            try db.create(table: "show") { t in
                t.primaryKey("id", .text)
                t.column("feedURL", .text).notNull()
                t.column("title", .text).notNull()
                t.column("author", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("artworkURL", .text)
                t.column("websiteURL", .text)
                t.column("isSerial", .boolean).notNull()
                t.column("followedAt", .datetime).indexed()
                t.column("lastRefreshed", .datetime)
                t.column("lastOpened", .datetime)
                t.column("etag", .text)
                t.column("lastModified", .text)
                t.column("playbackRate", .double)
                t.column("autoDownload", .boolean).notNull().defaults(to: false)
                t.column("oldestFirst", .boolean)
                t.column("hidePlayed", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "episode") { t in
                t.primaryKey("id", .text)
                t.column("showID", .text).notNull().indexed().references("show", onDelete: .cascade)
                t.column("guid", .text).notNull()
                t.column("title", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("notesHTML", .text).notNull()
                t.column("publishedAt", .datetime).indexed()
                t.column("duration", .double)
                t.column("audioURL", .text).notNull()
                t.column("mimeType", .text)
                t.column("byteLength", .integer)
                t.column("artworkURL", .text)
                t.column("season", .integer)
                t.column("number", .integer)
                t.column("episodeType", .text)
                t.column("chaptersURL", .text)
                t.column("position", .double).notNull().defaults(to: 0)
                t.column("playedAt", .datetime)
                t.column("lastPlayedAt", .datetime)
                t.column("savedAt", .datetime)
                t.column("firstSeenAt", .datetime).notNull()
                t.column("generation", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "upNext") { t in
                t.primaryKey("episodeID", .text).references("episode", onDelete: .cascade)
                t.column("sortOrder", .double).notNull()
            }
            try db.create(table: "episodeDownload") { t in
                t.primaryKey("episodeID", .text).references("episode", onDelete: .cascade)
                t.column("state", .text).notNull().indexed()
                t.column("fileName", .text)
                t.column("bytes", .integer).notNull().defaults(to: 0)
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("error", .text)
                t.column("requestedAt", .datetime).notNull()
                t.column("isAutomatic", .boolean).notNull().defaults(to: false)
            }
        }
        return migrator
    }
}

extension EpisodeRecord {
    static let show = belongsTo(ShowRecord.self)
    static let download = hasOne(EpisodeDownloadRecord.self, using: ForeignKey(["episodeID"]))
}

extension ShowRecord {
    static let episodes = hasMany(EpisodeRecord.self)
}

extension ShowSummary {
    public init(row: Row) throws {
        show = try ShowRecord(row: row)
        newCount = row["newCount"] ?? 0
        latestAt = row["latestAt"]
    }
}

// MARK: - Reads

public extension PodcastDatabase {
    /// Episodes joined with their show and download.
    private static func items(_ request: QueryInterfaceRequest<EpisodeRecord>) -> QueryInterfaceRequest<EpisodeItem> {
        request
            .including(required: EpisodeRecord.show)
            .including(optional: EpisodeRecord.download)
            .asRequest(of: EpisodeItem.self)
    }

    /// Followed shows, most recently updated first, with their new-episode counts.
    func followedShows() -> ValueObservation<ValueReducers.Fetch<[ShowSummary]>> {
        ValueObservation.tracking { db in
            try ShowSummary.fetchAll(db, sql: """
                SELECT show.*,
                  (SELECT COUNT(*) FROM episode e
                     WHERE e.showID = show.id AND e.playedAt IS NULL AND e.position = 0
                       AND e.firstSeenAt > COALESCE(show.lastOpened, show.followedAt)) AS newCount,
                  (SELECT MAX(e.publishedAt) FROM episode e WHERE e.showID = show.id) AS latestAt
                FROM show
                WHERE show.followedAt IS NOT NULL
                ORDER BY latestAt DESC
                """)
        }
    }

    func show(id: String) -> ValueObservation<ValueReducers.Fetch<ShowRecord?>> {
        ValueObservation.tracking { db in try ShowRecord.fetchOne(db, key: id) }
    }

    func showNow(id: String) throws -> ShowRecord? {
        try pool.read { db in try ShowRecord.fetchOne(db, key: id) }
    }

    func followedShowsNow() throws -> [ShowRecord] {
        try pool.read { db in try ShowRecord.filter(Column("followedAt") != nil).fetchAll(db) }
    }

    /// One show's episodes in its display order.
    func episodes(showID: String, oldestFirst: Bool, hidePlayed: Bool) -> ValueObservation<ValueReducers.Fetch<[EpisodeItem]>> {
        ValueObservation.tracking { db in
            var request = EpisodeRecord.filter(Column("showID") == showID)
            if hidePlayed { request = request.filter(Column("playedAt") == nil) }
            let order = oldestFirst ? Column("publishedAt").ascNullsLast : Column("publishedAt").desc
            return try Self.items(request.order(order)).fetchAll(db)
        }
    }

    func episode(id: String) -> ValueObservation<ValueReducers.Fetch<EpisodeItem?>> {
        ValueObservation.tracking { db in try Self.items(EpisodeRecord.filter(key: id)).fetchOne(db) }
    }

    func episodeNow(id: String) throws -> EpisodeItem? {
        try pool.read { db in try Self.items(EpisodeRecord.filter(key: id)).fetchOne(db) }
    }

    func episodesNow(ids: [String]) throws -> [EpisodeItem] {
        let byID = try pool.read { db in
            try Self.items(EpisodeRecord.filter(keys: ids)).fetchAll(db)
        }
        .reduce(into: [String: EpisodeItem]()) { $0[$1.id] = $1 }
        return ids.compactMap { byID[$0] }
    }

    /// Newest unplayed episodes across followed shows.
    func latestEpisodes(limit: Int = 50) -> ValueObservation<ValueReducers.Fetch<[EpisodeItem]>> {
        ValueObservation.tracking { db in
            let followed = ShowRecord.filter(Column("followedAt") != nil).select(Column("id"))
            let request = EpisodeRecord
                .filter(followed.contains(Column("showID")))
                .filter(Column("playedAt") == nil)
                .order(Column("publishedAt").desc)
                .limit(limit)
            return try Self.items(request).fetchAll(db)
        }
    }

    /// The Podcasts tab's Up Next shelf, like Apple Podcasts: episodes in progress, then the
    /// user's queue, then the newest unplayed episode of each followed show.
    func upNextShelf(limit: Int = 20) -> ValueObservation<ValueReducers.Fetch<[EpisodeItem]>> {
        ValueObservation.tracking { db in
            let inProgress = try Self.items(
                EpisodeRecord
                    .filter(Column("position") > 0 && Column("playedAt") == nil)
                    .order(Column("lastPlayedAt").desc)
                    .limit(10)
            ).fetchAll(db)
            let queued = try Self.queueItems(db)
            let newest = try Self.items(EpisodeRecord.filter(sql: """
                episode.id IN (
                  SELECT e.id FROM episode e JOIN show s ON s.id = e.showID
                  WHERE s.followedAt IS NOT NULL AND e.playedAt IS NULL AND e.position = 0
                    AND e.publishedAt = (SELECT MAX(publishedAt) FROM episode x WHERE x.showID = e.showID)
                )
                """)).order(Column("publishedAt").desc).limit(limit).fetchAll(db)
            var seen = Set<String>()
            return (inProgress + queued + newest).filter { seen.insert($0.id).inserted }.prefix(limit).map(\.self)
        }
    }

    /// The manual Up Next queue, in order.
    func queue() -> ValueObservation<ValueReducers.Fetch<[EpisodeItem]>> {
        ValueObservation.tracking { db in try Self.queueItems(db) }
    }

    func queueNow() throws -> [EpisodeItem] {
        try pool.read { db in try Self.queueItems(db) }
    }

    private static func queueItems(_ db: Database) throws -> [EpisodeItem] {
        let ids = try String.fetchAll(db, sql: "SELECT episodeID FROM upNext ORDER BY sortOrder")
        let byID = try items(EpisodeRecord.filter(keys: ids)).fetchAll(db).reduce(into: [String: EpisodeItem]()) { $0[$1.id] = $1 }
        return ids.compactMap { byID[$0] }
    }

    func saved() -> ValueObservation<ValueReducers.Fetch<[EpisodeItem]>> {
        ValueObservation.tracking { db in
            try Self.items(EpisodeRecord.filter(Column("savedAt") != nil).order(Column("savedAt").desc)).fetchAll(db)
        }
    }

    func history(limit: Int = 200) -> ValueObservation<ValueReducers.Fetch<[EpisodeItem]>> {
        ValueObservation.tracking { db in
            try Self.items(
                EpisodeRecord.filter(Column("lastPlayedAt") != nil).order(Column("lastPlayedAt").desc).limit(limit)
            ).fetchAll(db)
        }
    }

    /// Downloaded and downloading episodes, newest request first.
    func downloads() -> ValueObservation<ValueReducers.Fetch<[EpisodeItem]>> {
        ValueObservation.tracking { db in
            try EpisodeRecord
                .including(required: EpisodeRecord.show)
                .including(required: EpisodeRecord.download)
                .asRequest(of: EpisodeItem.self)
                .fetchAll(db)
                .sorted { ($0.download?.requestedAt ?? .distantPast) > ($1.download?.requestedAt ?? .distantPast) }
        }
    }

    /// Download state per episode, for badges in any list.
    func downloadStates() -> ValueObservation<ValueReducers.Fetch<[String: EpisodeDownloadRecord]>> {
        ValueObservation.tracking { db in
            try EpisodeDownloadRecord.fetchAll(db).reduce(into: [:]) { $0[$1.episodeID] = $1 }
        }
    }

    func totalDownloadedBytes() -> ValueObservation<ValueReducers.Fetch<Int64>> {
        ValueObservation.tracking { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(bytes), 0) FROM episodeDownload WHERE state = 'done'") ?? 0
        }
    }

    struct SearchResults: Sendable, Equatable {
        public var shows: [ShowRecord] = []
        public var episodes: [EpisodeItem] = []
        public var isEmpty: Bool { shows.isEmpty && episodes.isEmpty }
        public init() {}
    }

    /// Followed shows and their episodes whose titles (or show author) match.
    func search(_ text: String) throws -> SearchResults {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return SearchResults() }
        let pattern = "%\(term.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: ""))%"
        return try pool.read { db in
            var results = SearchResults()
            results.shows = try ShowRecord
                .filter(Column("followedAt") != nil)
                .filter(Column("title").like(pattern) || Column("author").like(pattern))
                .order(Column("title"))
                .limit(20)
                .fetchAll(db)
            let followed = ShowRecord.filter(Column("followedAt") != nil).select(Column("id"))
            results.episodes = try Self.items(
                EpisodeRecord
                    .filter(followed.contains(Column("showID")))
                    .filter(Column("title").like(pattern))
                    .order(Column("publishedAt").desc)
                    .limit(30)
            ).fetchAll(db)
            return results
        }
    }

    func downloadedFileName(episodeID: String) -> String? {
        try? pool.read { db in
            try String.fetchOne(db, sql: "SELECT fileName FROM episodeDownload WHERE episodeID = ? AND state = 'done'", arguments: [episodeID])
        }
    }

    func pendingDownloads() throws -> [EpisodeItem] {
        try pool.read { db in
            try EpisodeRecord
                .including(required: EpisodeRecord.show)
                .including(required: EpisodeRecord.download.filter(["queued", "downloading"].contains(Column("state"))))
                .asRequest(of: EpisodeItem.self)
                .fetchAll(db)
        }
    }

    /// Positions and played dates for every episode with listening state (sync).
    func listeningState() throws -> [EpisodeRecord] {
        try pool.read { db in
            try EpisodeRecord.filter(Column("position") > 0 || Column("playedAt") != nil).fetchAll(db)
        }
    }
}

// MARK: - Writes

public extension PodcastDatabase {
    struct UpsertResult: Sendable {
        public var show: ShowRecord
        /// Episodes that weren't in the database before this fetch.
        public var newEpisodeIDs: [String]
    }

    /// Stores a fetched feed. Listening state on existing episodes is kept; episodes that left
    /// the feed are removed unless the user has a reason to keep them (progress, saved, queued
    /// or downloaded).
    func upsert(feed: ParsedFeed, feedURL: URL, validators: FeedValidators?, follow: Bool) async throws -> UpsertResult {
        let showID = PodcastID.show(feedURL: feedURL)
        return try await pool.write { db in
            let now = Date()
            var show = try ShowRecord.fetchOne(db, key: showID) ?? ShowRecord(
                id: showID, feedURL: feedURL, title: feed.title, author: feed.author, summary: feed.summary,
                artworkURL: feed.artworkURL, websiteURL: feed.websiteURL, isSerial: feed.isSerial
            )
            show.title = feed.title
            show.author = feed.author
            show.summary = feed.summary
            show.artworkURL = feed.artworkURL ?? show.artworkURL
            show.websiteURL = feed.websiteURL
            show.isSerial = feed.isSerial
            show.lastRefreshed = now
            if let validators {
                show.etag = validators.etag
                show.lastModified = validators.lastModified
            }
            if follow, show.followedAt == nil { show.followedAt = now }
            try show.save(db)

            let generation = (try Int.fetchOne(db, sql: "SELECT MAX(generation) FROM episode WHERE showID = ?", arguments: [showID]) ?? 0) + 1
            var newIDs: [String] = []
            for parsed in feed.episodes {
                let id = PodcastID.episode(feedURL: feedURL, guid: parsed.guid)
                if var existing = try EpisodeRecord.fetchOne(db, key: id) {
                    existing.title = parsed.title
                    existing.summary = parsed.summary
                    existing.notesHTML = parsed.notesHTML
                    existing.publishedAt = parsed.publishedAt
                    existing.duration = parsed.duration ?? existing.duration
                    existing.audioURL = parsed.audioURL
                    existing.mimeType = parsed.mimeType
                    existing.byteLength = parsed.byteLength
                    existing.artworkURL = parsed.artworkURL
                    existing.season = parsed.season
                    existing.number = parsed.number
                    existing.episodeType = parsed.episodeType
                    existing.chaptersURL = parsed.chaptersURL
                    existing.generation = generation
                    try existing.update(db)
                } else {
                    newIDs.append(id)
                    try EpisodeRecord(
                        id: id, showID: showID, guid: parsed.guid, title: parsed.title, summary: parsed.summary,
                        notesHTML: parsed.notesHTML, publishedAt: parsed.publishedAt, duration: parsed.duration,
                        audioURL: parsed.audioURL, mimeType: parsed.mimeType, byteLength: parsed.byteLength,
                        artworkURL: parsed.artworkURL, season: parsed.season, number: parsed.number,
                        episodeType: parsed.episodeType, chaptersURL: parsed.chaptersURL,
                        firstSeenAt: now, generation: generation
                    ).insert(db)
                }
            }
            try db.execute(sql: """
                DELETE FROM episode
                WHERE showID = ? AND generation < ?
                  AND position = 0 AND savedAt IS NULL
                  AND id NOT IN (SELECT episodeID FROM upNext)
                  AND id NOT IN (SELECT episodeID FROM episodeDownload)
                """, arguments: [showID, generation])
            return UpsertResult(show: show, newEpisodeIDs: newIDs)
        }
    }

    /// Records a 304 Not Modified refresh.
    func touch(showID: String) async throws {
        try await pool.write { db in
            try db.execute(sql: "UPDATE show SET lastRefreshed = ? WHERE id = ?", arguments: [Date(), showID])
        }
    }

    func setFollowed(showID: String, _ followed: Bool) async throws {
        try await pool.write { db in
            try db.execute(sql: "UPDATE show SET followedAt = ? WHERE id = ?", arguments: [followed ? Date() : nil, showID])
            if !followed {
                try db.execute(sql: "UPDATE show SET autoDownload = 0 WHERE id = ?", arguments: [showID])
                try db.execute(sql: "DELETE FROM upNext WHERE episodeID IN (SELECT id FROM episode WHERE showID = ?)", arguments: [showID])
            }
        }
    }

    func updateShow(id: String, _ change: @escaping @Sendable (inout ShowRecord) -> Void) async throws {
        try await pool.write { db in
            guard var show = try ShowRecord.fetchOne(db, key: id) else { return }
            change(&show)
            try show.update(db)
        }
    }

    func markOpened(showID: String) async throws {
        try await updateShow(id: showID) { $0.lastOpened = Date() }
    }

    /// Saves a resume point. Within 30 s of the end counts as finished: the episode is marked
    /// played, its position reset, and it leaves Up Next. Returns true when it just finished.
    @discardableResult
    func savePosition(episodeID: String, position: Double, duration: Double) async throws -> Bool {
        try await pool.write { db in
            guard var episode = try EpisodeRecord.fetchOne(db, key: episodeID) else { return false }
            let length = duration > 0 ? duration : (episode.duration ?? 0)
            if length > 0, episode.duration == nil || abs((episode.duration ?? 0) - length) > 5 { episode.duration = length }
            let finished = length > 0 && position >= length - 30
            episode.lastPlayedAt = Date()
            if finished {
                let wasPlayed = episode.isPlayed
                episode.playedAt = episode.playedAt ?? Date()
                episode.position = 0
                try episode.update(db)
                try UpNextRecord.deleteOne(db, key: episodeID)
                return !wasPlayed
            }
            // A few seconds in isn't a listen worth resuming.
            episode.position = position < 5 ? 0 : position
            if position >= 5 { episode.playedAt = nil }
            try episode.update(db)
            return false
        }
    }

    func setPlayed(episodeIDs: [String], _ played: Bool) async throws {
        try await pool.write { db in
            for id in episodeIDs {
                guard var episode = try EpisodeRecord.fetchOne(db, key: id) else { continue }
                episode.playedAt = played ? (episode.playedAt ?? Date()) : nil
                episode.position = 0
                try episode.update(db)
                if played { try UpNextRecord.deleteOne(db, key: id) }
            }
        }
    }

    func markAllPlayed(showID: String) async throws {
        try await pool.write { db in
            try db.execute(sql: "UPDATE episode SET playedAt = COALESCE(playedAt, ?), position = 0 WHERE showID = ?", arguments: [Date(), showID])
            try db.execute(sql: "DELETE FROM upNext WHERE episodeID IN (SELECT id FROM episode WHERE showID = ?)", arguments: [showID])
        }
    }

    func setSaved(episodeID: String, _ saved: Bool) async throws {
        try await pool.write { db in
            try db.execute(sql: "UPDATE episode SET savedAt = ? WHERE id = ?", arguments: [saved ? Date() : nil, episodeID])
        }
    }

    // MARK: Up Next

    /// Adds to the front (Play Next) or back (Play Last) of Up Next, moving it if already queued.
    func enqueue(episodeID: String, atFront: Bool) async throws {
        try await pool.write { db in
            let bound = try Double.fetchOne(db, sql: atFront ? "SELECT MIN(sortOrder) FROM upNext" : "SELECT MAX(sortOrder) FROM upNext") ?? 0
            try UpNextRecord(episodeID: episodeID, sortOrder: atFront ? bound - 1 : bound + 1).save(db)
        }
    }

    func dequeue(episodeID: String) async throws {
        try await pool.write { db in _ = try UpNextRecord.deleteOne(db, key: episodeID) }
    }

    /// Rewrites the queue order (after a drag to reorder).
    func setQueue(_ episodeIDs: [String]) async throws {
        try await pool.write { db in
            try UpNextRecord.deleteAll(db)
            for (index, id) in episodeIDs.enumerated() {
                try UpNextRecord(episodeID: id, sortOrder: Double(index)).insert(db)
            }
        }
    }

    // MARK: Downloads

    /// Records a download request; returns false when it's already downloaded or underway.
    func requestDownload(episodeID: String, automatic: Bool) async throws -> Bool {
        try await pool.write { db in
            if let existing = try EpisodeDownloadRecord.fetchOne(db, key: episodeID), existing.state != .failed { return false }
            try EpisodeDownloadRecord(episodeID: episodeID, state: .queued, isAutomatic: automatic).save(db)
            return true
        }
    }

    func updateDownload(episodeID: String, _ change: @escaping @Sendable (inout EpisodeDownloadRecord) -> Void) async throws {
        try await pool.write { db in
            guard var record = try EpisodeDownloadRecord.fetchOne(db, key: episodeID) else { return }
            change(&record)
            try record.update(db)
        }
    }

    /// Forgets a download; returns its file name so the caller can delete it.
    func removeDownload(episodeID: String) async throws -> String? {
        try await pool.write { db in
            let record = try EpisodeDownloadRecord.fetchOne(db, key: episodeID)
            try EpisodeDownloadRecord.deleteOne(db, key: episodeID)
            return record?.fileName
        }
    }

    func removeAllDownloads() async throws -> [String] {
        try await pool.write { db in
            let names = try String.fetchAll(db, sql: "SELECT fileName FROM episodeDownload WHERE fileName IS NOT NULL")
            try EpisodeDownloadRecord.deleteAll(db)
            return names
        }
    }

    /// Downloads for played episodes (auto-delete), excluding ones the user saved.
    func playedDownloads() throws -> [String] {
        try pool.read { db in
            try String.fetchAll(db, sql: """
                SELECT d.episodeID FROM episodeDownload d JOIN episode e ON e.id = d.episodeID
                WHERE e.playedAt IS NOT NULL AND e.savedAt IS NULL AND d.state = 'done'
                """)
        }
    }

    /// Newest unplayed episodes per auto-download show that aren't downloaded yet.
    func autoDownloadCandidates(perShow count: Int) throws -> [String] {
        guard count > 0 else { return [] }
        return try pool.read { db in
            try String.fetchAll(db, sql: """
                SELECT id FROM (
                  SELECT e.id, e.playedAt, ROW_NUMBER() OVER (PARTITION BY e.showID ORDER BY e.publishedAt DESC) AS rank
                  FROM episode e JOIN show s ON s.id = e.showID
                  WHERE s.followedAt IS NOT NULL AND s.autoDownload = 1
                )
                WHERE rank <= ? AND playedAt IS NULL AND id NOT IN (SELECT episodeID FROM episodeDownload)
                """, arguments: [count])
        }
    }

    // MARK: Housekeeping

    /// Deletes previewed shows the user never followed, unless an episode has listening state.
    /// Returns download file names that went with them.
    func removeUnfollowedShows() async throws -> [String] {
        try await pool.write { db in
            let keep = """
                SELECT showID FROM episode
                WHERE position > 0 OR savedAt IS NOT NULL
                   OR id IN (SELECT episodeID FROM upNext) OR id IN (SELECT episodeID FROM episodeDownload)
                """
            let names = try String.fetchAll(db, sql: """
                SELECT d.fileName FROM episodeDownload d JOIN episode e ON e.id = d.episodeID JOIN show s ON s.id = e.showID
                WHERE s.followedAt IS NULL AND d.fileName IS NOT NULL AND s.id NOT IN (\(keep))
                """)
            try db.execute(sql: "DELETE FROM show WHERE followedAt IS NULL AND id NOT IN (\(keep))")
            return names
        }
    }

    /// Applies listening state from another device: newer positions win, played dates fill in.
    func applyRemote(positions: [String: (position: Double, updated: Date)], played: [String: Date]) async throws {
        try await pool.write { db in
            for (id, remote) in positions {
                guard var episode = try EpisodeRecord.fetchOne(db, key: id), episode.playedAt == nil else { continue }
                guard (episode.lastPlayedAt ?? .distantPast) < remote.updated else { continue }
                episode.position = remote.position
                episode.lastPlayedAt = remote.updated
                try episode.update(db)
            }
            for (id, date) in played {
                guard var episode = try EpisodeRecord.fetchOne(db, key: id), episode.playedAt == nil else { continue }
                // A local listen after the remote finish wins.
                if let local = episode.lastPlayedAt, local > date, episode.position > 0 { continue }
                episode.playedAt = date
                episode.position = 0
                try episode.update(db)
                try UpNextRecord.deleteOne(db, key: id)
            }
        }
    }
}
