import XCTest

@MainActor
final class WordFlowTests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(legacy: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        if legacy { app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"] = "1" }
        app.launch()
    }

    func testWholePartsAndSentenceNeighbors() {
        launch()
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.rootIPA"].label, "/pɔrt/")
        adjacent(app.staticTexts["course.rootIPA"], app.buttons["course.audio.root"])
        tap("course.audio.root")
        tap("course.branch.sense.portable.easy-carry")
        XCTAssertTrue(app.staticTexts["course.word"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["course.word"].label, "portable")
        XCTAssertEqual(app.staticTexts["course.partIPA.1"].label, "/əbəl/")
        adjacent(app.staticTexts["course.partIPA.1"], app.buttons["course.partAudio.1"])
        tap("course.audio.word")
        tap("course.partAudio.0")
        tap("course.partAudio.1")
        tap("course.next")
        XCTAssertTrue(app.staticTexts["course.word"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["course.word"].label, "I")
        XCTAssertEqual(app.staticTexts["course.context.line"].label, "Can I take this bag?")
        tap("course.context.basic.bag")
        XCTAssertTrue(app.staticTexts["course.word"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["course.word"].label, "bag")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "词骨")).firstMatch.exists)
    }

    func testLegacyPositionAndOneProgress() {
        launch(legacy: true)
        XCTAssertTrue(app.staticTexts["course.learnedSenses"].label.replacingOccurrences(of: ",", with: "").contains("4 / 1335"))
        XCTAssertFalse(app.staticTexts["course.basicProgress"].exists)
        tap("course.start")
        XCTAssertTrue(app.staticTexts["course.word"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["course.word"].label, "I")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.buttons["home.due"].value as? String, "共有4个词到期")
        XCTAssertFalse(app.tabBars.buttons["复习"].exists)
    }

    func testWrongChoiceRetriesWithoutExtendingInterval() {
        launch(legacy: true)
        app.tabBars.buttons["地图"].tap()
        tap("branch.sense.export.goods")
        tap("word.practice")
        tap("cards.mode.meaning")
        XCTAssertFalse(app.staticTexts["cards.feedback"].exists)
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cards.choice.'"))
        XCTAssertGreaterThanOrEqual(choices.count, 3)
        let wrong = choices.allElementsBoundByIndex.first { !$0.label.contains("出口") }!
        wrong.tap()
        XCTAssertTrue(app.staticTexts["cards.feedback"].label.contains("出口"))
        let date = app.staticTexts["cards.nextDate"].label
        XCTAssertTrue(date.contains("分钟"))
        tap("cards.next")
        tap("cards.mode.meaning")
        app.buttons["cards.choice.sense.export.goods"].tap()
        XCTAssertEqual(app.staticTexts["cards.nextDate"].label, date)
        tap("cards.next")
        XCTAssertTrue(app.staticTexts["cards.done"].exists)
        app.terminate(); app.launch()
        XCTAssertEqual(app.buttons["home.due"].value as? String, "共有3个词到期")
    }

    func testCorrectReviewPersistsAndRecapStartsCards() {
        launch()
        tap("course.start")
        tap("course.lessonAutoVoice")
        for _ in 0..<14 { tap("course.next") }
        tap("course.recapCards")
        tap("cards.mode.meaning")
        let answers = app.buttons.matching(identifier: "cards.choice.sense.import.goods")
        XCTAssertTrue(answers.firstMatch.waitForExistence(timeout: 4))
        answers.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["cards.nextDate"].label.contains("天"))
        app.terminate(); app.launch()
        XCTAssertEqual(app.buttons["home.due"].value as? String, "共有12个词到期")
    }

    func testPracticeFromMapAndOneVoice() {
        launch()
        app.tabBars.buttons["地图"].tap()
        tap("branch.sense.export.goods")
        tap("word.practice")
        XCTAssertTrue(app.buttons["cards.listen"].exists)
        tap("cards.mode.spelling")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cards.choice.'")).count, 3)
        XCTAssertFalse(app.textFields.firstMatch.exists)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["settings.voice"].label.contains("Heart"))
        XCTAssertFalse(app.buttons["settings.voice"].exists)
        tap("settings.voice.audition")
    }

    private func adjacent(_ left: XCUIElement, _ right: XCUIElement) {
        XCTAssertLessThan(abs(left.frame.midY - right.frame.midY), 12)
        XCTAssertLessThan(abs(right.frame.minX - left.frame.maxX), 25)
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 4), id, file: file, line: line)
        if id.hasPrefix("course.branch.") || id.hasPrefix("course.context.") || id=="word.practice" {
            let scroll = app.scrollViews.firstMatch
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            let foot = app.buttons["course.next"]
            let bottom = (foot.exists ? foot.frame.minY : app.tabBars.firstMatch.frame.minY) - 8
            for _ in 0..<12 {
                let y = button.frame.midY
                if y >= top && y <= bottom && button.isHittable { break }
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55))
                let shift = min(max(abs(y-(top+bottom)/2), 70), 200)
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: y < top ? shift : -shift)), withVelocity: .fast, thenHoldForDuration: 0.1)
            }
        } else {
            for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        }
        XCTAssertTrue(button.isHittable, id, file: file, line: line)
        button.tap()
    }
}
