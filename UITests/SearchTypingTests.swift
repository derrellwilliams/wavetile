import XCTest

/// Search tab checks: typing, and the ⋯ song menu.
/// Requires a signed-in session with a synced library, like the accessibility audits.
final class SearchTypingTests: XCTestCase {
    @MainActor func testSearchFieldAcceptsTyping() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "search"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No search field on the Search tab")
        field.tap()
        field.typeText("moon")

        XCTAssertEqual(field.value as? String, "moon")
    }

    @MainActor func testSongMenuGoesToAlbum() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "search"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("moon")

        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More for'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "No ⋯ button on song results")
        more.tap()

        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Go to Album"].exists)
        XCTAssertTrue(app.buttons["Go to Artist"].exists)

        app.buttons["Go to Album"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trackRow"].firstMatch.waitForExistence(timeout: 5), "Album page didn't open")
    }
}
