import XCTest

final class Simple_QuranUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstLaunchShowsPracticeHome() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.settings"].exists)
    }

    @MainActor
    func testQuranTabListsSurahs() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Quran"].tap()
        XCTAssertTrue(app.buttons["quran.surah.1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOpeningASurahDoesNotPresentCollectionEditor() throws {
        let app = XCUIApplication()
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
        app.launch()
        app.tabBars.buttons["Quran"].tap()
        app.buttons["quran.surah.1"].tap()
        XCTAssertTrue(app.buttons["quran.collect"].waitForExistence(timeout: 5))
        app.buttons["quran.collect"].tap()
        XCTAssertTrue(app.buttons["ayah.1"].waitForExistence(timeout: 5))
        app.buttons["ayah.1"].tap()
        app.buttons["ayah.7"].tap()
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
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
