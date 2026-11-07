import Foundation

/// One atomic storage change. Commands emit these, and repositories commit a batch transactionally.
enum LedgerMutation: Hashable, Sendable {
    case upsertPayment(PaymentIdentity)
    case upsertPaymentRevision(PaymentRevision)
    case deletePaymentRevision(id: UUID, paymentID: UUID)
    case upsertCategory(CategoryIdentity)
    case upsertCategoryRevision(CategoryRevision)
    case deleteCategoryRevision(id: UUID, categoryID: UUID)
    case upsertStatus(PaymentMonthStatus)
    case deleteStatus(StatusKey)
    case upsertDismissal(ReviewDismissal)
}

/// The complete user data as a value. Month views are always derived from it, never stored.
struct Ledger: Equatable, Sendable {
    var payments: [UUID: PaymentIdentity] = [:]
    /// Sorted ascending by effective month.
    var paymentRevisions: [UUID: [PaymentRevision]] = [:]
    var categories: [UUID: CategoryIdentity] = [:]
    /// Sorted ascending by effective month.
    var categoryRevisions: [UUID: [CategoryRevision]] = [:]
    var statuses: [StatusKey: PaymentMonthStatus] = [:]
    var dismissals: [String: ReviewDismissal] = [:]

    static func seeded(now: Date) -> Ledger {
        var ledger = Ledger()
        ledger.apply(LedgerCommands.seedMissingCategories(ledger: ledger, now: now))
        return ledger
    }

    mutating func apply(_ mutations: [LedgerMutation]) {
        for mutation in mutations { apply(mutation) }
    }

    private mutating func apply(_ mutation: LedgerMutation) {
        switch mutation {
        case .upsertPayment(let payment):
            payments[payment.id] = payment
        case .upsertPaymentRevision(let revision):
            var list = paymentRevisions[revision.paymentID, default: []]
            list.removeAll { $0.id == revision.id }
            list.append(revision)
            list.sort { $0.effectiveMonth < $1.effectiveMonth }
            paymentRevisions[revision.paymentID] = list
        case .deletePaymentRevision(let id, let paymentID):
            paymentRevisions[paymentID]?.removeAll { $0.id == id }
        case .upsertCategory(let category):
            categories[category.id] = category
        case .upsertCategoryRevision(let revision):
            var list = categoryRevisions[revision.categoryID, default: []]
            list.removeAll { $0.id == revision.id }
            list.append(revision)
            list.sort { $0.effectiveMonth < $1.effectiveMonth }
            categoryRevisions[revision.categoryID] = list
        case .deleteCategoryRevision(let id, let categoryID):
            categoryRevisions[categoryID]?.removeAll { $0.id == id }
        case .upsertStatus(let status):
            statuses[status.key] = status
        case .deleteStatus(let key):
            statuses[key] = nil
        case .upsertDismissal(let dismissal):
            dismissals[dismissal.contextKey] = dismissal
        }
    }
}

/// A payment's fields as they apply in a given month.
struct ResolvedPayment: Equatable, Sendable {
    var name: String
    var amount: Money
    var dueDay: DueDay
    var categoryID: UUID
    var sortPosition: Int
    var isIncluded: Bool
}

struct ResolvedCategory: Equatable, Sendable {
    var name: String
    var sortPosition: Int
    var kind: ReportingKind
    var isActive: Bool
}

extension Ledger {
    /// Applies each revision up to `month` in order. Later values win field by field.
    func resolvedPayment(_ id: UUID, at month: YearMonth) -> ResolvedPayment? {
        guard let identity = payments[id], identity.createdMonth <= month else { return nil }
        var name: String?, amount: Money?, dueDay: DueDay?, categoryID: UUID?, position: Int?, included: Bool?
        for revision in paymentRevisions[id] ?? [] {
            guard revision.effectiveMonth <= month else { break }
            name = revision.name ?? name
            amount = revision.amount ?? amount
            dueDay = revision.dueDay ?? dueDay
            categoryID = revision.categoryID ?? categoryID
            position = revision.sortPosition ?? position
            included = revision.isIncluded ?? included
        }
        guard let name, let amount, let dueDay, let categoryID, let position, let included else { return nil }
        return ResolvedPayment(name: name, amount: amount, dueDay: dueDay, categoryID: categoryID,
                               sortPosition: position, isIncluded: included)
    }

    func resolvedCategory(_ id: UUID, at month: YearMonth) -> ResolvedCategory? {
        guard let identity = categories[id], identity.createdMonth <= month else { return nil }
        var name: String?, position: Int?, kind: ReportingKind?, active: Bool?
        for revision in categoryRevisions[id] ?? [] {
            guard revision.effectiveMonth <= month else { break }
            name = revision.name ?? name
            position = revision.sortPosition ?? position
            kind = revision.kind ?? kind
            active = revision.isActive ?? active
        }
        guard let name, let position, let kind, let active else { return nil }
        return ResolvedCategory(name: name, sortPosition: position, kind: kind, isActive: active)
    }
}
