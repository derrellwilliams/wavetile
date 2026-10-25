import XCTest

/// Home shelf checks. Requires a signed-in session with play history.
final class HomeTests: XCTestCase {
    /// Long-pressing a Recently Played album offers removal (doesn't tap it, so nothing is hidden).
    @MainActor func testRecentlyPlayedLongPressOffersRemove() throws {
        let app = XCUIApplication()
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)

        let tile = app.buttons.matching(identifier: "albumTile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 8), "No album tiles on Home")
        tile.press(forDuration: 1.2)

        XCTAssertTrue(app.buttons["Remove from Recently Played"].waitForExistence(timeout: 3))
    }

    /// Regression (TestFlight 1.0.0 (2)): the add-to sheets crashed because they sat outside the
    /// environment that provides the library store. Opens the sheet and cancels, so nothing is changed.
    @MainActor func testLongPressAddToCollectionOpensSheet() throws {
        let app = XCUIApplication()
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)

        let tile = app.buttons.matching(identifier: "albumTile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 8), "No album tiles on Home")
        tile.press(forDuration: 1.2)
        let add = app.buttons["Add to Collection"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()

        XCTAssertTrue(app.navigationBars["Add to Collection"].waitForExistence(timeout: 5), "Sheet didn't open")
        XCTAssertEqual(app.state, .runningForeground, "App crashed")
        app.buttons["Cancel"].firstMatch.tap()
    }

    /// Album long press offers Go to Artist (after Favorite) and opens the artist page.
    @MainActor func testAlbumLongPressGoesToArtist() throws {
        let app = XCUIApplication()
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)

        let tile = app.buttons.matching(identifier: "albumTile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 8), "No album tiles on Home")
        tile.press(forDuration: 1.2)
        let goToArtist = app.buttons["Go to Artist"]
        XCTAssertTrue(goToArtist.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(goToArtist.frame.minY, app.buttons["Favorite"].frame.minY, "Go to Artist should follow Favorite")
        goToArtist.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5), "Artist page didn't open")
    }
}
