import XCTest

/// The tinted Back button, the edge swipe and the bar buttons on pushed screens (the system Back
/// is hidden there). Requires a signed-in session in the simulator.
final class BackNavigationTests: XCTestCase {
    /// List pages (Back in the bar), opened by tapping their Music row as a listener would, and
    /// an album page (Back floating over the header).
    private static let screens: [(name: String, arguments: [String], row: String?)] = [
        ("playlists", ["-tab", "music"], "Playlists"),
        ("albums", ["-tab", "music"], "Albums"),
        ("songs", ["-tab", "music"], "Songs"),
        ("album", ["-openFirstAlbum"], nil),
    ]

    @MainActor private func open(_ arguments: [String], row: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        if let row {
            XCTAssertTrue(app.buttons[row].firstMatch.waitForExistence(timeout: 10))
            app.buttons[row].firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10))
        return app
    }

    /// Back on a tab's root means the Back button is gone.
    @MainActor private func assertWentBack(_ app: XCUIApplication, _ how: String, file: StaticString = #filePath, line: UInt = #line) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = how
        attachment.lifetime = .keepAlways
        add(attachment)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Back"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 3), .completed, "\(how) didn't go back", file: file, line: line)
    }

    @MainActor func testTapBack() {
        for screen in Self.screens {
            let app = open(screen.arguments, row: screen.row)
            app.buttons["Back"].tap()
            assertWentBack(app, "tap back from \(screen.name)")
        }
    }

    @MainActor func testSwipeBack() {
        for screen in Self.screens {
            let app = open(screen.arguments, row: screen.row)
            let window = app.windows.firstMatch
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            assertWentBack(app, "swipe back from \(screen.name)")
        }
    }

    /// The floating capsule on a detail page takes taps (it sits under the hidden bar).
    @MainActor func testDetailMenuOpens() {
        let app = open(["-openFirstAlbum"])
        // The album page's More (the topmost), not a track row's.
        let more = app.buttons.matching(identifier: "More").allElementsBoundByIndex.min { $0.frame.minY < $1.frame.minY }
        more?.tap()
        XCTAssertTrue(app.buttons["Start Radio"].waitForExistence(timeout: 3))
    }
}
