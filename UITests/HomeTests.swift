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
}
