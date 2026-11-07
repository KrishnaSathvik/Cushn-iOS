import Foundation
import Observation

/// The app's single source of truth. Mutations are serialized on the main actor,
/// and in-memory state changes only after the repository has saved.
@Observable @MainActor
final class LedgerStore {
    private(set) var ledger: Ledger
    let clock: any AppClock

    @ObservationIgnored private let repository: any LedgerRepository
    @ObservationIgnored private var cache: [YearMonth: MonthView] = [:]
    /// Runs after every saved change. Reminders use it to stay in step with the list.
    @ObservationIgnored var onCommit: (@MainActor () -> Void)?

    init(repository: any LedgerRepository, clock: any AppClock) throws {
        self.repository = repository
        self.clock = clock
        var loaded = try repository.load()
        let seeds = LedgerCommands.seedMissingCategories(ledger: loaded, now: clock.now)
        if !seeds.isEmpty {
            try repository.commit(seeds)
            loaded.apply(seeds)
        }
        ledger = loaded
    }

    func view(for month: YearMonth) -> MonthView {
        // Reading `ledger` registers the observation even when the cache answers.
        let current = ledger
        if let cached = cache[month] { return cached }
        let view = MonthProjector.project(month: month, ledger: current)
        cache[month] = view
        return view
    }

    private func commit(_ mutations: [LedgerMutation]) throws {
        guard !mutations.isEmpty else { return }
        try repository.commit(mutations)
        cache.removeAll()
        ledger.apply(mutations)
        onCommit?()
    }

    // MARK: Payments

    @discardableResult
    func add(_ draft: PaymentDraft, month: YearMonth) throws -> UUID {
        let id = UUID()
        try commit(LedgerCommands.add(id: id, draft, month: month, ledger: ledger, now: clock.now))
        return id
    }

    func edit(id: UUID, _ draft: PaymentDraft, month: YearMonth) throws {
        try commit(LedgerCommands.edit(id: id, draft, month: month, ledger: ledger, now: clock.now))
    }

    func remove(id: UUID, month: YearMonth) throws {
        try commit(LedgerCommands.remove(id: id, month: month, ledger: ledger, now: clock.now))
    }

    func reorderPayments(_ ids: [UUID], month: YearMonth) throws {
        try commit(LedgerCommands.reorderPayments(ids, month: month, ledger: ledger, now: clock.now))
    }

    // MARK: Status

    func setStatus(_ status: PaymentStatus, id: UUID, month: YearMonth) throws {
        try commit(LedgerCommands.setStatus(status, id: id, month: month, ledger: ledger, now: clock.now))
    }

    /// Applies a status-circle tap. Returns `.openDetails` when the UI must ask instead.
    func tapStatusCircle(id: UUID, month: YearMonth) throws -> StatusCircleAction? {
        let current = ledger.statuses[StatusKey(paymentID: id, month: month)]?.status ?? .unconfirmed
        let action = StatusCircleAction.forTap(on: current)
        guard case .set(let status) = action else { return action }
        try setStatus(status, id: id, month: month)
        return nil
    }

    // MARK: Categories

    @discardableResult
    func addCategory(name: String, month: YearMonth) throws -> UUID {
        let id = UUID()
        try commit(LedgerCommands.addCategory(id: id, name: name, month: month, ledger: ledger, now: clock.now))
        return id
    }

    func renameCategory(id: UUID, name: String, month: YearMonth) throws {
        try commit(LedgerCommands.renameCategory(id: id, name: name, month: month, ledger: ledger, now: clock.now))
    }

    func setCategoryKind(id: UUID, kind: ReportingKind, month: YearMonth) throws {
        try commit(LedgerCommands.setCategoryKind(id: id, kind: kind, month: month, ledger: ledger, now: clock.now))
    }

    func reorderCategories(_ ids: [UUID], month: YearMonth) throws {
        try commit(LedgerCommands.reorderCategories(ids, month: month, ledger: ledger, now: clock.now))
    }

    func removeCategory(id: UUID, month: YearMonth) throws {
        try commit(LedgerCommands.removeCategory(id: id, month: month, ledger: ledger, now: clock.now))
    }

    // MARK: Review

    func recordDismissal(_ dismissal: ReviewDismissal) throws {
        try commit([.upsertDismissal(dismissal)])
    }
}
