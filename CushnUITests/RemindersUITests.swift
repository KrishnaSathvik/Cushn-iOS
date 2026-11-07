import XCTest

/// These launches fake the permission state, so nothing here reaches iOS.
@MainActor
final class RemindersUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launchWithInbox(_ extra: [String] = []) -> XCUIApplication {
        launch(demo: "standard", extra: ["-cushnInboxDays", "20", "-cushnReminders", "allowed"] + extra)
    }

    func testBellShowsUnreadAndFilterAndMarkAllRead() {
        let app = launchWithInbox()
        let bell = app.buttons["notificationsBell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        XCTAssertTrue(bell.label.contains("unread"), bell.label)
        // The bell shares the title's line.
        XCTAssertEqual(bell.frame.midY, app.buttons["monthTitle"].frame.midY, accuracy: 8)
        bell.tap()

        XCTAssertTrue(app.buttons["notification.Internet"].waitForExistence(timeout: 5))
        app.buttons["Unread"].tap()
        XCTAssertTrue(app.buttons["notification.Internet"].exists)
        app.buttons["markAllRead"].tap()
        XCTAssertTrue(app.staticTexts["You're all caught up"].waitForExistence(timeout: 3))
        app.buttons["All"].tap()
        XCTAssertTrue(app.buttons["notification.Internet"].waitForExistence(timeout: 3), "Mark All Read keeps the messages")
        app.done()
        XCTAssertEqual(bell.label, "Notifications")
    }

    func testDismissRemovesTheMessageNotThePayment() {
        let app = launchWithInbox()
        app.buttons["notificationsBell"].tap()
        XCTAssertTrue(app.buttons["notification.Internet"].waitForExistence(timeout: 5))
        app.buttons["notificationOptions.Internet"].firstMatch.tap()
        app.buttons["Dismiss"].tap()
        XCTAssertTrue(app.buttons["notification.Internet"].waitForNonExistence(timeout: 3))
        app.done()
        app.swipeUp()
        XCTAssertTrue(app.row("Internet").waitForExistence(timeout: 3))
    }

    func testTappingANotificationOpensThePaymentInItsMonth() {
        let app = launchWithInbox()
        // Start somewhere else, so going back to the right month is proven.
        app.next()
        app.next()
        app.buttons["notificationsBell"].tap()
        let item = app.buttons["notification.Internet"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.staticTexts["detailName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detailName"].label, "Internet")
        XCTAssertTrue(app.navigationBars["November 2026"].exists)
        app.done()
        XCTAssertEqual(app.monthTitle(), "November 2026")
        XCTAssertFalse(app.buttons["notificationsBell"].label.contains("3 unread"))
    }

    func testEmptyInbox() {
        let app = launch(demo: "standard")
        app.buttons["notificationsBell"].tap()
        XCTAssertTrue(app.staticTexts["No notifications yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["markAllRead"].exists)
    }

    func testPermissionOfferIsSkippableAndNeverOnEmptyList() {
        let empty = launch(extra: ["-cushnInMemory", "YES", "-cushnReminders", "prompt"])
        XCTAssertTrue(empty.buttons["addPayment"].waitForExistence(timeout: 5))
        XCTAssertFalse(empty.otherElements["reminderPrompt"].exists)
        empty.addPayment("Netflix", amount: "30", day: 28)
        let turnOn = empty.buttons["reminderPromptTurnOn"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: 5))
        empty.buttons["reminderPromptDismiss"].tap()
        XCTAssertTrue(turnOn.waitForNonExistence(timeout: 3))
        XCTAssertTrue(empty.row("Netflix").exists)
    }

    func testSettingsWhenAllowedAndWhenDenied() {
        var app = launch(demo: "standard", extra: ["-cushnReminders", "allowed"])
        app.openSettings()
        let main = app.switches["remindersToggle"]
        XCTAssertTrue(main.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["remindersThreeDays"].exists)
        XCTAssertTrue(app.switches["remindersDueToday"].exists)
        // State comes from the system switch, which VoiceOver reads as on or off.
        XCTAssertEqual(main.value as? String, "1")
        XCTAssertEqual(app.switches["remindersThreeDays"].value as? String, "1")
        main.switches.firstMatch.tap()
        XCTAssertEqual(main.value as? String, "0")
        XCTAssertTrue(app.switches["remindersThreeDays"].waitForNonExistence(timeout: 3))

        app.terminate()
        app = launch(demo: "standard", extra: ["-cushnReminders", "denied"])
        app.openSettings()
        XCTAssertTrue(app.buttons["remindersOpenSettings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["remindersToggle"].isEnabled)
    }

    /// Saves the screens for inspection when CUSHN_SHOTS names a folder.
    func testCaptureScreens() throws {
        let folder = ProcessInfo.processInfo.environment["CUSHN_SHOTS"] ?? ""
        try XCTSkipIf(folder.isEmpty, "Capture only")
        func save(_ name: String) throws {
            sleep(1)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
        }
        for (mode, extra) in [("light", ["-AppleInterfaceStyle", "Light", "-appearance", "light"]), ("dark", ["-appearance", "dark"]),
                              ("large", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])] {
            let app = launchWithInbox(extra)
            let bell = app.buttons["notificationsBell"]
            XCTAssertTrue(bell.waitForExistence(timeout: 5))
            bell.tap()
            XCTAssertTrue(app.buttons["notification.Internet"].waitForExistence(timeout: 5))
            try save("inbox-\(mode)")
            app.done()
            app.openSettings()
            XCTAssertTrue(app.switches["remindersToggle"].waitForExistence(timeout: 5))
            try save("settings-\(mode)")
            app.swipeUp()
            try save("settings-\(mode)-2")
            app.terminate()
        }
        let empty = launch(demo: "standard", extra: ["-appearance", "light", "-cushnReminders", "prompt"])
        XCTAssertTrue(empty.buttons["reminderPromptTurnOn"].exists || empty.buttons["notificationsBell"].waitForExistence(timeout: 5))
        empty.buttons["notificationsBell"].tap()
        XCTAssertTrue(empty.staticTexts["No notifications yet"].waitForExistence(timeout: 5))
        try save("inbox-empty")
        empty.terminate()
    }
}

/// Uses the real iOS notification system and waits for a real alert, so it takes about two minutes and changes the
/// simulator's permission for Cushn. Run on purpose with TEST_RUNNER_CUSHN_LIVE=1.
@MainActor
final class RemindersLiveUITests: XCTestCase {
    func testARealReminderIsDeliveredAndOpensThePayment() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CUSHN_LIVE"] == "1", "Live check only")
        continueAfterFailure = false

        // At least 40 seconds out, so the alert can't be missed while the test is still setting up.
        let target = Calendar.current.dateComponents([.day, .hour, .minute], from: Date().addingTimeInterval(100))
        let app = XCUIApplication()
        app.launchArguments = ["-cushnInMemory", "YES", "-cushnReminders", "live",
                               "-cushnReminderHour", "\(target.hour!)", "-cushnReminderMinute", "\(target.minute!)"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.addPayment("Live Check", amount: "30", day: target.day!)

        let turnOn = app.buttons["reminderPromptTurnOn"]
        if turnOn.waitForExistence(timeout: 3) {
            turnOn.tap()
            let allow = springboard.alerts.buttons["Allow"]
            XCTAssertTrue(allow.waitForExistence(timeout: 5), "iOS should ask only after the person chooses Turn On")
            allow.tap()
        }
        let bell = app.buttons["notificationsBell"]
        XCTAssertEqual(bell.label, "Notifications", "Nothing has come due yet")

        XCUIDevice.shared.press(.home)
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Live Check is due today'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 150), "iOS should show the alert while Cushn is in the background")
        sleep(1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "delivered-alert"
        shot.lifetime = .keepAlways
        add(shot)

        banner.tap()
        XCTAssertTrue(app.staticTexts["detailName"].waitForExistence(timeout: 10), "Tapping the alert should open the payment")
        XCTAssertEqual(app.staticTexts["detailName"].label, "Live Check")
    }
}
