import Foundation
import Testing
@testable import Cushn

@Suite struct ReviewServiceTests {
    let oct = ym(2026, 10), nov = ym(2026, 11), dec = ym(2026, 12)
    let today = CalendarDay(year: 2026, month: 11, day: 15)

    func row(_ h: Harness, _ id: UUID, _ m: YearMonth) throws -> MonthRow { try require2(h.row(id, m)) }

    @Test func dueStatesAreDerivedFromDateAndStatus() throws {
        var h = Harness()
        let past = try h.add("Past", 100, day: 3, in: nov)
        let due = try h.add("Today", 100, day: 15, in: nov)
        let later = try h.add("Later", 100, day: 28, in: nov)
        #expect(ReviewService.dueState(of: try row(h, past, nov), today: today) == .pastDue)
        #expect(ReviewService.dueState(of: try row(h, due, nov), today: today) == .dueToday)
        #expect(ReviewService.dueState(of: try row(h, later, nov), today: today) == .upcoming)
        try h.set(.paid, past, in: nov)
        #expect(ReviewService.dueState(of: try row(h, past, nov), today: today) == .resolved)
    }

    @Test func pastDueUnconfirmedTriggersPrompt() throws {
        var h = Harness()
        try h.add("Past", 100, day: 3, in: nov)
        let prompt = try #require(ReviewService.activePrompt(ledger: h.ledger, today: today))
        #expect(prompt.month == nov)
        #expect(prompt.scope == .currentMonth)
        #expect(prompt.count == 1)
    }

    @Test func dueTodayAndUpcomingDoNotTrigger() throws {
        var h = Harness()
        try h.add("Today", 100, day: 15, in: nov)
        try h.add("Later", 100, day: 28, in: nov)
        #expect(ReviewService.activePrompt(ledger: h.ledger, today: today) == nil)
    }

    @Test func paidAndSkippedAreExcluded() throws {
        var h = Harness()
        let a = try h.add("A", 100, day: 3, in: nov)
        let b = try h.add("B", 100, day: 4, in: nov)
        try h.set(.paid, a, in: nov)
        try h.set(.skipped, b, in: nov)
        #expect(ReviewService.activePrompt(ledger: h.ledger, today: today) == nil)
    }

    @Test func previousMonthComesFirstAndOnlyOnePromptShows() throws {
        var h = Harness()
        try h.add("Old", 100, day: 3, in: oct)
        let prompt = try #require(ReviewService.activePrompt(ledger: h.ledger, today: today))
        #expect(prompt.scope == .previousMonth)
        #expect(prompt.month == oct)
        #expect(prompt.count == 1)
        // The same payment is also past due in November; that's the next prompt after dismissal.
        h.ledger.apply([.upsertDismissal(ReviewService.dismissal(of: prompt, now: fixedNow))])
        let next = try #require(ReviewService.activePrompt(ledger: h.ledger, today: today))
        #expect(next.scope == .currentMonth)
    }

    @Test func monthsOlderThanPreviousDoNotPrompt() throws {
        var h = Harness()
        let id = try h.add("Old", 100, day: 3, in: ym(2026, 8))
        try h.remove(id, from: oct)
        #expect(ReviewService.activePrompt(ledger: h.ledger, today: today) == nil)
    }

    @Test func dismissingChangesNoStatusAndHidesPrompt() throws {
        var h = Harness()
        let id = try h.add("Past", 100, day: 3, in: nov)
        let prompt = try #require(ReviewService.activePrompt(ledger: h.ledger, today: today))
        let statusesBefore = h.ledger.statuses
        h.ledger.apply([.upsertDismissal(ReviewService.dismissal(of: prompt, now: fixedNow))])
        #expect(ReviewService.activePrompt(ledger: h.ledger, today: today) == nil)
        #expect(h.ledger.statuses == statusesBefore)
        #expect(h.row(id, nov)?.status == .unconfirmed)
    }

    @Test func dismissedPromptReturnsOnlyWhenCountGrows() throws {
        var h = Harness()
        try h.add("A", 100, day: 3, in: nov)
        let prompt = try #require(ReviewService.activePrompt(ledger: h.ledger, today: today))
        h.ledger.apply([.upsertDismissal(ReviewService.dismissal(of: prompt, now: fixedNow))])
        try h.add("B", 100, day: 4, in: nov)
        #expect(ReviewService.activePrompt(ledger: h.ledger, today: today)?.count == 2)
    }

    @Test func dismissedReviewRemainsReachable() throws {
        var h = Harness()
        try h.add("A", 100, day: 3, in: nov)
        let prompt = try #require(ReviewService.activePrompt(ledger: h.ledger, today: today))
        h.ledger.apply([.upsertDismissal(ReviewService.dismissal(of: prompt, now: fixedNow))])
        #expect(ReviewService.allPrompts(ledger: h.ledger, today: today).map(\.month) == [nov])
    }

    @Test func reviewRowsListPastDueUnconfirmedOnly() throws {
        var h = Harness()
        let a = try h.add("A", 100, day: 3, in: nov)
        let b = try h.add("B", 100, day: 4, in: nov)
        try h.add("C", 100, day: 28, in: nov)
        try h.set(.paid, b, in: nov)
        #expect(ReviewService.rows(month: nov, ledger: h.ledger, today: today).map(\.id) == [a])
    }

    @Test func wholePreviousMonthIsPastDue() throws {
        var h = Harness()
        let a = try h.add("A", 100, day: 31, in: oct)
        let janFirst = CalendarDay(year: 2026, month: 11, day: 1)
        #expect(ReviewService.rows(month: oct, ledger: h.ledger, today: janFirst).map(\.id) == [a])
    }

    @Test func reviewNeverWritesStatuses() throws {
        var h = Harness()
        try h.add("A", 100, day: 3, in: oct)
        let before = h.ledger
        _ = ReviewService.activePrompt(ledger: h.ledger, today: today)
        _ = ReviewService.allPrompts(ledger: h.ledger, today: today)
        _ = ReviewService.rows(month: oct, ledger: h.ledger, today: today)
        #expect(h.ledger == before)
    }
}
