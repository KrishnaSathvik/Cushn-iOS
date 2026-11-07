import Foundation

/// A calendar month in the Gregorian calendar. Never derived from display labels.
struct YearMonth: Hashable, Comparable, Codable, Sendable, Identifiable {
    let year: Int
    let month: Int

    /// Default categories exist from this month, so they are available wherever a user browses.
    static let origin = YearMonth(ordinal: 2000 * 12)
    /// Last month reachable in month navigation.
    static let latest = YearMonth(ordinal: 2100 * 12 + 11)

    init?(year: Int, month: Int) {
        guard (1...12).contains(month) else { return nil }
        self.year = year
        self.month = month
    }

    init(ordinal: Int) {
        year = ordinal / 12
        month = ordinal % 12 + 1
    }

    /// Months since year 0. Sortable, and the persisted representation.
    var ordinal: Int { year * 12 + (month - 1) }
    var id: Int { ordinal }
    var next: YearMonth { adding(months: 1) }
    var previous: YearMonth { adding(months: -1) }

    func adding(months: Int) -> YearMonth { YearMonth(ordinal: ordinal + months) }

    /// Number of days in this month, using Gregorian leap-year rules.
    var dayCount: Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool { lhs.ordinal < rhs.ordinal }
}

/// A date-only local calendar day. Due dates stay as these values so that
/// time zone or DST changes can't shift the day a user intended.
struct CalendarDay: Hashable, Comparable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, timeZone: TimeZone) {
        let parts = Calendar.gregorian(in: timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    var yearMonth: YearMonth { YearMonth(ordinal: year * 12 + (month - 1)) }

    /// Local noon of this day: a safe instant for display formatting, because noon always exists on DST days.
    func date(in timeZone: TimeZone) -> Date {
        Calendar.gregorian(in: timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension Calendar {
    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// The nominal day of the month (1...31). This is persisted, never the clamped day.
struct DueDay: Hashable, Codable, Sendable {
    let value: Int

    init?(_ value: Int) {
        guard (1...31).contains(value) else { return nil }
        self.value = value
    }

    func resolved(in month: YearMonth) -> CalendarDay {
        CalendarDay(year: month.year, month: month.month, day: min(value, month.dayCount))
    }
}

/// Injectable source of "now", so all date behavior can be tested deterministically.
protocol AppClock: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
}

extension AppClock {
    var today: CalendarDay { CalendarDay(date: now, timeZone: timeZone) }
    var currentMonth: YearMonth { today.yearMonth }
}

struct SystemClock: AppClock {
    var now: Date { Date() }
    var timeZone: TimeZone { .autoupdatingCurrent }
}

struct FixedClock: AppClock {
    var now: Date
    var timeZone: TimeZone = .autoupdatingCurrent
}
