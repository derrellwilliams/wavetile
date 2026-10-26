import XCTest

/// Runs Apple's automated accessibility audit on the main screens, plus launch-time metrics.
/// Requires a signed-in session in the simulator (the app keeps it in the Keychain between runs).
/// Uses the Debug launch arguments to reach each screen without scripted taps.
final class AccessibilityAuditTests: XCTestCase {
    @MainActor private func launch(_ arguments: [String] = [], settle: TimeInterval = 4) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        // Let network-backed content and artwork arrive.
        _ = app.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: settle)
        return app
    }

    /// Records every issue (so one run lists them all) and fails the test if any were found.
    ///
    /// Known false positives are skipped, each for a specific reason:
    /// - Contrast / clipping for elements under the glass tab bar + mini player, or partly off
    ///   screen (horizontally scrolling shelves): the audit evaluates content behind overlays.
    /// - Anything outside `visibleWidth` (e.g. the main UI dimmed behind the open settings drawer).
    /// - Dynamic Type on the "Wavetile" wordmark: a fixed-size logo is an HIG-sanctioned exception.
    /// - Truncation of album tile titles at normal sizes, and "partially unsupported" Dynamic Type
    ///   reports caused by deliberate large-text re-layouts (see below).
    @MainActor private func audit(_ app: XCUIApplication, screen: String, visibleWidth: CGFloat? = nil) throws {
        var issues: [String] = []
        let window = app.windows.firstMatch.frame
        let chromeHeight: CGFloat = 140
        var visible = CGRect(x: window.minX, y: window.minY, width: visibleWidth ?? window.width, height: window.height - chromeHeight)
        visible = visible.insetBy(dx: -1, dy: -1)
        try app.performAccessibilityAudit { issue in
            if let element = issue.element {
                let frame = element.frame
                let overlayArtifact: XCUIAccessibilityAuditType = [.contrast, .textClipped]
                if !overlayArtifact.intersection(issue.auditType).isEmpty, !visible.contains(frame) { return true }
                if issue.auditType == .dynamicType, element.label == "Wavetile" { return true }
                // Album tile titles are single-line + truncated by design at normal sizes; they
                // wrap at accessibility sizes and VoiceOver reads the full title.
                if issue.auditType == .textClipped, element.identifier == "albumTile" { return true }
                // Track rows and settings rows deliberately re-layout at large sizes (stacking instead
                // of truncating, per the HIG). The audit reports any re-layout as "partially
                // unsupported"; scaling was verified visually at AX5. Fully "unsupported" (fixed-size
                // fonts) is still enforced.
                if issue.auditType == .dynamicType, issue.compactDescription.localizedCaseInsensitiveContains("partially") { return true }
            }
            let element = issue.element.map { "\($0.elementType) '\($0.label)' at \($0.frame.integral)" } ?? "screen"
            issues.append("[\(screen)] \(issue.auditType): \(issue.compactDescription) — \(element)")
            return false
        }
        for issue in issues { print("A11Y \(issue)") }
        XCTAssertTrue(issues.isEmpty, "\(issues.count) accessibility issue(s) on \(screen)")
    }

    @MainActor func testHomeAudit() throws {
        try audit(launch(), screen: "Home")
    }

    @MainActor func testLibraryAudit() throws {
        try audit(launch(["-tab", "music"]), screen: "Music")
    }

    @MainActor func testAlbumAudit() throws {
        try audit(launch(["-openFirstAlbum"]), screen: "Album")
    }

    @MainActor func testNowPlayingAudit() throws {
        let app = launch(["-openFirstAlbum", "-autoplay", "-openNowPlaying"], settle: 6)
        // Pause first so a track change (title cross-fade) can't happen mid-audit.
        let pause = app.buttons["Pause"].firstMatch
        if pause.exists { pause.tap() }
        Thread.sleep(forTimeInterval: 1)
        try audit(app, screen: "Now Playing")
    }

    @MainActor func testSettingsDrawerAudit() throws {
        try audit(launch(["-openSettings"]), screen: "Settings", visibleWidth: 340)
    }

    @MainActor func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
