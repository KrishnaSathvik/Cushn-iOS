import Foundation
import Testing
import UIKit
@testable import Cushn

/// A repeatable generator, so the fairness check doesn't depend on luck.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite struct BrandThemeTests {
    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test func eachThemePairsTheBriefsColorsWithItsLogo() {
        #expect(CushnBrandTheme.allCases.count == 4)
        #expect(CushnBrandTheme.goldOnWhite.logoAsset == "CushnLogoGoldWhite")
        #expect(CushnBrandTheme.blackOnWhite.logoAsset == "CushnLogoBlackWhite")
        #expect(CushnBrandTheme.blackOnGold.logoAsset == "CushnLogoBlackGold")
        #expect(CushnBrandTheme.goldOnBlack.logoAsset == "CushnLogoGoldBlack")
        #expect(CushnBrandTheme.goldOnWhite.palette.buttonFill == 0x111111)
        #expect(CushnBrandTheme.blackOnWhite.palette.buttonFill == 0x111111)
        #expect(CushnBrandTheme.blackOnGold.palette.buttonFill == 0x111111)
        #expect(CushnBrandTheme.goldOnBlack.palette.buttonFill == CushnBrandTheme.goldOnBlack.palette.mark)
        #expect(CushnBrandTheme.goldOnBlack.colorScheme == .dark)
        #expect(CushnBrandTheme.blackOnGold.colorScheme == .light)
    }

    @Test(arguments: CushnBrandTheme.allCases)
    func logoAssetsAreBundled(theme: CushnBrandTheme) {
        let bundle = Bundle(for: AppModel.self)
        let original = UIImage(named: theme.logoAsset, in: bundle, compatibleWith: nil)
        let mark = UIImage(named: theme.markAsset, in: bundle, compatibleWith: nil)
        #expect(original?.size == CGSize(width: 1254, height: 1254))
        #expect(mark?.size == CGSize(width: 1254, height: 1254))
    }

    @Test(arguments: CushnBrandTheme.allCases)
    func textAndButtonsMeetAA(theme: CushnBrandTheme) {
        let palette = theme.palette
        #expect(contrast(palette.title, palette.background) >= 4.5)
        #expect(contrast(palette.secondary, palette.background) >= 4.5)
        #expect(contrast(palette.buttonText, palette.buttonFill) >= 4.5)
        #expect(contrast(palette.buttonFill, palette.background) >= 3)
    }

    @Test func lightLaunchesChooseEvenlyAmongTheLightThemes() {
        var generator = SeededGenerator(state: 42)
        var counts: [CushnBrandTheme: Int] = [:]
        for _ in 0..<30_000 { counts[CushnBrandTheme.random(for: .light, using: &generator), default: 0] += 1 }
        #expect(Set(counts.keys) == [.goldOnWhite, .blackOnWhite, .blackOnGold])
        for (theme, count) in counts {
            #expect(abs(count - 10_000) < 400, "\(theme): \(count)")
        }
    }

    @Test func darkLaunchesAlwaysGetTheDarkTheme() {
        var generator = SeededGenerator(state: 42)
        for _ in 0..<200 { #expect(CushnBrandTheme.random(for: .dark, using: &generator) == .goldOnBlack) }
    }

    @Test func theSystemDecidesUnlessSettingsHasAChoice() {
        #expect(CushnBrandTheme.launchScheme(setting: .system, systemIsDark: true) == .dark)
        #expect(CushnBrandTheme.launchScheme(setting: .system, systemIsDark: false) == .light)
        #expect(CushnBrandTheme.launchScheme(setting: .light, systemIsDark: true) == .light)
        #expect(CushnBrandTheme.launchScheme(setting: .dark, systemIsDark: false) == .dark)
    }
}

@Suite @MainActor struct FirstUseTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "cushn.tests.\(UUID().uuidString)")!
    }

    @Test nonisolated func gateDecisions() {
        #expect(OnboardingGate.decision(completed: false, hasPayments: false) == .show)
        #expect(OnboardingGate.decision(completed: false, hasPayments: true) == .skipExistingUser)
        #expect(OnboardingGate.decision(completed: true, hasPayments: false) == .skip)
        #expect(OnboardingGate.decision(completed: true, hasPayments: true) == .skip)
    }

    @Test func completionSurvivesRestart() {
        let defaults = freshDefaults()
        let first = FirstUseState(defaults: defaults)
        #expect(first.resolveOnboarding(hasPayments: false))
        first.completeOnboarding()
        let relaunched = FirstUseState(defaults: defaults)
        #expect(!relaunched.resolveOnboarding(hasPayments: false))
    }

    @Test func existingUserSkipsOnboardingAndHintsForGood() {
        let defaults = freshDefaults()
        let state = FirstUseState(defaults: defaults)
        #expect(!state.resolveOnboarding(hasPayments: true))
        #expect(state.activeHint(paymentCount: 5) == nil)
        // Removing every payment later doesn't turn them into a new user.
        let relaunched = FirstUseState(defaults: defaults)
        #expect(!relaunched.resolveOnboarding(hasPayments: false))
        #expect(relaunched.activeHint(paymentCount: 0) == nil)
    }

    @Test func hintsFollowTheListAndNeverFormATour() {
        let defaults = freshDefaults()
        let state = FirstUseState(defaults: defaults)
        #expect(state.activeHint(paymentCount: 0) == .add)
        state.finish(.add, wasShowing: true)
        #expect(state.activeHint(paymentCount: 0) == nil)
        #expect(state.activeHint(paymentCount: 1) == .status)
        state.finish(.status, wasShowing: true)
        #expect(state.activeHint(paymentCount: 1) == nil, "The next hint waits for another launch")

        let secondLaunch = FirstUseState(defaults: defaults)
        #expect(secondLaunch.activeHint(paymentCount: 1) == .more)
        secondLaunch.finish(.more, wasShowing: true)
        #expect(secondLaunch.activeHint(paymentCount: 1) == nil)

        let thirdLaunch = FirstUseState(defaults: defaults)
        #expect(thirdLaunch.activeHint(paymentCount: 1) == .months)
        thirdLaunch.finish(.months, wasShowing: true)

        let fourthLaunch = FirstUseState(defaults: defaults)
        #expect(fourthLaunch.activeHint(paymentCount: 1) == .settings)
        fourthLaunch.finish(.settings, wasShowing: true)

        let fifthLaunch = FirstUseState(defaults: defaults)
        #expect(fifthLaunch.activeHint(paymentCount: 1) == nil)
    }

    @Test func doingTheThingFirstRetiresItsHintWithoutEndingTheLaunch() {
        let state = FirstUseState(defaults: freshDefaults())
        state.finish(.add, wasShowing: false)
        state.finish(.more, wasShowing: false)
        #expect(state.activeHint(paymentCount: 2) == .status)
        state.finish(.status, wasShowing: false)
        #expect(state.activeHint(paymentCount: 2) == .months)
    }

    @Test func hintsCanBeTurnedOff() {
        let state = FirstUseState(defaults: freshDefaults(), hintsEnabled: false)
        #expect(state.activeHint(paymentCount: 0) == nil)
    }
}

@Suite @MainActor struct OnboardingSampleTests {
    private let november = YearMonth(year: 2026, month: 11)!
    private var december: YearMonth { november.adding(months: 1) }

    @Test func checklistHoldsARangeOfPaymentsWithRealIcons() throws {
        let view = try OnboardingSample.checklist(month: november).store.view(for: november)
        #expect(view.sections.map(\.title) == ["Credit Cards", "Subscriptions", "Bills"])
        #expect(view.rows.count == 8, "Fills the four-column grid")
        for name in ["Apple Card", "American Express", "Netflix", "ChatGPT", "Spotify"] {
            guard case .artwork = BrandMatcher.iconContent(for: name) else {
                Issue.record("\(name) should use bundled artwork")
                continue
            }
        }
        #expect(BrandMatcher.iconContent(for: "Rent") == .symbol("house"))
    }

    @Test func statusSampleStartsUnmarked() throws {
        let sample = try OnboardingSample.statuses(month: november)
        let rows = sample.model.store.view(for: november).rows
        #expect(rows.map(\.status) == [.unconfirmed])
        #expect(rows.first?.id == sample.target)
    }

    @Test func rolloverShowsRealMonthBehavior() throws {
        let store = try OnboardingSample.rollover(month: november).store
        let first = store.view(for: november).rows
        let second = store.view(for: december).rows

        #expect(!first.map(\.name).contains("Spotify"), "A payment added in December never appears in November")
        #expect(second.map(\.name).contains("Spotify"))
        #expect(Set(first.map(\.name)).isSubset(of: Set(second.map(\.name))), "The list carries forward")
        #expect(first.contains { $0.status == .paid }, "November keeps its statuses")
        #expect(second.allSatisfy { $0.status == .unconfirmed }, "December starts fresh")
    }

    @Test func tappingASampleChangesOnlyTheSample() throws {
        let first = try OnboardingSample.statuses(month: november)
        let second = try OnboardingSample.statuses(month: november)
        _ = first.model.tapStatusCircle(id: first.target, month: november)
        #expect(first.model.store.view(for: november).rows.first { $0.id == first.target }?.status == .paid)
        #expect(second.model.store.view(for: november).rows.first { $0.id == second.target }?.status == .unconfirmed)
    }
}

@Suite struct FallbackIconColorTests {
    @Test func sameNameAlwaysGetsTheSameColor() {
        #expect(FallbackIconColor.index(for: "Rent") == FallbackIconColor.index(for: " rent "))
        #expect(FallbackIconColor.index(for: "Rent") == FallbackIconColor.index(for: "RENT"))
    }

    @Test func commonBillsSpreadAcrossThePalette() {
        let names = ["Rent", "Electric", "Water", "Internet", "Gas", "Trash", "Phone", "Gym", "Piano lessons", "Daycare", "Insurance", "Mortgage"]
        #expect(Set(names.map(FallbackIconColor.index(for:))).count >= 5)
    }

    @Test func glyphStaysVisibleOnItsTile() {
        func luminance(_ hex: UInt32) -> Double {
            func channel(_ value: UInt32) -> Double {
                let c = Double(value) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
        }
        func contrast(_ a: UInt32, _ b: UInt32) -> Double {
            let (x, y) = (luminance(a), luminance(b))
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        #expect(FallbackIconColor.palette.count == 16)
        for pair in FallbackIconColor.palette {
            // 4.5, because a tile can hold a letter, which counts as text.
            #expect(contrast(pair.glyph.light, pair.tile.light) >= 4.5)
            #expect(contrast(pair.glyph.dark, pair.tile.dark) >= 4.5)
        }
    }

    @Test func tileAndGlyphAreDifferentColors() {
        func hue(_ hex: UInt32) -> Double {
            let (r, g, b) = (Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
            let (high, low) = (max(r, g, b), min(r, g, b))
            let degrees: Double = high == r ? (g - b) / (high - low) * 60 : high == g ? (b - r) / (high - low) * 60 + 120 : (r - g) / (high - low) * 60 + 240
            return (degrees + 360).truncatingRemainder(dividingBy: 360)
        }
        for pair in FallbackIconColor.palette {
            let distance = abs(hue(pair.tile.light) - hue(pair.glyph.light))
            #expect(min(distance, 360 - distance) >= 60)
        }
        #expect(Set(FallbackIconColor.palette.map(\.tile.light)).count == FallbackIconColor.palette.count)
    }
}

@MainActor @Suite struct SplashGateTests {
    private func fresh() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    @Test func showsOnlyOnTheFirstLaunchAfterDownload() {
        let defaults = fresh()
        #expect(FirstUseState(defaults: defaults).resolveSplash(hasPayments: false))
        #expect(!FirstUseState(defaults: defaults).resolveSplash(hasPayments: false), "Relaunch")
        #expect(!FirstUseState(defaults: defaults).resolveSplash(hasPayments: true))
    }

    @Test func someoneUpdatingWithPaymentsNeverSeesIt() {
        #expect(!FirstUseState(defaults: fresh()).resolveSplash(hasPayments: true))
    }
}
