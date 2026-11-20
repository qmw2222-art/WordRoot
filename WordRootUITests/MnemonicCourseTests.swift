import XCTest

@MainActor
final class MnemonicCourseTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
    }

    func testExportShowsTheDirectionSoundAndInference() {
        tap("course.start")
        tap("course.branch.sense.export.goods")
        XCTAssertEqual(app.staticTexts["course.ipa"].label, "/ɛkˈspɔrt/")
        assertSoundBesideIPA("course")
        let tip = app.staticTexts["course.coach.word"].label
        for clue in ["ex-", "向外", "port", "国外", "出口"] {
            XCTAssertTrue(tip.contains(clue), clue)
        }
        XCTAssertTrue(app.buttons["course.audio.word"].exists)
        XCTAssertFalse(app.buttons["course.audio.example"].isHittable)
        tap("course.related.sense.export.goods")
        XCTAssertEqual(app.staticTexts["word.ipa"].label, "/ɛkˈspɔrt/")
        assertSoundBesideIPA("word")
        tap("related.port.exporter")
        XCTAssertFalse(app.staticTexts["word.ipa"].label.isEmpty)
    }

    func testWordsLeadToAudioAndPracticeWithoutSelfAssessment() {
        XCTAssertFalse(app.staticTexts["course.mastered"].exists)
        tap("course.start")
        tap("course.lessonAutoVoice")
        tap("course.branch.sense.export.goods")
        XCTAssertTrue(app.buttons["course.audio.word"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["course.selfcheck"].exists)
        tap("course.related.sense.export.goods")
        XCTAssertTrue(app.buttons["word.audio.word"].exists)
        XCTAssertFalse(app.buttons["word.selfcheck"].exists)
        XCTAssertTrue(app.buttons["word.practice"].exists)
    }

    func testBasic850IsPartOfTheDayAndOffersAnOriginalReply() {
        tap("course.start")
        tap("course.context.basic.i")
        XCTAssertEqual(app.staticTexts["course.word"].label, "I")
        XCTAssertTrue(app.staticTexts["course.coach.word"].label.contains("自己"))
        XCTAssertTrue(app.buttons["course.demo"].exists)
        XCTAssertFalse(app.staticTexts["course.ipa"].label.isEmpty)
        assertSoundBesideIPA("course")
        for _ in 0..<17 {
            tap("course.next")
            if app.buttons["course.familyRecap.close"].exists { tap("course.familyRecap.close") }
        }
        tap("course.talk")
        XCTAssertTrue(app.buttons["talk.listen"].exists)
        XCTAssertTrue(app.staticTexts["talk.goal"].exists)
        XCTAssertFalse(app.staticTexts["talk.model"].exists)
        let reply = app.textFields["talk.reply"]
        reply.tap()
        reply.typeText("Yes, please.")
        tap("talk.save")
        XCTAssertTrue(app.staticTexts["talk.myReply"].label.contains("Yes, please."))
        tap("talk.follow")
        XCTAssertTrue(app.buttons["talk.listen"].exists)
        XCTAssertFalse(app.staticTexts["talk.model"].exists)
        let follow = app.textFields["talk.reply"]
        follow.tap()
        follow.typeText("Just one bag.")
        tap("talk.save")
        XCTAssertTrue(app.staticTexts["talk.myReply"].label.contains("Just one bag."))
        tap("talk.reveal")
        XCTAssertTrue(app.staticTexts["talk.model"].exists)
    }

    func testOldDayRetainsItsWordsAndNewMaterialStartsUnlearned() {
        app.terminate()
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["course.completedCount"].label.contains("0 / 100"))
        XCTAssertTrue(app.staticTexts["course.learnedSenses"].label.replacingOccurrences(of: ",", with: "").contains("4 / 1335"))
        XCTAssertFalse(app.staticTexts["course.basicProgress"].exists)
        XCTAssertFalse(app.staticTexts["course.mastered"].exists)
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.word"].label, "I")
    }

    func testEntireFourteenEntryFamilyCanBeLearnedInSequence() {
        tap("course.phase.daily")
        tap("course.day.18")
        tap("course.family.all")
        let expected = ["audio","audible","audience","audition","audibility","auditory","inaudible","audiobook","auditor","audit","audition","audiovisual","audiology","audiologist"]
        for (index, headword) in expected.enumerated() {
            XCTAssertEqual(app.staticTexts["family.word"].label, headword)
            XCTAssertTrue(app.staticTexts["family.position"].label.contains("\(index + 1) / 14"))
            tap("family.next")
        }
        XCTAssertTrue(app.staticTexts["family.done"].exists)
        let items = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "family.recap.word.")).allElementsBoundByIndex
        XCTAssertEqual(items.count, 14)
        for item in items {
            XCTAssertTrue(item.isHittable, item.identifier)
            XCTAssertLessThanOrEqual(item.frame.maxY, app.buttons["family.recapCards"].frame.minY, item.identifier)
        }
        XCTAssertTrue(app.buttons["family.recap.word.aud.audition.5"].label.contains("试演"))
        XCTAssertTrue(app.buttons["family.recap.word.aud.audition.extra3"].label.contains("参加试演"))
    }

    private func assertSoundBesideIPA(_ prefix: String) {
        let ipa = app.staticTexts[prefix + ".ipa"].frame
        let audio = app.buttons[prefix + ".audio.word"].frame
        XCTAssertLessThan(abs(ipa.midY - audio.midY), 12)
        XCTAssertGreaterThanOrEqual(audio.minX, ipa.maxX - 2)
        XCTAssertLessThan(audio.minX - ipa.maxX, 24)
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id].firstMatch
        if id.hasPrefix("course.branch.") && button.exists {
            let scroll = app.scrollViews.firstMatch
            let top = app.navigationBars.firstMatch.frame.maxY + 12
            let bottom = app.buttons["course.next"].frame.minY - 12
            for _ in 0..<12 {
                let y = button.frame.midY
                if y >= top && y <= bottom && button.isHittable { break }
                // A short drag keeps small word rows clear of the navigation bar and footer.
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.57))
                let distance = min(max(abs(y - (top + bottom) / 2), 60), 185)
                let end = start.withOffset(CGVector(dx: 0, dy: y < top ? distance : -distance))
                start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            XCTAssertGreaterThanOrEqual(button.frame.midY, top, id, file: file, line: line)
            XCTAssertLessThanOrEqual(button.frame.midY, bottom, id, file: file, line: line)
        } else {
            for _ in 0..<4 where !button.isHittable { app.swipeUp() }
        }
        XCTAssertTrue(button.isHittable, id, file: file, line: line)
        button.tap()
    }
}
