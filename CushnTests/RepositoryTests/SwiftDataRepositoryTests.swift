import Foundation
import SwiftData
import Testing
@testable import Cushn

@MainActor
@Suite struct SwiftDataRepositoryTests {
    let nov = ym(2026, 11), dec = ym(2026, 12), jan = ym(2027, 1)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cushn-test-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("test.store")

    /// Opens the on-disk store fresh, the way a relaunch does.
    func openRepository() throws -> SwiftDataLedgerRepository {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return SwiftDataLedgerRepository(container: try CushnPersistence.makeContainer(url: url))
    }

    func commit(_ repo: SwiftDataLedgerRepository, _ ledger: inout Ledger, _ mutations: [LedgerMutation]) throws {
        try repo.commit(mutations)
        ledger.apply(mutations)
    }

    @Test func emptyStoreLoadsEmptyLedger() throws {
        #expect(try openRepository().load() == Ledger())
    }

    @Test func fullLedgerRoundTripsAcrossRelaunch() throws {
        var ledger = Ledger()
        var repo = try openRepository()
        try commit(repo, &ledger, LedgerCommands.seedMissingCategories(ledger: ledger, now: fixedNow))
        let travel = UUID()
        try commit(repo, &ledger, LedgerCommands.addCategory(id: travel, name: "Travel", month: nov, ledger: ledger, now: fixedNow))
        try commit(repo, &ledger, LedgerCommands.renameCategory(id: travel, name: "Trips", month: dec, ledger: ledger, now: fixedNow))
        let id = UUID()
        try commit(repo, &ledger, LedgerCommands.add(id: id, draft("Netflix", usd(3000), day: 31, category: travel), month: nov, ledger: ledger, now: fixedNow))
        try commit(repo, &ledger, LedgerCommands.edit(id: id, draft("Netflix", Money(minorUnits: 500, currencyCode: "JPY"), day: 31, category: travel), month: jan, ledger: ledger, now: fixedNow))
        try commit(repo, &ledger, LedgerCommands.setStatus(.paid, id: id, month: nov, ledger: ledger, now: fixedNow))
        try commit(repo, &ledger, LedgerCommands.setStatus(.skipped, id: id, month: dec, ledger: ledger, now: fixedNow))
        try commit(repo, &ledger, [.upsertDismissal(ReviewDismissal(contextKey: "k", dismissedAt: fixedNow, lastSeenCount: 3))])

        repo = try openRepository()
        #expect(try repo.load() == ledger)
    }

    @Test func outOfOrderEditsAfterRelaunchStayCorrect() throws {
        var ledger = Ledger()
        var repo = try openRepository()
        try commit(repo, &ledger, LedgerCommands.seedMissingCategories(ledger: ledger, now: fixedNow))
        let id = UUID()
        try commit(repo, &ledger, LedgerCommands.add(id: id, draft("Spotify", usd(1200), day: 15), month: nov, ledger: ledger, now: fixedNow))
        try commit(repo, &ledger, LedgerCommands.edit(id: id, draft("Spotify", usd(2000), day: 15), month: jan, ledger: ledger, now: fixedNow))

        repo = try openRepository()
        ledger = try repo.load()
        try commit(repo, &ledger, LedgerCommands.edit(id: id, draft("Spotify", usd(1500), day: 15), month: dec, ledger: ledger, now: fixedNow))

        repo = try openRepository()
        let reloaded = try repo.load()
        #expect(MonthProjector.project(month: nov, ledger: reloaded).row(id)?.amount == usd(1200))
        #expect(MonthProjector.project(month: dec, ledger: reloaded).row(id)?.amount == usd(1500))
        #expect(MonthProjector.project(month: jan, ledger: reloaded).row(id)?.amount == usd(2000))
    }

    @Test func removalDeletesLaterRevisionsInStorageToo() throws {
        var ledger = Ledger()
        var repo = try openRepository()
        try commit(repo, &ledger, LedgerCommands.seedMissingCategories(ledger: ledger, now: fixedNow))
        let id = UUID()
        try commit(repo, &ledger, LedgerCommands.add(id: id, draft("Netflix", usd(3000), day: 28), month: nov, ledger: ledger, now: fixedNow))
        try commit(repo, &ledger, LedgerCommands.setStatus(.paid, id: id, month: nov, ledger: ledger, now: fixedNow))
        try commit(repo, &ledger, LedgerCommands.edit(id: id, draft("Netflix", usd(3500), day: 28), month: jan, ledger: ledger, now: fixedNow))
        try commit(repo, &ledger, LedgerCommands.remove(id: id, month: dec, ledger: ledger, now: fixedNow))

        repo = try openRepository()
        let reloaded = try repo.load()
        #expect(reloaded == ledger)
        #expect(MonthProjector.project(month: nov, ledger: reloaded).row(id)?.status == .paid)
        #expect(MonthProjector.project(month: jan, ledger: reloaded).row(id) == nil)
    }

    @Test func repeatedStatusUpsertsLeaveOneRecord() throws {
        let repo = try openRepository()
        let id = UUID()
        let paid = PaymentMonthStatus(paymentID: id, month: nov, status: .paid, confirmedAt: fixedNow)
        for _ in 0..<5 { try repo.commit([.upsertStatus(paid)]) }
        var skipped = paid; skipped.status = .skipped
        try repo.commit([.upsertStatus(skipped)])
        #expect(try repo.recordCount(of: CushnSchemaV1.StatusRecord.self) == 1)
        #expect(try repo.load().statuses[paid.key]?.status == .skipped)
        try repo.commit([.deleteStatus(paid.key)])
        #expect(try repo.recordCount(of: CushnSchemaV1.StatusRecord.self) == 0)
    }

    @Test func statusesForDifferentMonthsAreSeparateRecords() throws {
        let repo = try openRepository()
        let id = UUID()
        try repo.commit([.upsertStatus(PaymentMonthStatus(paymentID: id, month: nov, status: .paid, confirmedAt: fixedNow)),
                         .upsertStatus(PaymentMonthStatus(paymentID: id, month: dec, status: .skipped, confirmedAt: fixedNow))])
        #expect(try repo.recordCount(of: CushnSchemaV1.StatusRecord.self) == 2)
    }

    @Test func revisionUpsertUpdatesInPlace() throws {
        let repo = try openRepository()
        let id = UUID()
        var revision = PaymentRevision(id: UUID(), paymentID: id, effectiveMonth: nov, name: "A", amount: usd(1),
                                       dueDay: DueDay(1), categoryID: SeedCategory.other.id, sortPosition: 0,
                                       isIncluded: true, updatedAt: fixedNow)
        try repo.commit([.upsertPaymentRevision(revision)])
        revision.name = "B"
        try repo.commit([.upsertPaymentRevision(revision)])
        #expect(try repo.recordCount(of: CushnSchemaV1.PaymentRevisionRecord.self) == 1)
        #expect(try repo.load().paymentRevisions[id]?.first?.name == "B")
    }

    @Test func largeHistoryLoadsAndProjectsWithinBudget() throws {
        // 150 payments with 10 years of statuses: the largest fixture in the acceptance matrix.
        var ledger = Ledger()
        let repo = try openRepository()
        var batch = LedgerCommands.seedMissingCategories(ledger: ledger, now: fixedNow)
        ledger.apply(batch)
        for index in 0..<150 {
            let id = UUID()
            let add = try LedgerCommands.add(id: id, draft("Payment \(index)", usd(Int64(index) * 100), day: index % 31 + 1),
                                             month: ym(2020, 1), ledger: ledger, now: fixedNow)
            ledger.apply(add)
            batch += add
            for offset in 0..<120 {
                repo.context.insert(CushnSchemaV1.StatusRecord(paymentID: id, month: ym(2020, 1).adding(months: offset).ordinal,
                                                               status: "paid", confirmedAt: fixedNow))
            }
        }
        try repo.commit(batch)

        let clock = ContinuousClock()
        var loaded = Ledger()
        let loadTime = clock.measure { loaded = (try? repo.load()) ?? Ledger() }
        let projectTime = clock.measure { _ = MonthProjector.project(month: ym(2026, 11), ledger: loaded) }
        #expect(loaded.statuses.count == 18_000)
        #expect(loadTime < .seconds(3), "load took \(loadTime)")
        #expect(projectTime < .milliseconds(50), "projection took \(projectTime)")
    }
}
