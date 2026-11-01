import XCTest

/// The tinted system Back, the edge swipe and the bar buttons on pushed screens. Requires a
/// signed-in session in the simulator.
final class BackNavigationTests: XCTestCase {
    /// List pages, opened by tapping their Music row as a listener would, and an album page
    /// (over its header). `root` is on the screen going back lands on.
    private static let screens: [(name: String, arguments: [String], row: String?, root: String)] = [
        ("playlists", ["-tab", "music"], "Playlists", "Playlists"),
        ("albums", ["-tab", "music"], "Albums", "Albums"),
        ("songs", ["-tab", "music"], "Songs", "Songs"),
        ("album", ["-openFirstAlbum"], nil, "Wavetile"),
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

    /// Back on a tab's root: the Back button is gone, the app is still running and the root
    /// (`root` is one of its elements) is showing, so a crash or blank screen doesn't pass.
    @MainActor private func assertWentBack(_ app: XCUIApplication, to root: String, _ how: String, file: StaticString = #filePath, line: UInt = #line) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = how
        attachment.lifetime = .keepAlways
        add(attachment)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Back"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 3), .completed, "\(how) didn't go back", file: file, line: line)
        XCTAssertEqual(app.state, .runningForeground, "\(how) crashed the app", file: file, line: line)
        XCTAssertTrue(app.descendants(matching: .any)[root].firstMatch.waitForExistence(timeout: 3),
                      "\(how) didn't land on the root", file: file, line: line)
    }

    @MainActor func testTapBack() {
        for screen in Self.screens {
            let app = open(screen.arguments, row: screen.row)
            app.buttons["Back"].tap()
            assertWentBack(app, to: screen.root, "tap back from \(screen.name)")
        }
    }

    @MainActor func testSwipeBack() {
        for screen in Self.screens {
            let app = open(screen.arguments, row: screen.row)
            let window = app.windows.firstMatch
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            assertWentBack(app, to: screen.root, "swipe back from \(screen.name)")
        }
    }

    /// The capsule on a detail page (a custom bar item) takes taps.
    @MainActor func testDetailMenuOpens() {
        let app = open(["-openFirstAlbum"])
        // The album page's More (the topmost), not a track row's.
        let more = app.buttons.matching(identifier: "More").allElementsBoundByIndex.min { $0.frame.minY < $1.frame.minY }
        guard let more else { return XCTFail("No More button on the album page") }
        more.tap()
        XCTAssertTrue(app.buttons["Start Radio"].waitForExistence(timeout: 3))
    }
}
