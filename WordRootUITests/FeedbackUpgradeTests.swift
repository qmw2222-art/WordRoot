import XCTest

@MainActor
final class FeedbackUpgradeTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-wordroot.course.autoGuide", "NO", "-wordroot.familyStudy.family.port", "finished"]
        app.launch()
    }

    func testDay79KeepsRootOnNewAndPlaysInPlace() async throws {
        try await usePurchasedCourse()
        tap("course.phase.other")
        tap("course.day.79")
        tap("course.branch.duc.introduce")
        let root = app.staticTexts["course.reminder.root"]
        XCTAssertEqual(root.label, "duc")
        XCTAssertTrue(app.staticTexts["course.reminder.meaning"].label.contains("引领"))
        tap("course.reminder.audio")
        tap("course.context.basic.new")
        XCTAssertEqual(app.staticTexts["course.word"].label, "new")
        XCTAssertTrue(app.staticTexts["course.meaning"].label.contains("新的"))
        let rootY = root.frame.midY
        app.swipeUp()
        XCTAssertTrue(root.isHittable)
        XCTAssertEqual(root.frame.midY, rootY, accuracy: 4)
        app.swipeDown()
        tap("course.audio.word")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertEqual(app.staticTexts["course.word"].label, "new")
        tap("course.readingAid")
        XCTAssertEqual(app.staticTexts["course.readingSound"].label, "努")
        XCTAssertEqual(root.label, "duc")
    }

    func testDefaultChineseAndManualEnglishAcrossCardsAndHome() {
        tap("home.due")
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cards.choice.'"))
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(choices.allElementsBoundByIndex.allSatisfy { $0.label.range(of: "[一-龥]", options: .regularExpression) != nil })
        XCTAssertFalse(app.buttons["cards.answer.dictionary"].exists)
        tap("cards.mode.spelling")
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(choices.allElementsBoundByIndex.allSatisfy { $0.label.range(of: "[A-Za-z]", options: .regularExpression) != nil })
        tap("cards.unknown")
        XCTAssertTrue(app.buttons["cards.answer.audio.word"].exists)
        XCTAssertEqual(app.webViews.count, 0)
        tap("cards.next")
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["cards.prompt"].label.contains("哪个单词"))
        tap("cards.dismiss")
        tap("course.start")
        tap("course.family.all")
        tap("family.recapCards")
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["cards.prompt"].label.contains("意思"))
        XCTAssertTrue(choices.allElementsBoundByIndex.allSatisfy { $0.label.range(of: "[一-龥]", options: .regularExpression) != nil })
    }

    func testFourCourseSensesGiveUnambiguousPracticeChoices() {
        let targets = [("new", "新的", ""), ("now", "现在", ""), ("like", "像", "喜欢"), ("present", "现在", "现在的")]
        for (word, meaning, excluded) in targets {
            app.terminate()
            app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
            app.launchEnvironment["WORDROOT_TEST_DUE_WORD"] = "basic." + word
            app.launchArguments = ["-wordroot.course.autoGuide", "NO"]
            app.launch()
            tap("home.due")
            let target = app.buttons["cards.choice.basic." + word]
            XCTAssertTrue(target.waitForExistence(timeout: 15))
            XCTAssertTrue(target.label.hasPrefix(meaning), target.label)
            let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cards.choice.'"))
            XCTAssertEqual(choices.count, 4)
            if !excluded.isEmpty {
                XCTAssertFalse(app.staticTexts["cards.prompt"].label.contains("例句"))
                XCTAssertFalse(choices.allElementsBoundByIndex.contains { $0.label.components(separatedBy: "；").contains(excluded) })
            }
            tap("cards.mode.spelling")
            XCTAssertTrue(target.waitForExistence(timeout: 8))
            XCTAssertEqual(target.label, word)
            target.tap()
            XCTAssertTrue(app.staticTexts["cards.feedback"].label.contains("选对了"))
        }
    }

    func testFamilyReminderRemainsVisibleBetweenWords() {
        app.terminate()
        app.launchArguments = ["-wordroot.course.autoGuide","NO"]
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
        tap("course.start")
        tap("course.family.all")
        let root = app.staticTexts["family.reminder.root"]
        XCTAssertEqual(root.label, "port")
        let y = root.frame.midY
        app.swipeUp()
        XCTAssertTrue(root.isHittable)
        XCTAssertEqual(root.frame.midY, y, accuracy: 4)
        tap("family.next")
        XCTAssertEqual(root.label, "port")
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id].firstMatch
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 6), id, file: file, line: line)
        let footer = app.buttons["course.next"]
        if id.hasPrefix("course.context.") || id.hasPrefix("course.branch.") {
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<18 {
                let y = button.frame.midY
                let top = app.navigationBars.firstMatch.frame.maxY + 68
                let bottom = footer.frame.minY - 14
                if button.isHittable && y >= top && y <= bottom { break }
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.54))
                let amt = min(185, max(55, abs(y - (top+bottom)/2)))
                start.press(forDuration: 0.08, thenDragTo: start.withOffset(CGVector(dx: 0, dy: y < top ? amt : -amt)), withVelocity: .fast, thenHoldForDuration: 0.05)
            }
        }
        XCTAssertTrue(button.isHittable, id, file: file, line: line)
        button.tap()
    }
}
