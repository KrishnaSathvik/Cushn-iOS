import Foundation
import Testing
@testable import Cushn

@Suite struct AnalyticsTests {
    let oct = ym(2026, 10), nov = ym(2026, 11)

    func overview(_ h: Harness, _ month: YearMonth) -> [CurrencyOverview] {
        AnalyticsService.overview(for: h.view(month), previous: h.view(month.previous))
    }

    /// Credit card, Netflix, rent, electricity, investment and transfer, per the fixture in ANALYTICS_AND_REVIEW.md.
    func fixture() throws -> (Harness, card: UUID, netflix: UUID, rent: UUID, power: UUID, fund: UUID, transfer: UUID) {
        var h = Harness()
        let card = try h.add("Amex", 50000, day: 5, in: oct, category: SeedCategory.creditCards.id)
        let netflix = try h.add("Netflix", 1500, day: 28, in: oct, category: SeedCategory.subscriptions.id)
        let rent = try h.add("Rent", 150000, day: 1, in: oct, category: SeedCategory.housing.id)
        let power = try h.add("Electric", 8000, day: 12, in: oct, category: SeedCategory.utilities.id)
        let fund = try h.add("Index fund", 20000, day: 15, in: oct, category: SeedCategory.investments.id)
        let transfer = try h.add("Savings", 10000, day: 20, in: oct, category: SeedCategory.transfers.id)
        return (h, card, netflix, rent, power, fund, transfer)
    }

    @Test func scheduledEqualsPaidPlusUnconfirmedPlusSkipped() throws {
        var (h, card, netflix, _, _, _, _) = try fixture()
        try h.set(.paid, card, in: nov)
        try h.set(.skipped, netflix, in: nov)
        let t = try #require(overview(h, nov).first).totals
        #expect(t.scheduled == 239500)
        #expect(t.markedPaid == 50000)
        #expect(t.skipped == 1500)
        #expect(t.unconfirmed == 188000)
        #expect(t.scheduled == t.markedPaid + t.unconfirmed + t.skipped)
    }

    @Test func onlyExplicitPaidCountsAsMarkedPaid() throws {
        let (h, _, _, _, _, _, _) = try fixture()
        // Every due date in this past month has passed, and none became paid.
        #expect(overview(h, oct).first?.totals.markedPaid == 0)
        #expect(overview(h, oct).first?.paidCount == 0)
        #expect(overview(h, oct).first?.rowCount == 6)
    }

    @Test func nonExpenseFlowsStayOutOfEstimatedExpenses() throws {
        let (h, _, _, _, _, _, _) = try fixture()
        let flows = try #require(overview(h, nov).first).flows
        #expect(flows.estimatedExpenses == 159500)
        #expect(flows.creditRepayments == 50000)
        #expect(flows.investments == 20000)
        #expect(flows.transfers == 10000)
        #expect(flows.unclassified == 0)
    }

    @Test func unknownCategoryStaysUnclassifiedUntilOverridden() throws {
        var h = Harness()
        try h.add("Mystery", 700, day: 1, in: nov)
        #expect(overview(h, nov).first?.flows.unclassified == 700)
        #expect(overview(h, nov).first?.flows.estimatedExpenses == 0)
        h.ledger.apply(try LedgerCommands.setCategoryKind(id: SeedCategory.other.id, kind: .expense, month: nov, ledger: h.ledger, now: fixedNow))
        #expect(overview(h, nov).first?.flows.estimatedExpenses == 700)
    }

    @Test func flowsCoverScheduledExactlyOnce() throws {
        let (h, _, _, _, _, _, _) = try fixture()
        let o = try #require(overview(h, nov).first)
        let f = o.flows
        #expect(f.estimatedExpenses + f.creditRepayments + f.investments + f.transfers + f.unclassified == o.totals.scheduled)
    }

    @Test func categoryBreakdownFollowsSectionOrderAndSkipsOtherCurrencies() throws {
        var h = Harness()
        let netflix = try h.add("Netflix", 1500, day: 1, in: nov, category: SeedCategory.subscriptions.id)
        try h.add("Amex", 5000, day: 1, in: nov, category: SeedCategory.creditCards.id)
        try h.add("Foreign", 900, day: 1, in: nov, category: SeedCategory.utilities.id, currency: "EUR")
        try h.set(.paid, netflix, in: nov)
        let all = overview(h, nov)
        let dollars = try #require(all.first { $0.currencyCode == "USD" })
        #expect(dollars.categories.map(\.title) == ["Credit Cards", "Subscriptions"])
        #expect(dollars.categories[1].scheduled == 1500)
        #expect(dollars.categories[1].markedPaid == 1500)
        #expect(all.first { $0.currencyCode == "EUR" }?.categories.map(\.title) == ["Utilities"])
    }

    @Test func multiCurrencyIsNeverSummed() throws {
        var h = Harness()
        try h.add("Rent", 100000, day: 1, in: nov)
        try h.add("Flat", 80000, day: 1, in: nov, currency: "EUR")
        let all = overview(h, nov)
        #expect(all.map(\.currencyCode) == ["EUR", "USD"])
        #expect(all[0].totals.scheduled == 80000)
        #expect(all[1].totals.scheduled == 100000)
    }

    @Test func comparisonIsLikeForLike() throws {
        var h = Harness()
        let rent = try h.add("Rent", 100000, day: 1, in: oct)
        try h.edit(rent, in: nov) { $0.amount = usd(125000) }
        let c = try #require(overview(h, nov).first).scheduledComparison
        #expect(c.previous == 100000)
        #expect(c.delta == 25000)
        #expect(c.percent == 25)
        #expect(c.isNew == false)
    }

    @Test func comparisonHandlesZeroDenominator() throws {
        var h = Harness()
        try h.add("Rent", 100000, day: 1, in: nov)
        let c = try #require(overview(h, nov).first).scheduledComparison
        #expect(c.previous == 0)
        #expect(c.percent == nil)
        #expect(c.isNew)
    }

    @Test func comparisonDoesNotCrossCurrencies() throws {
        var h = Harness()
        let rent = try h.add("Rent", 100000, day: 1, in: oct)
        try h.edit(rent, in: nov) { $0.amount = Money(minorUnits: 90000, currencyCode: "EUR") }
        let euros = try #require(overview(h, nov).first { $0.currencyCode == "EUR" })
        #expect(euros.scheduledComparison.previous == 0)
        #expect(euros.scheduledComparison.isNew)
    }
}
