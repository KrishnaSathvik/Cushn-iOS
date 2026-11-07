import Foundation

/// Example payments for onboarding, run through the real ledger and month engine on throwaway in-memory stores.
/// Nothing here can reach the user's database, and the demonstrations can't drift from how the app behaves.
@MainActor
enum OnboardingSample {
    /// Everything starts on the first of the month, so no sample row reads as past due.
    private static func model(month: YearMonth) throws -> AppModel {
        let clock = FixedClock(now: CalendarDay(year: month.year, month: month.month, day: 1).date(in: .autoupdatingCurrent))
        return AppModel(store: try LedgerStore(repository: InMemoryLedgerRepository(), clock: clock),
                        firstUse: FirstUseState(hintsEnabled: false))
    }

    private static func draft(_ name: String, _ minor: Int64, _ day: Int, _ category: UUID) -> PaymentDraft {
        PaymentDraft(name: name, amount: Money(minorUnits: minor, currencyCode: "USD"), dueDay: DueDay(day)!, categoryID: category)
    }

    /// Page 1: the range of things a list can hold.
    static func checklist(month: YearMonth) throws -> AppModel {
        let model = try model(month: month)
        let store = model.store
        let bills = try store.addCategory(name: "Bills", month: month)
        try store.add(draft("Apple Card", 41_260, 5, SeedCategory.creditCards.id), month: month)
        try store.add(draft("American Express", 24_850, 12, SeedCategory.creditCards.id), month: month)
        try store.add(draft("Netflix", 1_799, 18, SeedCategory.subscriptions.id), month: month)
        try store.add(draft("ChatGPT", 2_000, 24, SeedCategory.subscriptions.id), month: month)
        try store.add(draft("Spotify", 1_199, 15, SeedCategory.subscriptions.id), month: month)
        try store.add(draft("Rent", 185_000, 2, bills), month: month)
        try store.add(draft("Electric", 8_640, 12, bills), month: month)
        try store.add(draft("GEICO", 13_200, 20, bills), month: month)
        return model
    }

    /// Page 2: one payment to play with.
    static func statuses(month: YearMonth) throws -> (model: AppModel, target: UUID) {
        let model = try model(month: month)
        let netflix = try model.store.add(draft("Netflix", 1_799, 18, SeedCategory.subscriptions.id), month: month)
        return (model, netflix)
    }

    /// Page 3: November is marked. December carries the list forward, unmarked, plus a payment added in December.
    static func rollover(month: YearMonth) throws -> AppModel {
        let model = try model(month: month)
        let store = model.store
        let next = month.adding(months: 1)
        let category = SeedCategory.subscriptions.id
        let rent = try store.add(draft("Rent", 185_000, 2, category), month: month)
        let netflix = try store.add(draft("Netflix", 1_799, 18, category), month: month)
        try store.add(draft("Electric", 8_640, 12, category), month: month)
        try store.setStatus(.paid, id: rent, month: month)
        try store.setStatus(.paid, id: netflix, month: month)
        try store.add(draft("Spotify", 1_199, 15, category), month: next)
        return model
    }
}
