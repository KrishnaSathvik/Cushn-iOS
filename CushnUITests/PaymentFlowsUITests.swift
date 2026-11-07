import XCTest

@MainActor
final class PaymentFlowsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testFreshInstallOpensCurrentMonthEmptyWithNoBlocker() {
        let app = launch(store: tempStorePath())
        XCTAssertEqual(app.monthTitle(), "November 2026")
        XCTAssertTrue(app.staticTexts["Nothing here yet. Add your first payment."].exists)
        XCTAssertTrue(app.buttons["emptyAddPayment"].exists)
        XCTAssertFalse(app.buttons["Organize sections"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testAddCarriesForwardNotBackward() {
        let app = launch(store: tempStorePath())
        app.addPayment("Netflix", amount: "30", day: 28)
        app.next()
        XCTAssertEqual(app.monthTitle(), "December 2026")
        XCTAssertTrue(app.row("Netflix").exists)
        app.previous(); app.previous()
        XCTAssertEqual(app.monthTitle(), "October 2026")
        XCTAssertFalse(app.row("Netflix").exists)
    }

    func testPaidIsPerMonthAndUndoable() {
        let app = launch(store: tempStorePath())
        app.addPayment("Netflix", amount: "30", day: 28)
        XCTAssertEqual(app.status("Netflix"), "unconfirmed")
        app.circle("Netflix").tap()
        XCTAssertEqual(app.status("Netflix"), "paid")
        app.next()
        XCTAssertEqual(app.status("Netflix"), "unconfirmed")
        app.previous()
        XCTAssertEqual(app.status("Netflix"), "paid")
        app.circle("Netflix").tap()
        XCTAssertEqual(app.status("Netflix"), "unconfirmed")
    }

    func testRowOrderDoesNotChangeWhenMarkedPaid() {
        let app = launch(demo: "standard")
        let before = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'paymentRow.'")).allElementsBoundByIndex.map { $0.identifier }
        app.circle("Capital One").tap()
        let after = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'paymentRow.'")).allElementsBoundByIndex.map { $0.identifier }
        XCTAssertEqual(before, after)
    }

    func testSkipFromDetailsIsPerMonthAndCircleCannotUnskipByAccident() {
        let app = launch(store: tempStorePath())
        app.addPayment("Netflix", amount: "30", day: 28)
        app.row("Netflix").tap()
        app.buttons["skipAction"].tap()
        app.done()
        XCTAssertEqual(app.status("Netflix"), "skipped")

        // Tapping the circle on a skipped row asks instead of changing the status.
        app.circle("Netflix").tap()
        XCTAssertTrue(app.buttons["undoSkipAction"].waitForExistence(timeout: 5))
        app.done()
        XCTAssertEqual(app.status("Netflix"), "skipped")

        app.next()
        XCTAssertEqual(app.status("Netflix"), "unconfirmed")
    }

    func testEditAppliesFromSelectedMonthOnward() {
        let app = launch(store: tempStorePath())
        app.addPayment("Spotify", amount: "12", day: 15)
        app.next()
        app.row("Spotify").tap()
        app.buttons["editAction"].tap()
        XCTAssertTrue(app.staticTexts["editorContext"].waitForExistence(timeout: 5))
        let amount = app.textFields["amountField"]
        amount.tap()
        amount.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        amount.typeText("15")
        app.buttons["savePayment"].tap()
        app.done()
        XCTAssertTrue(app.row("Spotify").label.contains("$15.00"), app.row("Spotify").label)
        app.next()
        XCTAssertTrue(app.row("Spotify").label.contains("$15.00"), app.row("Spotify").label)
        app.previous(); app.previous()
        XCTAssertTrue(app.row("Spotify").label.contains("$12.00"), app.row("Spotify").label)
    }

    func testRemoveExplainsConsequenceAndCancelChangesNothing() {
        let app = launch(store: tempStorePath())
        app.addPayment("Netflix", amount: "30", day: 28)
        app.circle("Netflix").tap()
        app.next()

        app.row("Netflix").tap()
        app.buttons["removeAction"].tap()
        XCTAssertTrue(app.staticTexts["Remove from December onward?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["November and earlier months stay in your history."].exists)
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["removeAction"].waitForExistence(timeout: 5))
        app.done()
        XCTAssertTrue(app.row("Netflix").waitForExistence(timeout: 5))
        app.next()
        XCTAssertTrue(app.row("Netflix").exists, "cancelling changes no month")
        app.previous()

        app.row("Netflix").tap()
        app.buttons["removeAction"].tap()
        app.alerts.buttons["Remove"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.row("Netflix"))
        wait(for: [gone], timeout: 5)

        app.next()
        XCTAssertFalse(app.row("Netflix").exists)
        app.previous(); app.previous()
        XCTAssertEqual(app.status("Netflix"), "paid", "November keeps its row and status")
    }

    func testValidationRequiresThreeFields() {
        let app = launch(store: tempStorePath())
        app.buttons["addPayment"].tap()
        XCTAssertTrue(app.buttons["savePayment"].waitForExistence(timeout: 5))
        app.buttons["savePayment"].tap()
        XCTAssertTrue(app.staticTexts["Enter a name"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Enter an amount"].exists)
        XCTAssertTrue(app.staticTexts["Choose a due day"].exists)
        // Nothing recurring/one-time, bank or account-related anywhere in the form.
        for banned in ["Recurring", "One-time", "One time", "Bank", "Account"] {
            let matches = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", banned))
            XCTAssertEqual(matches.count, 0, banned)
        }
    }

    func testSectionsCanBeAddedAndRenamedFromTheirMonthOnly() {
        let app = launch(store: tempStorePath())
        app.addPayment("Netflix", amount: "30", day: 28)
        XCTAssertTrue(app.sectionHeader("Subscriptions").exists, "Netflix is suggested into Subscriptions")
        app.next()

        app.openOrganize()
        XCTAssertTrue(app.buttons["addSection"].waitForExistence(timeout: 5))
        app.buttons["addSection"].tap()
        let alertField = app.textFields["Name"]
        XCTAssertTrue(alertField.waitForExistence(timeout: 5))
        alertField.typeText("Travel")
        app.buttons["Add"].firstMatch.tap()

        // Opening a row must work even though the list is in reorder mode.
        let subscriptions = app.staticTexts["Subscriptions"].firstMatch
        XCTAssertTrue(subscriptions.waitForExistence(timeout: 5))
        app.buttons["organizeRow.Subscriptions"].tap()
        let nameField = app.textFields["sectionNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(" Plus")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["addSection"].waitForExistence(timeout: 5))
        app.done()

        XCTAssertTrue(app.sectionHeader("Travel").waitForExistence(timeout: 5), "an empty user section stays visible")
        XCTAssertTrue(app.sectionHeader("Subscriptions Plus").exists)
        app.previous()
        XCTAssertTrue(app.sectionHeader("Subscriptions").waitForExistence(timeout: 5), "November keeps the old name")
        XCTAssertFalse(app.sectionHeader("Travel").exists, "a section can't appear before it was added")
    }

    func testDraggingReordersSectionsFromThatMonthOnly() {
        let app = launch(demo: "standard")
        func positions() -> (cards: CGFloat, utilities: CGFloat) {
            (app.sectionHeader("Credit Cards").frame.minY, app.sectionHeader("Utilities").frame.minY)
        }
        XCTAssertLessThan(positions().cards, positions().utilities)
        app.next()
        app.openOrganize()
        let handle = app.buttons["Reorder Utilities"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.press(forDuration: 0.6, thenDragTo: app.buttons["organizeRow.Credit Cards"])
        sleep(1)
        app.done()
        XCTAssertTrue(app.sectionHeader("Credit Cards").waitForExistence(timeout: 5))
        XCTAssertGreaterThan(positions().cards, positions().utilities, "December follows the new order")
        app.previous()
        XCTAssertLessThan(positions().cards, positions().utilities, "November keeps its order")
    }

    func testGermanLocaleParsesCommaDecimalsAndFormatsEuros() {
        let app = launch(store: tempStorePath(), extra: ["-AppleLocale", "de_DE", "-AppleLanguages", "(de)", "-defaultCurrency", "EUR"])
        app.addPayment("Miete", amount: "12,50", day: 3)
        XCTAssertTrue(app.row("Miete").label.contains("12,50"), app.row("Miete").label)
        XCTAssertTrue(app.row("Miete").label.contains("€"), app.row("Miete").label)
    }

    func testBrowsingPastMonthShowsAddingContext() {
        let app = launch(store: tempStorePath())
        app.previous()
        app.buttons["addPayment"].tap()
        XCTAssertTrue(app.staticTexts["Adding from October 2026 onward"].waitForExistence(timeout: 5))
    }
}

@MainActor
final class RelaunchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testForceQuitAndRelaunchKeepsDataStatusesAndHistory() {
        let store = tempStorePath()
        var app = launch(store: store)
        app.addPayment("Netflix", amount: "30", day: 28)
        app.addPayment("Rent", amount: "1500", day: 1)
        app.circle("Netflix").tap()
        app.next()
        app.row("Rent").tap()
        app.buttons["removeAction"].tap()
        app.alerts.buttons["Remove"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.row("Rent"))
        wait(for: [gone], timeout: 5)
        app.terminate()

        app = launch(store: store)
        XCTAssertEqual(app.monthTitle(), "November 2026")
        XCTAssertEqual(app.status("Netflix"), "paid")
        XCTAssertEqual(app.status("Rent"), "unconfirmed")
        app.next()
        XCTAssertEqual(app.status("Netflix"), "unconfirmed")
        XCTAssertFalse(app.row("Rent").exists)
        app.terminate()

        // A later launch in a new month opens there, with history intact and no forced cleanup.
        app = launch(store: store, now: "2027-01-02")
        XCTAssertEqual(app.monthTitle(), "January 2027")
        XCTAssertEqual(app.status("Netflix"), "unconfirmed")
        XCTAssertFalse(app.sheets.firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}

@MainActor
final class ReviewUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDismissingReviewChangesNothingAndStaysReachable() {
        let app = launch(demo: "standard")
        XCTAssertTrue(app.buttons["reviewStrip"].waitForExistence(timeout: 5))
        let before = app.row("Capital One").label
        app.buttons["dismissReview"].tap()
        XCTAssertEqual(app.row("Capital One").label, before)
        // Dismissed from Home, it stays reachable in the month selector.
        app.buttons["monthTitle"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Review'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testReviewingHistoricalPaymentUpdatesThatMonthOnly() {
        let app = launch(demo: "standard")
        app.buttons["reviewStrip"].tap()
        XCTAssertTrue(app.navigationBars["October review"].waitForExistence(timeout: 5))
        // Home's row is still in the tree under the sheet, so address the one that can be tapped.
        let circle = app.buttons.matching(identifier: "statusCircle.Capital One").allElementsBoundByIndex.first { $0.isHittable }!
        XCTAssertEqual(circle.value as? String, "unconfirmed")
        circle.tap()
        XCTAssertEqual(circle.value as? String, "paid", "the row stays in place after marking")
        app.done()
        XCTAssertEqual(app.monthTitle(), "November 2026")
        XCTAssertEqual(app.status("Capital One"), "unconfirmed", "November isn't changed by October's review")
        app.previous()
        XCTAssertEqual(app.status("Capital One"), "paid")
    }
}

@MainActor
final class OverviewCalendarUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testOverviewUpdatesAfterStatusChange() {
        let app = launch(store: tempStorePath())
        app.addPayment("Rent", amount: "1500", day: 1)
        app.tabBars.buttons["Overview"].tap()
        XCTAssertTrue(app.staticTexts["0 of 1 marked paid"].waitForExistence(timeout: 5) || app.otherElements.containing(NSPredicate(format: "label CONTAINS '0 of 1 marked paid'")).firstMatch.exists)
        app.tabBars.buttons["Home"].tap()
        app.circle("Rent").tap()
        app.tabBars.buttons["Overview"].tap()
        let updated = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '1 of 1 marked paid'")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
    }

    func testCalendarClampsFebruaryAndOpensSameDetails() {
        let app = launch(store: tempStorePath(), now: "2027-02-10")
        app.addPayment("Rent", amount: "1500", day: 31)
        app.tabBars.buttons["Calendar"].tap()
        let day28 = app.buttons["calendarDay.28"]
        XCTAssertTrue(day28.waitForExistence(timeout: 5))
        XCTAssertTrue(day28.label.contains("1 payment due"), day28.label)
        XCTAssertFalse(app.buttons["calendarDay.29"].exists)
        day28.tap()
        XCTAssertTrue(app.row("Rent").waitForExistence(timeout: 5))
        app.row("Rent").tap()
        XCTAssertTrue(app.buttons["editAction"].waitForExistence(timeout: 5))
        app.done()

        app.next()
        XCTAssertTrue(app.buttons["calendarDay.31"].label.contains("1 payment due"))
    }

    func testMonthIsSharedBetweenTabs() {
        let app = launch(store: tempStorePath())
        app.next()
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertEqual(app.monthTitle(), "December 2026")
        app.tabBars.buttons["Overview"].tap()
        XCTAssertEqual(app.monthTitle(), "December 2026")
    }
}
