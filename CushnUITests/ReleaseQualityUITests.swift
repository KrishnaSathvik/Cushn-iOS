import XCTest

/// Lifecycle, landscape, accessibility structure and scrolling at the largest list size.
@MainActor
final class ReleaseQualityUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func labels(_ query: XCUIElementQuery) -> [String] {
        query.allElementsBoundByIndex.map(\.label)
    }

    // MARK: Lifecycle

    /// Backgrounding, then killing mid-session, then relaunching: every saved change survives and the app
    /// reopens on the current month, even if the user was browsing another one.
    func testBackgroundKillAndRelaunchRestoresData() {
        let store = tempStorePath()
        var app = launch(store: store)
        app.addPayment("Netflix", amount: "30", day: 28)
        app.circle("Netflix").tap()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertEqual(app.status("Netflix"), "paid")

        sleep(2)
        app.next()
        XCTAssertEqual(app.monthTitle(), "December 2026")
        app.circle("Netflix").tap()
        XCTAssertEqual(app.status("Netflix"), "paid")
        app.terminate()

        app = launch(store: store)
        XCTAssertEqual(app.monthTitle(), "November 2026")
        XCTAssertEqual(app.status("Netflix"), "paid")
        app.next()
        XCTAssertEqual(app.status("Netflix"), "paid")
        app.next()
        XCTAssertEqual(app.status("Netflix"), "unconfirmed")
    }

    /// Reopening in a later month: the new month starts unconfirmed and the old one keeps its status.
    func testRelaunchInNextMonthStartsUnconfirmedAndKeepsHistory() {
        let store = tempStorePath()
        var app = launch(store: store, now: "2026-11-15")
        app.addPayment("Netflix", amount: "30", day: 28)
        app.circle("Netflix").tap()
        app.terminate()

        app = launch(store: store, now: "2026-12-02")
        XCTAssertEqual(app.monthTitle(), "December 2026")
        XCTAssertEqual(app.status("Netflix"), "unconfirmed")
        app.previous()
        XCTAssertEqual(app.status("Netflix"), "paid")
    }

    // MARK: Landscape

    func testPrimaryFlowsWorkInLandscape() {
        let app = launch(store: tempStorePath())
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        app.addPayment("Netflix", amount: "30", day: 28)
        XCTAssertTrue(app.circle("Netflix").isHittable)
        app.circle("Netflix").tap()
        XCTAssertEqual(app.status("Netflix"), "paid")
        app.row("Netflix").tap()
        XCTAssertTrue(app.buttons["undoPaidAction"].waitForExistence(timeout: 5))
        app.done()
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["calendarDay.28"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Overview"].tap()
        XCTAssertTrue(app.buttons["monthTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Accessibility structure

    /// Not a VoiceOver pass: this reads the tree VoiceOver would use. It checks order and grouping on Home and
    /// prints every screen's elements for manual review. Someone still has to listen on a real device.
    func testAccessibilityTreeOrderAndGrouping() {
        let app = launch(demo: "standard")
        let buttons = labels(app.buttons)
        print("TREE home buttons: \(buttons)")
        let identifiers = app.buttons.allElementsBoundByIndex.map(\.identifier)
        func position(_ id: String) -> Int { identifiers.firstIndex(of: id) ?? .max }

        XCTAssertLessThan(position("monthTitle"), position("notificationsBell"))
        XCTAssertLessThan(position("notificationsBell"), position("addPayment"))
        XCTAssertLessThan(position("addPayment"), position("reviewStrip"))
        XCTAssertLessThan(position("reviewStrip"), position("paymentRow.Amex Platinum"))
        XCTAssertEqual(position("statusCircle.Amex Platinum"), position("paymentRow.Amex Platinum") + 1,
                       "A row's status control should come right after the row")
        XCTAssertLessThan(position("statusCircle.Amex Platinum"), position("paymentRow.Capital One"))

        // A row reads as one element, with nothing inside it reachable separately.
        XCTAssertEqual(app.row("Capital One").label, "Capital One, due November 21, $382.00, unconfirmed")
        for element in app.buttons.allElementsBoundByIndex where element.label.isEmpty {
            print("TREE unlabeled button: id='\(element.identifier)' frame=\(element.frame) enabled=\(element.isEnabled)")
        }
        let cellCopy = app.buttons["Capital One, Nov 21, $382.00"]
        print("TREE cell copy: exists=\(cellCopy.exists) frame=\(cellCopy.frame) hittable=\(cellCopy.exists && cellCopy.isHittable) id='\(cellCopy.identifier)'")
        XCTAssertTrue(app.buttons["Add payment to Credit Cards"].exists)

        print("TREE home headers: \(labels(app.staticTexts))")

        app.row("Capital One").tap()
        XCTAssertTrue(app.buttons["removeAction"].waitForExistence(timeout: 5))
        print("TREE details buttons: \(labels(app.buttons))")
        print("TREE details texts: \(labels(app.staticTexts))")
        for action in ["markPaidAction", "skipAction", "editAction", "removeAction"] {
            XCTAssertFalse(app.buttons[action].label.isEmpty, action)
        }
        app.done()

        app.buttons["addPayment"].tap()
        XCTAssertTrue(app.buttons["dueDayField"].waitForExistence(timeout: 5))
        print("TREE add buttons: \(labels(app.buttons)) fields: \(labels(app.textFields))")
        XCTAssertEqual(app.buttons["dueDayField"].label, "Due day")
        XCTAssertEqual(app.buttons["dueDayField"].value as? String, "Not chosen")
        app.buttons["Cancel"].firstMatch.tap()

        app.tabBars.buttons["Overview"].tap()
        sleep(1)
        print("TREE overview texts: \(labels(app.staticTexts))")
        print("TREE overview buttons: \(labels(app.buttons))")

        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["calendarDay.21"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["calendarDay.21"].label, "November 21, 1 payment due")
        XCTAssertEqual(app.buttons["calendarDay.15"].label, "Today, November 15, 1 payment due")
        XCTAssertEqual(app.buttons["calendarDay.16"].label, "November 16, nothing due")
        print("TREE calendar buttons: \(labels(app.buttons).prefix(12))")
    }

    // MARK: Performance

    /// 150 payments, about a third of them with brand icons. Opt in with TEST_RUNNER_CUSHN_PERF=1.
    /// The simulator reports only durations here, not hitches, so this can't show whether scrolling is smooth.
    func testScrollingLargeListPerformance() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CUSHN_PERF"] != nil)
        let app = launch(demo: "large")
        XCTAssertTrue(app.buttons["monthTitle"].waitForExistence(timeout: 10))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTClockMetric()], options: options) {
            app.swipeUp(velocity: .fast)
            app.swipeUp(velocity: .fast)
            app.swipeUp(velocity: .fast)
            stopMeasuring()
            app.swipeDown(velocity: .fast)
            app.swipeDown(velocity: .fast)
            app.swipeDown(velocity: .fast)
        }
    }

    func testLaunchWithLargeListPerformance() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CUSHN_PERF"] != nil)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            let app = XCUIApplication()
            app.launchArguments = ["-cushnNow", "2026-11-15", "-cushnDemo", "large"]
            app.launch()
        }
    }
}
