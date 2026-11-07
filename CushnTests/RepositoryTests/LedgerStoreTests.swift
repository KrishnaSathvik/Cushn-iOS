import Foundation
import Testing
@testable import Cushn

/// A repository whose saves can be made to fail, to exercise the durability rule.
@MainActor
final class FlakyRepository: LedgerRepository {
    var stored = Ledger()
    var shouldFail = false
    struct SaveFailed: Error {}

    func load() throws -> Ledger { stored }
    func commit(_ mutations: [LedgerMutation]) throws {
        if shouldFail { throw SaveFailed() }
        stored.apply(mutations)
    }
}

@MainActor
@Suite struct LedgerStoreTests {
    let nov = ym(2026, 11), dec = ym(2026, 12)

    func makeStore(_ repo: FlakyRepository = FlakyRepository()) throws -> LedgerStore {
        try LedgerStore(repository: repo, clock: FixedClock(now: fixedNow))
    }

    @Test func seedsDefaultsOnFirstLoadAndPersistsThem() throws {
        let repo = FlakyRepository()
        let store = try makeStore(repo)
        #expect(!store.ledger.categories.isEmpty)
        #expect(repo.stored == store.ledger)
    }

    @Test func failedSaveLeavesVisibleStateUnchanged() throws {
        let repo = FlakyRepository()
        let store = try makeStore(repo)
        let id = try store.add(draft("Netflix", usd(3000), day: 28), month: nov)
        repo.shouldFail = true
        #expect(throws: FlakyRepository.SaveFailed.self) { try store.setStatus(.paid, id: id, month: nov) }
        #expect(store.view(for: nov).row(id)?.status == .unconfirmed)
    }

    @Test func viewsRefreshAfterCommitIncludingCachedLaterMonths() throws {
        let store = try makeStore()
        #expect(store.view(for: dec).rows.isEmpty)
        let id = try store.add(draft("Netflix", usd(3000), day: 28), month: nov)
        #expect(store.view(for: dec).row(id) != nil)
    }

    @Test func browsingWritesNothing() throws {
        let repo = FlakyRepository()
        let store = try makeStore(repo)
        let before = repo.stored
        for offset in -24...24 { _ = store.view(for: nov.adding(months: offset)) }
        #expect(repo.stored == before)
    }

    @Test func tappingCircleFollowsStatusRules() throws {
        let store = try makeStore()
        let id = try store.add(draft("Netflix", usd(3000), day: 28), month: nov)
        #expect(try store.tapStatusCircle(id: id, month: nov) == nil)
        #expect(store.view(for: nov).row(id)?.status == .paid)
        #expect(try store.tapStatusCircle(id: id, month: nov) == nil)
        #expect(store.view(for: nov).row(id)?.status == .unconfirmed)
        try store.setStatus(.skipped, id: id, month: nov)
        #expect(try store.tapStatusCircle(id: id, month: nov) == .openDetails)
        #expect(store.view(for: nov).row(id)?.status == .skipped)
    }
}

final class MutableClock: AppClock, @unchecked Sendable {
    var now: Date
    let timeZone = TimeZone(identifier: "UTC")!
    init(_ day: CalendarDay) { now = day.date(in: timeZone) }
    func set(_ day: CalendarDay) { now = day.date(in: timeZone) }
}

@MainActor
@Suite struct AppModelRolloverTests {
    func make(_ clock: MutableClock) throws -> AppModel {
        AppModel(store: try LedgerStore(repository: InMemoryLedgerRepository(), clock: clock))
    }

    @Test func opensOnCurrentLocalMonth() throws {
        let model = try make(MutableClock(CalendarDay(year: 2026, month: 11, day: 15)))
        #expect(model.selectedMonth == ym(2026, 11))
    }

    @Test func viewerOnCurrentMonthFollowsRolloverWithoutStatusCarry() throws {
        let clock = MutableClock(CalendarDay(year: 2026, month: 12, day: 31))
        let model = try make(clock)
        let id = try model.store.add(draft("Rent", usd(100), day: 1), month: ym(2026, 12))
        try model.store.setStatus(.paid, id: id, month: ym(2026, 12))
        clock.set(CalendarDay(year: 2027, month: 1, day: 1))
        model.refreshDate()
        #expect(model.selectedMonth == ym(2027, 1))
        #expect(model.store.view(for: ym(2027, 1)).row(id)?.status == .unconfirmed)
        #expect(model.store.view(for: ym(2026, 12)).row(id)?.status == .paid)
    }

    @Test func viewerBrowsingAnotherMonthStaysThereAfterRollover() throws {
        let clock = MutableClock(CalendarDay(year: 2026, month: 11, day: 30))
        let model = try make(clock)
        model.selectedMonth = ym(2026, 6)
        clock.set(CalendarDay(year: 2026, month: 12, day: 1))
        model.refreshDate()
        #expect(model.selectedMonth == ym(2026, 6))
        #expect(model.currentMonth == ym(2026, 12))
    }

    @Test func monthNavigationStaysInRange() throws {
        let model = try make(MutableClock(CalendarDay(year: 2026, month: 11, day: 15)))
        model.selectedMonth = .origin
        model.shiftMonth(by: -1)
        #expect(model.selectedMonth == .origin)
        model.selectedMonth = .latest
        model.shiftMonth(by: 1)
        #expect(model.selectedMonth == .latest)
    }
}
