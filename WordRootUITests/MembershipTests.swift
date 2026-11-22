import StoreKitTest
import XCTest

@MainActor
final class MembershipTests: XCTestCase {
    private let app = XCUIApplication()
    private var store: SKTestSession!
    private let prefix = "local.wordroot.ios."

    override func setUpWithError() throws {
        continueAfterFailure = false
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "WordRoot", withExtension: "storekit"))
        store = try SKTestSession(contentsOf: file)
        store.resetToDefaultState()
        store.disableDialogs = true
        store.storefront = "CHN"
        store.locale = Locale(identifier: "zh_CN")
        store.timeRate = .realTime
        store.clearTransactions()
        app.launchEnvironment["WORDROOT_TEST_LEGACY_DAY"] = "port-start-v24"
        app.launchEnvironment["WORDROOT_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-wordroot.course.autoGuide", "NO"]
    }

    override func tearDownWithError() throws {
        app.terminate()
        store?.clearTransactions()
    }

    func testFreeDayTenThenNextDayAndMapBoundaries() {
        app.launch()
        openDay(10)
        XCTAssertEqual(app.staticTexts["course.root"].label, "play")
        for _ in 0..<45 {
            if app.buttons["course.familyRecap.close"].exists { tap("course.familyRecap.close") }
            if app.buttons["course.followingDay"].exists { break }
            tap("course.next")
        }
        tap("course.followingDay")
        assertOffers()
        mapSearch("pay")
        tap("search.family.pay")
        XCTAssertTrue(app.buttons["map.family.all"].waitForExistence(timeout: 5))
        mapSearch("form")
        tap("search.family.form")
        tap("map.membership")
        assertOffers()
        mapSearch("formal")
        tap("search.form.formal")
        assertOffers()
    }

    func testSkippingAheadAndStandaloneWordsUseTheSameBoundary() {
        app.launch()
        openDay(42)
        assertOffers()
        mapSearch("now")
        tap("search.basic.now")
        assertOffers()
        mapSearch("bag")
        tap("search.basic.bag")
        XCTAssertTrue(app.buttons["word.practice"].waitForExistence(timeout: 5))
        tap("word.practice")
        XCTAssertTrue(app.staticTexts["cards.prompt"].waitForExistence(timeout: 6))
    }

    func testMonthlyPurchaseRenewalExpiryAndReview() throws {
        store.timeRate = .oneRenewalEveryThirtySeconds
        app.launch()
        openDay(11)
        assertOffers()
        tap("membership.buy.monthly")
        XCTAssertTrue(app.staticTexts["course.root"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["course.root"].label, "form")
        tap("course.next")
        tap("course.next")
        try store.forceRenewalOfSubscription(productIdentifier: prefix + "monthly")
        XCTAssertTrue(app.buttons["course.next"].waitForExistence(timeout: 7))
        let monthly = store.allTransactions().filter { $0.productIdentifier == prefix + "monthly" }
        XCTAssertGreaterThanOrEqual(monthly.count, 2)
        let renewed = try XCTUnwrap(monthly.max { $0.identifier < $1.identifier })
        store.shouldEnterBillingRetryOnRenewal = true
        store.billingGracePeriodIsEnabled = false
        try store.disableAutoRenewForTransaction(identifier: renewed.identifier)
        XCTAssertNotNil(renewed.expirationDate)
        XCTAssertTrue(app.buttons["membership.buy.monthly"].waitForExistence(timeout: 50))
        app.terminate()
        app.launch()
        let due = app.buttons["home.due"]
        XCTAssertTrue(due.waitForExistence(timeout: 10))
        due.tap()
        XCTAssertTrue(app.staticTexts["cards.prompt"].waitForExistence(timeout: 8))
        let studiedWord = app.buttons["cards.choice.form.form.0"]
        XCTAssertTrue(studiedWord.waitForExistence(timeout: 8))
        studiedWord.tap()
        XCTAssertTrue(app.staticTexts["cards.feedback"].label.contains("form"))
        tap("cards.next")
        XCTAssertTrue(app.staticTexts["cards.done"].waitForExistence(timeout: 5))
        tap("cards.close")
        openDay(11)
        assertOffers()
    }

    func testAnnualPurchaseRestorationAndCancellation() throws {
        store.timeRate = .oneRenewalEveryThirtySeconds
        app.launch()
        showSettingsOffers()
        assertOffers()
        tap("membership.buy.yearly")
        XCTAssertTrue(app.staticTexts["membership.active"].waitForExistence(timeout: 16))
        XCTAssertTrue(app.staticTexts["membership.active"].label.contains("年"))
        let transaction = try XCTUnwrap(store.allTransactions().last { $0.productIdentifier == prefix + "yearly" })
        try store.disableAutoRenewForTransaction(identifier: transaction.identifier)
        app.terminate()
        app.launch()
        showSettingsOffers()
        tap("membership.restore")
        XCTAssertTrue(app.staticTexts["membership.message"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["membership.active"].label.contains("年"))
        // End at the expiry in the signed StoreKit transaction while the app stays open.
        XCTAssertTrue(app.buttons["membership.buy.yearly"].waitForExistence(timeout: 45))
    }

    func testLifetimeSurvivesSubscriptionExpiryAndIsRevocable() async throws {
        app.launch()
        showSettingsOffers()
        assertOffers()
        tap("membership.buy.lifetime")
        XCTAssertTrue(app.staticTexts["membership.active"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["membership.active"].label.contains("永久"))
        _ = try await store.buyProduct(identifier: prefix + "monthly")
        try store.expireSubscription(productIdentifier: prefix + "monthly")
        app.terminate()
        app.launch()
        showSettingsOffers()
        tap("membership.restore")
        XCTAssertTrue(app.staticTexts["membership.message"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["membership.active"].label.contains("永久"))
        let purchase = try XCTUnwrap(store.allTransactions().last { $0.productIdentifier == prefix + "lifetime" })
        try store.refundTransaction(identifier: purchase.identifier)
        XCTAssertTrue(app.buttons["membership.buy.lifetime"].waitForExistence(timeout: 18))
        openDay(11)
        assertOffers()
    }

    func testPendingPurchaseDoesNotUnlockUntilApproved() throws {
        store.askToBuyEnabled = true
        app.launch()
        openDay(11)
        assertOffers()
        tap("membership.buy.monthly")
        let message = app.staticTexts["membership.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 15))
        XCTAssertTrue(message.label.contains("等待"), message.label)
        XCTAssertFalse(app.staticTexts["course.root"].exists)
        let pending = try XCTUnwrap(store.allTransactions().last { $0.productIdentifier == prefix + "monthly" })
        XCTAssertTrue(pending.pendingAskToBuyConfirmation)
        try store.approveAskToBuyTransaction(identifier: pending.identifier)
        XCTAssertTrue(app.staticTexts["course.root"].waitForExistence(timeout: 15))
    }

    func testDeclinedPurchaseStaysLockedAfterRelaunch() throws {
        store.askToBuyEnabled = true
        app.launch()
        openDay(11)
        assertOffers()
        tap("membership.buy.monthly")
        let message = app.staticTexts["membership.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 15))
        XCTAssertTrue(message.label.contains("等待"))
        let refused = try XCTUnwrap(store.allTransactions().first { $0.productIdentifier == prefix + "monthly" && $0.pendingAskToBuyConfirmation })
        try store.declineAskToBuyTransaction(identifier: refused.identifier)
        app.terminate()
        app.launch()
        openDay(11)
        assertOffers()
        XCTAssertFalse(app.staticTexts["course.root"].exists)
    }

    private func assertOffers(file: StaticString = #filePath, line: UInt = #line) {
        for (id, yuan) in [("monthly", "6"), ("yearly", "26"), ("lifetime", "48")] {
            let button = app.buttons["membership.buy." + id]
            XCTAssertTrue(button.waitForExistence(timeout: 12), id, file: file, line: line)
            let ready = NSPredicate(format: "enabled == true")
            let waiter = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: button)], timeout: 12)
            XCTAssertEqual(waiter, .completed, button.debugDescription, file: file, line: line)
            XCTAssertTrue(button.label.contains(yuan), button.label, file: file, line: line)
        }
    }

    private func showSettingsOffers() {
        app.tabBars.buttons["设置"].tap()
        if !app.buttons["membership.restore"].exists { tap("settings.membership") }
    }

    private func mapSearch(_ term: String) {
        app.tabBars.buttons["地图"].tap()
        while !app.textFields["map.search"].exists {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if !back.exists { break }
            back.tap()
        }
        let field = app.textFields["map.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if app.buttons["清空搜索"].exists { app.buttons["清空搜索"].tap() }
        field.tap()
        field.typeText(term + "\n")
    }

    private func openDay(_ day: Int) {
        app.tabBars.buttons["课程"].tap()
        if !app.buttons["course.phase.daily"].exists {
            app.tabBars.buttons["课程"].tap()
        }
        let phase = day <= 40 ? "daily" : day <= 75 ? "travel" : "other"
        tap("course.phase." + phase)
        tap("course.day." + String(day))
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id].firstMatch
        for _ in 0..<8 {
            if button.exists && button.isHittable { button.tap(); return }
            if button.waitForExistence(timeout: 0.35) && button.isHittable { button.tap(); return }
            app.swipeUp()
        }
        XCTFail("无法点按 " + id, file: file, line: line)
    }
}
