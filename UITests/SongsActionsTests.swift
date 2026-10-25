import XCTest

/// Library → Songs rows offer the same ⋯ actions as search.
final class SongsActionsTests: XCTestCase {
    @MainActor func testSongsGoToAlbumAndArtist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "library"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)

        let songs = app.buttons["Songs"].firstMatch
        XCTAssertTrue(songs.waitForExistence(timeout: 5))
        songs.tap()

        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More for'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "No ⋯ button on songs")
        more.tap()
        XCTAssertTrue(app.buttons["Go to Artist"].waitForExistence(timeout: 3))
        app.buttons["Go to Album"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trackRow"].firstMatch.waitForExistence(timeout: 5), "Album page didn't open")

        // Back to Songs, then the artist.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        app.buttons["Go to Artist"].tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Songs"].exists, "Artist page didn't open")
    }

    /// Long press on a song offers the same actions as its ⋯ sheet.
    @MainActor func testSongsLongPressMatchesMoreSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "library"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)

        let songs = app.buttons["Songs"].firstMatch
        XCTAssertTrue(songs.waitForExistence(timeout: 5))
        songs.tap()
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More for'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        // Press the row's title area, left of the ⋯ button.
        more.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: -200, dy: 0)).press(forDuration: 1.2)
        for title in ["Play", "Go to Album", "Go to Artist", "Play Next", "Add to Queue", "Add to Playlist", "Favorite"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3), "Long press is missing \(title)")
        }
        app.buttons["Go to Album"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trackRow"].firstMatch.waitForExistence(timeout: 5), "Album page didn't open")
    }
}
