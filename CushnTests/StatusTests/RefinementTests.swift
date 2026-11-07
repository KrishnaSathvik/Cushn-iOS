import Foundation
import Testing
@testable import Cushn

@Suite struct SectionOrderingTests {
    private let a = UUID(), b = UUID(), c = UUID(), hidden = UUID()

    @Test func movingDownLandsJustAfterTheTarget() {
        #expect(SectionOrdering.move(a, to: c, in: [a, b, c]) == [b, c, a])
    }

    @Test func movingUpLandsJustBeforeTheTarget() {
        #expect(SectionOrdering.move(c, to: a, in: [a, b, c]) == [c, a, b])
    }

    @Test func droppingOnItselfChangesNothing() {
        #expect(SectionOrdering.move(b, to: b, in: [a, b, c]) == [a, b, c])
    }

    @Test func unknownSectionsChangeNothing() {
        #expect(SectionOrdering.move(UUID(), to: c, in: [a, b, c]) == [a, b, c])
    }

    @Test func aMoveAmongVisibleSectionsSwapsThemAcrossAHiddenOne() {
        // Home shows a, b and c. `hidden` is an empty default that keeps its place between them.
        let order = SectionOrdering.move(c, to: b, in: [a, b, hidden, c])
        #expect(order.filter { $0 != hidden } == [a, c, b])
        #expect(order.contains(hidden))
    }

    @Test func aNewVisibleOrderLeavesHiddenSectionsInPlace() {
        #expect(SectionOrdering.placing([c, a, b], in: [a, hidden, b, c]) == [c, hidden, a, b])
        #expect(SectionOrdering.placing([a, b], in: [a, hidden, b]) == [a, hidden, b], "Nothing moved")
    }

    @Test func neighborsStopAtTheEnds() {
        #expect(SectionOrdering.neighbor(of: a, in: [a, b], movingDown: false) == nil)
        #expect(SectionOrdering.neighbor(of: b, in: [a, b], movingDown: true) == nil)
        #expect(SectionOrdering.neighbor(of: a, in: [a, b], movingDown: true) == b)
        #expect(SectionOrdering.neighbor(of: b, in: [a, b], movingDown: false) == a)
    }
}

@MainActor @Suite struct SectionReorderHistoryTests {
    private let november = YearMonth(year: 2026, month: 11)!

    private func store() throws -> LedgerStore {
        let clock = FixedClock(now: CalendarDay(year: 2026, month: 11, day: 15).date(in: .autoupdatingCurrent))
        return try LedgerStore(repository: InMemoryLedgerRepository(), clock: clock)
    }

    private func draft(_ name: String, _ category: SeedCategory) -> PaymentDraft {
        PaymentDraft(name: name, amount: Money(minorUnits: 1_000, currencyCode: "USD"), dueDay: DueDay(5)!, categoryID: category.id)
    }

    @Test func aMoveAppliesFromTheSelectedMonthAndLeavesEarlierMonths() throws {
        let store = try store()
        try store.add(draft("Visa", .creditCards), month: november)
        try store.add(draft("Water", .utilities), month: november)
        let december = november.adding(months: 1), january = november.adding(months: 2)

        let order = store.view(for: december).allCategories.map(\.id)
        try store.reorderCategories(SectionOrdering.move(SeedCategory.utilities.id, to: SeedCategory.creditCards.id, in: order), month: december)

        #expect(store.view(for: november).sections.map(\.title) == ["Credit Cards", "Utilities"])
        #expect(store.view(for: december).sections.map(\.title) == ["Utilities", "Credit Cards"])
        #expect(store.view(for: january).sections.map(\.title) == ["Utilities", "Credit Cards"])
    }

    @Test func aMoveKeepsStatusesAndRowsInEveryMonth() throws {
        let store = try store()
        let visa = try store.add(draft("Visa", .creditCards), month: november)
        try store.add(draft("Water", .utilities), month: november)
        try store.setStatus(.paid, id: visa, month: november)

        let order = store.view(for: november).allCategories.map(\.id)
        try store.reorderCategories(SectionOrdering.move(SeedCategory.creditCards.id, to: SeedCategory.utilities.id, in: order), month: november)

        #expect(store.view(for: november).row(visa)?.status == .paid)
        #expect(store.view(for: november).rows.count == 2)
        #expect(store.view(for: november.adding(months: 1)).row(visa)?.status == .unconfirmed)
    }
}

@Suite struct CategoryChoiceTests {
    private let all = SeedCategory.allCases.map(\.id)

    private func suggested(_ name: String, available: [UUID]? = nil) -> UUID {
        var choice = CategoryChoice(explicit: nil)
        choice.nameChanged(to: name, available: available ?? all)
        return choice.categoryID
    }

    @Test(arguments: [
        ("Netflix Premium", SeedCategory.subscriptions),
        ("American Express Gold", .creditCards),
        ("T-Mobile Bill", .utilities),
        ("Rent", .housing),
        ("Some Custom Payment", .other),
    ])
    func namesSuggestASection(name: String, section: SeedCategory) {
        #expect(suggested(name) == section.id)
    }

    @Test func aRecognizedNameIsLabeledAndOtherIsNot() {
        var choice = CategoryChoice(explicit: nil)
        #expect(!choice.isSuggestion)
        choice.nameChanged(to: "Netflix", available: all)
        #expect(choice.isSuggestion)
        choice.nameChanged(to: "Netflix Camera Repair", available: all)
        #expect(choice.categoryID == SeedCategory.other.id, "A suggestion follows the name while nothing has been chosen")
        #expect(!choice.isSuggestion)
    }

    @Test func aRemovedSectionFallsBackToOther() {
        let withoutSubscriptions = all.filter { $0 != SeedCategory.subscriptions.id }
        #expect(suggested("Netflix", available: withoutSubscriptions) == SeedCategory.other.id)
    }

    @Test func aManualChoiceSurvivesLaterTyping() {
        let custom = UUID()
        var choice = CategoryChoice(explicit: nil)
        choice.nameChanged(to: "Net", available: all + [custom])
        choice.choose(custom)
        choice.nameChanged(to: "Netflix", available: all + [custom])
        #expect(choice.categoryID == custom)
        #expect(!choice.isSuggestion)
    }

    @Test func aSectionsAddButtonWinsOverTheName() {
        var choice = CategoryChoice(explicit: SeedCategory.housing.id)
        choice.nameChanged(to: "Netflix", available: all)
        #expect(choice.categoryID == SeedCategory.housing.id)
    }

    @Test func editingNeverReclassifies() {
        var choice = CategoryChoice(saved: SeedCategory.other.id)
        choice.nameChanged(to: "Netflix", available: all)
        #expect(choice.categoryID == SeedCategory.other.id)
    }
}

@MainActor @Suite struct RenamedSectionSuggestionTests {
    @Test func aSuggestionFollowsTheSectionThroughARename() throws {
        let month = YearMonth(year: 2026, month: 11)!
        let clock = FixedClock(now: CalendarDay(year: 2026, month: 11, day: 15).date(in: .autoupdatingCurrent))
        let store = try LedgerStore(repository: InMemoryLedgerRepository(), clock: clock)
        try store.renameCategory(id: SeedCategory.subscriptions.id, name: "Streaming", month: month)

        var choice = CategoryChoice(explicit: nil)
        choice.nameChanged(to: "Netflix", available: store.view(for: month).allCategories.map(\.id))
        let id = try store.add(PaymentDraft(name: "Netflix", amount: Money(minorUnits: 1_799, currencyCode: "USD"),
                                            dueDay: DueDay(28)!, categoryID: choice.categoryID), month: month)

        #expect(store.view(for: month).sections.first { $0.rows.contains { $0.id == id } }?.title == "Streaming")
    }
}

@Suite struct OverviewPresentationTests {
    private func overview(rowCount: Int = 2, current: Int64 = 400, previous: Int64 = 0, flows: FlowBreakdown = FlowBreakdown()) -> OverviewPresentation {
        OverviewPresentation(overview: CurrencyOverview(
            totals: CurrencyTotals(currencyCode: "USD", scheduled: current),
            rowCount: rowCount,
            paidCount: 0,
            categories: [],
            flows: flows,
            scheduledComparison: MetricComparison(current: current, previous: previous)
        ))
    }

    @Test func onePaymentSimplifies() {
        #expect(!overview(rowCount: 1).showsStatusBreakdown)
        #expect(overview(rowCount: 2).showsStatusBreakdown)
    }

    @Test func aZeroTotalDrawsNoProgressBar() {
        #expect(!overview(current: 0).showsProgressBar)
    }

    @Test func noEarlierAmountMeansNoComparisonLine() {
        #expect(overview(previous: 0).comparisonLine == nil)
    }

    @Test func comparisonLinesStateTheChange() {
        #expect(overview(current: 400, previous: 400).comparisonLine == .same)
        #expect(overview(current: 400, previous: 200).comparisonLine == .change(delta: 200, percent: 100))
    }

    @Test func typeSlicesAddUpToEveryFlowWithoutDoubleCounting() {
        let flows = FlowBreakdown(estimatedExpenses: 100, creditRepayments: 500, investments: 30, transfers: 20, unclassified: 7)
        let slices = overview(flows: flows).typeSlices
        #expect(slices.map(\.amount).reduce(0, +) == 657)
        #expect(slices.map(\.kind) == [.cardRepayments, .expenses, .investmentsAndTransfers, .other], "Largest first")
        #expect(slices.first { $0.kind == .investmentsAndTransfers }?.amount == 50)
    }

    @Test func oneTypeGetsNoDonutAndEmptyTypesAreLeftOut() {
        let one = overview(flows: FlowBreakdown(estimatedExpenses: 100))
        #expect(one.typeSlices.map(\.kind) == [.expenses])
        #expect(!one.showsTypeChart)
        #expect(overview(flows: FlowBreakdown(estimatedExpenses: 100, unclassified: 5)).showsTypeChart)
        #expect(overview().typeSlices.isEmpty)
    }

    @Test func theEnginesFlowsSplitWithoutLoss() throws {
        var h = Harness()
        let nov = ym(2026, 11)
        try h.add("Amex", 100_000, day: 5, in: nov, category: SeedCategory.creditCards.id)
        try h.add("Netflix", 2_199, day: 28, in: nov, category: SeedCategory.subscriptions.id)
        try h.add("Index fund", 5_000, day: 2, in: nov, category: SeedCategory.investments.id)
        try h.add("Mystery", 1_000, day: 9, in: nov)
        let figures = try #require(AnalyticsService.overview(for: h.view(nov), previous: h.view(nov.previous)).first)
        let slices = OverviewPresentation(overview: figures).typeSlices
        #expect(slices.map(\.amount).reduce(0, +) == figures.totals.scheduled)
    }
}

@Suite struct MonthlyTrendTests {
    private let nov = ym(2026, 11)

    @Test func monthsBeforeTheFirstAmountAreLeftOut() {
        let points = MonthlyTrend.points(endingIn: nov) { $0 >= ym(2026, 10) ? 500 : 0 }
        #expect(points.map(\.month) == [ym(2026, 10), nov])
        #expect(MonthlyTrend.isMeaningful(points))
    }

    @Test func oneMonthIsNotAComparison() {
        let points = MonthlyTrend.points(endingIn: nov) { $0 == ym(2026, 11) ? 500 : 0 }
        #expect(points.count == 1)
        #expect(!MonthlyTrend.isMeaningful(points))
    }

    @Test func noDataGivesNoBars() {
        #expect(MonthlyTrend.points(endingIn: nov) { _ in 0 }.isEmpty)
    }

    @Test func aRealEmptyMonthInTheMiddleStays() {
        let points = MonthlyTrend.points(endingIn: nov) { $0 == ym(2026, 10) ? 0 : 500 }
        #expect(points.count == 6)
        #expect(points.map(\.scheduled).contains(0))
    }

    @Test func itStopsAtSixMonthsAcrossAYearChange() {
        let points = MonthlyTrend.points(endingIn: ym(2027, 2)) { _ in 500 }
        #expect(points.first?.month == ym(2026, 9))
        #expect(points.last?.month == ym(2027, 2))
    }

    @Test func itNeverReachesBeforeTheCalendarStarts() {
        #expect(MonthlyTrend.points(endingIn: .origin) { _ in 500 }.count == 1)
    }

    @MainActor @Test func currenciesStaySeparate() throws {
        var h = Harness()
        try h.add("Rent", 100_000, day: 1, in: ym(2026, 10))
        try h.add("Flat", 90_000, day: 1, in: nov, currency: "EUR")
        func total(_ code: String, _ month: YearMonth) -> Int64 {
            h.view(month).totals.first { $0.currencyCode == code }?.scheduled ?? 0
        }
        #expect(MonthlyTrend.points(endingIn: nov) { total("EUR", $0) }.map(\.scheduled) == [90_000], "Dollars never appear in the euro chart")
        #expect(MonthlyTrend.points(endingIn: nov) { total("USD", $0) }.map(\.scheduled) == [100_000, 100_000])
    }
}

@Suite struct ThirdPartyNoticeTests {
    /// Settings no longer shows this, so the bundled file is what carries the MIT notice with the app.
    @Test func theCopilotIconsNoticeShipsInTheApp() throws {
        let url = try #require(Bundle(for: AppModel.self).url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("Copyright (c) 2026 GitHub Inc."))
        #expect(text.contains("The above copyright notice and this permission notice shall be included"))
        #expect(text.contains("WITHOUT WARRANTY OF ANY KIND"))
    }
}

@Suite struct CalendarDayLoadTests {
    @Test func dotsColorByHowManyPaymentsADayHas() {
        #expect(CalendarLayout.load(forPaymentCount: 0) == nil)
        #expect(CalendarLayout.load(forPaymentCount: 1) == .one)
        #expect(CalendarLayout.load(forPaymentCount: 2) == .two)
        #expect(CalendarLayout.load(forPaymentCount: 3) == .many)
        #expect(CalendarLayout.load(forPaymentCount: 7) == .many)
    }
}

@Suite struct BrandNameCorrectionTests {
    @Test(arguments: [
        ("netflix", "Netflix"),
        ("NETFLIX", "Netflix"),
        ("chatgpt", "ChatGPT"),
        ("Chatgpt", "ChatGPT"),
        ("tmobile", "T-Mobile"),
        ("t mobile", "T-Mobile"),
        ("disney+", "Disney+"),
    ])
    func aBrandIsWrittenTheCompanysWay(typed: String, expected: String) {
        #expect(BrandMatcher.correctedName(typed) == expected)
    }

    @Test func otherWordsStayAsTyped() {
        #expect(BrandMatcher.correctedName("netflix premium") == "Netflix premium")
        #expect(BrandMatcher.correctedName("tmobile Bill") == "T-Mobile Bill")
    }

    @Test func aShortFormIsntExpanded() {
        #expect(BrandMatcher.correctedName("Amex Platinum") == "Amex Platinum")
    }

    @Test(arguments: ["Rent", "piano lessons", "Chase Bakery", "netflix camera repair", ""])
    func anythingUnrecognizedIsLeftAlone(name: String) {
        #expect(BrandMatcher.correctedName(name) == name)
    }

    @Test func aTrailingSpaceSurvivesSoTypingCanContinue() {
        #expect(BrandMatcher.correctedName("netflix ") == "Netflix ")
    }

    @Test func correctingTwiceChangesNothingMore() {
        #expect(BrandMatcher.correctedName(BrandMatcher.correctedName("chatgpt")) == "ChatGPT")
    }
}

@Suite struct YearlyEstimateTests {
    @Test func itIsTwelveMonthsInMinorUnits() {
        #expect(usd(2_199).yearlyEstimate == usd(26_388), "$21.99 a month is $263.88 a year, with no rounding")
    }

    @Test func itKeepsTheCurrency() {
        #expect(Money(minorUnits: 500, currencyCode: "JPY").yearlyEstimate?.currencyCode == "JPY")
    }

    @Test func anAmountTooLargeToMultiplyGivesNoFigure() {
        #expect(usd(.max / 2).yearlyEstimate == nil)
    }
}
