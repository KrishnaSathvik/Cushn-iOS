import Foundation
import Testing
@testable import Cushn

@Suite struct PaymentFormTests {
    let us = Locale(identifier: "en_US")

    func form(name: String = "Netflix", amount: String = "30", day: Int? = 28, currency: String = "USD") -> PaymentForm {
        PaymentForm(name: name, amountText: amount, currencyCode: currency, dueDay: day, categoryID: SeedCategory.other.id)
    }

    @Test func validFormProducesDraft() throws {
        let draft = try form().validated(locale: us).get()
        #expect(draft.name == "Netflix")
        #expect(draft.amount == usd(3000))
        #expect(draft.dueDay.value == 28)
    }
    @Test func requiresAllThreeFields() throws {
        let errors = try #require(form(name: " ", amount: "", day: nil).errors(locale: us))
        #expect(errors.name == "Enter a name")
        #expect(errors.amount == "Enter an amount")
        #expect(errors.dueDay == "Choose a due day")
    }
    @Test func explainsInvalidAmounts() {
        #expect(form(amount: "abc").errors(locale: us)?.amount == "Enter a valid amount")
        #expect(form(amount: "-3").errors(locale: us)?.amount == "Amount can't be negative")
        #expect(form(amount: "1.999").errors(locale: us)?.amount == "Use no more than 2 decimal places")
        #expect(form(amount: "1.5", currency: "JPY").errors(locale: us)?.amount == "JPY doesn't use decimals")
        #expect(form(amount: "99999999999999999999").errors(locale: us)?.amount == "That amount is too large")
    }
    @Test func rejectsOutOfRangeDay() {
        #expect(form(day: 32).errors(locale: us)?.dueDay == "Choose a due day")
    }
    @Test func editFormRoundTripsRow() throws {
        var h = Harness()
        let id = try h.add("Netflix", 123450, day: 31, in: ym(2026, 11))
        let row = try require2(h.row(id, ym(2026, 11)))
        let draft = try PaymentForm(row: row, locale: us).validated(locale: us).get()
        #expect(draft == PaymentDraft(name: "Netflix", amount: usd(123450), dueDay: DueDay(31)!, categoryID: row.categoryID))
    }
}

@Suite struct RowPresentationTests {
    let us = Locale(identifier: "en_US")
    let utc = TimeZone(identifier: "UTC")!
    let today = CalendarDay(year: 2026, month: 11, day: 15)

    func text(day: Int, status: PaymentStatus = .unconfirmed, in month: YearMonth = ym(2026, 11)) throws -> RowPresentation {
        var h = Harness()
        let id = try h.add("Netflix", 3000, day: day, in: month)
        if status != .unconfirmed { try h.set(status, id, in: month) }
        return RowPresentation(row: try require2(h.row(id, month)), today: today, locale: us, timeZone: utc)
    }

    @Test func showsPlainDateForUpcoming() throws {
        #expect(try text(day: 28).dueLine == "Nov 28")
        #expect(try text(day: 28).isPastDue == false)
    }
    @Test func showsDueToday() throws { #expect(try text(day: 15).dueLine == "Due today") }
    @Test func pastDueInCurrentMonthSaysNotMarkedPaidNeverUnpaid() throws {
        let p = try text(day: 3)
        #expect(p.dueLine == "Nov 3 · Not marked paid")
        #expect(p.isPastDue)
    }
    @Test func paidAndSkippedShowOnlyTheDate() throws {
        #expect(try text(day: 3, status: .paid).dueLine == "Nov 3")
        #expect(try text(day: 3, status: .skipped).dueLine == "Nov 3")
    }
    @Test func earlierMonthsStayQuiet() throws {
        let p = try text(day: 3, in: ym(2026, 10))
        #expect(p.dueLine == "Oct 3")
        #expect(p.isPastDue == false)
    }
    @Test func voiceOverReadsNameDueDateAmountAndStatus() throws {
        #expect(try text(day: 28).accessibilityLabel == "Netflix, due November 28, $30.00, unconfirmed")
        #expect(try text(day: 28, status: .paid).accessibilityLabel == "Netflix, due November 28, $30.00, marked paid")
        #expect(try text(day: 28, status: .skipped).accessibilityLabel == "Netflix, due November 28, $30.00, skipped")
    }
    @Test func statusButtonLabelsNameTheAction() throws {
        #expect(try text(day: 28).statusActionLabel == "Mark Netflix paid")
        #expect(try text(day: 28, status: .paid).statusActionLabel == "Undo paid for Netflix")
        #expect(try text(day: 28, status: .skipped).statusActionLabel == "Netflix skipped, show options")
    }
}

@Suite struct CalendarLayoutTests {
    @Test func paddingFollowsFirstWeekday() {
        // November 2026 starts on a Sunday.
        #expect(CalendarLayout.cells(month: ym(2026, 11), firstWeekday: 1).prefix(1) == [CalendarDay(year: 2026, month: 11, day: 1)])
        // With Monday-first weeks that Sunday sits in the seventh column.
        let monday = CalendarLayout.cells(month: ym(2026, 11), firstWeekday: 2)
        #expect(monday.prefix(6).allSatisfy { $0 == nil })
        #expect(monday[6] == CalendarDay(year: 2026, month: 11, day: 1))
    }
    @Test func containsEveryDayOfTheMonth() {
        for (month, count) in [(ym(2026, 2), 28), (ym(2028, 2), 29), (ym(2026, 12), 31)] {
            let days = CalendarLayout.cells(month: month, firstWeekday: 1).compactMap { $0 }
            #expect(days.count == count)
            #expect(days.last?.day == count)
        }
    }
    @Test func clampedDueDatesLandOnLastDayOfFebruary() throws {
        var h = Harness()
        let id = try h.add("Rent", 100, day: 31, in: ym(2027, 1))
        let byDay = CalendarLayout.rowsByDay(h.view(ym(2027, 2)))
        #expect(byDay[CalendarDay(year: 2027, month: 2, day: 28)]?.map(\.id) == [id])
    }
    @Test func marksShowOpenPaymentsFirstAndStopAtThree() throws {
        var h = Harness()
        let month = ym(2026, 11)
        let ids = try (1...5).map { try h.add("Payment \($0)", 100, day: 10, in: month) }
        try h.set(.paid, ids[0], in: month)
        try h.set(.paid, ids[1], in: month)
        try h.set(.skipped, ids[2], in: month)
        #expect(CalendarLayout.marks(for: h.view(month).rows) == [.unconfirmed, .unconfirmed, .paid])
        #expect(CalendarLayout.marks(for: []) == [])
    }
    @Test func marksFollowEachMonthsOwnStatus() throws {
        var h = Harness()
        let id = try h.add("Rent", 100, day: 10, in: ym(2026, 11))
        try h.set(.paid, id, in: ym(2026, 11))
        #expect(CalendarLayout.marks(for: h.view(ym(2026, 11)).rows) == [.paid])
        #expect(CalendarLayout.marks(for: h.view(ym(2026, 12)).rows) == [.unconfirmed])
    }
}
