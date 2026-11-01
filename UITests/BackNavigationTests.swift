import XCTest

/// The tinted Back button and the edge swipe on pushed screens (the system Back is hidden there).
/// Requires a signed-in session in the simulator.
final class BackNavigationTests: XCTestCase {
    @MainActor private func open(_ section: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "music", "-openSection", section]
        app.launch()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func assertBackOnMusic(_ app: XCUIApplication, _ how: String, file: StaticString = #filePath, line: UInt = #line) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = how
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(app.staticTexts["Recently Added"].waitForExistence(timeout: 3), "\(how) didn't return to Music", file: file, line: line)
    }

    @MainActor func testTapBack() {
        for section in ["playlists", "albums", "songs"] {
            let app = open(section)
            app.buttons["Back"].tap()
            assertBackOnMusic(app, "tap back from \(section)")
        }
    }

    @MainActor func testSwipeBack() {
        for section in ["playlists", "albums", "songs"] {
            let app = open(section)
            let window = app.windows.firstMatch
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            assertBackOnMusic(app, "swipe back from \(section)")
        }
    }
}
