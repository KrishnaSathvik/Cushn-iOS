import XCTest

@MainActor
extension XCTestCase {
    /// A unique on-disk store per test, so relaunches read real persisted data.
    func tempStorePath() -> String {
        NSTemporaryDirectory() + "cushn-ui-\(UUID().uuidString)/Cushn.store"
    }

    @discardableResult
    func launch(store: String? = nil, now: String = "2026-11-15", demo: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-cushnNow", now] + extra
        if let store { args += ["-cushnStorePath", store] }
        if let demo { args += ["-cushnDemo", demo] }
        app.launchArguments = args
        app.launch()
        return app
    }
}

@MainActor
extension XCUIApplication {
    func addPayment(_ name: String, amount: String, day: Int) {
        buttons["addPayment"].tap()
        let nameField = textFields["nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        textFields["amountField"].tap()
        textFields["amountField"].typeText(amount)
        buttons["dueDayField"].tap()
        buttons["day.\(day)"].tap()
        buttons["savePayment"].tap()
        XCTAssertTrue(row(name).waitForExistence(timeout: 5), "\(name) should appear after saving")
    }

    func row(_ name: String) -> XCUIElement { buttons["paymentRow.\(name)"] }
    func sectionHeader(_ title: String) -> XCUIElement { descendants(matching: .any)["sectionHeader.\(title)"].firstMatch }
    func circle(_ name: String) -> XCUIElement { buttons["statusCircle.\(name)"] }
    func status(_ name: String) -> String? { circle(name).value as? String }
    func next() { shiftMonth(by: 1) }
    func previous() { shiftMonth(by: -1) }

    /// Goes through the month selector, the way a person would.
    func shiftMonth(by delta: Int) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        let title = buttons["monthTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let shown = formatter.date(from: title.label)!
        let calendar = Calendar(identifier: .gregorian)
        let target = calendar.date(byAdding: .month, value: delta, to: shown)!
        title.tap()
        XCTAssertTrue(buttons["monthCell.1"].waitForExistence(timeout: 5))
        let years = calendar.component(.year, from: target) - calendar.component(.year, from: shown)
        for _ in 0..<abs(years) { buttons[years > 0 ? "nextYear" : "previousYear"].tap() }
        buttons["monthCell.\(calendar.component(.month, from: target))"].tap()
        XCTAssertTrue(title.waitForLabel(formatter.string(from: target)))
    }
    func openSettings() { buttons["settingsLogo"].tap() }

    /// Sections are managed from any section heading's menu.
    func openOrganize() {
        descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sectionHeader.'")).firstMatch.tap()
        XCTAssertTrue(buttons["All sections"].waitForExistence(timeout: 5))
        buttons["All sections"].tap()
    }

    func monthTitle() -> String { buttons["monthTitle"].label }
    func done() { buttons["Done"].firstMatch.tap() }
}

@MainActor
extension XCUIElement {
    func waitForLabel(_ text: String, timeout: TimeInterval = 5) -> Bool {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: self)
        return XCTWaiter().wait(for: [done], timeout: timeout) == .completed
    }
}
