import Foundation
import Testing
@testable import Cushn

/// Fixtures named in tests/ACCEPTANCE_TESTS.md that the engine tests don't already cover.
@Suite struct AcceptanceFixtureTests {
    private let november = ym(2026, 11)

    @Test func twentySectionsKeepTheirOrderAndRows() throws {
        var harness = Harness()
        var ids: [UUID] = []
        for index in 0..<20 {
            let id = UUID()
            harness.ledger.apply(try LedgerCommands.addCategory(id: id, name: "Section \(index)", month: november,
                                                                ledger: harness.ledger, now: fixedNow))
            ids.append(id)
            try harness.add("Payment \(index)", 100, day: 5, in: november, category: id)
        }
        let view = harness.view(november)
        let titles = view.sections.map(\.title)
        #expect(titles == (0..<20).map { "Section \($0)" })
        #expect(view.sections.allSatisfy { $0.rows.count == 1 })
        #expect(harness.view(ym(2026, 12)).sections.map(\.title) == titles)
        #expect(harness.view(ym(2026, 10)).rows.isEmpty)
    }

    @Test func manyPaymentsOnTheSameDayAllAppearOnThatDate() throws {
        var harness = Harness()
        for index in 0..<150 { try harness.add("Payment \(index)", 100, day: 15, in: november) }
        let byDay = CalendarLayout.rowsByDay(harness.view(november))
        #expect(byDay.count == 1)
        #expect(byDay[CalendarDay(year: 2026, month: 11, day: 15)]?.count == 150)
    }

    /// Edits are serialized on the main actor, so "simultaneous" means interleaved. Neither may lose the other's field.
    @Test func interleavedEditsToOnePaymentKeepBothChanges() throws {
        var harness = Harness()
        let id = try harness.add("Gym", 1_000, day: 5, in: november)
        try harness.edit(id, in: november) { $0.name = "Gym Plus" }
        try harness.edit(id, in: november) { $0.amount = usd(2_000) }
        try harness.edit(id, in: ym(2026, 12)) { $0.dueDay = DueDay(9)! }
        let december = try require2(harness.row(id, ym(2026, 12)))
        #expect(december.name == "Gym Plus")
        #expect(december.amount == usd(2_000))
        #expect(december.nominalDueDay == DueDay(9)!)
        #expect(try require2(harness.row(id, november)).nominalDueDay == DueDay(5)!)
    }

    /// Rows match their names on every render, but only visible rows render. This is a guard against matching
    /// becoming far slower, with a budget loose enough for a Debug build on a busy simulator: the whole
    /// list, about ten times what a screen shows at once.
    @Test func matchingAFullListStaysCheap() {
        let names = (0..<150).map { "Some Payment Name \($0)" }
        _ = BrandMatcher.match("warm up the alias table")
        let clock = ContinuousClock()
        let elapsed = clock.measure { for name in names { _ = BrandMatcher.match(name) } }
        print("BrandMatcher 150 names: \(elapsed)")
        #expect(elapsed < .milliseconds(100))
    }
}
