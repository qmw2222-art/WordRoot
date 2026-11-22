import XCTest

@MainActor
final class DailyStartTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-wordroot.course.autoGuide", "NO"]
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 6), id, file: file, line: line)
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable, id, file: file, line: line)
        button.tap()
    }

    private func startSecondDay() {
        let next = app.buttons["course.followingDay"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.label.contains("2") && next.label.contains("help") && next.label.contains("帮"))
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThan(next.frame.midY, app.frame.height * 0.75)
        next.tap()
        XCTAssertEqual(app.staticTexts["course.root"].label, "help")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "help")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].label.contains("help"))
    }

    func testNewDayFromGettingADrinkIntoAskingForHelp() {
        app.launch()
        XCTAssertTrue(app.staticTexts["course.focus"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["course.focus"].label.contains("drink"))
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.root"].label, "drink")
        let ids = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'course.branch.'")).allElementsBoundByIndex
        XCTAssertTrue(ids.contains { $0.identifier == "course.branch.basic.i" })
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "drink")
        XCTAssertEqual(app.staticTexts["course.context.line"].label, "I drink water.")
        for _ in ids {
            tap("course.next")
            if app.buttons["course.familyRecap.close"].exists { tap("course.familyRecap.close") }
        }
        startSecondDay()
    }

    func testCompletedPortStillOpensHelpAndRecapCanReview() {
        app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"] = "port-finished-v24"
        app.launch()
        XCTAssertEqual(app.staticTexts["course.suggestedDay"].label.replacingOccurrences(of: " ", with: ""), "第2天")
        XCTAssertTrue(app.staticTexts["course.focus"].label.contains("help"))
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.root"].label, "help")
        app.terminate()
        app.launch()
        tap("course.phase.daily")
        tap("course.day.1")
        tap("course.recapCards")
        XCTAssertTrue(app.buttons["cards.mode.meaning"].waitForExistence(timeout: 7))
        tap("cards.dismiss")
        startSecondDay()
    }

    func testUnfinishedPortBackupAndRelaunch() {
        app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"] = "port-backup-v24"
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].label.contains("portable"))
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.word"].label, "portable")
        tap("course.next")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].label.contains("exporter"))
    }

    func testNewDrinkingLessonBackupAndRelaunch() {
        app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"] = "drink-backup-v25"
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].label.contains("drinkable"))
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.word"].label, "drinkable")
        tap("course.next")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].label.contains("drinking water"))
    }

    func testPointReadAndListenToBothWordsFromPort() {
        app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"] = "port-start-v24"
        app.launch()
        tap("course.start")
        tap("course.branch.basic.i")
        XCTAssertEqual(app.staticTexts["course.word"].label, "I")
        tap("course.audio.word")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "take")
        tap("course.audio.word")
        tap("course.readingAid")
        XCTAssertFalse(app.staticTexts["course.readingSound"].label.contains("泰"))
        XCTAssertTrue(app.staticTexts["course.readingSound"].label.contains("诶"))
    }
}

