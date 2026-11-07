import Foundation
import Testing
@testable import Cushn

private let utc = TimeZone(identifier: "UTC")!
private let locale = Locale(identifier: "en_US")

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, in zone: TimeZone = utc) -> Date {
    Calendar.gregorian(in: zone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite struct ReminderPlannerTests {
    private func plan(_ h: Harness, now: Date, _ preferences: ReminderPreferences = .init(), capacity: Int = 60) -> [PlannedReminder] {
        ReminderPlanner.upcoming(ledger: h.ledger, now: now, timeZone: utc, preferences: preferences, capacity: capacity)
    }

    @Test func threeDaysBeforeAndDueDateAtTheChosenTime() throws {
        var h = Harness()
        let id = try h.add("Netflix", 3_000, day: 28, in: ym(2026, 11))
        let november = plan(h, now: date(2026, 11, 1)).filter { $0.paymentID == id && $0.month == ym(2026, 11) }
        #expect(november.map(\.kind) == [.threeDaysBefore, .dueToday])
        #expect(november[0].fireDay == CalendarDay(year: 2026, month: 11, day: 25))
        #expect(november[1].fireDay == CalendarDay(year: 2026, month: 11, day: 28))
        #expect(november[0].fireDate == date(2026, 11, 25, 9))
        #expect(november[0].title == "Netflix is due in 3 days")
        #expect(november[0].body(locale: locale, timeZone: utc) == "Your $30.00 Netflix payment is scheduled for November 28.")
        #expect(november[1].title == "Netflix is due today")
        #expect(november[1].body(locale: locale, timeZone: utc) == "Your $30.00 payment is scheduled for today. Open Cushn to check its status.")
    }

    @Test func wordingNeverClaimsAnOutcome() throws {
        var h = Harness()
        try h.add("Rent", 100, day: 20, in: ym(2026, 11))
        for reminder in plan(h, now: date(2026, 11, 1)) {
            let text = (reminder.title + " " + reminder.body(locale: locale, timeZone: utc)).lowercased()
            for word in ["unpaid", "missed", "overdue", "completed", " paid"] { #expect(!text.contains(word)) }
        }
    }

    @Test func februaryUsesTheEnginesClampedDate() throws {
        var h = Harness()
        try h.add("Card", 100, day: 31, in: ym(2026, 11))
        let plain = plan(h, now: date(2027, 2, 1)).filter { $0.month == ym(2027, 2) }
        #expect(plain.map(\.dueDate) == [CalendarDay(year: 2027, month: 2, day: 28), CalendarDay(year: 2027, month: 2, day: 28)])
        #expect(plain[0].fireDay == CalendarDay(year: 2027, month: 2, day: 25))
        let leap = plan(h, now: date(2028, 2, 1)).first { $0.month == ym(2028, 2) }
        #expect(leap?.dueDate == CalendarDay(year: 2028, month: 2, day: 29))
    }

    @Test func threeDayReminderCrossesMonthAndYear() throws {
        var h = Harness()
        try h.add("Rent", 100, day: 1, in: ym(2026, 11))
        let january = plan(h, now: date(2026, 12, 2)).first { $0.month == ym(2027, 1) }
        #expect(january?.fireDay == CalendarDay(year: 2026, month: 12, day: 29))
        let march = plan(h, now: date(2027, 2, 2)).first { $0.month == ym(2027, 3) }
        #expect(march?.fireDay == CalendarDay(year: 2027, month: 2, day: 26))
    }

    @Test func paidAndSkippedGetNoRemindersForThatMonthOnly() throws {
        var h = Harness()
        let paid = try h.add("Paid one", 100, day: 20, in: ym(2026, 11))
        let skipped = try h.add("Skipped one", 100, day: 21, in: ym(2026, 11))
        try h.set(.paid, paid, in: ym(2026, 11))
        try h.set(.skipped, skipped, in: ym(2026, 11))
        let reminders = plan(h, now: date(2026, 11, 1))
        #expect(!reminders.contains { $0.month == ym(2026, 11) })
        #expect(reminders.contains { $0.paymentID == paid && $0.month == ym(2026, 12) })
        #expect(reminders.contains { $0.paymentID == skipped && $0.month == ym(2026, 12) })
    }

    @Test func editsApplyFromTheirMonthAndRemovalsStopReminders() throws {
        var h = Harness()
        let id = try h.add("Gym", 1_000, day: 10, in: ym(2026, 11))
        // Out of order: edit January first, then look at earlier months.
        try h.edit(id, in: ym(2027, 1)) { $0.dueDay = DueDay(20)!; $0.name = "New Gym" }
        let before = plan(h, now: date(2026, 11, 1))
        #expect(before.first { $0.month == ym(2026, 12) }?.name == "Gym")
        #expect(before.first { $0.month == ym(2026, 12) }?.dueDate.day == 10)
        #expect(before.first { $0.month == ym(2027, 1) }?.name == "New Gym")
        #expect(before.first { $0.month == ym(2027, 1) }?.dueDate.day == 20)

        try h.remove(id, from: ym(2026, 12))
        let after = plan(h, now: date(2026, 11, 1))
        #expect(after.contains { $0.month == ym(2026, 11) })
        #expect(!after.contains { $0.month >= ym(2026, 12) })
    }

    @Test func aMonthBeforeThePaymentExistedGetsNothing() throws {
        var h = Harness()
        try h.add("New", 100, day: 15, in: ym(2026, 12))
        #expect(!plan(h, now: date(2026, 11, 1)).contains { $0.month == ym(2026, 11) })
    }

    @Test func pastMomentsAreNotScheduled() throws {
        var h = Harness()
        try h.add("Gym", 100, day: 10, in: ym(2026, 11))
        let reminders = plan(h, now: date(2026, 11, 10, 9, 0)).filter { $0.month == ym(2026, 11) }
        #expect(reminders.isEmpty)
        #expect(plan(h, now: date(2026, 11, 10, 8, 59)).first { $0.month == ym(2026, 11) }?.kind == .dueToday)
    }

    @Test func capacityKeepsTheNearestInOrder() throws {
        var h = Harness()
        for day in 1...28 { try h.add("P\(day)", 100, day: day, in: ym(2026, 11)) }
        let reminders = plan(h, now: date(2026, 11, 1, 10))
        #expect(reminders.count == ReminderPlanner.capacity)
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
        #expect(Set(reminders.map(\.id)).count == reminders.count)
        #expect(reminders.first?.fireDate == date(2026, 11, 2, 9))
    }

    @Test func preferencesControlKindsAndTime() throws {
        var h = Harness()
        try h.add("Gym", 100, day: 20, in: ym(2026, 11))
        var preferences = ReminderPreferences()
        preferences.threeDaysBefore = false
        preferences.hour = 18
        preferences.minute = 30
        let reminders = plan(h, now: date(2026, 11, 1), preferences).filter { $0.month == ym(2026, 11) }
        #expect(reminders.map(\.kind) == [.dueToday])
        #expect(reminders.first?.fireDate == date(2026, 11, 20, 18, 30))
        preferences.isEnabled = false
        #expect(plan(h, now: date(2026, 11, 1), preferences).isEmpty)
    }

    @Test func aDaylightSavingDayKeepsTheLocalTime() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        var h = Harness()
        try h.add("Gym", 100, day: 1, in: ym(2026, 11))
        // Clocks change on November 1, 2026 in New York.
        let reminder = ReminderPlanner.reminders(in: ym(2026, 11), ledger: h.ledger, preferences: .init(), timeZone: newYork)
            .first { $0.kind == .dueToday }
        #expect(reminder?.fireDay == CalendarDay(year: 2026, month: 11, day: 1))
        #expect(reminder?.hour == 9)
        #expect(reminder?.fireDate == date(2026, 11, 1, 9, 0, in: newYork))
    }
}

@MainActor
private final class RecordingClient: NotificationClient {
    var status = ReminderAuthorization.allowed
    var pending: [String: ReminderRequest] = [:]
    var permissionRequests = 0
    var answer = ReminderAuthorization.allowed

    func authorization() async -> ReminderAuthorization { status }
    func requestAuthorization() async -> Bool {
        permissionRequests += 1
        status = answer
        return answer == .allowed
    }
    func pendingIdentifiers() async -> [String] { Array(pending.keys) }
    func add(_ request: ReminderRequest) async { pending[request.id] = request }
    func remove(identifiers: [String]) { for id in identifiers { pending[id] = nil } }
}

private final class MovingClock: AppClock, @unchecked Sendable {
    var now: Date
    let timeZone = utc
    init(_ now: Date) { self.now = now }
}

@MainActor
private struct Rig {
    let clock: MovingClock
    let client = RecordingClient()
    let store: LedgerStore
    let center: ReminderCenter
    let model: AppModel
    let url: URL

    init(now: Date = date(2026, 11, 1, 8)) throws {
        clock = MovingClock(now)
        store = try LedgerStore(repository: InMemoryLedgerRepository(), clock: clock)
        url = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString).json")
        center = ReminderCenter(store: store, client: client, defaults: nil, inboxURL: url)
        model = AppModel(store: store, firstUse: FirstUseState(defaults: UserDefaults(suiteName: UUID().uuidString)!), reminders: center)
    }

    func add(_ name: String, day: Int, month: YearMonth = ym(2026, 11)) throws -> UUID {
        try store.add(draft(name, usd(3_000), day: day), month: month)
    }
}

@MainActor @Suite struct ReminderCenterTests {
    @Test func schedulesAndKeepsNothingDoubledAcrossPasses() async throws {
        let rig = try Rig()
        _ = try rig.add("Netflix", day: 28)
        await rig.center.reconcileNow()
        let first = rig.client.pending.count
        #expect(first > 0)
        await rig.center.reconcileNow()
        await rig.center.reconcileNow()
        #expect(rig.client.pending.count == first)
    }

    @Test func markingPaidOrSkippedCancelsThatMonthsReminders() async throws {
        let rig = try Rig()
        let id = try rig.add("Netflix", day: 28)
        let other = try rig.add("Spotify", day: 20)
        await rig.center.reconcileNow()
        #expect(rig.client.pending.values.contains { $0.paymentID == id && $0.month == ym(2026, 11) })

        try rig.store.setStatus(.paid, id: id, month: ym(2026, 11))
        try rig.store.setStatus(.skipped, id: other, month: ym(2026, 11))
        await rig.center.reconcileNow()
        #expect(!rig.client.pending.values.contains { $0.month == ym(2026, 11) })
        #expect(rig.client.pending.values.contains { $0.paymentID == id && $0.month == ym(2026, 12) })

        // Undo brings them back.
        try rig.store.setStatus(.unconfirmed, id: id, month: ym(2026, 11))
        await rig.center.reconcileNow()
        #expect(rig.client.pending.values.contains { $0.paymentID == id && $0.month == ym(2026, 11) })
    }

    @Test func editsReplaceAndRemovalsCancel() async throws {
        let rig = try Rig()
        let id = try rig.add("Netflix", day: 28)
        await rig.center.reconcileNow()
        try rig.store.edit(id: id, draft("Netflix Family", usd(4_500), day: 28), month: ym(2026, 11))
        await rig.center.reconcileNow()
        let edited = rig.client.pending.values.filter { $0.month == ym(2026, 11) && $0.paymentID == id }
        #expect(edited.count == 2)
        #expect(edited.allSatisfy { $0.title.hasPrefix("Netflix Family") })
        #expect(edited.contains { $0.body.contains("$45.00") })

        try rig.store.remove(id: id, month: ym(2026, 11))
        await rig.center.reconcileNow()
        #expect(rig.client.pending.isEmpty)
    }

    @Test func leavesOtherNotificationsAlone() async throws {
        let rig = try Rig()
        rig.client.pending["someone.else"] = ReminderRequest(id: "someone.else", title: "", body: "", fireDay: CalendarDay(year: 2026, month: 12, day: 1),
                                                             hour: 9, minute: 0, paymentID: UUID(), month: ym(2026, 12))
        await rig.center.reconcileNow()
        #expect(rig.client.pending["someone.else"] != nil)
    }

    @Test func deniedPermissionSchedulesNothingAndKeepsTheInboxWorking() async throws {
        let rig = try Rig()
        rig.client.status = .denied
        _ = try rig.add("Netflix", day: 2)
        await rig.center.reconcileNow()
        #expect(rig.client.pending.isEmpty)
        #expect(rig.center.authorization == .denied)
        #expect(!rig.center.offersPermissionPrompt)

        rig.clock.now = date(2026, 11, 2, 10)
        await rig.center.reconcileNow()
        #expect(rig.center.entries.map(\.name) == ["Netflix"])
    }

    @Test func permissionIsAskedOnlyInContextAndOnlyOnce() async throws {
        let rig = try Rig()
        rig.client.status = .notDetermined
        rig.client.answer = .denied
        await rig.center.reconcileNow()
        #expect(rig.client.permissionRequests == 0)
        #expect(!rig.center.offersPermissionPrompt, "Nothing to remind about yet")

        _ = try rig.add("Netflix", day: 28)
        #expect(rig.center.offersPermissionPrompt)
        #expect(rig.client.permissionRequests == 0, "Adding a payment offers but never asks by itself")

        await rig.center.requestPermission()
        await rig.center.requestPermission()
        #expect(rig.client.permissionRequests == 1)
        #expect(!rig.center.offersPermissionPrompt)
    }

    @Test func aDismissedOfferStaysGone() async throws {
        let rig = try Rig()
        rig.client.status = .notDetermined
        _ = try rig.add("Netflix", day: 28)
        await rig.center.reconcileNow()
        rig.center.dismissPrompt()
        #expect(!rig.center.offersPermissionPrompt)
        #expect(rig.client.permissionRequests == 0)
    }

    @Test func turningRemindersOffCancelsEverything() async throws {
        let rig = try Rig()
        _ = try rig.add("Netflix", day: 28)
        await rig.center.reconcileNow()
        rig.center.update { $0.isEnabled = false }
        await rig.center.reconcileNow()
        #expect(rig.client.pending.isEmpty)
    }

    // MARK: Inbox

    @Test func theFirstLookNeverFloodsTheInbox() async throws {
        let rig = try Rig(now: date(2026, 11, 20))
        _ = try rig.add("Old", day: 5)
        await rig.center.reconcileNow()
        #expect(rig.center.entries.isEmpty)
    }

    @Test func eachPaymentAndMonthKeepsOneLineNoMatterHowOftenTheAppOpens() async throws {
        let rig = try Rig()
        _ = try rig.add("Netflix", day: 28)
        await rig.center.reconcileNow()
        rig.clock.now = date(2026, 11, 25, 10)
        await rig.center.reconcileNow()
        await rig.center.reconcileNow()
        #expect(rig.center.entries.map(\.kind) == [.threeDaysBefore])
        #expect(rig.center.unreadCount == 1)
        let first = try require2(rig.center.entries.first?.id)
        rig.center.markRead(first)

        // The due-date reminder replaces the earlier line and counts as new.
        rig.clock.now = date(2026, 11, 28, 10)
        await rig.center.reconcileNow()
        #expect(rig.center.entries.map(\.kind) == [.dueToday])
        #expect(rig.center.unreadCount == 1)

        // Next month is its own line.
        rig.clock.now = date(2026, 12, 25, 10)
        await rig.center.reconcileNow()
        #expect(rig.center.entries.map(\.month) == [ym(2026, 12), ym(2026, 11)])
    }

    @Test func aLongAbsenceStillGivesOneLinePerPaymentAndMonth() async throws {
        let rig = try Rig()
        _ = try rig.add("Netflix", day: 28)
        await rig.center.reconcileNow()
        rig.clock.now = date(2026, 11, 30, 10)
        await rig.center.reconcileNow()
        #expect(rig.center.entries.map(\.kind) == [.dueToday])
    }

    @Test func paidBeforeTheMomentMeansNoEntry() async throws {
        let rig = try Rig()
        let id = try rig.add("Netflix", day: 28)
        await rig.center.reconcileNow()
        try rig.store.setStatus(.paid, id: id, month: ym(2026, 11))
        rig.clock.now = date(2026, 11, 28, 10)
        await rig.center.reconcileNow()
        #expect(rig.center.entries.isEmpty)
    }

    @Test func anEditCantInventAMomentInThePast() async throws {
        let rig = try Rig()
        let id = try rig.add("Netflix", day: 28)
        rig.clock.now = date(2026, 11, 15, 10)
        await rig.center.reconcileNow()
        try rig.store.edit(id: id, draft("Netflix", usd(3_000), day: 16), month: ym(2026, 11))
        await rig.center.reconcileNow()
        #expect(rig.center.entries.isEmpty)
    }

    @Test func readDismissAndMarkAllLeavePaymentsUntouched() async throws {
        let rig = try Rig()
        let a = try rig.add("Netflix", day: 28)
        _ = try rig.add("Spotify", day: 28)
        await rig.center.reconcileNow()
        rig.clock.now = date(2026, 11, 25, 10)
        await rig.center.reconcileNow()
        #expect(rig.center.unreadCount == 2)
        let before = rig.store.ledger

        let netflix = try require2(rig.center.entries.first { $0.name == "Netflix" })
        rig.center.markRead(netflix.id)
        #expect(rig.center.unreadCount == 1)
        rig.center.markAllRead()
        #expect(rig.center.unreadCount == 0)
        #expect(rig.center.entries.count == 2)

        rig.center.dismiss(netflix.id)
        #expect(rig.center.entries.map(\.name) == ["Spotify"])
        await rig.center.reconcileNow()
        #expect(rig.center.entries.map(\.name) == ["Spotify"], "A dismissed item doesn't come back")
        #expect(rig.store.ledger == before)
        #expect(rig.store.view(for: ym(2026, 11)).row(a)?.status == .unconfirmed)
    }

    @Test func theInboxSurvivesARelaunch() async throws {
        let rig = try Rig()
        _ = try rig.add("Netflix", day: 28)
        await rig.center.reconcileNow()
        rig.clock.now = date(2026, 11, 25, 10)
        await rig.center.reconcileNow()
        let id = try require2(rig.center.entries.first?.id)
        rig.center.markRead(id)

        let again = ReminderCenter(store: rig.store, client: rig.client, defaults: nil, inboxURL: rig.url)
        #expect(again.entries.map(\.id) == [id])
        #expect(again.unreadCount == 0)
        await again.reconcileNow()
        #expect(again.entries.count == 1)
    }

    @Test func aDamagedInboxFileStartsEmptyAndLeavesPaymentsAlone() async throws {
        let rig = try Rig()
        _ = try rig.add("Netflix", day: 28)
        try Data("not json".utf8).write(to: rig.url)
        let again = ReminderCenter(store: rig.store, client: rig.client, defaults: nil, inboxURL: rig.url)
        #expect(again.entries.isEmpty)
        #expect(rig.store.view(for: ym(2026, 11)).rows.count == 1)
    }

    // MARK: Navigation

    @Test func openingGoesToTheEntrysOwnMonth() async throws {
        let rig = try Rig()
        let id = try rig.add("Netflix", day: 28)
        rig.model.selectedTab = .calendar
        rig.model.selectedMonth = ym(2027, 3)
        rig.model.openPayment(id, month: ym(2026, 11))
        #expect(rig.model.selectedMonth == ym(2026, 11))
        #expect(rig.model.selectedTab == .home)
        #expect(rig.model.pendingPaymentRoute == DetailRoute(paymentID: id, month: ym(2026, 11)))
    }

    @Test func aStaleEntryNeverOpensAPayment() async throws {
        let rig = try Rig()
        let id = try rig.add("Netflix", day: 28)
        try rig.store.remove(id: id, month: ym(2026, 11))
        rig.model.openPayment(id, month: ym(2026, 11))
        #expect(rig.model.pendingPaymentRoute == nil)
        // A month before the payment existed has no row either.
        let later = try rig.add("Later", day: 5, month: ym(2027, 1))
        rig.model.openPayment(later, month: ym(2026, 12))
        #expect(rig.model.pendingPaymentRoute == nil)
    }

    @Test func sampleModelsNeverReachIOSOrSaveAnything() async throws {
        let store = try LedgerStore(repository: InMemoryLedgerRepository(), clock: MovingClock(date(2026, 11, 1)))
        let model = AppModel(store: store, firstUse: FirstUseState(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        _ = try store.add(draft("Netflix", usd(100), day: 28), month: ym(2026, 11))
        await model.reminders.reconcileNow()
        #expect(model.reminders.authorization == .unknown)
        #expect(!model.reminders.offersPermissionPrompt)
    }
}

@Suite struct InboxTextTests {
    private func entry(day: Int) throws -> (InboxEntry, MonthRow) {
        var h = Harness()
        let id = try h.add("Netflix", 3_000, day: day, in: ym(2026, 11))
        let reminder = try require2(ReminderPlanner.reminders(in: ym(2026, 11), ledger: h.ledger, preferences: .init(), timeZone: utc).first)
        return (InboxEntry(reminder: reminder), try require2(h.row(id, ym(2026, 11))))
    }

    @Test func wordingFollowsTodayAndStatus() throws {
        let (item, row) = try entry(day: 20)
        func text(_ day: Int) -> String { InboxText.status(row: row, entry: item, today: CalendarDay(year: 2026, month: 11, day: day), timeZone: utc) }
        #expect(text(17) == "Due in 3 days")
        #expect(text(19) == "Due tomorrow")
        #expect(text(20) == "Due today")
        #expect(text(21).hasPrefix("Was due"))
        let today = CalendarDay(year: 2026, month: 11, day: 21)
        #expect(!InboxText.detail(row: row, entry: item, today: today, timeZone: utc).contains("Nov"), "The status line already has the date")
        #expect(InboxText.detail(row: row, entry: item, today: CalendarDay(year: 2026, month: 11, day: 17), timeZone: utc).contains("Nov"))
        #expect(InboxText.status(row: nil, entry: item, today: CalendarDay(year: 2026, month: 11, day: 1)) == "No longer on your list")
    }
}

@Suite struct ShortMonthNameTests {
    @Test func usesTheAbbreviatedMonth() {
        #expect(DateText.shortMonthName(ym(2026, 9), locale: locale, timeZone: utc) == "Sep")
    }
}
