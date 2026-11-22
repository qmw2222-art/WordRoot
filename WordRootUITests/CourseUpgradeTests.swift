import XCTest

@MainActor
final class CourseUpgradeTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchArguments = ["-wordroot.course.autoGuide", "NO"]
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
    }

    private func launch(_ fixture: String) {
        app.launchEnvironment["WORDROOT_TEST_COURSE30"] = fixture
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].waitForExistence(timeout: 12))
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let control = app.buttons[id].firstMatch
        for _ in 0..<8 where !control.isHittable { app.swipeUp() }
        XCTAssertTrue(control.isHittable, id, file: file, line: line)
        control.tap()
    }

    private func openFinished(_ day: Int) {
        let phase = day <= 40 ? "daily" : day <= 75 ? "travel" : "other"
        tap("course.phase." + phase)
        let row = app.buttons["course.day.\(day)"].firstMatch
        for _ in 0..<16 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(app.staticTexts["course.done"].waitForExistence(timeout: 7))
    }

    func testV29AliasBackupKeepsScheduleAndResume() {
        launch("alias-backup")
        XCTAssertTrue(app.buttons["course.start"].label.contains("soap"))
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.word"].label, "soap")
        tap("course.next")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].label.contains("with"))
    }

    func testPressConnectsToButtonBeforeLongFamily() async throws {
        try await usePurchasedCourse()
        launch("start-22")
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.root"].label, "press")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'course.branch.'")).count, 20)
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "press")
        XCTAssertTrue(app.staticTexts["course.context.line"].label.contains("button"))
        tap("course.context.pieces")
        XCTAssertTrue(app.staticTexts["course.context.piece.0"].label.contains("按"))
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "button")
        XCTAssertTrue(app.buttons["course.talk"].exists)
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "door")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].label.contains("door"))
    }

    func testReplayKeepsWordsInTheSameTeachingOrder() async throws {
        try await usePurchasedCourse()
        launch("replay-41")
        tap("course.phase.travel")
        tap("course.day.41")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "rebook")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "night")
        tap("course.previous")
        XCTAssertEqual(app.staticTexts["course.word"].label, "rebook")
        tap("course.next")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "for")
        var seen = Set(["rebook", "night", "for"])
        for _ in 0..<8 {
            tap("course.next")
            XCTAssertTrue(seen.insert(app.staticTexts["course.word"].label).inserted)
        }
        XCTAssertEqual(seen.count, 11)
        tap("course.next")
        XCTAssertTrue(app.staticTexts["course.done"].label.contains("第 41 天学完了"))
        tap("course.previous")
        XCTAssertTrue(seen.contains(app.staticTexts["course.word"].label))
        tap("course.next")
        XCTAssertTrue(app.staticTexts["course.done"].exists)
    }

    func testHotelGuestAndChangedCondition() async throws {
        try await usePurchasedCourse()
        launch("finished-41")
        openFinished(41)
        tap("course.talk")
        XCTAssertTrue(app.staticTexts["talk.goal"].label.contains("周五"))
        XCTAssertFalse(app.staticTexts["talk.model"].exists)
        tap("talk.reveal")
        XCTAssertEqual(app.staticTexts["talk.model"].label, "Can I rebook for Friday?")
        tap("talk.follow")
        tap("talk.reveal")
        XCTAssertEqual(app.staticTexts["talk.model"].label, "Two nights, please.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("course.transfer")
        XCTAssertTrue(app.staticTexts["transfer.prompt"].label.contains("住一晚"))
        XCTAssertFalse(app.staticTexts["transfer.model"].exists)
        tap("transfer.reveal")
        XCTAssertTrue(app.staticTexts["transfer.model"].label.contains("one more night"))
    }

    func testWetlandAndStationRoles() async throws {
        try await usePurchasedCourse()
        for (day, expected) in [(75, "Which animals live here?"), (100, "Yes. Could you carry this parcel to the ticket desk?")] {
            app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
            launch("finished-\(day)")
            openFinished(day)
            tap("course.talk")
            tap("talk.reveal")
            XCTAssertEqual(app.staticTexts["talk.model"].label, expected)
            tap("talk.follow")
            tap("talk.reveal")
            XCTAssertEqual(app.staticTexts["talk.model"].label, day == 75 ? "What is that tall plant called?" : "Yes. Can I take the next train?")
            app.terminate()
        }
    }

    func testNextDayRecallKeepsUnaidedAnswerAcrossRestart() throws {
        launch("yesterday-1")
        func recognitionCount() -> String {
            app.tabBars.buttons["记录"].tap()
            let number = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "记忆卡选择")).count
            app.tabBars.buttons["课程"].tap()
            return String(number)
        }
        let recognitions = recognitionCount()
        XCTAssertEqual(recognitions, "1")
        tap("home.transfer")
        let following = app.staticTexts["transfer.prompt"].label
        XCTAssertTrue(following.contains("热水"))
        XCTAssertFalse(app.staticTexts["transfer.model"].exists)
        let field = app.textFields["transfer.draft"].firstMatch
        let editor = field.exists ? field : app.textViews["transfer.draft"].firstMatch
        editor.tap()
        editor.typeText("Warm water, please.")
        tap("transfer.save")
        let draft = app.staticTexts["transfer.saved"].label
        XCTAssertTrue(app.staticTexts["你先想到的说法"].exists)
        let unaided = "unaided"
        app.terminate()
        app.launch()
        let afterCount = recognitionCount()
        tap("home.transfer")
        let restart = app.staticTexts["transfer.saved"].label
        XCTAssertEqual(restart, draft)
        tap("transfer.done")
        XCTAssertFalse(app.buttons["home.transfer"].exists)
        openFinished(1)
        tap("course.transfer")
        let initial = app.staticTexts["transfer.prompt"].label
        XCTAssertNotEqual(initial, following)
        tap("transfer.reveal")
        let initialField = app.textFields["transfer.draft"].firstMatch
        let initialEditor = initialField.exists ? initialField : app.textViews["transfer.draft"].firstMatch
        initialEditor.tap()
        initialEditor.typeText("No ice, please.")
        tap("transfer.save")
        XCTAssertTrue(app.staticTexts["听过示范后写下的说法"].exists)
        let assisted = app.staticTexts["transfer.saved"].label
        let result: [String: String] = ["initialPrompt": initial, "followingPrompt": following,
             "courseWordRecognitions": recognitions, "recognitionsAfter": afterCount, "draftText": draft,
             "assistedText": assisted, "unaidedMode": unaided, "afterHintMode": "assisted", "restartText": restart]
        let capture = XCTAttachment(data: try JSONEncoder().encode(result), uniformTypeIdentifier: "public.json")
        capture.name = "native-recall.json"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
