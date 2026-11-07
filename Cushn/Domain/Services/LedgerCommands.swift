import Foundation

enum LedgerError: Error, Equatable {
    case emptyName, negativeAmount, paymentNotVisible, categoryNotActive, cannotRemoveOther
}

struct PaymentDraft: Equatable, Sendable {
    var name: String
    var amount: Money
    var dueDay: DueDay
    var categoryID: UUID
}

/// What tapping the trailing status circle does. Skipped never toggles by accident:
/// leaving it requires an explicit choice in details.
enum StatusCircleAction: Equatable, Sendable {
    case set(PaymentStatus)
    case openDetails

    static func forTap(on status: PaymentStatus) -> StatusCircleAction {
        switch status {
        case .unconfirmed: .set(.paid)
        case .paid: .set(.unconfirmed)
        case .skipped: .openDetails
        }
    }
}

/// Pure commands. Each validates against a ledger and returns the mutations to commit atomically.
/// Nothing changes until the mutations are applied, so a cancelled action has no effect.
enum LedgerCommands {

    // MARK: Payments

    static func add(id: UUID, _ draft: PaymentDraft, month: YearMonth, ledger: Ledger, now: Date) throws -> [LedgerMutation] {
        let name = try validatedName(draft.name)
        try validate(amount: draft.amount)
        let categoryID = activeCategory(draft.categoryID, month: month, ledger: ledger)
        let revision = PaymentRevision(
            id: UUID(), paymentID: id, effectiveMonth: month,
            name: name, amount: draft.amount, dueDay: draft.dueDay, categoryID: categoryID,
            sortPosition: endPosition(in: categoryID, month: month, ledger: ledger, excluding: nil),
            isIncluded: true, updatedAt: now
        )
        return [.upsertPayment(PaymentIdentity(id: id, createdMonth: month, createdAt: now)),
                .upsertPaymentRevision(revision)]
    }

    /// Writes only the fields that differ from the month's current values, effective from `month`.
    static func edit(id: UUID, _ draft: PaymentDraft, month: YearMonth, ledger: Ledger, now: Date) throws -> [LedgerMutation] {
        let current = try visiblePayment(id, month: month, ledger: ledger)
        let name = try validatedName(draft.name)
        try validate(amount: draft.amount)
        let currentCategory = activeCategory(current.categoryID, month: month, ledger: ledger)
        let targetCategory = activeCategory(draft.categoryID, month: month, ledger: ledger)

        let changes = PaymentFields(
            name: name != current.name ? name : nil,
            amount: draft.amount != current.amount ? draft.amount : nil,
            dueDay: draft.dueDay != current.dueDay ? draft.dueDay : nil,
            categoryID: targetCategory != currentCategory ? targetCategory : nil,
            sortPosition: targetCategory != currentCategory
                ? endPosition(in: targetCategory, month: month, ledger: ledger, excluding: id) : nil
        )
        guard !changes.isEmpty else { return [] }
        return [.upsertPaymentRevision(mergedRevision(id, month: month, ledger: ledger, now: now, changes))]
    }

    /// V1 removal policy: tombstone from `month` and drop later revisions, so saved future edits can't
    /// bring the payment back. Earlier revisions and all statuses are preserved.
    static func remove(id: UUID, month: YearMonth, ledger: Ledger, now: Date) throws -> [LedgerMutation] {
        _ = try visiblePayment(id, month: month, ledger: ledger)
        let later = (ledger.paymentRevisions[id] ?? []).filter { $0.effectiveMonth > month }
        return later.map { .deletePaymentRevision(id: $0.id, paymentID: id) }
            + [.upsertPaymentRevision(mergedRevision(id, month: month, ledger: ledger, now: now,
                                                     PaymentFields(isIncluded: false)))]
    }

    /// Sets row order within a section, effective from `month`. `orderedIDs` is the section's full order.
    static func reorderPayments(_ orderedIDs: [UUID], month: YearMonth, ledger: Ledger, now: Date) throws -> [LedgerMutation] {
        try orderedIDs.enumerated().compactMap { index, id in
            let current = try visiblePayment(id, month: month, ledger: ledger)
            guard current.sortPosition != index else { return nil }
            return .upsertPaymentRevision(mergedRevision(id, month: month, ledger: ledger, now: now,
                                                         PaymentFields(sortPosition: index)))
        }
    }

    // MARK: Statuses

    /// Status belongs to one month only. Repeating the same status writes nothing,
    /// so rapid taps can't create duplicates or move the confirmation time.
    static func setStatus(_ status: PaymentStatus, id: UUID, month: YearMonth, ledger: Ledger, now: Date) throws -> [LedgerMutation] {
        _ = try visiblePayment(id, month: month, ledger: ledger)
        let key = StatusKey(paymentID: id, month: month)
        let existing = ledger.statuses[key]
        switch status {
        case .unconfirmed:
            return existing == nil ? [] : [.deleteStatus(key)]
        case .paid, .skipped:
            guard existing?.status != status else { return [] }
            return [.upsertStatus(PaymentMonthStatus(paymentID: id, month: month, status: status, confirmedAt: now))]
        }
    }

    // MARK: Categories

    static func seedMissingCategories(ledger: Ledger, now: Date) -> [LedgerMutation] {
        SeedCategory.allCases.filter { ledger.categories[$0.id] == nil }.flatMap { seed -> [LedgerMutation] in
            [.upsertCategory(CategoryIdentity(id: seed.id, createdMonth: .origin, isUserCreated: false, createdAt: now)),
             .upsertCategoryRevision(CategoryRevision(
                id: UUID(), categoryID: seed.id, effectiveMonth: .origin, name: seed.title,
                sortPosition: seed.rawValue, kind: seed.kind, isActive: true, updatedAt: now))]
        }
    }

    /// New sections go just above Other, which stays last until the user moves it.
    static func addCategory(id: UUID, name: String, month: YearMonth, ledger: Ledger, now: Date) throws -> [LedgerMutation] {
        let name = try validatedName(name)
        let otherID = SeedCategory.other.id
        let otherPosition = ledger.resolvedCategory(otherID, at: month)?.sortPosition ?? Int.max - 1
        let highest = ledger.categories.keys
            .filter { $0 != otherID }
            .compactMap { id in ledger.resolvedCategory(id, at: month).flatMap { $0.isActive ? $0.sortPosition : nil } }
            .max() ?? -1
        let position = highest + 1
        var mutations: [LedgerMutation] = [
            .upsertCategory(CategoryIdentity(id: id, createdMonth: month, isUserCreated: true, createdAt: now)),
            .upsertCategoryRevision(CategoryRevision(
                id: UUID(), categoryID: id, effectiveMonth: month, name: name,
                sortPosition: position, kind: .unclassified, isActive: true, updatedAt: now))
        ]
        if otherPosition <= position {
            mutations.append(.upsertCategoryRevision(
                mergedCategoryRevision(otherID, month: month, ledger: ledger, now: now) { $0.sortPosition = position + 1 }))
        }
        return mutations
    }

    static func renameCategory(id: UUID, name: String, month: YearMonth, ledger: Ledger, now: Date) throws -> [LedgerMutation] {
        let name = try validatedName(name)
        try requireActive(id, month: month, ledger: ledger)
        return [.upsertCategoryRevision(mergedCategoryRevision(id, month: month, ledger: ledger, now: now) { $0.name = name })]
    }

    static func setCategoryKind(id: UUID, kind: ReportingKind, month: YearMonth, ledger: Ledger, now: Date) throws -> [LedgerMutation] {
        try requireActive(id, month: month, ledger: ledger)
        return [.upsertCategoryRevision(mergedCategoryRevision(id, month: month, ledger: ledger, now: now) { $0.kind = kind })]
    }

    static func reorderCategories(_ orderedIDs: [UUID], month: YearMonth, ledger: Ledger, now: Date) throws -> [LedgerMutation] {
        try orderedIDs.enumerated().compactMap { index, id in
            try requireActive(id, month: month, ledger: ledger)
            guard ledger.resolvedCategory(id, at: month)?.sortPosition != index else { return nil }
            return .upsertCategoryRevision(mergedCategoryRevision(id, month: month, ledger: ledger, now: now) { $0.sortPosition = index })
        }
    }

    /// Removes a section from `month` onward. Its rows appear under Other from that month; earlier months are unchanged.
    static func removeCategory(id: UUID, month: YearMonth, ledger: Ledger, now: Date) throws -> [LedgerMutation] {
        guard id != SeedCategory.other.id else { throw LedgerError.cannotRemoveOther }
        try requireActive(id, month: month, ledger: ledger)
        let later = (ledger.categoryRevisions[id] ?? []).filter { $0.effectiveMonth > month }
        return later.map { .deleteCategoryRevision(id: $0.id, categoryID: id) }
            + [.upsertCategoryRevision(mergedCategoryRevision(id, month: month, ledger: ledger, now: now) { $0.isActive = false })]
    }

    // MARK: Helpers

    private struct PaymentFields {
        var name: String?, amount: Money?, dueDay: DueDay?, categoryID: UUID?, sortPosition: Int?, isIncluded: Bool?
        var isEmpty: Bool {
            name == nil && amount == nil && dueDay == nil && categoryID == nil && sortPosition == nil && isIncluded == nil
        }
    }

    /// Merges into the month's existing revision, keeping at most one revision per payment per month.
    private static func mergedRevision(_ id: UUID, month: YearMonth, ledger: Ledger, now: Date, _ fields: PaymentFields) -> PaymentRevision {
        var revision = ledger.paymentRevisions[id]?.first { $0.effectiveMonth == month }
            ?? PaymentRevision(id: UUID(), paymentID: id, effectiveMonth: month, updatedAt: now)
        revision.name = fields.name ?? revision.name
        revision.amount = fields.amount ?? revision.amount
        revision.dueDay = fields.dueDay ?? revision.dueDay
        revision.categoryID = fields.categoryID ?? revision.categoryID
        revision.sortPosition = fields.sortPosition ?? revision.sortPosition
        revision.isIncluded = fields.isIncluded ?? revision.isIncluded
        revision.updatedAt = now
        return revision
    }

    private static func mergedCategoryRevision(_ id: UUID, month: YearMonth, ledger: Ledger, now: Date,
                                               _ change: (inout CategoryRevision) -> Void) -> CategoryRevision {
        var revision = ledger.categoryRevisions[id]?.first { $0.effectiveMonth == month }
            ?? CategoryRevision(id: UUID(), categoryID: id, effectiveMonth: month, updatedAt: now)
        change(&revision)
        revision.updatedAt = now
        return revision
    }

    private static func visiblePayment(_ id: UUID, month: YearMonth, ledger: Ledger) throws -> ResolvedPayment {
        guard let state = ledger.resolvedPayment(id, at: month), state.isIncluded else {
            throw LedgerError.paymentNotVisible
        }
        return state
    }

    private static func requireActive(_ id: UUID, month: YearMonth, ledger: Ledger) throws {
        guard ledger.resolvedCategory(id, at: month)?.isActive == true else { throw LedgerError.categoryNotActive }
    }

    private static func activeCategory(_ id: UUID, month: YearMonth, ledger: Ledger) -> UUID {
        ledger.resolvedCategory(id, at: month)?.isActive == true ? id : SeedCategory.other.id
    }

    private static func endPosition(in categoryID: UUID, month: YearMonth, ledger: Ledger, excluding: UUID?) -> Int {
        let positions = ledger.payments.keys.compactMap { id -> Int? in
            guard id != excluding, let state = ledger.resolvedPayment(id, at: month), state.isIncluded,
                  activeCategory(state.categoryID, month: month, ledger: ledger) == categoryID else { return nil }
            return state.sortPosition
        }
        return (positions.max() ?? -1) + 1
    }

    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LedgerError.emptyName }
        return trimmed
    }

    private static func validate(amount: Money) throws {
        guard amount.minorUnits >= 0 else { throw LedgerError.negativeAmount }
    }
}
