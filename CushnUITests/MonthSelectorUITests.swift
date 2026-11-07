import XCTest

@MainActor
final class MonthSelectorUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testChoosingAMonthAcrossYearsAndComingBack() {
        let app = launch(demo: "standard")
        let title = app.buttons["monthTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "November 2026")
        title.tap()
        XCTAssertTrue(app.buttons["monthCell.3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["monthCell.11"].isSelected)
        XCTAssertFalse(app.buttons["goToCurrentMonth"].exists, "Already on the current month")

        app.buttons["nextYear"].tap()
        XCTAssertEqual(app.staticTexts["pickerYear"].label, "2027")
        XCTAssertEqual(title.label, "November 2026", "Stepping the year alone doesn't change the list")
        XCTAssertFalse(app.buttons["monthCell.11"].isSelected, "November 2027 isn't the month in view")
        app.buttons["monthCell.3"].tap()
        XCTAssertTrue(title.waitForLabel("March 2027"))

        title.tap()
        XCTAssertTrue(app.buttons["goToCurrentMonth"].waitForExistence(timeout: 5))
        app.buttons["goToCurrentMonth"].tap()
        XCTAssertTrue(title.waitForLabel("November 2026"))
    }

    func testCancelKeepsTheMonth() {
        let app = launch(demo: "standard")
        app.buttons["monthTitle"].tap()
        XCTAssertTrue(app.buttons["previousYear"].waitForExistence(timeout: 5))
        app.buttons["previousYear"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["monthTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.monthTitle(), "November 2026")
    }

    func testAllTabsShareTheMonth() {
        let app = launch(demo: "standard")
        app.next()
        XCTAssertEqual(app.monthTitle(), "December 2026")
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertEqual(app.monthTitle(), "December 2026")
        app.tabBars.buttons["Overview"].tap()
        XCTAssertEqual(app.monthTitle(), "December 2026")
    }

    func testHomeKeepsEveryActionOnTheTitleLine() {
        let app = launch(demo: "standard")
        let title = app.buttons["monthTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        for id in ["settingsLogo", "notificationsBell", "addPayment"] {
            XCTAssertEqual(app.buttons[id].frame.midY, title.frame.midY, accuracy: 6, id)
        }
        XCTAssertFalse(app.buttons["moreMenu"].exists, "The ellipsis is gone")
    }
}
