import XCTest

/// Diagnostic: prints every issue the system audit reports with nothing exempted. It never fails on audit
/// findings; the real gates are in AccessibilityUITests. Run it when investigating an audit change.
@MainActor
final class AuditInventoryUITests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CUSHN_AUDIT_INVENTORY"] != nil,
                          "Diagnostic only. Set TEST_RUNNER_CUSHN_AUDIT_INVENTORY=1 to run.")
    }

    private func inventory(_ screen: String, _ app: XCUIApplication) throws {
        sleep(2)
        try app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element
            print("INV|\(screen)|\(issue.auditType.rawValue)|\(issue.compactDescription)|id=\(element?.identifier ?? "nil")|label=\(element?.label ?? "nil")|type=\(element?.elementType.rawValue ?? 0)|frame=\(element?.frame ?? .zero)")
            return true
        }
    }

    func testInventory() throws {
        for (mode, extra) in [("light", ["-appearance", "light"]), ("dark", ["-appearance", "dark"])] {
            var app = launch(demo: "standard", extra: extra)
            try inventory("\(mode)-home", app)
            app.row("Capital One").tap()
            XCTAssertTrue(app.buttons["removeAction"].waitForExistence(timeout: 5))
            try inventory("\(mode)-details", app)
            app.done()
            app.buttons["addPayment"].tap()
            XCTAssertTrue(app.buttons["dueDayField"].waitForExistence(timeout: 5))
            try inventory("\(mode)-add", app)
            app.terminate()
            app = launch(demo: "standard", extra: extra + ["-cushnTab", "overview"])
            try inventory("\(mode)-overview", app)
            app.terminate()
            app = launch(demo: "standard", extra: extra + ["-cushnTab", "calendar"])
            try inventory("\(mode)-calendar", app)
            app.terminate()
        }
    }

    private func located(_ tag: String, _ type: XCUIAccessibilityAuditType, _ app: XCUIApplication) throws {
        sleep(2)
        let tabTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : -1
        print("LOC|\(tag)|tabBarTop=\(tabTop)")
        try app.performAccessibilityAudit(for: type) { issue in
            print("LOC|\(tag)|\(issue.compactDescription)|\(issue.detailedDescription)|elementNil=\(issue.element == nil)|label=\(issue.element?.label ?? "-")|frame=\(issue.element?.frame ?? .zero)")
            return true
        }
    }

    func testLocateFindings() throws {
        for mode in ["light", "dark"] {
            var app = launch(demo: "standard", extra: ["-appearance", mode])
            try located("\(mode)-home-top", .contrast, app)
            app.swipeUp(velocity: .slow)
            sleep(1)
            try located("\(mode)-home-scrolled", .contrast, app)
            app.terminate()
            app = launch(demo: "standard", extra: ["-appearance", mode, "-cushnTab", "overview"])
            try located("\(mode)-overview-top", .contrast, app)
            try located("\(mode)-overview-top", .elementDetection, app)
            app.swipeUp(velocity: .slow)
            sleep(1)
            try located("\(mode)-overview-scrolled", .contrast, app)
            try located("\(mode)-overview-scrolled", .elementDetection, app)
            app.terminate()
            app = launch(demo: "standard", extra: ["-appearance", mode])
            app.row("Capital One").tap()
            XCTAssertTrue(app.buttons["removeAction"].waitForExistence(timeout: 5))
            try located("\(mode)-details", .contrast, app)
            try located("\(mode)-details", .textClipped, app)
            try located("\(mode)-details", .dynamicType, app)
            app.terminate()
        }
    }
}
