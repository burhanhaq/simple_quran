import XCTest

final class Simple_QuranUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(appearance: String = "light", extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-focus", "-settings.appearance", appearance, "-settings.quranReadingLayout", "ayahByAyah",
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
    func testMultipleSurahsAndWholeJuzCanBeTrackedTogether() {
        let app = launch()
        let add = app.buttons["focus.add"]
        for _ in 0..<5 where !add.isHittable { app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.navigationBars["Add a focus"].waitForExistence(timeout: 3))
        app.buttons["focus.select.ayah.1"].tap()
        app.buttons["focus.select.ayah.8"].tap()
        app.segmentedControls.buttons["Juz"].tap()
        app.buttons["focus.select.juz.1"].tap()
        XCTAssertTrue(app.staticTexts["3 selected"].exists)
        capture(app, name: "Focus-Multiple-Selection")
        app.buttons["focus.save"].tap()
        let juz = app.buttons["focus.item.1.148"]
        for _ in 0..<6 where !juz.isHittable { app.swipeUp() }
        XCTAssertTrue(juz.exists)
        juz.tap()
        XCTAssertTrue(app.buttons["focus.practice"].waitForExistence(timeout: 3))
        capture(app, name: "Focus-Juz-Detail")
        app.buttons["focus.practice"].tap()
        app.buttons["practice.finish"].tap()
        app.buttons["practice.rate.solid"].tap()
        app.buttons["practice.nextPassage"].tap()
        XCTAssertTrue(app.navigationBars["Al-Baqara"].waitForExistence(timeout: 3))
        app.buttons["reader.close"].tap()
        XCTAssertTrue(app.staticTexts["7 of 148 ayahs practiced"].exists)
    }

    @MainActor
    func testCustomRangeCanBeAddedEditedAndReopenedWithoutChangingIt() {
        let app = launch()
        let add = app.buttons["focus.add"]
        for _ in 0..<5 where !add.isHittable { app.swipeUp() }
        add.tap()
        app.buttons["focus.custom"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "2")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "5")
        capture(app, name: "Focus-Custom-Range")
        app.buttons["focus.range.save"].tap()
        app.buttons["focus.save"].tap()
        let focus = app.buttons["focus.item.2.5"]
        for _ in 0..<5 where !focus.isHittable { app.swipeUp() }
        focus.tap()
        app.buttons["focus.edit"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "2")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "5")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "6")
        app.buttons["focus.range.save"].tap()
        app.buttons["focus.practice"].tap()
        app.buttons["practice.change"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        let end = app.pickerWheels.element(boundBy: 1).value as? String
        app.buttons["passage.start"].tap()
        app.buttons["practice.change"].tap()
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, end)
        capture(app, name: "Passage-Exact-Range")
    }

    @MainActor
    func testFocusRangeControlsInDarkModeWithLargeText() {
        let app = launch(appearance: "night", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        let add = app.buttons["focus.add"]
        for _ in 0..<10 where !add.isHittable { app.swipeUp() }
        add.tap()
        let custom = app.buttons["focus.custom"]
        for _ in 0..<8 where !custom.isHittable { app.swipeUp() }
        custom.tap()
        XCTAssertTrue(app.buttons["focus.range.save"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["focus.range.save"].isHittable)
        let wheel = app.pickerWheels.element(boundBy: 0)
        for _ in 0..<5 where !wheel.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(wheel.isHittable)
        wheel.adjust(toPickerWheelValue: "2")
        capture(app, name: "Focus-Range-Night-LargeText")
        app.buttons["focus.range.save"].tap()
        XCTAssertTrue(app.buttons["focus.save"].isHittable)
        app.buttons["focus.save"].tap()
    }

    @MainActor
    func testChoosingAnotherSurahKeepsTheNewRange() {
        let app = launch()
        let add = app.buttons["focus.add"]
        for _ in 0..<5 where !add.isHittable { app.swipeUp() }
        add.tap()
        app.buttons["focus.custom"].tap()
        app.buttons["range.startSurah"].tap()
        app.buttons["2. Al-Baqara"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "4")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "6")
        app.buttons["focus.range.save"].tap()
        app.buttons["focus.save"].tap()
        let focus = app.buttons["focus.item.11.13"]
        for _ in 0..<5 where !focus.isHittable { app.swipeUp() }
        XCTAssertTrue(focus.exists)
        focus.tap()
        app.buttons["focus.edit"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "4")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "6")
    }

    @MainActor
    func testRangeEditorKeepsSaveVisibleInLandscape() {
        let app = launch()
        let add = app.buttons["focus.add"]
        for _ in 0..<5 where !add.isHittable { app.swipeUp() }
        add.tap()
        app.buttons["focus.custom"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["focus.range.save"].isHittable)
        XCTAssertTrue(app.pickerWheels.element(boundBy: 0).isHittable)
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "2")
        capture(app, name: "Focus-Range-Landscape")
        app.buttons["focus.range.save"].tap()
        XCTAssertTrue(app.buttons["focus.save"].isHittable)
        capture(app, name: "Focus-Selection-Landscape")
        app.buttons["focus.save"].tap()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
