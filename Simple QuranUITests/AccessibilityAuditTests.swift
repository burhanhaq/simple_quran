import XCTest

/// Runs Xcode's accessibility audit (contrast, hit areas, labels, traits, element detection) on every
/// main screen. A failure names the screen and the element it found.
///
/// Dynamic Type and clipped-text checks are left out: in iOS 26 they flag system controls
/// (toolbar buttons, list headers, pickers) on every screen. Large text is covered by the
/// large-text tests in Simple_QuranUITests and by a manual pass at the largest sizes.
final class AccessibilityAuditTests: XCTestCase {
    private static let auditTypes: XCUIAccessibilityAuditType = XCUIAccessibilityAuditType.all
        .subtracting([.dynamicType, .textClipped])

    override func setUpWithError() throws { continueAfterFailure = true }

    @MainActor
    private func launch(layout: String = "ayahByAyah", onboarding: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-focus",
                               onboarding ? "-ui-testing-reset-onboarding" : "-ui-testing-skip-onboarding",
                               "-settings.appearance", "light", "-settings.quranReadingLayout", layout,
                               "-settings.startTab", "memorize", "-reading.ayah", "0", "-learning.pieceSize", "halfPage"]
        app.launch()
        return app
    }

    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String) {
        // Lets pushes, sheets, and fades finish, so contrast is measured on the settled screen.
        sleep(1)
        do {
            try app.performAccessibilityAudit(for: Self.auditTypes) { issue in
                if Self.isKnownFalsePositive(issue, in: app) { return true }
                XCTFail("\(screen): \(issue.auditType) — \(issue.compactDescription) — \(issue.element?.debugDescription ?? "no element")")
                return true
            }
        } catch {
            XCTFail("\(screen): the audit couldn't run: \(error)")
        }
    }

    /// Issues the audit reports that don't hold up on the device, each checked by hand:
    /// - No element: nothing to inspect or fix.
    /// - Partly off screen: contrast is measured on pixels that aren't drawn.
    /// - The system's Liquid Glass toolbar buttons: the audit samples the glass, not what shows through it.
    /// - Text on the Today card: the audit samples its gradient and line art; its 80% white is over 6:1 on the lightest green.
    @MainActor
    private static func isKnownFalsePositive(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        guard let element = issue.element else { return true }
        guard issue.auditType == .contrast else { return false }
        if !app.frame.contains(element.frame) { return true }
        if element.elementType == .button, app.navigationBars.buttons[element.label].exists,
           element.frame.maxY < app.frame.minY + 140 { return true }
        return todayCardText.contains(element.identifier) || todayCardText.contains(element.label)
    }

    private static let todayCardText: Set<String> = [
        "memorize.choosePlan", "memorize.markKnown", "Most people start with the short surahs at the end."
    ]

    @MainActor
    func testOnboarding() {
        let app = launch(onboarding: true)
        XCTAssertTrue(app.buttons["onboarding.intent.readAndListen"].waitForExistence(timeout: 5))
        audit(app, "Onboarding")
    }

    @MainActor
    func testMemorizeAndQuranTabs() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Memorize"].waitForExistence(timeout: 5))
        audit(app, "Memorize")
        app.tabBars.buttons["Quran"].tap()
        XCTAssertTrue(app.buttons["quran.surah.1"].waitForExistence(timeout: 3))
        audit(app, "Quran")
    }

    @MainActor
    func testReaderInBothLayouts() {
        for layout in ["ayahByAyah", "mushaf"] {
            let app = launch(layout: layout)
            app.tabBars.buttons["Quran"].tap()
            app.buttons["quran.surah.2"].tap()
            XCTAssertTrue(app.buttons["surah.close"].waitForExistence(timeout: 5))
            audit(app, "Reader (\(layout))")
            app.terminate()
        }
    }

    @MainActor
    func testMemorizingWithTheArabicHidden() {
        let app = launch()
        let start = app.buttons["memorize.startSuggested"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.buttons["session.recite"].waitForExistence(timeout: 5))
        audit(app, "Memorize session (listen)")
        app.buttons["session.recite"].tap()
        XCTAssertTrue(app.buttons["session.check"].waitForExistence(timeout: 3))
        audit(app, "Memorize session (recite)")
    }

    @MainActor
    func testSettingsAndItsPages() {
        let app = launch()
        let settings = app.buttons["memorize.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.buttons["settings.reciter"].waitForExistence(timeout: 3))
        audit(app, "Settings")

        open(app, "settings.reciter")
        audit(app, "Reciter")
        app.navigationBars.buttons.firstMatch.tap()

        open(app, "settings.privacy")
        audit(app, "Privacy")
        app.navigationBars.buttons.firstMatch.tap()

        open(app, "settings.acknowledgements")
        audit(app, "Acknowledgements")
    }

    /// Scrolls Settings until the row can be tapped, then opens it. Rows further down
    /// aren't created until they scroll into view.
    @MainActor
    private func open(_ app: XCUIApplication, _ identifier: String) {
        let row = app.buttons[identifier]
        for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.isHittable, "\(identifier) never came into view")
        row.tap()
    }
}
