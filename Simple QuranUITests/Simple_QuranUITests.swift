import XCTest

final class Simple_QuranUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstLaunchShowsPracticeHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-settings.appearance", "light", "-settings.quranReadingLayout", "ayahByAyah"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.settings"].exists)
    }

    @MainActor
    func testQuranTabListsSurahs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-settings.appearance", "light", "-settings.quranReadingLayout", "ayahByAyah"]
        app.launch()
        app.tabBars.buttons["Quran"].tap()
        XCTAssertTrue(app.buttons["quran.surah.1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOpeningASurahDoesNotPresentCollectionEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-settings.appearance", "light", "-settings.quranReadingLayout", "ayahByAyah"]
        app.launch()
        app.tabBars.buttons["Quran"].tap()
        app.buttons["quran.surah.1"].tap()
        XCTAssertTrue(app.buttons["quran.play"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ayah.1"].waitForExistence(timeout: 5))
        app.buttons["quran.play"].tap()
        XCTAssertFalse(app.textFields["set.editor.title"].exists)
        app.buttons["ayah.1"].tap()
        XCTAssertFalse(app.textFields["set.editor.title"].exists)
    }

    @MainActor
    func testCreateSetFromAlFatiha() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-settings.appearance", "light", "-settings.quranReadingLayout", "ayahByAyah"]
        app.launch()
        app.tabBars.buttons["Quran"].tap()
        app.buttons["quran.surah.1"].tap()
        XCTAssertTrue(app.buttons["quran.collect"].waitForExistence(timeout: 5))
        app.buttons["quran.collect"].tap()
        XCTAssertTrue(app.buttons["ayah.1"].waitForExistence(timeout: 5))
        app.buttons["ayah.1"].tap()
        let lastAyah = app.buttons["ayah.7"]
        for _ in 0..<8 where !lastAyah.isHittable { app.swipeUp() }
        XCTAssertTrue(lastAyah.isHittable)
        lastAyah.tap()
        XCTAssertTrue(app.buttons["quran.tray.save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["set.editor.title"].exists)
        app.buttons["quran.tray.save"].tap()
        let title = app.textFields["set.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["set.editor.save"].tap()
        app.tabBars.buttons["Collections"].tap()
        XCTAssertTrue(app.staticTexts["Al-Faatiha"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPracticeControlsAndOptions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-settings.appearance", "light"]
        app.launch()
        app.buttons["home.startPractice"].tap()
        XCTAssertTrue(app.buttons["practice.play"].waitForExistence(timeout: 5))
        capture(app, name: "Practice-Light")
        app.buttons["practice.next"].tap()
        XCTAssertTrue(app.staticTexts["Ayah 2 of 7"].waitForExistence(timeout: 5))
        app.buttons["practice.previous"].tap()
        XCTAssertTrue(app.staticTexts["Ayah 1 of 7"].waitForExistence(timeout: 5))
        app.buttons["practice.hideArabic"].tap()
        XCTAssertTrue(app.buttons["practice.hideArabic"].label.contains("Reveal"))
        app.buttons["practice.options"].tap()
        XCTAssertTrue(app.navigationBars["Practice options"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Advance manually"].exists)
        capture(app, name: "Practice-Options")
        app.navigationBars["Practice options"].buttons["Done"].tap()
        app.buttons["practice.finish"].tap()
        XCTAssertTrue(app.navigationBars["How did recall feel?"].waitForExistence(timeout: 5))
        app.buttons["Skip Rating"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeReaderCanSaveWholePassage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-settings.appearance", "light"]
        app.launch()
        let surah = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Al-Faatiha, The Opening")).firstMatch
        for _ in 0..<5 where !surah.isHittable { app.swipeUp() }
        XCTAssertTrue(surah.isHittable)
        surah.tap()
        app.buttons["quran.memorizeWhole"].tap()
        XCTAssertTrue(app.textFields["set.editor.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["set.editor.save"].label, "Save & practice")
        app.buttons["set.editor.save"].tap()
        XCTAssertTrue(app.buttons["practice.play"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testThemesAndExpandedPlayer() throws {
        let app = XCUIApplication()
        for appearance in ["light", "night"] {
            app.launchArguments = ["-ui-testing", "-settings.appearance", appearance, "-settings.quranReadingLayout", "ayahByAyah"]
            app.launch()
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
            capture(app, name: "Today-\(appearance)")
            app.tabBars.buttons["Quran"].tap()
            XCTAssertTrue(app.buttons["quran.surah.1"].waitForExistence(timeout: 5))
            capture(app, name: "Quran-\(appearance)")
            app.buttons["quran.surah.1"].tap()
            XCTAssertTrue(app.buttons["quran.play"].waitForExistence(timeout: 5))
            capture(app, name: "Reader-\(appearance)")
            app.buttons["quran.play"].tap()
            XCTAssertTrue(app.buttons["playback.open"].waitForExistence(timeout: 5))
            app.buttons["playback.open"].tap()
            XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 5))
            capture(app, name: "Player-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testLargeTextAndLandscapePractice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-settings.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        let start = app.buttons["home.startPractice"]
        for _ in 0..<6 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        capture(app, name: "Today-LargeText")
        start.tap()
        XCTAssertTrue(app.buttons["practice.play"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["practice.next"].isHittable)
        capture(app, name: "Practice-LargeText")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-settings.appearance", "night"]
        app.launch()
        app.buttons["home.startPractice"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["practice.next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["practice.next"].isHittable)
        app.buttons["practice.next"].tap()
        XCTAssertTrue(app.staticTexts["Ayah 2 of 7"].waitForExistence(timeout: 5))
        capture(app, name: "Practice-Landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
