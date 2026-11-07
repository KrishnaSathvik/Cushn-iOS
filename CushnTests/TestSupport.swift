import Foundation
@testable import Cushn

/// Fixed instant so tests are independent of wall-clock time.
let fixedNow = Date(timeIntervalSince1970: 1_793_000_000)

func ym(_ year: Int, _ month: Int) -> YearMonth { YearMonth(year: year, month: month)! }
func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }
func draft(_ name: String, _ amount: Money, day: Int, category: UUID = SeedCategory.other.id) -> PaymentDraft {
    PaymentDraft(name: name, amount: amount, dueDay: DueDay(day)!, categoryID: category)
}

/// Thin test driver: runs real commands and applies their real mutations.
struct Harness {
    var ledger = Ledger.seeded(now: fixedNow)

    @discardableResult
    mutating func add(_ name: String, _ cents: Int64, day: Int, in month: YearMonth,
                      category: UUID = SeedCategory.other.id, currency: String = "USD") throws -> UUID {
        let id = UUID()
        let money = Money(minorUnits: cents, currencyCode: currency)
        ledger.apply(try LedgerCommands.add(id: id, draft(name, money, day: day, category: category),
                                            month: month, ledger: ledger, now: fixedNow))
        return id
    }

    /// Edit using the currently projected values, changing only what the closure changes.
    mutating func edit(_ id: UUID, in month: YearMonth, _ change: (inout PaymentDraft) -> Void) throws {
        let row = try require2(view(month).row(id))
        var d = PaymentDraft(name: row.name, amount: row.amount, dueDay: row.nominalDueDay, categoryID: row.categoryID)
        change(&d)
        ledger.apply(try LedgerCommands.edit(id: id, d, month: month, ledger: ledger, now: fixedNow))
    }

    mutating func remove(_ id: UUID, from month: YearMonth) throws {
        ledger.apply(try LedgerCommands.remove(id: id, month: month, ledger: ledger, now: fixedNow))
    }

    mutating func set(_ status: PaymentStatus, _ id: UUID, in month: YearMonth) throws {
        ledger.apply(try LedgerCommands.setStatus(status, id: id, month: month, ledger: ledger, now: fixedNow))
    }

    func view(_ month: YearMonth) -> MonthView { MonthProjector.project(month: month, ledger: ledger) }
    func row(_ id: UUID, _ month: YearMonth) -> MonthRow? { view(month).row(id) }
}

struct Missing: Error {}
func require2<T>(_ value: T?) throws -> T {
    guard let value else { throw Missing() }
    return value
}
