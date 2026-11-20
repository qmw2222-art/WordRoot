import XCTest

@MainActor
final class WordMapTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
    }

    func testPortBranchesContinueThroughRelatedWords() {
        selectFamily("port")
        let formations = [
            "sense.import.goods": "im（向内）+ port（携带）= 进口",
            "sense.export.goods": "ex（向外）+ port（携带）= 出口",
            "sense.transport.carry": "trans（穿过）+ port（运输）= 运输",
            "sense.portable.easy-carry": "port（携带）+ -able（能……的）→ 能够携带的 = 便携的"
        ]
        for (word, formation) in formations {
            XCTAssertTrue(app.buttons["branch." + word].label.contains(formation))
        }
        attach("port 词根地图")

        tap("branch.sense.export.goods")
        assertWord("export")
        XCTAssertTrue(app.staticTexts["word.meaning"].label.contains("出口"))
        XCTAssertEqual(app.staticTexts["word.formation"].label, formations["sense.export.goods"])
        XCTAssertTrue(app.staticTexts["word.example"].label.contains("exports tea"))
        XCTAssertTrue(app.staticTexts["word.translation"].label.contains("茶叶"))
        tap("word.audio.word")
        tap("word.audio.example")
        let speechStarted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "朗读中"),
            object: app.buttons["word.audio.example"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [speechStarted], timeout: 4), .completed)
        attach("export 词条")
        tap("related.port.exporter")
        assertWord("exporter")
        tap("related.port.importer")
        assertWord("importer")
        navigateBack()
        assertWord("exporter")
        tap("word.returnToFamily")

        tap("branch.sense.portable.easy-carry")
        assertWord("portable")
        XCTAssertEqual(app.staticTexts["word.formation"].label, formations["sense.portable.easy-carry"])
        tap("related.port.portability")
        assertWord("portability")
        tap("related.sense.transport.carry")
        assertWord("transport")
        tap("related.port.transportation")
        assertWord("transportation")
    }

    func testSearchAndAnotherFamilyUseTheSameDetails() {
        selectFamily("form")
        tap("branch.form.transform")
        assertWord("transform")
        tap("related.form.transformation")
        assertWord("transformation")
        tap("word.returnToFamily")

        let search = app.textFields["map.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 4))
        search.tap()
        search.typeText("portable")
        tap("search.sense.portable.easy-carry")
        assertWord("portable")
        navigateBack()
        XCTAssertTrue(app.buttons["search.sense.portable.easy-carry"].waitForExistence(timeout: 4))
        tap("清空搜索")

        search.tap()
        search.typeText("zzqwordroot")
        XCTAssertTrue(app.descendants(matching: .any)["search.empty"].firstMatch.waitForExistence(timeout: 4))
        tap("清空搜索")

        search.tap()
        search.typeText("出口商")
        tap("search.port.exporter")
        assertWord("exporter")
        tap("related.port.importer")
        assertWord("importer")
    }

    func testFullCatalogIsBrowsableOnOwnerBuild() {
        app.tabBars.buttons["地图"].tap()
        let search = app.textFields["map.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("vers")
        tap("search.family.vers")
        tap("branch.vers.reverse.0")
        assertWord("reverse")
        tap("related.vers.reversal.extra2")
        assertWord("reversal")
    }

    func testWordPracticePersistsAnAnswer() {
        selectFamily("port")
        tap("branch.sense.export.goods")
        tap("word.practice")
        XCTAssertFalse(app.textFields.firstMatch.exists)
        tap("cards.mode.meaning")
        let correct = app.buttons["cards.choice.sense.export.goods"]
        XCTAssertTrue(correct.waitForExistence(timeout: 4)); correct.tap()
        XCTAssertTrue(app.staticTexts["cards.feedback"].label.contains("出口"))
        app.terminate()
        app.launch()
        app.tabBars.buttons["记录"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '作答：出口'")).firstMatch.waitForExistence(timeout: 4))
    }

    func testBeginnerCanStartQuietlyAndResumeTheActualWord() {
        let start = app.buttons["course.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertEqual(start.label, "跟我学第一课")
        let sound = app.buttons["course.autoVoice"]
        XCTAssertTrue(sound.exists)
        sound.tap()
        tap("course.start")
        XCTAssertTrue(app.staticTexts["course.guide"].label.contains("运"))
        XCTAssertEqual(app.buttons["course.demo"].value as? String, "可播放")
        app.terminate()
        app.launch()
        XCTAssertEqual(start.label, "跟我学第一课")
        tap("course.start")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "import")
        XCTAssertTrue(app.staticTexts["course.coach.word"].label.contains("运进来"))
        XCTAssertEqual(app.buttons["course.demo"].value as? String, "可播放")
        tap("course.demo")
        let speaking = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "带读中"), object: app.buttons["course.demo"])
        XCTAssertEqual(XCTWaiter.wait(for: [speaking], timeout: 5), .completed)
        tap("course.demo")
        tap("course.next")
        app.terminate()
        app.launch()
        XCTAssertEqual(start.label, "继续学 export")
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.word"].label, "export")
        XCTAssertEqual(app.buttons["course.demo"].value as? String, "可播放")
    }

    func testReturningBeginnerCanRestartAndFinishForToday() {
        tap("course.start")
        tap("course.branch.sense.portable.easy-carry")
        tap("course.next")
        app.terminate()
        app.launch()
        XCTAssertEqual(app.buttons["course.start"].label, "继续学 I")
        tap("course.restart")
        XCTAssertEqual(app.staticTexts["course.root"].label, "port")
        tap("course.next")
        finishCurrentDay()
        tap("course.talk")
        XCTAssertTrue(app.staticTexts["talk.goal"].exists)
        navigateBack()
        tap("course.rest")
        XCTAssertEqual(app.buttons["course.start"].label, "跟我学第 2 天")
        app.terminate()
        app.launch()
        XCTAssertEqual(app.staticTexts["course.suggestedDay"].label, "第 2 天")
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.root"].label, "cook")
        XCTAssertEqual(app.buttons["course.demo"].value as? String, "带读中")
    }

    func testCourseStartsAtDayOneAndResumesAfterRelaunch() {
        XCTAssertTrue(app.staticTexts["course.title"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["course.suggestedDay"].label, "第 1 天")
        XCTAssertEqual(app.staticTexts["course.completedCount"].label, "已完成 0 / 100 天")
        XCTAssertTrue(app.buttons["course.start"].label.contains("跟我学第一课"))
        attach("第一次打开 · 从 port 开始")
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.root"].label, "port")
        XCTAssertTrue(app.staticTexts["course.guide"].label.contains("port"))
        XCTAssertEqual(app.buttons["course.demo"].value as? String, "带读中")
        for id in ["sense.import.goods", "sense.export.goods", "sense.transport.carry", "sense.portable.easy-carry"] {
            XCTAssertTrue(app.buttons["course.branch." + id].exists)
        }
        attach("同一个 port 的四种去向")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "import")
        XCTAssertEqual(app.staticTexts["course.formation"].label, "im（向内）+ port（携带）= 进口")
        XCTAssertTrue(app.buttons["course.audio.word"].exists)
        tap("course.context.audio")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attach("import 的拆词和例句")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "export")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["course.start"].label.contains("继续学 export"))
        tap("course.start")
        XCTAssertEqual(app.staticTexts["course.word"].label, "export")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "transport")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "portable")
        tap("course.next")
        XCTAssertEqual(app.staticTexts["course.word"].label, "I")
        finishCurrentDay()
        tap("course.talk")
        tap("talk.listen")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        navigateBack()
        finishCurrentDay()
        XCTAssertEqual(app.staticTexts["course.done"].label, "第 1 天学完了")
        XCTAssertTrue(app.staticTexts["course.tomorrow"].label.contains("cook"))
        XCTAssertTrue(app.buttons["course.rest"].exists)
        tap("course.followingDay")
        XCTAssertTrue(app.navigationBars["第 2 天"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["course.root"].label, "cook")
        app.terminate()
        app.launch()
        XCTAssertEqual(app.staticTexts["course.completedCount"].label, "已完成 1 / 100 天")
        XCTAssertEqual(app.staticTexts["course.suggestedDay"].label, "第 2 天")
        XCTAssertEqual(app.staticTexts["course.learnedSenses"].label.replacingOccurrences(of: ",", with: ""), "已学 13 / 1335 个用法")
    }

    func testCourseStagesAndLinkToWordMap() {
        tap("course.phase.travel")
        tap("course.day.42")
        XCTAssertEqual(app.staticTexts["course.root"].label, "port")
        tap("course.branch.sense.portable.easy-carry")
        tap("course.related.sense.portable.easy-carry")
        assertWord("portable")
        tap("related.port.portability")
        assertWord("portability")
        app.tabBars.buttons["课程"].tap()
        XCTAssertEqual(app.staticTexts["course.word"].label, "portable")
        navigateBack()
        navigateBack()
        tap("course.phase.other")
        tap("course.day.76")
        XCTAssertEqual(app.staticTexts["course.root"].label, "act")
    }

    func testLastDayReturnsToPlan() {
        tap("course.phase.other")
        let lastDay = app.buttons["course.day.100"]
        for _ in 0..<16 where !lastDay.isHittable { app.swipeUp() }
        tap("course.day.100")
        XCTAssertEqual(app.staticTexts["course.root"].label, "port")
        tap("course.branch.port.portability")
        XCTAssertEqual(app.staticTexts["course.word"].label, "portability")
        finishCurrentDay()
        XCTAssertTrue(app.buttons["course.followingDay"].label.contains("回到课程路线"))
        tap("course.followingDay")
        XCTAssertTrue(app.staticTexts["course.title"].exists)
        XCTAssertEqual(app.staticTexts["course.completedCount"].label, "已完成 1 / 100 天")
    }

    func testVoiceCanBeAuditionedAndStopped() {
        app.tabBars.buttons["设置"].tap()
        let voice = app.staticTexts["settings.voice"]
        XCTAssertTrue(voice.waitForExistence(timeout: 4))
        XCTAssertEqual(voice.label, "Heart · 美式女声")
        XCTAssertFalse(app.buttons["settings.voice"].exists)
        app.terminate(); app.launch(); app.tabBars.buttons["设置"].tap()
        XCTAssertEqual(voice.label, "Heart · 美式女声")
        let sample = app.buttons["settings.voice.audition"]
        tap("settings.voice.audition")
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "朗读中"), object: sample)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 4), .completed)
        attach("主讲音色试听")
        sample.tap()
        XCTAssertEqual(sample.label, "试听声音")
    }

    private func selectFamily(_ root: String) {
        app.tabBars.buttons["地图"].tap()
        XCTAssertTrue(app.staticTexts["map.title"].waitForExistence(timeout: 8))
        tap("map.directory")
        tap("directory.family." + root)
        XCTAssertTrue(app.navigationBars["全部词根"].waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["map.root"].firstMatch.waitForExistence(timeout: 4))
    }

    private func assertWord(_ word: String) {
        let headword = app.staticTexts["word.headword"]
        XCTAssertTrue(headword.waitForExistence(timeout: 4))
        XCTAssertEqual(headword.label, word)
        XCTAssertFalse(app.staticTexts["word.meaning"].label.isEmpty)
        XCTAssertFalse(app.staticTexts["word.formation"].label.isEmpty)
        XCTAssertFalse(app.staticTexts["word.explanation"].label.isEmpty)
        XCTAssertFalse(app.staticTexts["word.example"].label.isEmpty)
        XCTAssertFalse(app.staticTexts["word.translation"].label.isEmpty)
        XCTAssertTrue(app.buttons["word.audio.word"].exists)
        XCTAssertTrue(app.buttons["word.audio.example"].exists)
    }

    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier].firstMatch
        if !button.isHittable {
            for _ in 0..<6 {
                if button.isHittable { break }
                app.swipeUp()
            }
        }
        XCTAssertTrue(button.isHittable, identifier, file: file, line: line)
        button.tap()
    }

    private func finishCurrentDay(file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<35 {
            if app.staticTexts["course.done"].exists { return }
            tap("course.next", file: file, line: line)
        }
        XCTFail("The lesson never reached its summary", file: file, line: line)
    }

    private func navigateBack() {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
