import XCTest

/// The Storage sheet: reached from the Downloads overflow menu and from Storage Used in the
/// profile drawer. Non-destructive: nothing is removed. Requires a signed-in session.
final class StorageTests: XCTestCase {
    @MainActor private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        return app
    }

    /// Downloads ▸ More ▸ Manage Storage opens the sheet; Done closes it.
    @MainActor func testManageStorageFromDownloadsMenu() throws {
        let app = launch(["-tab", "downloaded"])
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 8), "No More button on Downloads")
        more.tap()
        app.buttons["Manage Storage"].tap()

        XCTAssertTrue(app.navigationBars["Storage"].waitForExistence(timeout: 5), "Storage sheet didn't open")
        XCTAssertTrue(app.staticTexts["Music"].exists, "Music total missing")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5), "Sheet didn't close")
    }

    /// Storage Used in the profile drawer opens the same sheet.
    @MainActor func testStorageUsedOpensSheet() throws {
        let app = launch(["-openSettings"])
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Storage Used'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "No Storage Used row")
        row.tap()
        XCTAssertTrue(app.navigationBars["Storage"].waitForExistence(timeout: 5), "Storage sheet didn't open")
    }

    /// Select (when there are downloads) swaps to Cancel and back, with nothing selected.
    @MainActor func testSelectTogglesEditMode() throws {
        let app = launch(["-tab", "downloaded"])
        app.buttons["More"].tap()
        app.buttons["Manage Storage"].tap()
        XCTAssertTrue(app.navigationBars["Storage"].waitForExistence(timeout: 5))

        let select = app.buttons["Select"]
        try XCTSkipUnless(select.waitForExistence(timeout: 3), "No downloads on this device")
        select.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Remove 0 Selected"].exists, "Bulk remove bar missing")
        XCTAssertFalse(app.buttons["Remove 0 Selected"].isEnabled, "Nothing selected, so removal must be off")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 3))
    }
}
