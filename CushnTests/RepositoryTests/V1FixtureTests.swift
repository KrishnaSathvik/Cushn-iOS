import Foundation
import Testing
@testable import Cushn

/// A frozen V1 store with synthetic data. Don't regenerate it after Cushn 1.0 ships: its value is that it was written by
/// V1 code. See `planning/V1_FIXTURE.md`.
private enum V1Fixture {
    final class BundleToken {}
    static let utc = TimeZone(identifier: "UTC")!
    /// Sept 2026 is before anything exists. Feb 2027 and Feb 2028 cover short months and a leap year.
    static let months = (0...18).map { YearMonth(year: 2026, month: 9)!.adding(months: $0) }

    struct Snapshot: Codable, Equatable {
        struct Row: Codable, Equatable {
            let name: String
            let minorUnits: Int64
            let currency: String
            let nominalDueDay: Int
            let dueDate: String
            let kind: String
            let status: String
            let confirmedAt: Double?
        }
        struct Section: Codable, Equatable {
            let title: String
            let rows: [Row]
        }
        struct Total: Codable, Equatable {
            let currency: String
            let scheduled: Int64
            let markedPaid: Int64
            let unconfirmed: Int64
            let skipped: Int64
        }
        let month: String
        let sections: [Section]
        let totals: [Total]
    }

    static func snapshot(_ month: YearMonth, ledger: Ledger) -> Snapshot {
        let view = MonthProjector.project(month: month, ledger: ledger)
        func date(_ day: CalendarDay) -> String { String(format: "%04d-%02d-%02d", day.year, day.month, day.day) }
        return Snapshot(
            month: String(format: "%04d-%02d", month.year, month.month),
            sections: view.sections.map { section in
                .init(title: section.title, rows: section.rows.map { row in
                    .init(name: row.name, minorUnits: row.amount.minorUnits, currency: row.amount.currencyCode,
                          nominalDueDay: row.nominalDueDay.value, dueDate: date(row.dueDate), kind: row.reportingKind.rawValue,
                          status: row.status.rawValue, confirmedAt: row.confirmedAt?.timeIntervalSince1970)
                })
            },
            totals: view.totals.map {
                .init(currency: $0.currencyCode, scheduled: $0.scheduled, markedPaid: $0.markedPaid,
                      unconfirmed: $0.unconfirmed, skipped: $0.skipped)
            }
        )
    }

    static func url(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext))
    }

    /// Opens a copy, because opening a store can change the file.
    @MainActor
    static func openCopy() throws -> (repository: SwiftDataLedgerRepository, ledger: Ledger) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "v1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: "Cushn.store")
        try FileManager.default.copyItem(at: url("CushnV1", "store"), to: copy)
        let repository = SwiftDataLedgerRepository(container: try CushnPersistence.makeContainer(url: copy))
        return (repository, try repository.load())
    }
}

@MainActor @Suite struct V1FixtureTests {
    private func rows(_ month: YearMonth, _ ledger: Ledger) -> [MonthRow] {
        MonthProjector.project(month: month, ledger: ledger).rows
    }
    private func row(_ name: String, _ month: YearMonth, _ ledger: Ledger) -> MonthRow? {
        rows(month, ledger).first { $0.name == name }
    }

    @Test func everyMonthMatchesTheRecordedProjection() throws {
        let (_, ledger) = try V1Fixture.openCopy()
        let data = try Data(contentsOf: V1Fixture.url("CushnV1.expected", "json"))
        let expected = try JSONDecoder().decode([V1Fixture.Snapshot].self, from: data)
        #expect(expected.count == V1Fixture.months.count)
        for (month, recorded) in zip(V1Fixture.months, expected) {
            #expect(V1Fixture.snapshot(month, ledger: ledger) == recorded, "\(recorded.month)")
        }
    }

    @Test func storeHasNoDamage() throws {
        let (repository, ledger) = try V1Fixture.openCopy()
        #expect(SeedCategory.allCases.allSatisfy { ledger.categories[$0.id] != nil })
        #expect(ledger.categories.count == 9)
        for id in ledger.payments.keys {
            let first = ledger.paymentRevisions[id]?.first
            #expect(first?.effectiveMonth == ledger.payments[id]?.createdMonth, "Each payment has its creation revision")
            let perMonth = (ledger.paymentRevisions[id] ?? []).map(\.effectiveMonth)
            #expect(Set(perMonth).count == perMonth.count, "At most one revision per month")
        }
        #expect(ledger.paymentRevisions.keys.allSatisfy { ledger.payments[$0] != nil }, "No orphaned revisions")
        #expect(ledger.statuses.values.allSatisfy { ledger.payments[$0.paymentID] != nil }, "No orphaned statuses")
        #expect(ledger.dismissals.count == 1)
        #expect(try repository.recordCount(of: CushnSchemaV1.PaymentRecord.self) == ledger.payments.count)
        #expect(try repository.recordCount(of: CushnSchemaV1.StatusRecord.self) == ledger.statuses.count)
    }

    /// Written by hand, so these hold even if the recorded JSON were somehow wrong.
    @Test func keyBehaviorsByHand() throws {
        let (_, l) = try V1Fixture.openCopy()
        // Nothing before the first month, and nothing appears in a month before it was added.
        #expect(rows(ym(2026, 9), l).isEmpty)
        #expect(row("Sample Gym", ym(2026, 11), l) == nil)
        #expect(row("Sample Gym", ym(2026, 12), l)?.amount == Money(minorUnits: 4_500, currencyCode: "EUR"))
        // Due day 31 in short months and a leap year.
        for (month, day) in [(ym(2026, 10), 31), (ym(2026, 11), 30), (ym(2027, 2), 28), (ym(2028, 2), 29)] {
            #expect(row("Sample Card", month, l)?.dueDate.day == day)
            #expect(row("Sample Card", month, l)?.nominalDueDay.value == 31)
        }
        // Statuses are per month, and a new month starts unconfirmed.
        #expect(row("Sample Rent", ym(2026, 10), l)?.status == .paid)
        #expect(row("Sample Rent", ym(2026, 12), l)?.status == .unconfirmed)
        #expect(row("Sample Card", ym(2026, 10), l)?.status == .skipped)
        // Undo leaves Unconfirmed with no confirmation time.
        #expect(row("Sample Streaming", ym(2026, 11), l)?.status == .unconfirmed)
        #expect(row("Sample Streaming", ym(2026, 11), l)?.confirmedAt == nil)
        // Skipped then changed to Paid.
        #expect(row("Sample Storage", ym(2026, 11), l)?.status == .paid)
        // An edit applies from its month, not before, even when made out of order.
        #expect(row("Sample Streaming", ym(2026, 12), l)?.amount.minorUnits == 1_299)
        #expect(row("Sample Streaming", ym(2027, 1), l)?.amount.minorUnits == 1_599)
        #expect(row("Sample Streaming", ym(2026, 11), l)?.amount.minorUnits == 999)
        // Removed from February, with history kept. The re-added one is a new payment with a clean history.
        #expect(row("Sample Storage", ym(2027, 1), l) != nil)
        #expect(row("Sample Storage", ym(2027, 2), l) == nil)
        #expect(row("Sample Storage", ym(2026, 10), l)?.status == .paid)
        let readded = try #require(row("Sample Storage", ym(2027, 4), l))
        #expect(readded.id != row("Sample Storage", ym(2027, 1), l)?.id)
        #expect(readded.status == .unconfirmed)
        // Currencies stay separate, and yen has no decimals.
        let december = MonthProjector.project(month: ym(2026, 12), ledger: l)
        #expect(december.totals.map(\.currencyCode) == ["EUR", "JPY", "USD"])
        #expect(row("Sample Storage", ym(2026, 11), l)?.amount == Money(minorUnits: 1_200, currencyCode: "JPY"))
        // A section renamed from January keeps its old name before that, and removal moves rows to Other.
        func section(_ month: YearMonth) -> String? {
            MonthProjector.project(month: month, ledger: l).sections.first { $0.rows.contains { $0.name == "Sample Class" } }?.title
        }
        #expect(section(ym(2026, 12)) == "Sample Projects")
        #expect(section(ym(2027, 1)) == "Sample Hobbies")
        #expect(section(ym(2027, 3)) == SeedCategory.other.title)
        // A reorder applies from its month.
        func order(_ month: YearMonth) -> [String] {
            MonthProjector.project(month: month, ledger: l).sections.first { $0.title == "Subscriptions" }?.rows.map(\.name) ?? []
        }
        #expect(order(ym(2027, 1)) == ["Sample Streaming", "Sample Music"])
        #expect(order(ym(2027, 2)) == ["Sample Music", "Sample Streaming"])
    }

    /// Run on purpose with TEST_RUNNER_CUSHN_WRITE_V1_FIXTURE=<folder>. Don't use after Cushn 1.0 ships.
    @Test func writeFixture() throws {
        guard let folder = ProcessInfo.processInfo.environment["CUSHN_WRITE_V1_FIXTURE"] else { return }
        let storeURL = URL(fileURLWithPath: folder).appending(path: "CushnV1.store")
        final class Clock: AppClock, @unchecked Sendable {
            var now = Date(timeIntervalSince1970: 1_790_000_000)
            let timeZone = V1Fixture.utc
        }
        let clock = Clock()
        let store = try LedgerStore(repository: SwiftDataLedgerRepository(container: try CushnPersistence.makeContainer(url: storeURL)), clock: clock)
        func tick() { clock.now.addTimeInterval(3_600) }
        func add(_ name: String, _ minor: Int64, _ code: String, day: Int, _ category: UUID, _ month: YearMonth) throws -> UUID {
            tick()
            return try store.add(PaymentDraft(name: name, amount: Money(minorUnits: minor, currencyCode: code), dueDay: DueDay(day)!, categoryID: category), month: month)
        }
        func set(_ status: PaymentStatus, _ id: UUID, _ month: YearMonth) throws {
            tick()
            try store.setStatus(status, id: id, month: month)
        }
        let (oct, nov, dec) = (ym(2026, 10), ym(2026, 11), ym(2026, 12))
        let (jan, feb, mar, apr) = (ym(2027, 1), ym(2027, 2), ym(2027, 3), ym(2027, 4))

        let rent = try add("Sample Rent", 185_000, "USD", day: 1, SeedCategory.housing.id, oct)
        let card = try add("Sample Card", 38_200, "USD", day: 31, SeedCategory.creditCards.id, oct)
        let streaming = try add("Sample Streaming", 999, "USD", day: 15, SeedCategory.subscriptions.id, oct)
        let music = try add("Sample Music", 1_199, "USD", day: 20, SeedCategory.subscriptions.id, oct)
        let storage = try add("Sample Storage", 1_200, "JPY", day: 10, SeedCategory.other.id, oct)

        try set(.paid, rent, oct)
        try set(.paid, rent, nov)
        try set(.skipped, card, oct)
        try set(.paid, storage, oct)
        // Undo, and a status changed from one mark to another.
        try set(.paid, streaming, nov)
        try set(.unconfirmed, streaming, nov)
        try set(.skipped, storage, nov)
        try set(.paid, storage, nov)

        // Edited out of order: January first, then December.
        tick()
        try store.edit(id: streaming, draft("Sample Streaming", usd(1_599), day: 15, category: SeedCategory.subscriptions.id), month: jan)
        tick()
        try store.edit(id: streaming, draft("Sample Streaming", usd(1_299), day: 15, category: SeedCategory.subscriptions.id), month: dec)

        _ = try add("Sample Gym", 4_500, "EUR", day: 20, SeedCategory.other.id, dec)

        tick()
        let section = try store.addCategory(name: "Sample Projects", month: nov)
        _ = try add("Sample Class", 12_000, "USD", day: 5, section, nov)
        tick()
        try store.renameCategory(id: section, name: "Sample Hobbies", month: jan)
        tick()
        try store.setCategoryKind(id: section, kind: .expense, month: jan)
        tick()
        try store.removeCategory(id: section, month: mar)

        tick()
        try store.reorderPayments([music, streaming], month: feb)

        tick()
        try store.remove(id: storage, month: feb)
        _ = try add("Sample Storage", 1_500, "JPY", day: 10, SeedCategory.other.id, apr)

        tick()
        try store.recordDismissal(ReviewDismissal(contextKey: "previousMonth|\(oct.ordinal)", dismissedAt: clock.now, lastSeenCount: 2))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let snapshots = V1Fixture.months.map { V1Fixture.snapshot($0, ledger: store.ledger) }
        try encoder.encode(snapshots).write(to: URL(fileURLWithPath: folder).appending(path: "CushnV1.expected.json"))
    }
}
