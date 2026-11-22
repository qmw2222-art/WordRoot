import XCTest

@MainActor
final class LearningRepairTests: XCTestCase {
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
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8), id, file: file, line: line)
        for _ in 0..<7 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable, id, file: file, line: line)
        button.tap()
    }

    private func summary(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let total = app.staticTexts["course.learnedSenses"]
        XCTAssertTrue(total.waitForExistence(timeout: 7), file: file, line: line)
        XCTAssertTrue(total.label.replacingOccurrences(of: ",", with: "").contains("已学 \(count) / 1333"), total.label, file: file, line: line)
        XCTAssertTrue(app.staticTexts["course.completedCount"].label.contains("0 / 100"), file: file, line: line)
    }

    func testMapAndCourseCountTheSameUseOnlyOnce() {
        app.launch()
        summary(0)
        app.tabBars.buttons["地图"].tap()
        tap("map.family.all")
        for _ in port { tap("family.next") }
        XCTAssertTrue(app.staticTexts["family.done"].exists)
        app.tabBars.buttons["课程"].tap()
        summary(8)
        XCTAssertTrue(app.buttons["home.due"].exists)
        tap("course.start")
        tap("course.next")
        tap("course.next")
        app.terminate()
        app.launch()
        summary(8)
    }

    func testFamilyRoundResumesAfterCloseAndRelaunchWithItsRetry() {
        app.launchArguments += ["-wordroot.familyStudy.family.port", "finished"]
        app.launch()
        openFamilyCards()
        for id in port.prefix(2) {
            tap("cards.choice." + id)
            tap("cards.next")
        }
        tap("cards.unknown")
        XCTAssertTrue(app.staticTexts["cards.feedback"].label.contains("transport"))
        let retryDate = app.staticTexts["cards.nextDate"].label
        tap("cards.dismiss") // Leave after answering, before tapping Next.
        tap("family.recapCards")
        XCTAssertTrue(app.staticTexts["第 4 张 · 共 9 张"].waitForExistence(timeout: 5))
        tap("cards.choice." + port[3])
        tap("cards.next")
        app.terminate()
        app.launch()
        openFamilyCards()
        let remaining = [port[4], port[2], port[5], port[6], port[7]]
        XCTAssertTrue(app.staticTexts["第 5 张 · 共 9 张"].waitForExistence(timeout: 5))
        for id in remaining {
            tap("cards.choice." + id)
            if id == port[2] { XCTAssertEqual(app.staticTexts["cards.nextDate"].label, retryDate) }
            tap("cards.next")
        }
        XCTAssertTrue(app.staticTexts["这一轮练完了"].exists)
        XCTAssertTrue(app.staticTexts["共练了 8 个用法，第一次就选对了 7 个。"].exists)
        tap("cards.close")
        tap("family.recapCards")
        XCTAssertTrue(app.staticTexts["第 1 张 · 共 8 张"].waitForExistence(timeout: 5))
    }

    private func openFamilyCards() {
        tap("course.start")
        tap("course.family.all")
        tap("family.recapCards")
    }

    func testDayOneTeachesBothSidesOfPort() {
        app.launch()
        tap("course.start")
        let guide = app.staticTexts["course.guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 6))
        XCTAssertTrue(guide.label.contains("ex-") && guide.label.contains("出口"), guide.label)
        XCTAssertTrue(guide.label.contains("-able") && guide.label.contains("便携"), guide.label)
        XCTAssertFalse(guide.label.contains("看开头就知道"), guide.label)
    }
}
