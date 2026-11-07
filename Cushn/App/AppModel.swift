import Foundation
import Observation

enum AppTab: String, Hashable { case home, overview, calendar }

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Shared UI state. All tabs read the same selected month.
@Observable @MainActor
final class AppModel {
    let store: LedgerStore
    let firstUse: FirstUseState
    let reminders: ReminderCenter
    var selectedMonth: YearMonth
    var selectedTab: AppTab = .home
    var errorMessage: String?
    /// A payment to open on Home, set by the inbox or a tapped reminder.
    var pendingPaymentRoute: DetailRoute?
    /// Settings opens from the logo on every tab, so it's presented from the root rather than one tab.
    var showingSettings = false
    /// Counts Settings closing, which is when a payment that waited behind it can open.
    private(set) var settingsCloseCount = 0
    private(set) var today: CalendarDay

    /// With no `reminders`, this model never reaches iOS or saves reminder data, which is what sample lists need.
    init(store: LedgerStore, firstUse: FirstUseState = FirstUseState(), reminders: ReminderCenter? = nil) {
        self.store = store
        self.firstUse = firstUse
        let center = reminders ?? ReminderCenter(store: store, client: InertNotificationClient(), defaults: nil, inboxURL: nil)
        self.reminders = center
        store.onCommit = { [weak center] in center?.requestReconcile() }
        today = store.clock.today
        selectedMonth = store.clock.today.yearMonth
    }

    var currentMonth: YearMonth { today.yearMonth }

    var canGoBack: Bool { selectedMonth > .origin }
    var canGoForward: Bool { selectedMonth < .latest }

    func shiftMonth(by delta: Int) {
        selectedMonth = min(max(selectedMonth.adding(months: delta), .origin), .latest)
    }

    /// Call when returning to the foreground or when the day changes. Someone on the current
    /// month follows the rollover; someone browsing another month stays where they are.
    func refreshDate() {
        let newToday = store.clock.today
        guard newToday != today else { return }
        let wasOnCurrentMonth = selectedMonth == today.yearMonth
        today = newToday
        if wasOnCurrentMonth { selectedMonth = newToday.yearMonth }
    }

    /// Goes to a payment in its own month. A payment that isn't in that month opens the month only.
    func openPayment(_ paymentID: UUID, month: YearMonth) {
        selectedMonth = month
        selectedTab = .home
        pendingPaymentRoute = store.view(for: month).row(paymentID) == nil ? nil : DetailRoute(paymentID: paymentID, month: month)
    }

    func settingsDidClose() {
        settingsCloseCount += 1
    }

    /// Runs a store action, surfacing a save failure rather than pretending it worked.
    func attempt(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = "That change couldn't be saved, so nothing was changed. Please try again."
        }
    }

    /// Returns true when the row should open details instead.
    func tapStatusCircle(id: UUID, month: YearMonth) -> Bool {
        var opensDetails = false
        attempt { opensDetails = try store.tapStatusCircle(id: id, month: month) == .openDetails }
        return opensDetails
    }

    // MARK: Settings

    static let defaultCurrencyKey = "defaultCurrency"

    var defaultCurrency: String {
        UserDefaults.standard.string(forKey: Self.defaultCurrencyKey)
            ?? Locale.autoupdatingCurrent.currency?.identifier ?? "USD"
    }
}

enum CurrencyOptions {
    static let common = ["USD", "EUR", "GBP", "INR", "CAD", "AUD", "JPY", "CHF", "CNY", "MXN", "BRL", "SGD", "AED"]

    static func options(including codes: String...) -> [String] {
        var result = codes
        for code in common where !result.contains(code) { result.append(code) }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    static func displayName(_ code: String) -> String {
        Locale.autoupdatingCurrent.localizedString(forCurrencyCode: code) ?? code
    }
}
