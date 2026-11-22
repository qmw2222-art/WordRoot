import XCTest

@MainActor
final class NoviceJourneyTests: XCTestCase {
    private let app = XCUIApplication()
    private let port = ["sense.import.goods", "sense.export.goods", "sense.transport.carry",
                        "sense.portable.easy-carry", "port.exporter", "port.importer",
                        "port.transportation", "port.portability"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"] = "port-start-v24"
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-wordroot.course.autoGuide", "NO"]
        app.launch()
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 6), id, file: file, line: line)
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable, id, file: file, line: line)
        button.tap()
    }

    private func reachCards() {
        tap("course.start")
        tap("course.next")
        for _ in port { tap("course.next") }
        tap("course.familyRecap.cards")
    }

    func testStartFromChineseAndLearnTheOppositeDirection() {
        tap("course.start")
        XCTAssertEqual(app.buttons["course.next"].label, "学 import（进口）")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "import")
        XCTAssertTrue(app.buttons["course.audio.word"].exists)
        XCTAssertEqual(app.buttons["course.next"].label, "学 export（出口）")
        tap("course.next")
        let explanation = app.staticTexts["course.coach.word"].label
        for clue in ["im-", "向内", "进口", "ex-", "向外", "出口"] {
            XCTAssertTrue(explanation.contains(clue), explanation)
        }
        app.terminate()
        app.launch()
        XCTAssertEqual(app.buttons["course.start"].label, "继续学 export（出口）")
    }

    func testFamilyCardsReturnStraightToTheNextWord() {
        reachCards()
        for id in port {
            tap("cards.choice." + id)
            tap("cards.next")
        }
        XCTAssertEqual(app.buttons["cards.close"].label, "继续学 I（我）")
        tap("cards.close")
        XCTAssertTrue(app.staticTexts["course.word"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["course.word"].label, "I")
    }

    func testHomeResumesExactCardAndClearsItAfterFinishing() {
        reachCards()
        for id in port.prefix(3) {
            tap("cards.choice." + id)
            if id != port[2] { tap("cards.next") }
        }
        app.terminate()
        app.launch()
        let resume = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.resumeCards.'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        for value in ["port", "第 4 张"] { XCTAssertTrue(resume.label.contains(value), resume.label) }
        XCTAssertTrue(resume.isHittable)
        resume.tap()
        XCTAssertTrue(app.staticTexts["第 4 张 · 共 8 张"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cards.prompt"].label, "听到的词是什么意思？")
        for id in port.dropFirst(3) {
            tap("cards.choice." + id)
            tap("cards.next")
        }
        tap("cards.close")
        XCTAssertTrue(app.buttons["course.start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["course.start"].label, "继续学 I（我）")
        XCTAssertFalse(resume.exists)
    }
}
