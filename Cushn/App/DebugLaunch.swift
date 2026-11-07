#if DEBUG
import Foundation
import SwiftData

/// Debug-only launch overrides for UI tests and screenshots. Compiled out of release builds.
/// Arguments: -cushnNow 2026-11-15, -cushnDemo standard|large, -cushnInMemory YES,
/// -cushnStorePath <path>, -cushnTab overview|calendar.
/// Any of those turns off the splash, onboarding and hints, so existing tests see Home directly. To bring them back:
/// -cushnSplash run|hold, -cushnTheme <CushnBrandTheme>, -cushnOnboarding YES, -cushnHints YES,
/// -cushnFirstUse auto (the real new-user routing), -cushnResetFirstUse YES (forget first-use markers first).
/// Reminders never reach iOS unless asked: -cushnReminders live uses the real system, while prompt|allowed|denied
/// fake that permission state. -cushnInboxDays <n> fills the inbox from the last n days. -cushnReminderHour and
/// -cushnReminderMinute set the alert time for a live check.
enum DebugLaunch {
    @MainActor
    static func makeModel() throws -> AppModel? {
        let defaults = UserDefaults.standard
        let nowText = defaults.string(forKey: "cushnNow")
        let demo = defaults.string(forKey: "cushnDemo")
        let storePath = defaults.string(forKey: "cushnStorePath")
        let inMemory = defaults.bool(forKey: "cushnInMemory")
        let tab = defaults.string(forKey: "cushnTab")
        guard nowText != nil || demo != nil || storePath != nil || inMemory || tab != nil else { return nil }

        let clock: any AppClock = nowText.flatMap(fixedClock(from:)) ?? SystemClock()
        let repository: any LedgerRepository
        if let storePath {
            let url = URL(fileURLWithPath: storePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            repository = SwiftDataLedgerRepository(container: try CushnPersistence.makeContainer(url: url))
        } else if inMemory || demo != nil {
            repository = InMemoryLedgerRepository()
        } else {
            repository = SwiftDataLedgerRepository(container: try CushnPersistence.makeContainer(url: CushnPersistence.defaultStoreURL()))
        }

        let store = try LedgerStore(repository: repository, clock: clock)
        if let demo { try DemoData.load(demo, into: store) }
        let model = makeReminderModel(store: store, defaults: defaults)
        if let tab = tab.flatMap(AppTab.init(rawValue:)) { model.selectedTab = tab }
        return model
    }

    @MainActor
    private static func makeReminderModel(store: LedgerStore, defaults: UserDefaults) -> AppModel {
        let mode = defaults.string(forKey: "cushnReminders")
        let model: AppModel
        if mode == "live" {
            model = makeLiveModel(store: store, defaults: nil, inboxURL: nil)
        } else {
            let status: ReminderAuthorization = switch mode {
            case "prompt": .notDetermined
            case "allowed": .allowed
            case "denied": .denied
            default: .unknown
            }
            model = AppModel(store: store, reminders: ReminderCenter(store: store, client: InertNotificationClient(status: status), defaults: nil, inboxURL: nil))
        }
        if defaults.object(forKey: "cushnReminderHour") != nil {
            model.reminders.update {
                $0.hour = defaults.integer(forKey: "cushnReminderHour")
                $0.minute = defaults.integer(forKey: "cushnReminderMinute")
            }
        }
        if defaults.integer(forKey: "cushnInboxDays") > 0 {
            model.reminders.debugBackdateLastLook(days: defaults.integer(forKey: "cushnInboxDays"))
            model.reminders.refreshInbox()
        }
        return model
    }

    private static var overridesModel: Bool {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: "cushnNow") != nil || defaults.string(forKey: "cushnDemo") != nil
            || defaults.string(forKey: "cushnStorePath") != nil || defaults.bool(forKey: "cushnInMemory")
            || defaults.string(forKey: "cushnTab") != nil
    }

    @MainActor
    static func experience(for model: AppModel, fallbackTheme: CushnBrandTheme) -> LaunchExperience? {
        let defaults = UserDefaults.standard
        let splash = defaults.string(forKey: "cushnSplash")
        let themeOverride = defaults.string(forKey: "cushnTheme").flatMap(CushnBrandTheme.init(rawValue:))
        if defaults.bool(forKey: "cushnResetFirstUse") { model.firstUse.reset() }

        let usesRealRouting = defaults.string(forKey: "cushnFirstUse") == "auto"
        guard overridesModel || usesRealRouting || splash != nil || themeOverride != nil else { return nil }
        let theme = themeOverride ?? fallbackTheme

        if usesRealRouting {
            let onboarding = model.firstUse.resolveOnboarding(hasPayments: !model.store.ledger.payments.isEmpty)
            return LaunchExperience(theme: theme, showsSplash: splash != nil, holdsSplash: splash == "hold", showsOnboarding: onboarding)
        }
        model.firstUse.hintsEnabled = defaults.bool(forKey: "cushnHints")
        return LaunchExperience(theme: theme, showsSplash: splash != nil, holdsSplash: splash == "hold",
                                showsOnboarding: defaults.bool(forKey: "cushnOnboarding"))
    }

    private static func fixedClock(from text: String) -> FixedClock? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let day = CalendarDay(year: parts[0], month: parts[1], day: parts[2])
        return FixedClock(now: day.date(in: .autoupdatingCurrent))
    }
}

/// Synthetic demo content for screenshots. Debug builds only; never seeded for real users.
enum DemoData {
    @MainActor
    static func load(_ kind: String, into store: LedgerStore) throws {
        let month = store.clock.currentMonth
        switch kind {
        case "standard": try standard(month, store)
        case "large": try large(month, store)
        case "brands": try brands(month, store)
        case "single": try _ = store.add(sample("Netflix", 2_199, 28, .subscriptions, "USD"), month: month)
        case "mixed": try mixed(month, store)
        case "busy":
            // One, two and three or more payments on different days, in a mix of statuses.
            let bill = try store.add(sample("Rent", 185_000, 3, .housing, "USD"), month: month)
            let paid = try store.add(sample("Netflix", 1_799, 10, .subscriptions, "USD"), month: month)
            try store.add(sample("Spotify", 1_199, 10, .subscriptions, "USD"), month: month)
            for (name, minor) in [("Amex Platinum", 24_850), ("Capital One", 38_200), ("Discover", 9_100), ("Citi", 4_000)] {
                try store.add(sample(name, Int64(minor), 21, .creditCards, "USD"), month: month)
            }
            try store.setStatus(.paid, id: bill, month: month)
            try store.setStatus(.paid, id: paid, month: month)
        case "appstore": try appStore(month, store)
        case "owner":
            // The owner's three-payment example: a new list with a card repayment and two subscriptions.
            let card = try store.add(sample("Amex Platinum", 100_000, 5, .creditCards, "USD"), month: month)
            try store.add(sample("Netflix", 2_199, 28, .subscriptions, "USD"), month: month)
            try store.add(sample("ChatGPT", 1_999, 24, .subscriptions, "USD"), month: month)
            try store.setStatus(.paid, id: card, month: month)
        case "compare":
            try standard(month, store)
            try _ = store.add(sample("Planet Fitness", 2_499, 9, .subscriptions, "USD"), month: month)
        default: break
        }
    }

    private static func sample(_ name: String, _ minor: Int64, _ day: Int, _ category: SeedCategory, _ code: String) -> PaymentDraft {
        PaymentDraft(name: name, amount: Money(minorUnits: minor, currencyCode: code), dueDay: DueDay(day)!, categoryID: category.id)
    }

    /// The App Store and website screens, with real company logos by the owner's decision.
    /// Last month is fully marked, so the comparison has real data and no review note shows. Meant for the 15th.
    @MainActor
    private static func appStore(_ month: YearMonth, _ store: LedgerStore) throws {
        let previous = month.previous
        let rows: [(String, Int64, Int, SeedCategory, PaymentStatus)] = [
        ("American Express", 64_250, 21, .creditCards, .unconfirmed),
        ("Chase", 12_800, 8, .creditCards, .paid),
        ("Rent", 165_000, 1, .housing, .paid),
        ("Electric", 8_640, 12, .utilities, .paid),
        ("Water", 4_210, 17, .utilities, .unconfirmed),
        ("Xfinity", 6_500, 18, .utilities, .unconfirmed),
        ("Verizon", 5_500, 15, .utilities, .unconfirmed),
        ("GEICO", 11_800, 21, .insurance, .unconfirmed),
        ("State Farm", 1_900, 21, .insurance, .unconfirmed),
        ("Spotify", 1_199, 10, .subscriptions, .paid),
        ("Netflix", 1_799, 28, .subscriptions, .skipped),
        ("ChatGPT", 1_999, 18, .subscriptions, .unconfirmed),
        ("Piano lessons", 12_000, 5, .other, .paid),
        ("Fidelity", 25_000, 2, .investments, .paid),
        ]
        for (name, minor, day, category, status) in rows {
            // Piano lessons starts this month, so the two months differ and the comparison has something to say.
            let starts = name == "Piano lessons" ? month : previous
            let id = try store.add(sample(name, minor, day, category, "USD"), month: starts)
            if starts == previous { try store.setStatus(.paid, id: id, month: previous) }
            if status != .unconfirmed { try store.setStatus(status, id: id, month: month) }
        }
    }

    /// Two currencies and a very large amount, for Overview's edge cases.
    @MainActor
    private static func mixed(_ month: YearMonth, _ store: LedgerStore) throws {
        let rent = try store.add(sample("Rent", 185_000, 1, .housing, "USD"), month: month)
        try store.add(sample("Netflix", 1_799, 12, .subscriptions, "USD"), month: month)
        try store.add(sample("Holiday flat", 123_456_789, 20, .other, "EUR"), month: month)
        try store.add(sample("Spotify", 999, 20, .subscriptions, "EUR"), month: month)
        try store.setStatus(.paid, id: rent, month: month)
    }

    /// One row per brand, for inspecting the icon set.
    @MainActor
    private static func brands(_ month: YearMonth, _ store: LedgerStore) throws {
        for (index, brand) in BrandCatalog.all.enumerated() {
            try _ = store.add(PaymentDraft(name: brand.name, amount: Money(minorUnits: 1_000, currencyCode: "USD"),
                                           dueDay: DueDay(index % 28 + 1)!, categoryID: brand.category.id), month: month)
        }
    }

    @MainActor
    private static func standard(_ month: YearMonth, _ store: LedgerStore) throws {
        let previous = month.previous
        let code = "USD"
        func add(_ name: String, _ minor: Int64, _ day: Int, _ category: SeedCategory) throws -> UUID {
            try store.add(PaymentDraft(name: name, amount: Money(minorUnits: minor, currencyCode: code),
                                       dueDay: DueDay(day)!, categoryID: category.id), month: previous)
        }
        let amex = try add("Amex Platinum", 124_850, 5, .creditCards)
        _ = try add("Capital One", 38_200, 21, .creditCards)
        let rent = try add("Rent", 185_000, 1, .housing)
        let electric = try add("Electric", 8_640, 12, .utilities)
        _ = try add("Internet", 6_500, 18, .utilities)
        let netflix = try add("Netflix", 1_799, 28, .subscriptions)
        _ = try add("Spotify", 1_199, 15, .subscriptions)
        _ = try add("Piano lessons", 12_000, 31, .other)
        _ = try add("Index fund", 50_000, 2, .investments)

        for id in [amex, rent, electric, netflix] { try store.setStatus(.paid, id: id, month: previous) }
        try store.setStatus(.paid, id: rent, month: month)
        try store.setStatus(.paid, id: amex, month: month)
        try store.setStatus(.skipped, id: netflix, month: month)
    }

    @MainActor
    private static func large(_ month: YearMonth, _ store: LedgerStore) throws {
        let categories: [SeedCategory] = [.creditCards, .subscriptions, .housing, .utilities, .insurance, .other]
        let brands = BrandCatalog.all.filter { $0.icon != nil }
        for index in 0..<150 {
            let name: String
            if index == 3 {
                name = "An extremely long payment name that keeps going to test truncation in the row layout"
            } else if index % 3 == 0 {
                name = brands[index % brands.count].name
            } else {
                name = "Payment \(index + 1)"
            }
            let id = try store.add(PaymentDraft(name: name, amount: Money(minorUnits: Int64(index + 1) * 1_234, currencyCode: "USD"),
                                                dueDay: DueDay(index % 31 + 1)!, categoryID: categories[index % categories.count].id), month: month)
            if index % 4 == 0 { try store.setStatus(.paid, id: id, month: month) }
        }
    }
}
#endif
