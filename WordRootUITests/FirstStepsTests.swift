import XCTest
@MainActor
final class FirstStepsTests: XCTestCase {
    private let app = XCUIApplication()
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"] = "port-start-v24"
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-wordroot.course.autoGuide","NO"]
    }
    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let b = app.buttons[id].firstMatch
        for _ in 0..<8 {
            if b.exists && b.isHittable { b.tap(); return }
            app.swipeUp()
        }
        XCTFail(id, file: file, line: line)
    }
    func testFirstPairCanPauseAndContinueAtTransport() {
        app.launch()
        let focus=app.staticTexts["course.focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 8))
        XCTAssertTrue(focus.label.contains("import") && focus.label.contains("export"))
        tap("course.start")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label,"import")
        XCTAssertTrue(app.staticTexts["course.group"].label.contains("1 / 2"))
        XCTAssertFalse(app.buttons["course.pause"].exists)
        XCTAssertEqual(app.staticTexts["course.context.line"].label,"We import tea.")
        tap("course.context.pieces")
        XCTAssertEqual(app.staticTexts["course.context.piece.0"].label,"We · 我们")
        XCTAssertEqual(app.staticTexts["course.context.piece.1"].label,"import · 进口")
        XCTAssertEqual(app.staticTexts["course.context.piece.2"].label,"tea · 茶叶")
        tap("course.context.audio")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.context.line"].label,"We export tea.")
        XCTAssertFalse(app.staticTexts["course.context.piece.0"].exists)
        XCTAssertTrue(app.staticTexts["course.group"].label.contains("2 / 2"))
        tap("course.pause")
        XCTAssertTrue(app.buttons["course.start"].label.contains("transport"))
        XCTAssertTrue(app.staticTexts["course.learnedSenses"].label.replacingOccurrences(of:",",with:"").contains("2 / 1335"))
        app.terminate(); app.launch()
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.word"].label,"transport")
        XCTAssertEqual(app.staticTexts["course.reminder.root"].label,"port")
    }
    func testMistakeShowsAndPlaysBothWordsOnlyAfterAnswer() {
        app.launch()
        tap("course.start"); tap("course.next"); tap("course.next")
        app.navigationBars.buttons.element(boundBy:0).tap()
        tap("home.due")
        let right="cards.choice.sense.import.goods"
        XCTAssertTrue(app.buttons[right].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["cards.comparison"].exists)
        let options=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@", "cards.choice.")).allElementsBoundByIndex
        let wrong=options.first { $0.identifier != right }!
        let answer = wrong.label
        wrong.tap()
        XCTAssertTrue(app.staticTexts["cards.feedback"].label.contains("import"))
        XCTAssertTrue(app.staticTexts["cards.comparison"].label.contains(answer))
        tap("cards.wrongAudio")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        tap("cards.answer.audio.word")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let due=app.staticTexts["cards.nextDate"].label
        tap("cards.next")
        XCTAssertFalse(app.staticTexts["cards.comparison"].exists)
        tap(right)
        XCTAssertFalse(app.staticTexts["cards.comparison"].exists)
        XCTAssertTrue(app.staticTexts["cards.feedback"].label.contains("选对了"))
        XCTAssertEqual(app.staticTexts["cards.nextDate"].label,due)
    }
}
