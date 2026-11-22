import XCTest

@MainActor
final class SequenceTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-wordroot.course.autoGuide","NO"]
    }

    private func tap(_ id: String) {
        let b=app.buttons[id].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 7), id)
        for _ in 0..<10 where !b.isHittable { app.swipeUp() }
        XCTAssertTrue(b.isHittable, id)
        b.tap()
    }

    func testNewLearnerPractisesHelpThenEats() {
        app.launch()
        tap("course.phase.daily")
        tap("course.day.2")
        XCTAssertEqual(app.staticTexts["course.root"].label,"help")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label,"help")
        tap("course.next")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].label.contains("helper"))
        tap("course.phase.daily")
        tap("course.day.3")
        XCTAssertEqual(app.staticTexts["course.root"].label,"eat")
    }

    func testEarlierWashPositionFollowsTheLessonWhenDayChanges() {
        app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"]="wash-v22"
        app.launch()
        XCTAssertEqual(app.staticTexts["course.suggestedDay"].label,"第 8 天")
        XCTAssertTrue(app.buttons["course.start"].label.contains("soap"))
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.word"].label,"soap")
        tap("course.next")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].label.contains("with"))
    }
}
