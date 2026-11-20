import XCTest

@MainActor
final class ListeningCourseTests: XCTestCase {
    private var app: XCUIApplication!
    private var runID = ""
    private let family = [
        ("sense.import.goods", "import", "进口"), ("sense.export.goods", "export", "出口"),
        ("sense.transport.carry", "transport", "运输"), ("sense.portable.easy-carry", "portable", "便于携带"),
        ("port.exporter", "exporter", "出口商"), ("port.importer", "importer", "进口商"),
        ("port.transportation", "transportation", "交通、运输"), ("port.portability", "portability", "便携性")
    ]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        runID = UUID().uuidString
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = runID
        app.launch()
        let attachment = XCTAttachment(string: runID)
        attachment.name = "trace-id"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCompleteFamilyListsEverySenseAndPractisesEveryWord() {
        tap("course.start"); tap("course.family.all")
        for (id, english, chinese) in family {
            let meaning = app.staticTexts["family.meaning"]
            XCTAssertTrue(meaning.waitForExistence(timeout: 8), english)
            XCTAssertEqual(app.staticTexts["family.word"].label, english)
            XCTAssertTrue(meaning.label.contains(chinese), meaning.label)
            if id == "port.transportation" {
                let part = app.descendants(matching: .any).matching(identifier: "family.part.0").firstMatch
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", "正在讲这一段"), object: part)], timeout: 12), .completed)
                snapshot("meaning")
            }
            tap("family.next")
        }
        XCTAssertTrue(app.staticTexts["family.done"].waitForExistence(timeout: 4))
        for (id, english, chinese) in family { assertRow("family.recap", id, english, chinese) }
        snapshot("familyList")
        tap("family.recapCards")
        snapshot("familyCards")
        var sequence = family.map { $0 }
        sequence.insert(family[0], at: 3)
        var firstDue = ""
        for (i, item) in sequence.enumerated() {
            XCTAssertFalse(app.staticTexts["cards.answer.ipa"].exists)
            XCTAssertFalse(app.staticTexts["cards.feedback"].exists)
            let spelling = i.isMultiple(of: 2)
            if i == 0 { tap("cards.listen") }
            tap(spelling ? "cards.mode.spelling" : "cards.mode.meaning")
            let answer = app.buttons["cards.choice." + item.0]
            XCTAssertTrue(answer.waitForExistence(timeout: 3), item.0)
            XCTAssertTrue(spelling ? answer.label == item.1 : answer.label.contains(item.2), item.0)
            let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cards.choice.'")).allElementsBoundByIndex
            XCTAssertEqual(choices.count, 4)
            XCTAssertEqual(Set(choices.map(\.label)).count, 4)
            if i == 0 {
                snapshot("hearWord")
                choices.first { $0.identifier != "cards.choice." + item.0 }!.tap()
            } else {
                if i == 1 { snapshot("hearMeaning") }
                if i == 3 { XCTAssertTrue(app.staticTexts["刚才那张，再想一次"].exists); snapshot("retry") }
                answer.tap()
            }
            let feedback = app.staticTexts["cards.feedback"]
            XCTAssertTrue(feedback.waitForExistence(timeout: 4))
            XCTAssertTrue(feedback.label.contains(item.1))
            XCTAssertTrue(app.staticTexts["cards.clue"].exists)
            let due = app.staticTexts["cards.nextDate"].label
            if i == 0 { firstDue = due; XCTAssertTrue(due.contains("分钟")) }
            if i == 3 { XCTAssertEqual(due, firstDue) }
            tap("cards.next")
        }
        XCTAssertTrue(app.staticTexts["cards.done"].exists)
    }

    func testDayOneHasEightRelatedSingleWordCards() {
        tap("course.start"); tap("course.lessonAutoVoice"); tap("course.next")
        let eligible = Set(family.map { "cards.choice." + $0.0 })
        for (index,item) in family.enumerated() {
            XCTAssertEqual(app.staticTexts["course.word"].label, item.1)
            if index == 0 {
                tap("course.audio.word")
                tap("course.readingAid")
                XCTAssertEqual(app.staticTexts["course.readingSound"].label, "因破得")
                XCTAssertEqual(app.webViews.count, 0)
            }
            tap("course.next")
        }
        for (id, spelling, meaning) in family { assertRow("course.familyRecap", id, spelling, meaning) }
        assertVisibleWords(prefix: "course.familyRecap.word.", count: 8,
                           bottom: app.buttons["course.familyRecap.cards"].frame.minY)
        snapshot("eight-words-one-screen")
        let last = app.buttons["course.familyRecap.word.port.portability"]
        last.tap()
        let phonetic = app.staticTexts["course.familyRecap.port.portability.ipa"]
        let sound = app.buttons["course.familyRecap.port.portability.audio.word"]
        XCTAssertTrue(phonetic.waitForExistence(timeout: 4))
        XCTAssertLessThan(abs(phonetic.frame.midY - sound.frame.midY), 12)
        sound.tap()
        app.buttons["course.familyRecap.closeWord"].tap()
        tap("course.familyRecap.cards")
        for (index,item) in family.enumerated() {
            let answer = app.buttons["cards.choice." + item.0]
            XCTAssertTrue(answer.waitForExistence(timeout: 8), item.1)
            XCTAssertEqual(app.staticTexts["cards.family"].label, "port 词族")
            XCTAssertFalse(app.staticTexts["cards.prompt"].label.contains("例句"))
            let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cards.choice.'")).allElementsBoundByIndex
            XCTAssertEqual(choices.count, 4)
            XCTAssertTrue(Set(choices.map(\.identifier)).isSubset(of: eligible))
            XCTAssertFalse(app.buttons["cards.answer.readingAid"].exists)
            if index == 2 || index == 4 {
                tap("cards.listen")
                snapshot("port-card-\(index+1)")
            }
            XCTAssertTrue(answer.label.contains(item.2), answer.label)
            answer.tap()
            XCTAssertTrue(app.staticTexts["cards.feedback"].label.contains(item.1))
            tap("cards.next")
        }
        XCTAssertTrue(app.staticTexts["cards.done"].exists)
    }

    func testReturningLearnerCompletesOnlyMissingFamilyWords() {
        app.terminate()
        app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"] = "completed-v11"
        app.launch()
        XCTAssertTrue(app.staticTexts["course.completedCount"].label.contains("1 / 100"))
        tap("course.phase.daily"); tap("course.day.1")
        let supplement = app.buttons["course.supplementFamily"]
        XCTAssertTrue(supplement.waitForExistence(timeout: 5))
        XCTAssertEqual(supplement.label, "补学 port 剩下的 4 个词")
        tap("course.supplementFamily")
        for item in family.dropFirst(4) {
            XCTAssertEqual(app.staticTexts["course.word"].label, item.1)
            tap("course.next")
        }
        for (id, spelling, meaning) in family { assertRow("course.familyRecap", id, spelling, meaning) }
        tap("course.familyRecap.cards")
        XCTAssertTrue(app.staticTexts["第 1 张 · 共 8 张"].exists)
        XCTAssertTrue(app.buttons["cards.choice.sense.import.goods"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["course.completedCount"].label.contains("1 / 100"))
        XCTAssertTrue(app.staticTexts["course.learnedSenses"].label.replacingOccurrences(of: ",", with: "").contains("17 / 1335"))
    }

    func testDayRecapAndClearBagAction() {
        XCTAssertFalse(app.buttons["home.due"].exists)
        tap("course.start"); tap("course.lessonAutoVoice"); tap("course.next")
        let day = family + [
            ("basic.i","I","我"), ("basic.take","take","拿"), ("basic.this","this","这"),
            ("basic.bag","bag","包"), ("basic.you","you","你"), ("basic.please","please","请"),
            ("basic.give","give","给"), ("basic.of","of","的"), ("basic.small","small","小")]
        for (_, english, _) in day {
            XCTAssertEqual(app.staticTexts["course.word"].label, english)
            if english == "this" {
                XCTAssertEqual(app.buttons["course.next"].label, "学 bag（包）")
                snapshot("bag")
            }
            tap("course.next")
            if english == "portability" {
                for (id, spelling, meaning) in family { assertRow("course.familyRecap", id, spelling, meaning) }
                tap("course.familyRecap.close")
            }
        }
        for (id, english, chinese) in family { assertRow("course.recap", id, english, chinese) }
        snapshot("dayList")
        tap("course.recapCards")
        tap("cards.mode.meaning")
        XCTAssertTrue(app.buttons["cards.choice.sense.import.goods"].exists)
    }

    func testForgottenWordComesBackAndTheHomeQueueUpdates() {
        XCTAssertFalse(app.tabBars.buttons["复习"].exists)
        XCTAssertFalse(app.buttons["home.due"].exists)
        tap("course.start"); tap("course.next"); tap("course.next")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let due = app.buttons["home.due"]
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        XCTAssertTrue(due.label.contains("1 个词"), due.label)
        snapshot("dueHome")
        tap("home.due")
        tap("cards.unknown")
        XCTAssertTrue(app.staticTexts["cards.feedback"].label.contains("进口"))
        XCTAssertTrue(app.staticTexts["cards.clue"].exists)
        let date = app.staticTexts["cards.nextDate"].label
        XCTAssertTrue(date.contains("分钟"))
        snapshot("unknown")
        tap("cards.next"); tap("cards.mode.spelling"); tap("cards.choice.sense.import.goods")
        XCTAssertEqual(app.staticTexts["cards.nextDate"].label, date)
        tap("cards.next"); tap("cards.close")
        XCTAssertFalse(due.exists)
        app.terminate(); app.launch()
        XCTAssertFalse(app.tabBars.buttons["复习"].exists)
        XCTAssertFalse(due.exists)
        XCTAssertTrue(app.staticTexts["course.learnedSenses"].label.replacingOccurrences(of: ",", with: "").contains("1 / 1335"))
        snapshot("restart")
    }

    func testLegacyFinishedFamilyCanPracticeFromHomeOrItsList() {
        app.terminate()
        app.launchArguments = ["-wordroot.familyStudy.family.port", "finished"]
        app.launch()
        XCTAssertEqual(app.buttons["home.due"].value as? String, "共有8个词到期")
        tap("course.start")
        tap("course.family.all")
        XCTAssertTrue(app.staticTexts["family.done"].exists)
        for (id, english, chinese) in family { assertRow("family.recap", id, english, chinese) }
        tap("family.recapCards")
        tap("cards.mode.meaning")
        XCTAssertTrue(app.buttons["cards.choice.sense.import.goods"].exists)
    }

    func testFirstLessonAndMapShowEveryWordWithoutScrolling() {
        tap("course.start")
        assertVisibleWords(prefix: "course.branch.", count: 17, bottom: app.buttons["course.next"].frame.minY)
        snapshot("entire-first-lesson")
        app.tabBars.buttons["地图"].tap()
        assertVisibleWords(prefix: "catalog.", count: 8, bottom: app.tabBars.firstMatch.frame.minY)
        snapshot("entire-port-map")
    }

    func testLargestLessonShowsAll28UsesWithoutScrolling() {
        tap("course.phase.daily")
        let lesson = app.buttons["course.day.29"]
        for _ in 0..<12 where !lesson.isHittable { app.swipeUp() }
        XCTAssertTrue(lesson.isHittable)
        lesson.tap()
        XCTAssertTrue(app.buttons["course.next"].waitForExistence(timeout: 5))
        assertVisibleWords(prefix: "course.branch.", count: 28, bottom: app.buttons["course.next"].frame.minY)
        let verb = app.buttons["course.branch.duc.conduct"]
        let noun = app.buttons["course.branch.duc.conduct.behavior"]
        XCTAssertTrue(verb.label.hasPrefix("conduct，"))
        XCTAssertTrue(noun.label.hasPrefix("conduct，"))
        XCTAssertNotEqual(verb.label, noun.label)
        snapshot("entire-largest-lesson")
        tap("course.lessonAutoVoice")
        tap("course.next")
        for _ in 0..<28 {
            tap("course.next")
            let close = app.buttons["course.familyRecap.close"]
            if close.exists { close.tap() }
        }
        assertVisibleWords(prefix: "course.recap.word.", count: 28, bottom: app.buttons["course.recapCards"].frame.minY)
        snapshot("largest-lesson-recap")
    }

    private func assertVisibleWords(prefix: String, count: Int, bottom: CGFloat,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), prefix, file: file, line: line)
        let entries = rows.allElementsBoundByIndex
        XCTAssertEqual(entries.count, count, file: file, line: line)
        for entry in entries {
            XCTAssertTrue(entry.isHittable, entry.identifier, file: file, line: line)
            XCTAssertGreaterThanOrEqual(entry.frame.minY, app.scrollViews.firstMatch.frame.minY - 1,
                                        entry.identifier, file: file, line: line)
            XCTAssertLessThanOrEqual(entry.frame.maxY, bottom + 1, entry.identifier, file: file, line: line)
        }
    }

    private func assertRow(_ prefix: String, _ id: String, _ word: String, _ meaning: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons[prefix + ".word." + id]
        XCTAssertTrue(row.exists, id, file: file, line: line)
        XCTAssertTrue(row.label.hasPrefix(word + "，"), row.label, file: file, line: line)
        XCTAssertTrue(row.label.contains(meaning), row.label, file: file, line: line)
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8), id, file: file, line: line)
        if id == "course.family.all" {
            let scroll = app.scrollViews.firstMatch
            let top = app.navigationBars.firstMatch.frame.maxY + 10
            let bottom = app.buttons["course.next"].frame.minY - 10
            for _ in 0..<12 {
                let y = button.frame.midY
                if button.isHittable && y > top && y < bottom { break }
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55))
                let distance = min(max(abs(y - (top + bottom) / 2), 80), 180)
                let end = start.withOffset(CGVector(dx: 0, dy: y < top ? distance : -distance))
                start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.1)
            }
        } else {
            for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        }
        XCTAssertTrue(button.isHittable, id, file: file, line: line)
        button.tap()
    }
}
