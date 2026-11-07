import Foundation
import Testing
@testable import Cushn

@Suite struct CategoryVersionTests {
    let nov = ym(2026, 11), dec = ym(2026, 12), jan = ym(2027, 1)
    let subs = SeedCategory.subscriptions.id
    let cards = SeedCategory.creditCards.id

    func title(_ h: Harness, _ id: UUID, _ m: YearMonth) -> String? {
        h.view(m).sections.first { $0.id == id }?.title
    }

    @Test func seedingIsIdempotent() {
        var ledger = Ledger.seeded(now: fixedNow)
        #expect(!ledger.categories.isEmpty)
        let before = ledger
        ledger.apply(LedgerCommands.seedMissingCategories(ledger: ledger, now: fixedNow))
        #expect(ledger == before)
    }

    @Test func seedingDoesNotResurrectARemovedDefault() throws {
        var h = Harness()
        h.ledger.apply(try LedgerCommands.removeCategory(id: subs, month: nov, ledger: h.ledger, now: fixedNow))
        #expect(LedgerCommands.seedMissingCategories(ledger: h.ledger, now: fixedNow).isEmpty)
    }

    @Test func emptyDefaultSectionsAreHiddenButUserSectionsShow() throws {
        var h = Harness()
        let travel = UUID()
        h.ledger.apply(try LedgerCommands.addCategory(id: travel, name: "Travel", month: nov, ledger: h.ledger, now: fixedNow))
        #expect(h.view(nov).sections.map(\.id) == [travel])
        #expect(h.view(ym(2026, 10)).sections.isEmpty)
        #expect(h.view(nov).allCategories.contains { $0.id == subs })
    }

    @Test func renameIsEffectiveFromItsMonth() throws {
        var h = Harness()
        try h.add("Netflix", 100, day: 1, in: nov, category: subs)
        h.ledger.apply(try LedgerCommands.renameCategory(id: subs, name: "Streaming", month: dec, ledger: h.ledger, now: fixedNow))
        #expect(title(h, subs, nov) == "Subscriptions")
        #expect(title(h, subs, dec) == "Streaming")
        #expect(title(h, subs, jan) == "Streaming")
    }

    @Test func reorderIsEffectiveFromItsMonth() throws {
        var h = Harness()
        try h.add("Netflix", 100, day: 1, in: nov, category: subs)
        try h.add("Amex", 100, day: 1, in: nov, category: cards)
        let original = h.view(nov).sections.map(\.id)
        let reversed = Array(h.view(dec).allCategories.map(\.id).reversed())
        h.ledger.apply(try LedgerCommands.reorderCategories(reversed, month: dec, ledger: h.ledger, now: fixedNow))
        #expect(h.view(nov).sections.map(\.id) == original)
        #expect(h.view(dec).sections.map(\.id) == Array(original.reversed()))
        #expect(h.view(jan).sections.map(\.id) == Array(original.reversed()))
    }

    @Test func movingARowIsEffectiveFromItsMonthAndGoesToSectionEnd() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 100, day: 1, in: nov, category: subs)
        let amex = try h.add("Amex", 100, day: 1, in: nov, category: cards)
        try h.edit(netflix, in: dec) { $0.categoryID = self.cards }
        #expect(h.row(netflix, nov)?.categoryID == subs)
        #expect(h.view(dec).sections.first { $0.id == cards }?.rows.map(\.id) == [amex, netflix])
        #expect(h.view(jan).sections.first { $0.id == cards }?.rows.map(\.id) == [amex, netflix])
    }

    @Test func rowReorderIsEffectiveFromItsMonth() throws {
        var h = Harness()
        let a = try h.add("A", 100, day: 1, in: nov, category: subs)
        let b = try h.add("B", 100, day: 1, in: nov, category: subs)
        h.ledger.apply(try LedgerCommands.reorderPayments([b, a], month: dec, ledger: h.ledger, now: fixedNow))
        #expect(h.view(nov).rows.map(\.id) == [a, b])
        #expect(h.view(dec).rows.map(\.id) == [b, a])
        #expect(h.view(jan).rows.map(\.id) == [b, a])
    }

    @Test func movingARowDoesNotGetUndoneByLaterAmountEdit() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 100, day: 1, in: nov, category: subs)
        try h.edit(netflix, in: jan) { $0.amount = usd(200) }
        try h.edit(netflix, in: dec) { $0.categoryID = self.cards }
        #expect(h.row(netflix, jan)?.categoryID == cards)
    }

    @Test func removingASectionMovesItsRowsToOtherFromThatMonthOnly() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 100, day: 1, in: nov, category: subs)
        h.ledger.apply(try LedgerCommands.removeCategory(id: subs, month: dec, ledger: h.ledger, now: fixedNow))
        #expect(h.row(netflix, nov)?.categoryID == subs)
        #expect(title(h, subs, nov) == "Subscriptions")
        #expect(h.row(netflix, dec)?.categoryID == SeedCategory.other.id)
        #expect(h.row(netflix, jan) != nil)
    }

    @Test func otherSectionCannotBeRemoved() {
        let h = Harness()
        #expect(throws: LedgerError.cannotRemoveOther) {
            try LedgerCommands.removeCategory(id: SeedCategory.other.id, month: nov, ledger: h.ledger, now: fixedNow)
        }
    }

    @Test func blankSectionNamesAreRejected() {
        let h = Harness()
        #expect(throws: LedgerError.emptyName) {
            try LedgerCommands.addCategory(id: UUID(), name: "  ", month: nov, ledger: h.ledger, now: fixedNow)
        }
        #expect(throws: LedgerError.emptyName) {
            try LedgerCommands.renameCategory(id: subs, name: "", month: nov, ledger: h.ledger, now: fixedNow)
        }
    }

    @Test func categoryKindOverrideIsEffectiveFromItsMonth() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 100, day: 1, in: nov, category: subs)
        #expect(h.row(netflix, nov)?.reportingKind == .expense)
        h.ledger.apply(try LedgerCommands.setCategoryKind(id: subs, kind: .transfer, month: dec, ledger: h.ledger, now: fixedNow))
        #expect(h.row(netflix, nov)?.reportingKind == .expense)
        #expect(h.row(netflix, dec)?.reportingKind == .transfer)
    }
}
