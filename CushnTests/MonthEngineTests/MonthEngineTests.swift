import Foundation
import Testing
@testable import Cushn

/// P0 engine scenarios from tests/ACCEPTANCE_TESTS.md and MONTH_ENGINE.md.
@Suite struct MonthEngineTests {
    let oct = ym(2026, 10), nov = ym(2026, 11), dec = ym(2026, 12), jan = ym(2027, 1), feb = ym(2027, 2), mar = ym(2027, 3)

    @Test func freshLedgerProjectsAnEmptyMonth() {
        let h = Harness()
        #expect(h.view(nov).rows.isEmpty)
        #expect(h.view(nov).sections.isEmpty)
    }

    @Test func addedPaymentCarriesForwardButNotBackward() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        #expect(h.row(netflix, oct) == nil)
        #expect(h.row(netflix, nov)?.amount == usd(3000))
        #expect(h.row(netflix, dec)?.name == "Netflix")
        #expect(h.row(netflix, nov)?.dueDate == CalendarDay(year: 2026, month: 11, day: 28))
    }

    @Test func paidIsScopedToItsMonth() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        try h.set(.paid, netflix, in: nov)
        #expect(h.row(netflix, nov)?.status == .paid)
        #expect(h.row(netflix, nov)?.confirmedAt == fixedNow)
        #expect(h.row(netflix, dec)?.status == .unconfirmed)
    }

    @Test func undoPaidReturnsToUnconfirmedAndClearsTimestamp() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        try h.set(.paid, netflix, in: nov)
        try h.set(.unconfirmed, netflix, in: nov)
        #expect(h.row(netflix, nov)?.status == .unconfirmed)
        #expect(h.row(netflix, nov)?.confirmedAt == nil)
        #expect(h.row(netflix, dec)?.status == .unconfirmed)
    }

    @Test func skipIsScopedAndNeverCountsAsPaid() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        try h.set(.skipped, netflix, in: nov)
        #expect(h.row(netflix, nov)?.status == .skipped)
        #expect(h.row(netflix, dec)?.status == .unconfirmed)
        let totals = try #require(h.view(nov).totals.first)
        #expect(totals.markedPaid == 0)
        #expect(totals.skipped == 3000)
    }

    @Test func addAfterBrowsingLaterMonthStillAppearsThere() throws {
        var h = Harness()
        _ = h.view(jan) // January viewed first.
        let spotify = try h.add("Spotify", 1200, day: 15, in: dec)
        #expect(h.row(spotify, nov) == nil)
        #expect(h.row(spotify, dec) != nil)
        #expect(h.row(spotify, jan) != nil)
    }

    @Test func editCarriesForwardButNotBackward() throws {
        var h = Harness()
        let spotify = try h.add("Spotify", 1200, day: 15, in: dec)
        try h.edit(spotify, in: jan) { $0.amount = usd(1500) }
        #expect(h.row(spotify, dec)?.amount == usd(1200))
        #expect(h.row(spotify, jan)?.amount == usd(1500))
        #expect(h.row(spotify, feb)?.amount == usd(1500))
    }

    @Test func editInAddMonthKeepsPriorMonthsAbsentAndFlowsForward() throws {
        var h = Harness()
        let spotify = try h.add("Spotify", 1200, day: 15, in: dec)
        _ = h.view(jan)
        try h.edit(spotify, in: dec) { $0.amount = usd(1500) }
        #expect(h.row(spotify, nov) == nil)
        #expect(h.row(spotify, dec)?.amount == usd(1500))
        #expect(h.row(spotify, jan)?.amount == usd(1500))
    }

    @Test func laterExplicitEditWinsOverEarlierEdit() throws {
        var h = Harness()
        let spotify = try h.add("Spotify", 1200, day: 15, in: nov)
        try h.edit(spotify, in: jan) { $0.amount = usd(2000) }
        try h.edit(spotify, in: dec) { $0.amount = usd(1500) }
        #expect(h.row(spotify, nov)?.amount == usd(1200))
        #expect(h.row(spotify, dec)?.amount == usd(1500))
        #expect(h.row(spotify, jan)?.amount == usd(2000))
        #expect(h.row(spotify, feb)?.amount == usd(2000))
    }

    /// The snapshot trap: an earlier-month edit of a *different* field must still reach later months.
    @Test func earlierEditOfOtherFieldReachesLaterRevision() throws {
        var h = Harness()
        let spotify = try h.add("Spotify", 1200, day: 15, in: nov)
        try h.edit(spotify, in: jan) { $0.amount = usd(2000) }
        try h.edit(spotify, in: dec) { $0.name = "Spotify Family" }
        #expect(h.row(spotify, nov)?.name == "Spotify")
        #expect(h.row(spotify, jan)?.name == "Spotify Family")
        #expect(h.row(spotify, jan)?.amount == usd(2000))
    }

    @Test func repeatedEditInSameMonthKeepsOneRevision() throws {
        var h = Harness()
        let spotify = try h.add("Spotify", 1200, day: 15, in: nov)
        try h.edit(spotify, in: dec) { $0.amount = usd(1300) }
        try h.edit(spotify, in: dec) { $0.amount = usd(1400) }
        try h.edit(spotify, in: dec) { $0.name = "Spotify Duo" }
        let decRevisions = h.ledger.paymentRevisions[spotify]!.filter { $0.effectiveMonth == dec }
        #expect(decRevisions.count == 1)
        #expect(h.row(spotify, dec)?.amount == usd(1400))
        #expect(h.row(spotify, dec)?.name == "Spotify Duo")
    }

    @Test func editWithNoChangesWritesNothing() throws {
        var h = Harness()
        let spotify = try h.add("Spotify", 1200, day: 15, in: nov)
        let before = h.ledger
        try h.edit(spotify, in: dec) { _ in }
        #expect(h.ledger == before)
    }

    @Test func removalPreservesEarlierMonthsAndStatus() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        try h.set(.paid, netflix, in: nov)
        try h.remove(netflix, from: dec)
        #expect(h.row(netflix, nov)?.status == .paid)
        #expect(h.row(netflix, dec) == nil)
        #expect(h.row(netflix, jan) == nil)
    }

    @Test func removalDominatesSavedFutureEdits() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        try h.edit(netflix, in: jan) { $0.amount = usd(3500) }
        try h.edit(netflix, in: mar) { $0.amount = usd(3600) }
        try h.remove(netflix, from: dec)
        #expect(h.row(netflix, dec) == nil)
        #expect(h.row(netflix, jan) == nil)
        #expect(h.row(netflix, mar) == nil)
        #expect(h.row(netflix, ym(2030, 1)) == nil)
        #expect(h.row(netflix, nov)?.amount == usd(3000))
    }

    /// Deleting later revisions matters when one explicitly re-includes the payment, such as in imported or older data.
    @Test func removalEliminatesLaterRevisionsIncludingExplicitReinclusion() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        h.ledger.apply([.upsertPaymentRevision(PaymentRevision(
            id: UUID(), paymentID: netflix, effectiveMonth: jan, isIncluded: true, updatedAt: fixedNow))])
        try h.remove(netflix, from: dec)
        #expect(h.row(netflix, jan) == nil)
        #expect(h.ledger.paymentRevisions[netflix]!.allSatisfy { $0.effectiveMonth <= dec })
    }

    @Test func removalInCreationMonthHidesEverywhereWithoutDestroyingIdentity() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        try h.remove(netflix, from: nov)
        #expect(h.row(netflix, nov) == nil)
        #expect(h.row(netflix, dec) == nil)
        #expect(h.ledger.payments[netflix] != nil)
    }

    @Test func editBeforeRemovalDoesNotResurrect() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        try h.remove(netflix, from: jan)
        try h.edit(netflix, in: dec) { $0.amount = usd(9900) }
        #expect(h.row(netflix, dec)?.amount == usd(9900))
        #expect(h.row(netflix, jan) == nil)
    }

    @Test func commandsOnInvisibleMonthsThrow() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        #expect(throws: LedgerError.paymentNotVisible) { try h.set(.paid, netflix, in: oct) }
        #expect(throws: LedgerError.paymentNotVisible) { try h.remove(netflix, from: oct) }
        try h.remove(netflix, from: dec)
        #expect(throws: LedgerError.paymentNotVisible) { try h.set(.paid, netflix, in: jan) }
        let money = usd(100)
        #expect(throws: LedgerError.paymentNotVisible) {
            try LedgerCommands.edit(id: netflix, draft("X", money, day: 1), month: jan, ledger: h.ledger, now: fixedNow)
        }
    }

    @Test func notCommittingDeleteChangesNothing() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        let before = h.ledger
        // Building the mutations is pure; a cancelled confirmation never applies them.
        _ = try LedgerCommands.remove(id: netflix, month: dec, ledger: h.ledger, now: fixedNow)
        #expect(h.ledger == before)
        #expect(h.row(netflix, dec) != nil)
    }

    @Test func reAddedNameIsSeparateIdentityWithCleanHistory() throws {
        var h = Harness()
        let old = try h.add("Netflix", 3000, day: 28, in: nov)
        try h.set(.paid, old, in: nov)
        try h.remove(old, from: dec)
        let new = try h.add("Netflix", 1800, day: 3, in: feb)
        #expect(new != old)
        #expect(h.row(new, feb)?.status == .unconfirmed)
        #expect(h.row(new, nov) == nil)
        #expect(h.row(old, feb) == nil)
        #expect(h.row(old, nov)?.status == .paid)
    }

    @Test func nominal31ClampsInFebruaryAndReturnsInMarch() throws {
        var h = Harness()
        let spotify = try h.add("Spotify", 1200, day: 15, in: dec)
        try h.edit(spotify, in: feb) { $0.dueDay = DueDay(31)! }
        #expect(h.row(spotify, jan)?.dueDate.day == 15)
        #expect(h.row(spotify, feb)?.dueDate == CalendarDay(year: 2027, month: 2, day: 28))
        #expect(h.row(spotify, mar)?.dueDate == CalendarDay(year: 2027, month: 3, day: 31))
        #expect(h.row(spotify, ym(2028, 2))?.dueDate == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(h.row(spotify, feb)?.nominalDueDay.value == 31)
    }

    @Test func yearCrossingKeepsListAndResetsStatus() throws {
        var h = Harness()
        let rent = try h.add("Rent", 150000, day: 1, in: dec)
        try h.set(.paid, rent, in: dec)
        #expect(h.row(rent, jan)?.status == .unconfirmed)
        #expect(h.row(rent, jan)?.dueDate == CalendarDay(year: 2027, month: 1, day: 1))
    }

    @Test func projectionIsReadOnlyAndIdempotent() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        try h.set(.paid, netflix, in: nov)
        let before = h.ledger
        let first = h.view(jan)
        _ = h.view(oct); _ = h.view(ym(2031, 6))
        #expect(h.view(jan) == first)
        #expect(h.ledger == before)
    }

    @Test func rapidStatusTapsLeaveOneLogicalStatus() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 3000, day: 28, in: nov)
        for _ in 0..<5 { try h.set(.paid, netflix, in: nov) }
        #expect(h.ledger.statuses.values.filter { $0.paymentID == netflix && $0.month == nov }.count == 1)
        #expect(h.row(netflix, nov)?.status == .paid)
    }

    @Test func statusChangeDoesNotReorderRows() throws {
        var h = Harness()
        let a = try h.add("A", 100, day: 1, in: nov)
        let b = try h.add("B", 100, day: 2, in: nov)
        let c = try h.add("C", 100, day: 3, in: nov)
        let order = h.view(nov).rows.map(\.id)
        #expect(order == [a, b, c])
        try h.set(.paid, a, in: nov)
        try h.set(.skipped, b, in: nov)
        #expect(h.view(nov).rows.map(\.id) == order)
    }

    @Test func rejectsInvalidDrafts() {
        let h = Harness()
        #expect(throws: LedgerError.emptyName) {
            try LedgerCommands.add(id: UUID(), draft("   ", usd(100), day: 1), month: nov, ledger: h.ledger, now: fixedNow)
        }
        #expect(throws: LedgerError.negativeAmount) {
            try LedgerCommands.add(id: UUID(), draft("X", usd(-1), day: 1), month: nov, ledger: h.ledger, now: fixedNow)
        }
    }

    @Test func preservesUserTypedNameExceptOuterWhitespace() throws {
        var h = Harness()
        let id = try h.add("  aMeX pLaTiNuM ", 100, day: 1, in: nov)
        #expect(h.row(id, nov)?.name == "aMeX pLaTiNuM")
    }

    @Test func duplicateNamesAreIndependent() throws {
        var h = Harness()
        let a = try h.add("Rent", 100, day: 1, in: nov)
        let b = try h.add("Rent", 200, day: 2, in: nov)
        try h.set(.paid, a, in: nov)
        #expect(h.row(b, nov)?.status == .unconfirmed)
    }

    @Test func statusOnHistoricalMonthUpdatesOnlyThatMonth() throws {
        var h = Harness()
        let rent = try h.add("Rent", 100, day: 1, in: oct)
        try h.set(.paid, rent, in: nov)
        try h.set(.paid, rent, in: oct)
        try h.set(.unconfirmed, rent, in: oct)
        #expect(h.row(rent, oct)?.status == .unconfirmed)
        #expect(h.row(rent, nov)?.status == .paid)
    }
}

@Suite struct StatusCircleTests {
    @Test func circleTogglesOnlyBetweenUnconfirmedAndPaid() {
        #expect(StatusCircleAction.forTap(on: .unconfirmed) == .set(.paid))
        #expect(StatusCircleAction.forTap(on: .paid) == .set(.unconfirmed))
    }
    @Test func circleOnSkippedOpensDetailsInsteadOfChangingStatus() {
        #expect(StatusCircleAction.forTap(on: .skipped) == .openDetails)
    }
}
