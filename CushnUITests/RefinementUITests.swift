import XCTest

/// M5.9: the simplified header, direct section reordering, the compact editor and the short Settings.
@MainActor
final class RefinementUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func header(_ app: XCUIApplication, _ title: String) -> XCUIElement { app.sectionHeader(title) }

    /// Opens Reorder from a section's handle, drags one section onto another with the system's handles, and closes.
    private func reorder(_ app: XCUIApplication, from handle: String, moving section: String, onto target: String) {
        app.buttons["reorderHandle.\(handle)"].tap()
        let grip = app.buttons["Reorder \(section)"]
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        grip.press(forDuration: 0.6, thenDragTo: app.buttons["Reorder \(target)"])
        sleep(1)
        app.buttons["reorderDone"].tap()
        XCTAssertTrue(header(app, target).waitForExistence(timeout: 5))
    }

    func testLogoOpensShortSettingsFromEveryTab() {
        let app = launch(demo: "standard", extra: ["-cushnReminders", "allowed"])
        XCTAssertFalse(app.buttons["moreMenu"].exists)
        for tab in ["Home", "Overview", "Calendar"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertEqual(app.buttons["settingsLogo"].label, "Cushn settings")
            app.openSettings()
            XCTAssertTrue(app.switches["remindersToggle"].waitForExistence(timeout: 5), tab)
            app.done()
            XCTAssertTrue(app.buttons["settingsLogo"].waitForExistence(timeout: 5))
        }
        app.openSettings()
        XCTAssertTrue(app.switches["remindersToggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["versionRow"].exists, "About fits without scrolling")
        for gone in ["Acknowledgements", "is a checklist", "connect to banks", "Lock Screen", "Existing payments keep"] {
            let matches = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", gone))
            XCTAssertEqual(matches.count, 0, gone)
        }
    }

    func testSettingsLinksToPrivacyAndSupport() {
        let app = launch(demo: "standard")
        app.openSettings()
        XCTAssertTrue(app.buttons["privacyLink"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["privacyLink"].label, "Privacy Policy")
        XCTAssertTrue(app.buttons["supportLink"].exists)
    }

    func testLogoStaysReachableAtTheLargestText() {
        let app = launch(demo: "standard", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["settingsLogo"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["settingsLogo"].isHittable, "It's in the fixed toolbar while the header scrolls")
        app.openSettings()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
    }

    func testReorderingSectionsAppliesFromThatMonthOnly() {
        let app = launch(demo: "standard")
        XCTAssertLessThan(header(app, "Credit Cards").frame.minY, header(app, "Subscriptions").frame.minY)
        app.next()
        reorder(app, from: "Housing", moving: "Subscriptions", onto: "Credit Cards")
        XCTAssertGreaterThan(header(app, "Credit Cards").frame.minY, header(app, "Subscriptions").frame.minY, "December follows the new order")
        app.previous()
        XCTAssertLessThan(header(app, "Credit Cards").frame.minY, header(app, "Subscriptions").frame.minY, "November keeps its order")
    }

    func testTappingAHeadingOpensItsOptionsAndMovesNothing() {
        let app = launch(demo: "standard")
        let before = (header(app, "Credit Cards").frame.minY, header(app, "Subscriptions").frame.minY)
        header(app, "Subscriptions").tap()
        XCTAssertTrue(app.buttons["Edit section"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Move up"].exists)
        XCTAssertTrue(app.buttons["All sections"].exists)
        app.buttons["Edit section"].tap()
        XCTAssertTrue(app.textFields["sectionNameField"].waitForExistence(timeout: 5))
        app.done()
        XCTAssertTrue(header(app, "Credit Cards").waitForExistence(timeout: 5))
        XCTAssertEqual(header(app, "Credit Cards").frame.minY, before.0)
        XCTAssertEqual(header(app, "Subscriptions").frame.minY, before.1)
    }

    func testMoveUpIsTheAlternativeToDragging() {
        let app = launch(demo: "standard")
        app.next()
        let first = header(app, "Credit Cards").frame.minY
        let housing = header(app, "Housing")
        XCTAssertGreaterThan(housing.frame.minY, first)
        housing.tap()
        XCTAssertTrue(app.buttons["Move up"].waitForExistence(timeout: 5))
        app.buttons["Move up"].tap()
        sleep(1)
        XCTAssertLessThan(header(app, "Housing").frame.minY, header(app, "Subscriptions").frame.minY)
        app.previous()
        XCTAssertGreaterThan(header(app, "Housing").frame.minY, header(app, "Subscriptions").frame.minY, "November keeps its order")
    }

    func testRecognizedNameSuggestsASectionAndAManualChoiceStays() {
        let app = launch(store: tempStorePath())
        app.buttons["addPayment"].tap()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let section = app.buttons["sectionPicker"]
        XCTAssertEqual(section.value as? String, "Other")
        name.typeText("Netflix")
        XCTAssertEqual(section.value as? String, "Subscriptions")
        XCTAssertEqual(section.label, "Section, suggested")

        section.tap()
        let housing = app.buttons["sectionChoice.Housing"]
        XCTAssertTrue(housing.waitForExistence(timeout: 5))
        XCTAssertLessThan(section.frame.maxY, housing.frame.minY + 1, "The choices open in place, below the row, covering nothing")
        housing.tap()
        XCTAssertTrue(housing.waitForNonExistence(timeout: 3), "Choosing closes them")
        XCTAssertEqual(section.value as? String, "Housing")
        XCTAssertEqual(section.label, "Section")

        name.tap()
        name.typeText(" Premium")
        XCTAssertEqual(section.value as? String, "Housing", "Typing doesn't undo a choice")

        app.textFields["amountField"].tap()
        app.textFields["amountField"].typeText("21.99")
        app.buttons["dueDayField"].tap()
        app.buttons["day.28"].tap()
        app.buttons["savePayment"].tap()
        XCTAssertTrue(header(app, "Housing").waitForExistence(timeout: 5))
        XCTAssertTrue(app.row("Netflix Premium").exists)
    }

    func testABrandIsWrittenTheCompanysWayAsYouType() {
        let app = launch(store: tempStorePath())
        app.buttons["addPayment"].tap()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("chatgpt")
        XCTAssertEqual(name.value as? String, "ChatGPT", "A change of capitals happens right away")
        app.buttons["cancelPayment"].tap()
        app.buttons["Discard"].firstMatch.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 3))

        app.buttons["addPayment"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("tmobile")
        app.textFields["amountField"].tap()
        XCTAssertEqual(name.value as? String, "T-Mobile", "A change of length waits for the field to be left")
    }

    func testASectionsAddButtonWins() {
        let app = launch(demo: "standard")
        app.buttons["Add payment to Housing"].tap()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Netflix Two")
        XCTAssertEqual(app.buttons["sectionPicker"].value as? String, "Housing")
    }

    func testCancelAsksOnlyWhenThereAreChanges() {
        let app = launch(store: tempStorePath())
        app.buttons["addPayment"].tap()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.buttons["cancelPayment"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 3), "Nothing typed, nothing to ask")

        app.buttons["addPayment"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Rent")
        app.buttons["cancelPayment"].tap()
        XCTAssertTrue(app.buttons["Keep Editing"].waitForExistence(timeout: 3))
        app.buttons["Keep Editing"].tap()
        XCTAssertEqual(name.value as? String, "Rent")
        app.buttons["cancelPayment"].tap()
        app.buttons["Discard"].firstMatch.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 3))
    }

    /// Fields stay above the keyboard, and Save stays reachable. Worth rerunning on the small simulator.
    func testEditorControlsStayClearOfTheKeyboard() {
        let app = launch(store: tempStorePath())
        app.buttons["addPayment"].tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        sleep(1)
        for id in ["nameField", "amountField"] {
            XCTAssertLessThanOrEqual(app.textFields[id].frame.maxY, keyboard.frame.minY, id)
        }
        XCTAssertLessThanOrEqual(app.buttons["dueDayField"].frame.maxY, keyboard.frame.minY)
        XCTAssertTrue(app.buttons["savePayment"].isHittable)
        XCTAssertTrue(app.buttons["cancelPayment"].isHittable)
    }

    func testOverviewSimplifiesForOnePayment() {
        let app = launch(demo: "single", extra: ["-cushnTab", "overview"])
        XCTAssertTrue(app.staticTexts["scheduledTotal"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["scheduledTotal"].label, "Total scheduled, $21.99")
        XCTAssertFalse(app.staticTexts["Marked paid"].exists, "One payment's split would repeat the total")
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["typeLine.Estimated expenses"].exists)
        XCTAssertFalse(app.staticTexts["Scheduled by section"].exists)
        app.swipeUp()
        XCTAssertTrue(any["trendEmpty"].waitForExistence(timeout: 3), "A tasteful empty state, not zero bars")
        XCTAssertFalse(any["comparisonLine"].exists)
    }

    func testYearlyEstimateShowsOnOverviewAndInDetails() {
        let app = launch(demo: "single", extra: ["-cushnTab", "overview"])
        let overview = app.staticTexts["yearlyEstimate"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertEqual(overview.label, "About $263.88 a year")
        app.tabBars.buttons["Home"].tap()
        app.row("Netflix").tap()
        let details = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'About $263.88 a year'")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
    }

    func testOverviewNeverCombinesCurrencies() {
        let app = launch(demo: "mixed", extra: ["-cushnTab", "overview"])
        let totals = app.staticTexts.matching(identifier: "scheduledTotal")
        XCTAssertTrue(totals.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(totals.firstMatch.label, "Total scheduled, €1,234,577.88")
        XCTAssertTrue(app.staticTexts["Euro"].exists)
    }

    func testOverviewTrendAndInfo() {
        let app = launch(demo: "compare", extra: ["-cushnTab", "overview"])
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["overviewInfo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Scheduled by section"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'bank'")).count, 0, "Explanations live in the info sheet")
        app.buttons["overviewInfo"].tap()
        XCTAssertTrue(any["About these figures"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(any.matching(NSPredicate(format: "label CONTAINS 'verified spending'")).count, 0)
        app.done()
        sleep(1)
        app.swipeUp()
        XCTAssertTrue(any["comparisonLine"].waitForExistence(timeout: 5))
        for (month, amount) in [("October", "$4,281.88"), ("November", "$4,306.87")] {
            let bar = any.matching(NSPredicate(format: "label == %@ AND value == %@", month, amount)).firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 5), "\(month) bar reads its exact amount")
        }
        XCTAssertTrue(any["comparisonLine"].exists)
    }

    func testCalendarTodayReturnsAcrossMonths() {
        let app = launch(demo: "standard", extra: ["-cushnTab", "calendar"])
        XCTAssertTrue(app.staticTexts["selectedDayTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["selectedDayTitle"].label, "Sunday, November 15")
        XCTAssertFalse(app.buttons["calendarToday"].exists, "Already on today")
        app.next()
        XCTAssertTrue(app.buttons["calendarToday"].waitForExistence(timeout: 5))
        app.buttons["calendarToday"].tap()
        XCTAssertTrue(app.buttons["monthTitle"].waitForLabel("November 2026"))
        XCTAssertEqual(app.staticTexts["selectedDayTitle"].label, "Sunday, November 15")
    }

    /// Saves the raw App Store and website screens when CUSHN_SHOTS names a folder. CUSHN_STYLE is light or dark.
    func testCaptureAppStore() throws {
        let folder = ProcessInfo.processInfo.environment["CUSHN_SHOTS"] ?? ""
        try XCTSkipIf(folder.isEmpty, "Capture only")
        func save(_ name: String) throws {
            sleep(2)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
        }
        let style = ProcessInfo.processInfo.environment["CUSHN_STYLE"] ?? "light"
        let setup = ["-appearance", style, "-cushnReminders", "allowed", "-cushnNow", "2026-11-15"]
        var app = launch(demo: "appstore", extra: setup)
        XCTAssertTrue(app.buttons["addPayment"].waitForExistence(timeout: 5))
        try save("1-home")
        app.row("ChatGPT").tap()
        XCTAssertTrue(app.buttons["markPaidAction"].waitForExistence(timeout: 5))
        try save("2-status")
        app.terminate()

        app = launch(demo: "appstore", extra: setup + ["-cushnTab", "overview"])
        XCTAssertTrue(app.staticTexts["scheduledTotal"].waitForExistence(timeout: 5))
        try save("3-overview")
        app.terminate()

        app = launch(demo: "appstore", extra: setup + ["-cushnTab", "calendar"])
        XCTAssertTrue(app.staticTexts["selectedDayTitle"].waitForExistence(timeout: 5))
        app.buttons["calendarDay.21"].tap()
        try save("4-calendar")
        app.terminate()

        app = launch(demo: "appstore", extra: setup + ["-cushnInboxDays", "20"])
        XCTAssertTrue(app.buttons["notificationsBell"].waitForExistence(timeout: 5))
        app.buttons["notificationsBell"].tap()
        try save("5-reminders")
    }

    /// Saves what a new user sees under the simulator's current appearance, for comparing light and dark by eye.
    func testCaptureFirstRunMatchesAppearance() throws {
        let folder = ProcessInfo.processInfo.environment["CUSHN_SHOTS"] ?? ""
        try XCTSkipIf(folder.isEmpty, "Capture only")
        for attempt in 1...4 {
            let store = tempStorePath()
            let app = launch(store: store, extra: ["-cushnFirstUse", "auto", "-cushnResetFirstUse", "YES"])
            XCTAssertTrue(app.buttons["onboardingSkip"].waitForExistence(timeout: 5))
            sleep(1)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/onboarding-\(attempt).png"))
            if attempt == 4 {
                app.buttons["onboardingSkip"].tap()
                XCTAssertTrue(app.buttons["addPayment"].waitForExistence(timeout: 5))
                sleep(1)
                try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/home.png"))
            }
            app.terminate()
        }
    }

    /// Saves Overview's states when CUSHN_SHOTS names a folder.
    func testCaptureOverview() throws {
        let folder = ProcessInfo.processInfo.environment["CUSHN_SHOTS"] ?? ""
        try XCTSkipIf(folder.isEmpty, "Capture only")
        let style = ProcessInfo.processInfo.environment["CUSHN_STYLE"] ?? "light"
        func save(_ name: String) throws {
            sleep(1)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
        }
        for demo in ["standard", "compare", "single", "mixed", "owner"] {
            let app = launch(demo: demo, extra: ["-appearance", style, "-cushnTab", "overview"])
            XCTAssertTrue(app.staticTexts["scheduledTotal"].waitForExistence(timeout: 5))
            try save("\(demo)-1")
            app.swipeUp()
            try save("\(demo)-2")
            app.terminate()
        }
        let empty = launch(store: tempStorePath(), extra: ["-appearance", style, "-cushnTab", "overview"])
        XCTAssertTrue(empty.buttons["monthTitle"].waitForExistence(timeout: 5))
        try save("empty")
        empty.terminate()
        let info = launch(demo: "standard", extra: ["-appearance", style, "-cushnTab", "overview"])
        XCTAssertTrue(info.buttons["overviewInfo"].waitForExistence(timeout: 5))
        info.buttons["overviewInfo"].tap()
        try save("info")
    }

    /// Saves this milestone's screens when CUSHN_SHOTS names a folder. Run per device or appearance as needed.
    func testCaptureScreens() throws {
        let folder = ProcessInfo.processInfo.environment["CUSHN_SHOTS"] ?? ""
        try XCTSkipIf(folder.isEmpty, "Capture only")
        let style = ProcessInfo.processInfo.environment["CUSHN_STYLE"] ?? "light"
        let large = ProcessInfo.processInfo.environment["CUSHN_LARGE"] == "1"
        var extra = ["-appearance", style]
        if large { extra += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        func save(_ name: String) throws {
            sleep(1)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
        }

        var app = launch(demo: "standard", extra: extra)
        XCTAssertTrue(app.buttons["addPayment"].waitForExistence(timeout: 5))
        try save("home")
        // At the largest text only the first section may be on screen.
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reorderHandle.'")).firstMatch.tap()
        try save("home-reorder")
        app.buttons["reorderDone"].tap()
        sleep(1)
        app.buttons["monthTitle"].tap()
        try save("month-picker")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(1)

        app.buttons["addPayment"].tap()
        try save("add-keyboard")
        app.textFields["nameField"].typeText("Netflix Premium")
        try save("add-recognized")
        app.buttons["dueDayField"].tap()
        try save("add-days")
        app.buttons["day.28"].tap()
        app.buttons["sectionPicker"].tap()
        try save("add-section-choices")
        app.buttons["sectionChoice.Housing"].tap()
        try save("add-manual-override")
        app.buttons["cancelPayment"].tap()
        if app.buttons["Discard"].firstMatch.waitForExistence(timeout: 3) { app.buttons["Discard"].firstMatch.tap() }
        sleep(1)

        if !large {
            app.row("Spotify").tap()
            sleep(1)
            app.buttons["editAction"].tap()
            try save("edit")
            app.buttons["cancelPayment"].tap()
            sleep(1)
            app.done()
            sleep(1)
        }

        app.openSettings()
        try save("settings")
        app.done()
        app.terminate()

        app = launch(demo: "standard", extra: extra + ["-cushnTab", "overview"])
        XCTAssertTrue(app.staticTexts["scheduledTotal"].waitForExistence(timeout: 5))
        try save("overview")
        app.swipeUp()
        try save("overview-2")
        app.terminate()

        app = launch(demo: "compare", extra: extra + ["-cushnTab", "overview"])
        XCTAssertTrue(app.staticTexts["scheduledTotal"].waitForExistence(timeout: 5))
        app.swipeUp()
        try save("overview-compare")
        app.terminate()

        app = launch(demo: "single", extra: extra + ["-cushnTab", "overview"])
        try save("overview-single")
        app.terminate()

        app = launch(demo: "mixed", extra: extra + ["-cushnTab", "overview"])
        try save("overview-mixed")
        app.terminate()

        app = launch(demo: "standard", extra: extra + ["-cushnTab", "calendar"])
        XCTAssertTrue(app.staticTexts["selectedDayTitle"].waitForExistence(timeout: 5))
        try save("calendar-today")
        app.buttons["calendarDay.14"].tap()
        try save("calendar-nothing-due")
        app.buttons["calendarDay.21"].tap()
        try save("calendar-due-day")
        app.terminate()

        app = launch(demo: "busy", extra: extra + ["-cushnTab", "calendar"])
        XCTAssertTrue(app.staticTexts["selectedDayTitle"].waitForExistence(timeout: 5))
        app.buttons["calendarDay.21"].tap()
        try save("calendar-busy")
        app.terminate()

        for theme in ["goldOnWhite", "goldOnBlack"] {
            app = launch(store: tempStorePath(), extra: extra + ["-cushnOnboarding", "YES", "-cushnTheme", theme])
            XCTAssertTrue(app.buttons["onboardingNext"].waitForExistence(timeout: 5))
            try save("onboarding-\(theme)-1")
            if !large {
                app.buttons["sampleTile.Rent"].tap()
                try save("onboarding-\(theme)-1b")
            }
            app.buttons["onboardingNext"].tap()
            try save("onboarding-\(theme)-2")
            app.buttons["statusOption.skipped"].tap()
            try save("onboarding-\(theme)-2b")
            app.buttons["onboardingNext"].tap()
            try save("onboarding-\(theme)-3")
            app.terminate()
        }
    }
}
