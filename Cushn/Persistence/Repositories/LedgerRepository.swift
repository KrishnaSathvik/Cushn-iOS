import Foundation

@MainActor
protocol LedgerRepository: AnyObject {
    func load() throws -> Ledger
    /// Commits a batch atomically: after a throw, nothing from the batch is stored.
    func commit(_ mutations: [LedgerMutation]) throws
}

/// Non-persistent repository for previews, demos and UI tests.
@MainActor
final class InMemoryLedgerRepository: LedgerRepository {
    private var stored: Ledger
    init(_ ledger: Ledger = Ledger()) { stored = ledger }
    func load() throws -> Ledger { stored }
    func commit(_ mutations: [LedgerMutation]) throws { stored.apply(mutations) }
}
