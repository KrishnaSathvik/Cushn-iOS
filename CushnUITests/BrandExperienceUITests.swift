import XCTest

/// New-user routing, the three onboarding pages, first-use hints and the shared header line.
@MainActor
final class BrandExperienceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private let realRouting = ["-cushnFirstUse", "auto"]
    private let forgetFirstUse = ["-cushnResetFirstUse", "YES"]

    func testNewUserSeesOnboardingOnceAndSkipKeepsItAway() {
        let store = tempStorePath()
        let app = launch(store: store, extra: realRouting + forgetFirstUse)
        XCTAssertTrue(app.buttons["onboardingSkip"].waitForExistence(timeout: 5))
        app.buttons["onboardingSkip"].tap()
        XCTAssertTrue(app.buttons["addPayment"].waitForExistence(timeout: 5))
        app.terminate()

        let relaunched = launch(store: store, extra: realRouting)
        XCTAssertTrue(relaunched.buttons["addPayment"].waitForExistence(timeout: 5))
        XCTAssertFalse(relaunched.buttons["onboardingSkip"].exists)
    }

    func testExistingUserGoesStraightToHomeWithTheirData() {
        let store = tempStorePath()
        let setup = launch(store: store)
        setup.addPayment("Netflix", amount: "30", day: 28)
        setup.terminate()

        let app = launch(store: store, extra: realRouting + forgetFirstUse)
        XCTAssertTrue(app.row("Netflix").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboardingSkip"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["coachMark.status"].exists, "Existing users get no first-use hints")
    }

    func testPagesNavigateAndSamplesDoNotTouchRealData() {
        let store = tempStorePath()
        let app = launch(store: store, extra: realRouting + forgetFirstUse + ["-cushnTheme", "blackOnGold"])
        let next = app.buttons["onboardingNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["onboardingProgress"].label, "Page 1 of 3")
        XCTAssertFalse(app.buttons["onboardingBack"].isHittable)

        // Page 1: tapping a tile shows that payment as a row in its section.
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["sampleRow.Netflix"].exists)
        XCTAssertEqual(any["sampleSection"].label, "Subscriptions")
        app.buttons["sampleTile.Rent"].tap()
        XCTAssertTrue(any["sampleRow.Rent"].waitForExistence(timeout: 3))
        XCTAssertEqual(any["sampleSection"].label, "Bills")

        // Back and forward by button and by swipe.
        next.tap()
        XCTAssertTrue(app.buttons["statusCircle.Netflix"].waitForExistence(timeout: 3))
        app.buttons["onboardingBack"].tap()
        XCTAssertTrue(any["sampleRow.Rent"].waitForExistence(timeout: 3))
        app.swipeLeft()

        // Page 2: paid, undo, skip, undo skip. Nothing moves.
        let circle = app.buttons["statusCircle.Netflix"]
        XCTAssertTrue(circle.waitForExistence(timeout: 3))
        let circleY = circle.frame.minY
        XCTAssertEqual(circle.value as? String, "unconfirmed")
        circle.tap()
        XCTAssertEqual(circle.value as? String, "paid")
        XCTAssertEqual(circle.frame.minY, circleY)
        circle.tap()
        XCTAssertEqual(circle.value as? String, "unconfirmed")
        app.buttons["statusOption.skipped"].tap()
        XCTAssertEqual(circle.value as? String, "skipped")
        XCTAssertEqual(circle.frame.minY, circleY)
        app.buttons["statusOption.unconfirmed"].tap()
        XCTAssertEqual(circle.value as? String, "unconfirmed")

        // Page 3: November has its marks and no Spotify. December has Spotify and nothing marked.
        app.buttons["onboardingNext"].tap()
        let novemberRent = app.buttons["rollover.first.Rent"]
        let decemberRent = app.buttons["rollover.second.Rent"]
        XCTAssertTrue(novemberRent.waitForExistence(timeout: 3))
        XCTAssertEqual(novemberRent.value as? String, "paid")
        XCTAssertEqual(decemberRent.value as? String, "unconfirmed")
        XCTAssertFalse(app.buttons["rollover.first.Spotify"].exists)
        XCTAssertTrue(app.buttons["rollover.second.Spotify"].exists)
        XCTAssertEqual(novemberRent.frame.minY, decemberRent.frame.minY, accuracy: 0.5, "A payment lines up across months")

        // A tap in one month leaves the other alone.
        novemberRent.tap()
        XCTAssertEqual(novemberRent.value as? String, "unconfirmed")
        decemberRent.tap()
        XCTAssertEqual(decemberRent.value as? String, "paid")
        XCTAssertEqual(novemberRent.value as? String, "unconfirmed")
        XCTAssertFalse(app.buttons["onboardingSkip"].isHittable, "The last page has only Get Started")

        app.buttons["onboardingStart"].tap()
        XCTAssertTrue(app.buttons["emptyAddPayment"].waitForExistence(timeout: 5), "Sample payments must not reach the real list")
    }

    func testHeaderTitleSitsAtTheSameHeightOnEveryTab() {
        let app = launch(demo: "standard")
        let title = app.buttons["monthTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "November 2026", "VoiceOver keeps the year")
        let homeY = title.frame.minY
        XCTAssertTrue(app.buttons["addPayment"].isHittable)
        XCTAssertEqual(app.buttons["addPayment"].frame.midY, title.frame.midY, accuracy: 6, "Actions share the title's line")
        app.tabBars.buttons["Overview"].tap()
        XCTAssertEqual(app.buttons["monthTitle"].frame.minY, homeY, accuracy: 0.5)
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertEqual(app.buttons["monthTitle"].frame.minY, homeY, accuracy: 0.5)
    }

    func testAddStaysReachableWhenTheHeaderScrolls() {
        let app = launch(demo: "large", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["addPayment"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["addPayment"].isHittable)
    }

    func testHintsAreDismissibleContextualAndShownOnce() {
        let store = tempStorePath()
        let hints = ["-cushnHints", "YES"]
        let app = launch(store: store, extra: hints + forgetFirstUse)
        func hint(_ name: String) -> XCUIElement { app.descendants(matching: .any)["coachMark.\(name)"] }
        XCTAssertTrue(hint("add").waitForExistence(timeout: 5))
        XCTAssertFalse(hint("status").exists, "Only one hint at a time")

        // Add doesn't have to wait for the hint, and doing it retires the hint.
        app.addPayment("Netflix", amount: "30", day: 28)
        XCTAssertFalse(hint("add").exists)
        XCTAssertTrue(hint("status").waitForExistence(timeout: 3))

        // Doing what the hint says ends it, and the next hint waits for another launch.
        app.circle("Netflix").tap()
        XCTAssertEqual(app.status("Netflix"), "paid")
        XCTAssertFalse(hint("status").exists)
        XCTAssertFalse(hint("more").exists)
        app.terminate()

        let second = launch(store: store, extra: hints)
        let more = second.descendants(matching: .any)["coachMark.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        second.buttons["dismissCoachMark"].tap()
        XCTAssertFalse(more.exists)
        second.terminate()

        let third = launch(store: store, extra: hints)
        let months = third.descendants(matching: .any)["coachMark.months"]
        XCTAssertTrue(months.waitForExistence(timeout: 5))
        third.next()
        XCTAssertFalse(months.exists)
        third.terminate()

        // The logo's hint ends when Settings is opened.
        let fourth = launch(store: store, extra: hints)
        let settings = fourth.descendants(matching: .any)["coachMark.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        fourth.openSettings()
        fourth.done()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
        fourth.terminate()

        let fifth = launch(store: store, extra: hints)
        XCTAssertTrue(fifth.row("Netflix").waitForExistence(timeout: 5))
        XCTAssertFalse(fifth.buttons["dismissCoachMark"].exists)
    }

    func testSplashIsNonBlockingAndLeavesOnItsOwn() {
        let app = launch(demo: "standard", extra: ["-cushnSplash", "run", "-cushnTheme", "goldOnBlack"])
        // Home is already there and takes a tap while the splash is fading.
        let circle = app.buttons["statusCircle.Spotify"]
        XCTAssertTrue(circle.waitForExistence(timeout: 5))
        circle.tap()
        XCTAssertEqual(circle.value as? String, "paid")
    }

    // MARK: Audits

    private func auditOnboarding(theme: String, extra: [String] = []) throws {
        let app = launch(store: tempStorePath(), extra: realRouting + forgetFirstUse + ["-cushnTheme", theme] + extra)
        XCTAssertTrue(app.buttons["onboardingNext"].waitForExistence(timeout: 5))
        for page in 0..<3 {
            sleep(1)
            try app.performAccessibilityAudit { issue in
                print("AUDIT \(theme) page \(page): \(issue.auditType.rawValue) \(issue.compactDescription) | '\(issue.element?.label ?? "NO ELEMENT")'")
                return false
            }
            if page < 2 { app.buttons["onboardingNext"].tap() }
        }
    }

    func testAuditOnboardingBlackOnWhite() throws { try auditOnboarding(theme: "blackOnWhite") }
    func testAuditOnboardingGoldOnWhite() throws { try auditOnboarding(theme: "goldOnWhite") }
    func testAuditOnboardingBlackOnGold() throws { try auditOnboarding(theme: "blackOnGold") }
    func testAuditOnboardingGoldOnBlack() throws { try auditOnboarding(theme: "goldOnBlack") }

    // MARK: Screenshots

    private func save(_ name: String) {
        let folder = ProcessInfo.processInfo.environment["CUSHN_SHOTS"] ?? (NSTemporaryDirectory() + "cushn-shots")
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: "\(folder)/\(name).png", contents: XCUIScreen.main.screenshot().pngRepresentation)
    }

    /// Opt-in: scripts run this for review, not on every test pass.
    func testCaptureBrandExperience() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CUSHN_SHOTS"] != nil, "Set CUSHN_SHOTS to capture")
        let environment = ProcessInfo.processInfo.environment
        let themes = environment["CUSHN_THEMES"]?.split(separator: ",").map(String.init)
            ?? ["goldOnWhite", "blackOnWhite", "blackOnGold", "goldOnBlack"]
        let text = environment["CUSHN_TEXT"].map { ["-UIPreferredContentSizeCategoryName", $0] } ?? []
        for theme in themes {
            let splash = launch(store: tempStorePath(), extra: text + ["-cushnSplash", "hold", "-cushnTheme", theme])
            sleep(1)
            save("splash-\(theme)")
            splash.terminate()

            let app = launch(store: tempStorePath(), extra: text + realRouting + forgetFirstUse + ["-cushnTheme", theme])
            XCTAssertTrue(app.buttons["onboardingNext"].waitForExistence(timeout: 5))
            sleep(1)
            save("onboarding-\(theme)-1")
            app.buttons["onboardingNext"].tap()
            sleep(1)
            save("onboarding-\(theme)-2")
            app.buttons["onboardingNext"].tap()
            sleep(1)
            save("onboarding-\(theme)-3")
            app.swipeUp()
            sleep(1)
            save("onboarding-\(theme)-3-scrolled")
            app.terminate()
        }
    }

    func testCaptureMainScreens() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CUSHN_SHOTS"] != nil, "Set CUSHN_SHOTS to capture")
        let scheme = ProcessInfo.processInfo.environment["CUSHN_APPEARANCE"] ?? "light"
        let text = ProcessInfo.processInfo.environment["CUSHN_TEXT"].map { ["-UIPreferredContentSizeCategoryName", $0] } ?? []
        let appearance = ["-appearance", scheme] + text
        let app = launch(demo: "standard", extra: appearance)
        XCTAssertTrue(app.buttons["monthTitle"].waitForExistence(timeout: 5))
        sleep(1)
        save("main-\(scheme)-home")
        app.tabBars.buttons["Overview"].tap(); sleep(1)
        save("main-\(scheme)-overview")
        app.tabBars.buttons["Calendar"].tap(); sleep(1)
        save("main-\(scheme)-calendar")
        app.tabBars.buttons["Home"].tap()
        app.buttons["addPayment"].tap(); sleep(1)
        save("main-\(scheme)-add")
        app.buttons["Cancel"].firstMatch.tap(); sleep(1)
        app.row("Spotify").tap(); sleep(1)
        save("main-\(scheme)-details")
        app.buttons["Done"].firstMatch.tap(); sleep(1)
        app.openSettings(); sleep(1)
        save("main-\(scheme)-settings")
        app.buttons["Done"].firstMatch.tap(); sleep(1)
        app.openOrganize(); sleep(1)
        save("main-\(scheme)-organize")
        app.buttons["Done"].firstMatch.tap(); sleep(1)
        app.terminate()

        let hint = launch(store: tempStorePath(), extra: appearance + ["-cushnHints", "YES", "-cushnResetFirstUse", "YES"])
        XCTAssertTrue(hint.buttons["addPayment"].waitForExistence(timeout: 5))
        sleep(1)
        save("main-\(scheme)-empty-hint")
        hint.addPayment("Netflix", amount: "17.99", day: 28)
        sleep(1)
        save("main-\(scheme)-status-hint")
    }

    func testLandscapeLayouts() throws {
        func rotate(_ app: XCUIApplication) throws {
            XCUIDevice.shared.orientation = .portrait
            sleep(1)
            XCUIDevice.shared.orientation = .landscapeLeft
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                let frame = app.windows.firstMatch.frame
                if frame.width > frame.height { break }
                usleep(250_000)
            }
            sleep(1)
            let frame = app.windows.firstMatch.frame
            // Without this the test would pass while still in portrait. Some simulator sessions don't rotate,
            // including on the M5.5 baseline, and that must read as "not checked" rather than a pass.
            try XCTSkipUnless(frame.width > frame.height, "This simulator session didn't rotate, so landscape wasn't checked")
        }
        defer { XCUIDevice.shared.orientation = .portrait }

        let splash = launch(store: tempStorePath(), extra: ["-cushnSplash", "hold", "-cushnTheme", "blackOnGold"])
        try rotate(splash)
        save("landscape-splash")
        splash.terminate()

        let app = launch(store: tempStorePath(), extra: realRouting + forgetFirstUse + ["-cushnTheme", "goldOnBlack"])
        XCTAssertTrue(app.buttons["onboardingNext"].waitForExistence(timeout: 5))
        try rotate(app)
        save("landscape-onboarding")
        XCTAssertTrue(app.buttons["onboardingNext"].isHittable, "The primary action stays reachable in landscape")
        app.terminate()

        let home = launch(demo: "standard")
        XCTAssertTrue(home.buttons["addPayment"].waitForExistence(timeout: 5))
        try rotate(home)
        save("landscape-home")
        XCTAssertTrue(home.buttons["addPayment"].isHittable, "Add stays reachable in landscape")
    }
}
