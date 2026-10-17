import XCTest

final class Simple_QuranUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(appearance: String = "light", extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-focus", "-ui-testing-skip-onboarding",
                               "-settings.appearance", appearance, "-settings.quranReadingLayout", "ayahByAyah",
                               "-settings.startTab", "memorize",
                               "-learning.start", "0", "-learning.end", "0", "-reading.ayah", "0", "-learning.byPage", "NO"] + extra
        app.launch()
        return app
    }

    /// Picks a surah (by its first global ayah) or juz as the plan from the Memorize tab.
    @MainActor
    private func choosePlan(_ app: XCUIApplication, select identifier: String = "plan.select.ayah.1", juz: Bool = false) {
        let choose = app.buttons["memorize.choosePlan"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        XCTAssertTrue(app.navigationBars["Choose your plan"].waitForExistence(timeout: 3))
        if juz { app.segmentedControls.buttons["Juz"].tap() }
        let row = app.buttons[identifier]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        app.buttons["plan.save"].tap()
    }

    @MainActor
    private func memorizedCount(_ app: XCUIApplication) -> String {
        app.tabBars.buttons["Progress"].tap()
        let count = app.staticTexts["progress.memorizedCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 3))
        return count.label
    }

    @MainActor
    func testThreeTabsPlanAndMemorizingCountsOnlyWhatIsClaimed() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Memorize"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        capture(app, name: "Memorize-Empty")
        choosePlan(app)
        XCTAssertTrue(app.buttons["memorize.start"].waitForExistence(timeout: 3))
        capture(app, name: "Memorize-Plan")
        app.buttons["memorize.start"].tap()
        XCTAssertTrue(app.buttons["session.play"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["session.play"].label, "Play")
        capture(app, name: "Session-Listen")
        app.buttons["session.nextStep"].tap()
        app.buttons["session.nextStep"].tap()
        XCTAssertTrue(app.buttons["session.answer.memorized"].waitForExistence(timeout: 3))
        capture(app, name: "Session-FromMemory")
        app.buttons["session.answer.memorized"].tap()
        app.buttons["session.done"].tap()
        XCTAssertTrue(app.navigationBars["Memorize"].waitForExistence(timeout: 3))
        XCTAssertEqual(memorizedCount(app), "7")
        capture(app, name: "Progress-Light")
    }

    @MainActor
    func testLeavingWithoutAnAnswerChangesNothing() {
        let app = launch()
        choosePlan(app)
        app.buttons["memorize.start"].tap()
        XCTAssertTrue(app.buttons["session.done"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["From memory"].tap()
        app.buttons["session.done"].tap()
        XCTAssertEqual(memorizedCount(app), "0")
    }

    @MainActor
    func testReaderIsForReadingAndListeningOnly() {
        let app = launch()
        app.tabBars.buttons["Quran"].tap()
        capture(app, name: "Quran-Light")
        app.buttons["quran.surah.2"].tap()
        XCTAssertTrue(app.buttons["quran.play"].waitForExistence(timeout: 3))
        app.buttons["reader.next"].tap()
        XCTAssertTrue(app.staticTexts["Ayah 2 of 286"].exists)
        XCTAssertFalse(app.buttons["session.done"].exists)
        XCTAssertFalse(app.buttons["session.answer.memorized"].exists)
        capture(app, name: "Reader")
    }

    /// Opening a long surah deep down lands on the ayah in both layouts.
    @MainActor
    func testSearchOpensAlBaqarahAtAyah282() {
        for layout in ["ayahByAyah", "mushaf"] {
            let app = launch(extra: ["-settings.quranReadingLayout", layout])
            app.tabBars.buttons["Quran"].tap()
            let search = app.searchFields.firstMatch
            // In portrait the search bar stays tucked under the title until the list is pulled down.
            if !search.waitForExistence(timeout: 2) { app.swipeDown() }
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("2:282")
            let hit = app.buttons["quran.search.verse-289"]
            XCTAssertTrue(hit.waitForExistence(timeout: 3))
            hit.tap()
            XCTAssertTrue(app.buttons["quran.play"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Ayah 282 of 286"].exists)
            if layout == "ayahByAyah" {
                XCTAssertTrue(app.buttons["ayah.289"].waitForExistence(timeout: 3))
                XCTAssertTrue(app.buttons["ayah.289"].isHittable)
            }
            capture(app, name: "Reader-2-282-\(layout)")
            app.terminate()
        }
    }

    @MainActor
    func testMiniPlayerReturnsToTheSession() {
        let app = launch()
        choosePlan(app, select: "plan.select.ayah.8")
        app.buttons["memorize.start"].tap()
        XCTAssertTrue(app.buttons["session.change"].waitForExistence(timeout: 5))
        app.buttons["session.close"].tap()
        XCTAssertTrue(app.buttons["playback.open"].waitForExistence(timeout: 3))
        app.buttons["playback.open"].tap()
        XCTAssertTrue(app.buttons["session.change"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["session.play"].exists)
    }

    @MainActor
    func testChangePassageAndMoveToTheNextOne() {
        let app = launch()
        choosePlan(app, select: "plan.select.ayah.8")
        app.buttons["memorize.start"].tap()
        app.buttons["session.change"].tap()
        XCTAssertTrue(app.navigationBars["Your passage"].waitForExistence(timeout: 3))
        app.buttons["One page"].tap()
        capture(app, name: "Passage-Picker")
        app.buttons["passage.start"].tap()
        XCTAssertTrue(app.buttons["session.play"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["From memory"].tap()
        app.buttons["session.answer.memorized"].tap()
        app.buttons["session.nextPassage"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ayahs 6–16")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["session.done"].tap()
        XCTAssertTrue(app.buttons["memorize.start"].waitForExistence(timeout: 3))
        capture(app, name: "Memorize-Continue")
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
        XCTAssertTrue(app.buttons["quran.play"].exists)
        capture(app, name: "Juz-Reader")
    }

    @MainActor
    func testNightAppearanceAndContinuousText() {
        let app = launch(appearance: "night", extra: ["-settings.quranReadingLayout", "mushaf"])
        capture(app, name: "Memorize-Night")
        app.buttons["memorize.other"].tap()
        app.buttons["plan.select.ayah.1"].tap()
        app.buttons["plan.start"].tap()
        XCTAssertTrue(app.buttons["session.play"].waitForExistence(timeout: 5))
        capture(app, name: "Session-Night-Continuous")
        app.segmentedControls.buttons["From memory"].tap()
        XCTAssertTrue(app.buttons["session.answer.memorized"].waitForExistence(timeout: 3))
        capture(app, name: "Session-Night-Recall")
    }

    @MainActor
    func testLargeTextAndLandscape() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        choosePlan(app)
        let start = app.buttons["memorize.start"]
        for _ in 0..<6 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["session.play"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["session.nextStep"].isHittable)
        XCTAssertTrue(app.buttons["session.done"].isHittable)
        capture(app, name: "Session-LargeText")
        app.terminate()
        let landscape = launch()
        choosePlan(landscape)
        landscape.buttons["memorize.start"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            landscape.frame.width > landscape.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        XCTAssertTrue(landscape.buttons["session.next"].waitForExistence(timeout: 3))
        XCTAssertTrue(landscape.buttons["session.nextStep"].isHittable)
        capture(landscape, name: "Session-Landscape")
    }

    @MainActor
    func testSwitchingPlansKeepsTheOtherWaiting() {
        let app = launch()
        choosePlan(app)
        app.buttons["memorize.plan"].tap()
        XCTAssertTrue(app.buttons["plan.memorizeNext"].waitForExistence(timeout: 3))
        app.buttons["plan.change"].tap()
        app.segmentedControls.buttons["Juz"].tap()
        app.buttons["plan.select.juz.1"].tap()
        app.buttons["plan.save"].tap()
        XCTAssertTrue(app.staticTexts["Juz 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Switch"].exists)
        capture(app, name: "Plan-UpNext")
    }

    @MainActor
    func testCustomRangeCanBeChosenEditedAndReopenedWithoutChangingIt() {
        let app = launch()
        app.buttons["memorize.choosePlan"].tap()
        app.buttons["plan.custom"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "2")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "5")
        capture(app, name: "Plan-Custom-Range")
        app.buttons["plan.range.save"].tap()
        app.buttons["plan.save"].tap()
        app.buttons["memorize.plan"].tap()
        app.buttons["plan.edit"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "2")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "5")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "6")
        app.buttons["plan.range.save"].tap()
        app.buttons["plan.memorizeNext"].tap()
        app.buttons["session.change"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        let end = app.pickerWheels.element(boundBy: 1).value as? String
        app.buttons["passage.start"].tap()
        app.buttons["session.change"].tap()
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, end)
        capture(app, name: "Passage-Exact-Range")
    }

    @MainActor
    func testRangeControlsInDarkModeWithLargeText() {
        let app = launch(appearance: "night", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        let choose = app.buttons["memorize.choosePlan"]
        for _ in 0..<10 where !choose.isHittable { app.swipeUp() }
        choose.tap()
        app.buttons["plan.custom"].tap()
        XCTAssertTrue(app.buttons["plan.range.save"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["plan.range.save"].isHittable)
        let wheel = app.pickerWheels.element(boundBy: 0)
        for _ in 0..<5 where !wheel.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(wheel.isHittable)
        wheel.adjust(toPickerWheelValue: "2")
        capture(app, name: "Range-Night-LargeText")
        app.buttons["plan.range.save"].tap()
        XCTAssertTrue(app.buttons["plan.save"].isHittable)
        app.buttons["plan.save"].tap()
    }

    @MainActor
    func testChoosingAnotherSurahKeepsTheNewRange() {
        let app = launch()
        app.buttons["memorize.choosePlan"].tap()
        app.buttons["plan.custom"].tap()
        app.buttons["range.startSurah"].tap()
        app.buttons["2. Al-Baqara"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "4")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "6")
        app.buttons["plan.range.save"].tap()
        app.buttons["plan.save"].tap()
        app.buttons["memorize.plan"].tap()
        app.buttons["plan.edit"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "4")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "6")
    }

    @MainActor
    func testRangeEditorKeepsSaveVisibleInLandscape() {
        let app = launch()
        app.buttons["memorize.choosePlan"].tap()
        app.buttons["plan.custom"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["plan.range.save"].isHittable)
        XCTAssertTrue(app.pickerWheels.element(boundBy: 0).isHittable)
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "2")
        capture(app, name: "Range-Landscape")
        app.buttons["plan.range.save"].tap()
        XCTAssertTrue(app.buttons["plan.save"].isHittable)
        app.buttons["plan.save"].tap()
    }

    @MainActor
    private func launchFresh() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-focus", "-ui-testing-reset-onboarding",
                               "-settings.appearance", "light", "-settings.quranReadingLayout", "ayahByAyah",
                               "-learning.start", "0", "-learning.end", "0", "-reading.ayah", "0", "-learning.byPage", "NO"]
        app.launch()
        return app
    }

    @MainActor
    func testOnboardingForReadersOpensTheQuran() {
        let app = launchFresh()
        XCTAssertTrue(app.buttons["onboarding.intent.readAndListen"].waitForExistence(timeout: 5))
        capture(app, name: "Onboarding-Intent")
        app.buttons["onboarding.intent.readAndListen"].tap()
        XCTAssertTrue(app.navigationBars["Quran"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOnboardingForMemorizersSeedsWhatTheyKnowAndAPlan() {
        let app = launchFresh()
        app.buttons["onboarding.intent.memorize"].tap()
        XCTAssertTrue(app.buttons["known.1"].waitForExistence(timeout: 3))
        app.buttons["known.1"].tap()
        capture(app, name: "Onboarding-Known")
        app.buttons["known.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.plan.juz30"].waitForExistence(timeout: 3))
        capture(app, name: "Onboarding-Plan")
        app.buttons["onboarding.plan.juz30"].tap()
        XCTAssertTrue(app.buttons["memorize.start"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["memorize.plan"].label.contains("Juz 30"))
        XCTAssertEqual(memorizedCount(app), "7")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
