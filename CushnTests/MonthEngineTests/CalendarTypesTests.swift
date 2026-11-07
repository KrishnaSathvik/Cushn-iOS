import Foundation
import Testing
@testable import Cushn

@Suite struct YearMonthTests {
    @Test func rejectsInvalidMonth() {
        #expect(YearMonth(year: 2026, month: 0) == nil)
        #expect(YearMonth(year: 2026, month: 13) == nil)
    }
    @Test func crossesYearBoundaries() {
        #expect(ym(2026, 12).next == ym(2027, 1))
        #expect(ym(2027, 1).previous == ym(2026, 12))
        #expect(ym(2026, 11).adding(months: 14) == ym(2028, 1))
        #expect(ym(2026, 2).adding(months: -3) == ym(2025, 11))
    }
    @Test func ordersChronologicallyAcrossYears() {
        #expect(ym(2026, 12) < ym(2027, 1))
        #expect(ym(2026, 2) < ym(2026, 11))
    }
    @Test func ordinalRoundTrips() {
        #expect(YearMonth(ordinal: ym(2026, 12).ordinal) == ym(2026, 12))
        #expect(YearMonth(ordinal: ym(2027, 1).ordinal) == ym(2027, 1))
    }
    @Test func knowsLeapYearLengths() {
        #expect(ym(2026, 2).dayCount == 28)
        #expect(ym(2028, 2).dayCount == 29)
        #expect(ym(1900, 2).dayCount == 28)
        #expect(ym(2000, 2).dayCount == 29)
        #expect(ym(2026, 4).dayCount == 30)
        #expect(ym(2026, 12).dayCount == 31)
    }
}

@Suite struct DueDayTests {
    @Test func rejectsOutOfRange() {
        #expect(DueDay(0) == nil)
        #expect(DueDay(32) == nil)
        #expect(DueDay(1) != nil)
        #expect(DueDay(31) != nil)
    }
    @Test func clampsToShortMonthsAndKeepsNominalDay() {
        let d = DueDay(31)!
        #expect(d.resolved(in: ym(2026, 2)) == CalendarDay(year: 2026, month: 2, day: 28))
        #expect(d.resolved(in: ym(2028, 2)) == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(d.resolved(in: ym(2026, 3)) == CalendarDay(year: 2026, month: 3, day: 31))
        #expect(d.resolved(in: ym(2026, 4)) == CalendarDay(year: 2026, month: 4, day: 30))
        #expect(d.value == 31)
    }
}

@Suite struct CalendarDayTimeZoneTests {
    /// 2026-11-15 02:00 UTC is the 15th in London but still the 14th in Los Angeles.
    let instant = Date(timeIntervalSince1970: 1_794_708_000)

    @Test func todayFollowsLocalCalendarDay() {
        let london = CalendarDay(date: instant, timeZone: TimeZone(identifier: "Europe/London")!)
        let la = CalendarDay(date: instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(london == CalendarDay(year: 2026, month: 11, day: 15))
        #expect(la == CalendarDay(year: 2026, month: 11, day: 14))
    }
    @Test func dueDayIsTheSameInEveryTimeZone() {
        // Due days are date-only: no Date conversion takes part in resolving them.
        #expect(DueDay(15)!.resolved(in: ym(2026, 11)) == CalendarDay(year: 2026, month: 11, day: 15))
    }
    @Test func localDateSurvivesDSTTransitionDays() {
        // 2026-03-08 and 2026-11-01 are US DST changes; 02:30 doesn't exist on the first.
        let ny = TimeZone(identifier: "America/New_York")!
        for day in [CalendarDay(year: 2026, month: 3, day: 8), CalendarDay(year: 2026, month: 11, day: 1)] {
            #expect(CalendarDay(date: day.date(in: ny), timeZone: ny) == day)
        }
    }
    @Test func worksWhenDeviceCalendarIsNotGregorian() {
        // CalendarDay always reads Gregorian components, whatever the user's locale calendar is.
        let utc = TimeZone(identifier: "UTC")!
        #expect(CalendarDay(date: instant, timeZone: utc).year == 2026)
    }
}
