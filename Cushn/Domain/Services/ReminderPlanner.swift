import Foundation

enum ReminderKind: String, Codable, CaseIterable, Sendable {
    case threeDaysBefore, dueToday

    var daysBefore: Int { self == .threeDaysBefore ? 3 : 0 }
}

struct ReminderPreferences: Equatable, Sendable {
    /// Off stops phone alerts and new inbox items. iOS permission is separate: without it the inbox still works.
    var isEnabled = true
    var threeDaysBefore = true
    var dueToday = true
    var hour = 9
    var minute = 0

    var kinds: [ReminderKind] {
        guard isEnabled else { return [] }
        return ReminderKind.allCases.filter { $0 == .threeDaysBefore ? threeDaysBefore : dueToday }
    }
}

/// One reminder for one payment in one month. The identifier is stable, so scheduling it again replaces it.
struct PlannedReminder: Identifiable, Equatable, Sendable {
    static let identifierPrefix = "cushn.reminder."

    let paymentID: UUID
    let month: YearMonth
    let kind: ReminderKind
    let name: String
    let amount: Money
    let dueDate: CalendarDay
    /// The local day and time to alert. iOS gets these rather than an instant, so the time stays 9:00 AM wherever
    /// the phone is and across daylight saving changes.
    let fireDay: CalendarDay
    let hour: Int
    let minute: Int
    /// Used only for ordering and for deciding what has passed.
    let fireDate: Date

    var id: String { "\(Self.identifierPrefix)\(paymentID.uuidString).\(month.ordinal).\(kind.rawValue)" }

    var title: String {
        kind == .dueToday ? "\(name) is due today" : "\(name) is due in 3 days"
    }

    /// Says what's scheduled. Never that a payment was made, missed or is unpaid.
    func body(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let amountText = amount.formatted(locale: locale)
        if kind == .dueToday {
            return "Your \(amountText) payment is scheduled for today. Open Cushn to check its status."
        }
        let date = DateText.monthDay(dueDate.date(in: timeZone), locale: locale, timeZone: timeZone, wide: true)
        return "Your \(amountText) \(name) payment is scheduled for \(date)."
    }
}

/// Works out reminders from the monthly engine's own output, so clamped due dates, effective months, removals and
/// statuses all come from one place. Pure and read-only.
enum ReminderPlanner {
    /// iOS keeps 64 pending local notifications per app. This leaves a margin.
    static let capacity = 60
    /// A reminder for a payment due early next month can fall in this one, so planning always looks ahead.
    static let monthsAhead = 13
    /// How far back the inbox reaches after the app hasn't been opened for a long time.
    static let inboxLookbackDays = 45

    static func reminders(in month: YearMonth, ledger: Ledger, preferences: ReminderPreferences, timeZone: TimeZone) -> [PlannedReminder] {
        let kinds = preferences.kinds
        guard !kinds.isEmpty else { return [] }
        let calendar = Calendar.gregorian(in: timeZone)
        return MonthProjector.project(month: month, ledger: ledger).rows
            .filter { $0.status == .unconfirmed }
            .flatMap { row in
                kinds.compactMap { kind -> PlannedReminder? in
                    guard let shifted = calendar.date(byAdding: .day, value: -kind.daysBefore, to: row.dueDate.date(in: timeZone)) else { return nil }
                    let fireDay = CalendarDay(date: shifted, timeZone: timeZone)
                    let parts = DateComponents(year: fireDay.year, month: fireDay.month, day: fireDay.day,
                                               hour: preferences.hour, minute: preferences.minute)
                    guard let fireDate = calendar.date(from: parts) else { return nil }
                    return PlannedReminder(paymentID: row.id, month: month, kind: kind, name: row.name, amount: row.amount,
                                           dueDate: row.dueDate, fireDay: fireDay, hour: preferences.hour,
                                           minute: preferences.minute, fireDate: fireDate)
                }
            }
    }

    /// The nearest future reminders, up to what iOS will hold. Later ones get scheduled as the app is reopened.
    static func upcoming(ledger: Ledger, now: Date, timeZone: TimeZone, preferences: ReminderPreferences,
                         capacity: Int = capacity) -> [PlannedReminder] {
        let current = CalendarDay(date: now, timeZone: timeZone).yearMonth
        let future = (0...monthsAhead).flatMap { offset in
            reminders(in: current.adding(months: offset), ledger: ledger, preferences: preferences, timeZone: timeZone)
        }
        .filter { $0.fireDate > now }
        return Array(sorted(future).prefix(capacity))
    }

    /// Reminder moments that passed since the inbox last looked, for payments still unconfirmed now.
    /// A moment that only "passed" because of an edit isn't after the last look, so it never appears.
    static func occurred(after lastLook: Date, upTo now: Date, ledger: Ledger, timeZone: TimeZone, preferences: ReminderPreferences) -> [PlannedReminder] {
        let lookback = now.addingTimeInterval(-Double(inboxLookbackDays) * 86_400)
        let earliest = max(lastLook, lookback)
        guard earliest < now else { return [] }
        let first = CalendarDay(date: earliest, timeZone: timeZone).yearMonth
        let last = CalendarDay(date: now, timeZone: timeZone).yearMonth.next
        let passed = (first.ordinal...last.ordinal).flatMap { ordinal in
            reminders(in: YearMonth(ordinal: ordinal), ledger: ledger, preferences: preferences, timeZone: timeZone)
        }
        .filter { $0.fireDate > earliest && $0.fireDate <= now }
        return sorted(passed)
    }

    private static func sorted(_ reminders: [PlannedReminder]) -> [PlannedReminder] {
        reminders.sorted { a, b in a.fireDate != b.fireDate ? a.fireDate < b.fireDate : a.id < b.id }
    }
}

/// One line in the in-app inbox, per payment per month. A newer reminder replaces the earlier one and shows as unread
/// again, because wording is worked out when shown and two lines would read the same. It keeps the name and amount from when it was created, so it survives later edits
/// and removals as history. The payment checklist stays the source of truth for status.
struct InboxEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let paymentID: UUID
    let month: YearMonth
    let kind: ReminderKind
    let name: String
    let amount: Money
    let dueDate: CalendarDay
    let occurredAt: Date
    var readAt: Date?

    var isRead: Bool { readAt != nil }

    static func id(paymentID: UUID, month: YearMonth) -> String { "\(paymentID.uuidString).\(month.ordinal)" }

    init(reminder: PlannedReminder) {
        id = Self.id(paymentID: reminder.paymentID, month: reminder.month)
        paymentID = reminder.paymentID
        month = reminder.month
        kind = reminder.kind
        name = reminder.name
        amount = reminder.amount
        dueDate = reminder.dueDate
        occurredAt = reminder.fireDate
    }
}

/// Inbox wording, worked out when shown, so an old item never keeps saying "due in 3 days".
enum InboxText {
    static func status(row: MonthRow?, entry: InboxEntry, today: CalendarDay, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        guard let row else { return "No longer on your list" }
        switch row.status {
        case .paid: return "Marked paid"
        case .skipped: return "Skipped"
        case .unconfirmed: break
        }
        if row.dueDate == today { return "Due today" }
        if row.dueDate < today {
            return "Was due \(DateText.monthDay(row.dueDate.date(in: timeZone), timeZone: timeZone, wide: false))"
        }
        let calendar = Calendar.gregorian(in: timeZone)
        let days = calendar.dateComponents([.day], from: today.date(in: timeZone), to: row.dueDate.date(in: timeZone)).day ?? 0
        return days == 1 ? "Due tomorrow" : "Due in \(days) days"
    }

    /// The amount and due date, leaving out the date when the status line already says it.
    static func detail(row: MonthRow?, entry: InboxEntry, today: CalendarDay, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let amount = entry.amount.formatted()
        let dueDate = row?.dueDate ?? entry.dueDate
        if let row, row.status == .unconfirmed, row.dueDate < today { return amount }
        return "\(amount) · \(DateText.monthDay(dueDate.date(in: timeZone), timeZone: timeZone, wide: false))"
    }
}
