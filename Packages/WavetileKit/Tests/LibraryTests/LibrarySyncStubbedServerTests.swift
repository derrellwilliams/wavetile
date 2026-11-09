import Foundation
import GRDB
import Testing
import os
@testable import Library
@testable import JellyfinKit
@testable import Persistence

/// Serves canned Jellyfin JSON to `LibrarySync`, routed by the request's path and query.
nonisolated private final class StubServer: URLProtocol, @unchecked Sendable {
    enum Reply {
        case json(String)
        case status(Int)
        /// Answers once the work finishes, for changing the server while a sync waits on it.
        indirect case after(@Sendable () async -> Reply)
    }

    static let handler = OSAllocatedUnfairLock<@Sendable (URL) -> Reply>(initialState: { _ in .status(404) })
    /// Consulted first, for tests that care about the method; nil falls through to `handler`.
    static let requestHandler = OSAllocatedUnfairLock<(@Sendable (String, URL) -> Reply?)?>(initialState: nil)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let reply = Self.requestHandler.withLock { $0 }?(request.httpMethod ?? "GET", url) ?? Self.handler.withLock { $0 }(url)
        if case let .after(work) = reply {
            // Not on the loading thread, which the work's own requests need.
            // The compiler calls the marker unnecessary, yet rejects the capture without it.
            nonisolated(unsafe) let this = self
            Task {
                var later = await work()
                if case .after = later { later = .status(500) }
                this.send(later, for: url)
            }
            return
        }
        send(reply, for: url)
    }

    private func send(_ reply: Reply, for url: URL) {
        let status: Int, body: Data
        switch reply {
        case let .json(text): (status, body) = (200, Data(text.utf8))
        case let .status(code): (status, body) = (code, Data())
        case .after: (status, body) = (500, Data())
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// A tiny music server: artists, albums, tracks and playlists, with knobs for breaking one pass.
nonisolated private struct FakeLibrary: Sendable {
    var artists = ["ar1"]
    var albums = ["al1"]
    var tracks = ["t1", "t2", "t3"]
    var playlists: [String: [String]] = ["pl1": ["t1", "t2"]]
    /// Track page that reports more items than it returns (a cut-off response).
    var tracksReportTotal: Int?
    /// A playlist pass that fails with this HTTP status.
    var playlistFailure: Int?

    func page(_ items: [String], total: Int? = nil) -> StubServer.Reply {
        .json(#"{"Items":[\#(items.joined(separator: ","))],"TotalRecordCount":\#(total ?? items.count),"StartIndex":0}"#)
    }

    func reply(_ url: URL) -> StubServer.Reply {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let types = query.filter { $0.name.lowercased() == "includeitemtypes" }.compactMap(\.value)
        let path = url.path
        if path.hasSuffix("/Artists/AlbumArtists") {
            return page(artists.map { #"{"Id":"\#($0)","Name":"Artist \#($0)","Type":"MusicArtist"}"# })
        }
        if path.hasPrefix("/Items/"), let id = path.components(separatedBy: "/").last, playlists[id] != nil {
            return .json(#"{"Id":"\#(id)","Name":"Playlist \#(id)","Type":"Playlist"}"#)
        }
        if path.contains("/Playlists/") {
            if let playlistFailure { return .status(playlistFailure) }
            let id = path.components(separatedBy: "/").dropLast().last ?? ""
            return page((playlists[id] ?? []).enumerated().map { index, track in
                #"{"Id":"\#(track)","Name":"Track \#(track)","Type":"Audio","PlaylistItemId":"e\#(index)"}"#
            })
        }
        if path.hasSuffix("/Items") {
            if types.contains("MusicAlbum") {
                return page(albums.map { #"{"Id":"\#($0)","Name":"Album \#($0)","Type":"MusicAlbum","AlbumArtist":"Artist ar1"}"# })
            }
            if types.contains("Audio") {
                let items = tracks.map {
                    #"{"Id":"\#($0)","Name":"Track \#($0)","Type":"Audio","AlbumId":"al1","Album":"Album al1","RunTimeTicks":1800000000}"#
                }
                return page(items, total: tracksReportTotal)
            }
            if types.contains("Playlist") {
                if let playlistFailure { return .status(playlistFailure) }
                return page(playlists.keys.sorted().map { #"{"Id":"\#($0)","Name":"Playlist \#($0)","Type":"Playlist"}"# })
            }
            if types.contains("BoxSet") { return page([]) }
        }
        return .status(404)
    }
}

@Suite(.serialized)
struct LibrarySyncStubbedServerTests {
    private let session = ServerSession(
        serverURL: URL(string: "https://stub.invalid")!, serverID: "stub", serverName: "Stub", userID: "u1", userName: "Test"
    )

    private func makeSync(_ database: LibraryDatabase) -> LibrarySync {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        let auth = AuthService(
            identity: .init(clientName: "Test", version: "1", deviceName: "Test", deviceID: "stub-device"),
            sessionConfiguration: config
        )
        return LibrarySync(session: session, token: "synthetic", auth: auth, database: database)
    }

    private func serve(_ library: FakeLibrary) {
        StubServer.handler.withLock { $0 = { library.reply($0) } }
    }

    private func trackIDs(_ db: LibraryDatabase) throws -> [String] {
        try db.pool.read { try TrackRecord.order(Column("id")).fetchAll($0).map(\.id) }
    }

    private func playlistTrackIDs(_ db: LibraryDatabase, _ playlist: String) throws -> [String] {
        try db.pool.read {
            try PlaylistEntryRecord.filter(Column("playlistID") == playlist).order(Column("position")).fetchAll($0).map(\.trackID)
        }
    }

    /// An album download with one finished song (`t1`) and one still queued (`t2`).
    private func seedDownloads(_ db: LibraryDatabase) async throws {
        let album = DownloadCollectionRecord(id: "al1", kind: .album, name: "Album al1", subtitle: "Artist", imageTag: nil)
        _ = try await db.requestDownload(album, trackIDs: ["t1", "t2"])
        try await db.updateDownload(trackID: "t1") {
            $0.state = .done
            $0.fileName = "t1.mp3"
            $0.bytes = 1000
            $0.progress = 1
        }
    }

    private func expectDownloadsIntact(_ db: LibraryDatabase) throws {
        #expect(db.downloadedFileName(trackID: "t1") == "t1.mp3")
        #expect(try db.pendingDownloads().map(\.trackID) == ["t2"])
        #expect(try db.pool.read { try DownloadMembershipRecord.fetchCount($0) } == 2)
    }

    @Test func fullSyncMirrorsTheServerAndLeavesDownloadsAlone() async throws {
        let db = try LibraryDatabase.temporary()
        serve(FakeLibrary())
        try await seedDownloads(db)
        try await makeSync(db).run()
        #expect(try trackIDs(db) == ["t1", "t2", "t3"])
        #expect(try playlistTrackIDs(db, "pl1") == ["t1", "t2"])
        #expect(try db.syncState()?.lastCompleted != nil)
        try expectDownloadsIntact(db)
    }

    @Test func cutOffTrackPageFailsTheSyncAndKeepsEverything() async throws {
        let db = try LibraryDatabase.temporary()
        serve(FakeLibrary())
        let sync = makeSync(db)
        try await sync.run()
        try await seedDownloads(db)
        let before = try db.syncState()

        // The server drops t3 and claims 3 tracks but sends 2: not a pass that saw everything.
        serve(FakeLibrary(tracks: ["t1", "t2"], tracksReportTotal: 3))
        await #expect(throws: URLError.self) { try await sync.run() }

        #expect(try trackIDs(db) == ["t1", "t2", "t3"])
        #expect(try db.syncState()?.lastCompleted == before?.lastCompleted)
        #expect(try db.syncState()?.generation == before?.generation)
        try expectDownloadsIntact(db)
    }

    @Test func serverErrorMidSyncKeepsLibraryPlaylistsAndDownloads() async throws {
        let db = try LibraryDatabase.temporary()
        serve(FakeLibrary())
        let sync = makeSync(db)
        try await sync.run()
        try await seedDownloads(db)
        let before = try db.syncState()

        // Tracks changed on the server, then the playlist pass fails: nothing is pruned or committed.
        serve(FakeLibrary(tracks: ["t1"], playlists: ["pl1": ["t1"]], playlistFailure: 500))
        await #expect(throws: (any Error).self) { try await sync.run() }

        #expect(try trackIDs(db) == ["t1", "t2", "t3"])
        #expect(try playlistTrackIDs(db, "pl1") == ["t1", "t2"])
        #expect(try db.syncState()?.lastCompleted == before?.lastCompleted)
        try expectDownloadsIntact(db)
    }

    @Test func unauthorizedServerChangesNothing() async throws {
        let db = try LibraryDatabase.temporary()
        serve(FakeLibrary())
        let sync = makeSync(db)
        try await sync.run()
        try await seedDownloads(db)

        StubServer.handler.withLock { $0 = { _ in .status(401) } }
        await #expect(throws: (any Error).self) { try await sync.run() }

        #expect(try trackIDs(db) == ["t1", "t2", "t3"])
        try expectDownloadsIntact(db)
    }

    @Test func completeSyncPrunesRemovedTracksButNotTheirDownloads() async throws {
        let db = try LibraryDatabase.temporary()
        serve(FakeLibrary())
        let sync = makeSync(db)
        try await sync.run()
        try await seedDownloads(db)

        // t1 was deleted on the server. The library row goes (a complete pass saw everything else);
        // the downloaded copy stays until the user removes it, and the playlist loses the entry.
        serve(FakeLibrary(tracks: ["t2", "t3"], playlists: ["pl1": ["t2"]]))
        try await sync.run()

        #expect(try trackIDs(db) == ["t2", "t3"])
        #expect(try playlistTrackIDs(db, "pl1") == ["t2"])
        try expectDownloadsIntact(db)
    }

    @Test func understatedTotalFailsTheSyncAndKeepsEverything() async throws {
        let db = try LibraryDatabase.temporary()
        serve(FakeLibrary())
        let sync = makeSync(db)
        try await sync.run()
        try await seedDownloads(db)

        // One track sent, with a total that says that's all of them (zero, then negative).
        for total in [0, -1] {
            serve(FakeLibrary(tracks: ["t1"], tracksReportTotal: total))
            await #expect(throws: URLError.self) { try await sync.run() }
            #expect(try trackIDs(db) == ["t1", "t2", "t3"])
        }
        try expectDownloadsIntact(db)
    }

    @Test func repeatedItemsAreNotACompletePass() async throws {
        let db = try LibraryDatabase.temporary()
        serve(FakeLibrary())
        let sync = makeSync(db)
        try await sync.run()

        // Pages shifted under the sync: t1 came twice and t3 never did, though the count adds up.
        serve(FakeLibrary(tracks: ["t1", "t1", "t2"]))
        await #expect(throws: URLError.self) { try await sync.run() }
        #expect(try trackIDs(db) == ["t1", "t2", "t3"])
    }

    @Test func playlistCreatedDuringASyncSurvivesItsPrune() async throws {
        let db = try LibraryDatabase.temporary()
        let sync = makeSync(db)
        // The sync lists playlists before `pl2` exists; it's created (and re-read, as an edit
        // does) while the collections pass, the last one before the prune, is waiting.
        let before = FakeLibrary()
        let after = FakeLibrary(playlists: ["pl1": ["t1", "t2"], "pl2": ["t3"]])
        let created = OSAllocatedUnfairLock(initialState: false)
        StubServer.handler.withLock {
            $0 = { url in
                let isCollections = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .contains { $0.name.lowercased() == "includeitemtypes" && $0.value == "BoxSet" } == true
                if isCollections, created.withLock({ done in defer { done = true }; return !done }) {
                    return .after {
                        try? await sync.refreshPlaylist(id: "pl2")
                        return after.reply(url)
                    }
                }
                return created.withLock { $0 } ? after.reply(url) : before.reply(url)
            }
        }
        try await sync.run()
        #expect(try playlistTrackIDs(db, "pl1") == ["t1", "t2"])
        #expect(try playlistTrackIDs(db, "pl2") == ["t3"])
    }

    @Test func renameByRecreatingKeepsTheOriginalWhenTheCopyIsShort() async throws {
        let db = try LibraryDatabase.temporary()
        let sync = makeSync(db)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        let auth = AuthService(
            identity: .init(clientName: "Test", version: "1", deviceName: "Test", deviceID: "stub-device"),
            sessionConfiguration: config
        )
        let editor = LibraryEditor(session: session, token: "synthetic", auth: auth, database: db, sync: sync)
        let album = { @Sendable (id: String) in #"{"Id":"\#(id)","Name":"Album \#(id)","Type":"MusicAlbum"}"# }
        let page = { @Sendable (items: [String]) in
            StubServer.Reply.json(#"{"Items":[\#(items.joined(separator: ","))],"TotalRecordCount":\#(items.count),"StartIndex":0}"#)
        }
        // A non-admin account: saving the item is refused, so the rename recreates the collection.
        // The server then shows the copy holding one of the two albums.
        let calls = OSAllocatedUnfairLock(initialState: [String]())
        StubServer.requestHandler.withLock {
            $0 = { method, url in
                let parent = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first { $0.name.lowercased() == "parentid" }?.value
                calls.withLock { $0.append("\(method) \(url.path)\(parent.map { "?parent=\($0)" } ?? "")") }
                switch (method, url.path, parent) {
                case ("GET", "/Items/c1", _): return .json(#"{"Id":"c1","Name":"Old","Type":"BoxSet"}"#)
                case ("POST", "/Items/c1", _): return .status(403)
                case ("GET", "/Items", "c1"): return page([album("al1"), album("al2")])
                case ("POST", "/Collections", _): return .json(#"{"Id":"c2"}"#)
                case ("GET", "/Items", "c2"): return page([album("al1")])
                case ("DELETE", _, _): return .status(204)
                default: return .status(404)
                }
            }
        }
        defer { StubServer.requestHandler.withLock { $0 = nil } }

        await #expect(throws: URLError.self) { try await editor.renameCollection(id: "c1", to: "New") }
        let made = calls.withLock { $0 }
        #expect(made.contains("DELETE /Items/c2"))
        #expect(!made.contains("DELETE /Items/c1"))
    }

    @Test func emptyButValidServerPrunesTheLibraryOnly() async throws {
        let db = try LibraryDatabase.temporary()
        serve(FakeLibrary())
        let sync = makeSync(db)
        try await sync.run()
        try await seedDownloads(db)

        serve(FakeLibrary(artists: [], albums: [], tracks: [], playlists: [:]))
        try await sync.run()

        #expect(try trackIDs(db).isEmpty)
        try expectDownloadsIntact(db)
    }
}
