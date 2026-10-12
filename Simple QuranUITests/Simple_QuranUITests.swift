import XCTest

final class Simple_QuranUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(appearance: String = "light", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-settings.appearance", appearance, "-settings.quranReadingLayout", "ayahByAyah",
                               "-learning.start", "0", "-learning.end", "0", "-reading.ayah", "0", "-learning.byPage", "NO"] + extra
        app.launch()
        return app
    }

    @MainActor
    func testHomeHasTwoTabsAndDirectPractice() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 2)
        XCTAssertFalse(app.staticTexts["Collections"].exists)
        capture(app, name: "Today-Light")
        app.buttons["home.startPractice"].tap()
        XCTAssertTrue(app.buttons["practice.play"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["practice.play"].label, "Play")
        XCTAssertFalse(app.textFields["set.editor.title"].exists)
        capture(app, name: "Practice-Light")
        app.buttons["practice.next"].tap()
        XCTAssertTrue(app.staticTexts["Ayah 2 of 7"].exists)
        app.buttons["practice.previous"].tap()
        XCTAssertTrue(app.staticTexts["Ayah 1 of 7"].exists)
        app.buttons["practice.hideArabic"].tap()
        XCTAssertTrue(app.buttons["practice.hideArabic"].label.contains("Show text"))
        app.buttons["practice.hideArabic"].tap()
        app.buttons["practice.options"].tap()
        XCTAssertTrue(app.navigationBars["Practice tools"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["Move to the next ayah myself"].exists)
        capture(app, name: "Practice-Tools")
        app.navigationBars["Practice tools"].buttons["Done"].tap()
        app.buttons["practice.finish"].tap()
        XCTAssertTrue(app.buttons["practice.rate.solid"].waitForExistence(timeout: 3))
        capture(app, name: "Reflection")
        app.buttons["practice.rate.solid"].tap()
        XCTAssertTrue(app.buttons["practice.done"].waitForExistence(timeout: 3))
        capture(app, name: "Finished")
        app.buttons["practice.done"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["home.progress"].exists)
    }

    @MainActor
    func testReadingBecomesPracticeInSameReaderAndMiniPlayerRestoresIt() {
        let app = launch()
        app.tabBars.buttons["Quran"].tap()
        capture(app, name: "Quran-Light")
        app.buttons["quran.surah.2"].tap()
        XCTAssertTrue(app.buttons["quran.play"].waitForExistence(timeout: 3))
        app.buttons["practice.next"].tap()
        app.buttons["reader.practice"].tap()
        XCTAssertTrue(app.buttons["practice.change"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["practice.play"].exists)
        XCTAssertFalse(app.buttons["quran.play"].exists)
        XCTAssertTrue(app.buttons["practice.play"].label == "Play")
        app.buttons["reader.close"].tap()
        app.buttons["playback.open"].tap()
        XCTAssertTrue(app.buttons["practice.change"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["practice.play"].exists)
    }

    @MainActor
    func testChangePassageAndAdvanceAfterReflectionWithoutAudio() {
        let app = launch()
        app.tabBars.buttons["Quran"].tap()
        app.buttons["quran.surah.2"].tap()
        app.buttons["reader.practice"].tap()
        app.buttons["practice.change"].tap()
        XCTAssertTrue(app.navigationBars["Your passage"].waitForExistence(timeout: 3))
        app.buttons["One page"].tap()
        capture(app, name: "Passage-Picker")
        app.buttons["passage.start"].tap()
        XCTAssertTrue(app.buttons["practice.finish"].waitForExistence(timeout: 3))
        app.buttons["practice.finish"].tap()
        app.buttons["practice.rate.solid"].tap()
        XCTAssertTrue(app.buttons["practice.nextPassage"].waitForExistence(timeout: 3))
        app.buttons["practice.nextPassage"].tap()
        XCTAssertTrue(app.buttons["practice.play"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ayahs 6–16")).firstMatch.exists)
        app.buttons["reader.close"].tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["home.continue"].waitForExistence(timeout: 3))
        capture(app, name: "Today-Progress")
    }

    @MainActor
    func testFinishWithoutRatingAndReturnToPractice() {
        let app = launch()
        app.buttons["home.startPractice"].tap()
        app.buttons["practice.finish"].tap()
        app.buttons["Finish without rating"].tap()
        app.buttons["practice.done"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        app.buttons["home.continue"].tap()
        XCTAssertTrue(app.buttons["practice.play"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testBrowseByPageAndJuzUsesTheSameReader() {
        let app = launch()
        app.tabBars.buttons["Quran"].tap()
        app.buttons["quran.goToPage"].tap()
        app.buttons["Open page"].tap()
        XCTAssertTrue(app.navigationBars["Page 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quran.play"].exists)
        app.buttons["reader.close"].tap()
        app.segmentedControls.buttons["Juz"].tap()
        app.buttons["quran.juz.1"].tap()
        XCTAssertTrue(app.navigationBars["Juz 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reader.practice"].exists)
        capture(app, name: "Juz-Reader")
    }

    @MainActor
    func testNightAppearanceAndContinuousText() {
        let app = launch(appearance: "night", extra: ["-settings.quranReadingLayout", "mushaf"])
        capture(app, name: "Today-Night")
        app.buttons["home.startPractice"].tap()
        XCTAssertTrue(app.buttons["practice.play"].waitForExistence(timeout: 3))
        capture(app, name: "Practice-Night-Continuous")
        app.buttons["practice.hideArabic"].tap()
        XCTAssertTrue(app.buttons["practice.hideArabic"].label.contains("Show text"))
        capture(app, name: "Practice-Recall")
    }

    @MainActor
    func testLargeTextAndLandscape() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        let start = app.buttons["home.startPractice"]
        for _ in 0..<6 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["practice.play"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["practice.finish"].isHittable)
        capture(app, name: "Practice-LargeText")
        app.terminate()
        let landscape = launch()
        landscape.buttons["home.startPractice"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            landscape.frame.width > landscape.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        XCTAssertTrue(landscape.buttons["practice.next"].waitForExistence(timeout: 3))
        XCTAssertTrue(landscape.buttons["practice.finish"].isHittable)
        landscape.buttons["practice.next"].tap()
        XCTAssertTrue(landscape.staticTexts["Ayah 2 of 7"].exists)
        capture(landscape, name: "Practice-Landscape")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
