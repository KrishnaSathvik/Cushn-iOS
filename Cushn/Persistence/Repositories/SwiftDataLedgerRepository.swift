import Foundation
import SwiftData

private typealias V1 = CushnSchemaV1

@MainActor
final class SwiftDataLedgerRepository: LedgerRepository {
    let context: ModelContext
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load() throws -> Ledger {
        var ledger = Ledger()
        for record in try context.fetch(FetchDescriptor<V1.PaymentRecord>()) {
            ledger.payments[record.id] = PaymentIdentity(id: record.id, createdMonth: YearMonth(ordinal: record.createdMonth),
                                                         createdAt: record.createdAt)
        }
        for record in try context.fetch(FetchDescriptor<V1.PaymentRevisionRecord>()) {
            ledger.paymentRevisions[record.paymentID, default: []].append(Self.revision(from: record))
        }
        for record in try context.fetch(FetchDescriptor<V1.CategoryRecord>()) {
            ledger.categories[record.id] = CategoryIdentity(id: record.id, createdMonth: YearMonth(ordinal: record.createdMonth),
                                                            isUserCreated: record.isUserCreated, createdAt: record.createdAt)
        }
        for record in try context.fetch(FetchDescriptor<V1.CategoryRevisionRecord>()) {
            ledger.categoryRevisions[record.categoryID, default: []].append(Self.revision(from: record))
        }
        for record in try context.fetch(FetchDescriptor<V1.StatusRecord>()) {
            guard let status = PaymentStatus(rawValue: record.status) else { continue }
            let value = PaymentMonthStatus(paymentID: record.paymentID, month: YearMonth(ordinal: record.month),
                                           status: status, confirmedAt: record.confirmedAt)
            ledger.statuses[value.key] = value
        }
        for record in try context.fetch(FetchDescriptor<V1.DismissalRecord>()) {
            ledger.dismissals[record.contextKey] = ReviewDismissal(contextKey: record.contextKey, dismissedAt: record.dismissedAt,
                                                                   lastSeenCount: record.lastSeenCount)
        }
        for key in ledger.paymentRevisions.keys {
            ledger.paymentRevisions[key]?.sort { $0.effectiveMonth < $1.effectiveMonth }
        }
        for key in ledger.categoryRevisions.keys {
            ledger.categoryRevisions[key]?.sort { $0.effectiveMonth < $1.effectiveMonth }
        }
        return ledger
    }

    func commit(_ mutations: [LedgerMutation]) throws {
        guard !mutations.isEmpty else { return }
        do {
            for mutation in mutations { try apply(mutation) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func recordCount<T: PersistentModel>(of type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    private func apply(_ mutation: LedgerMutation) throws {
        switch mutation {
        case .upsertPayment(let value):
            let id = value.id
            if try first(#Predicate<V1.PaymentRecord> { $0.id == id }) == nil {
                context.insert(V1.PaymentRecord(id: id, createdMonth: value.createdMonth.ordinal, createdAt: value.createdAt))
            }

        case .upsertPaymentRevision(let value):
            let id = value.id
            let record = try first(#Predicate<V1.PaymentRevisionRecord> { $0.id == id }) ?? {
                let new = V1.PaymentRevisionRecord(id: id, paymentID: value.paymentID,
                                                   effectiveMonth: value.effectiveMonth.ordinal, updatedAt: value.updatedAt)
                context.insert(new)
                return new
            }()
            record.name = value.name
            record.amountMinorUnits = value.amount?.minorUnits
            record.currencyCode = value.amount?.currencyCode
            record.dueDay = value.dueDay?.value
            record.categoryID = value.categoryID
            record.sortPosition = value.sortPosition
            record.isIncluded = value.isIncluded
            record.updatedAt = value.updatedAt

        case .deletePaymentRevision(let id, _):
            if let record = try first(#Predicate<V1.PaymentRevisionRecord> { $0.id == id }) { context.delete(record) }

        case .upsertCategory(let value):
            let id = value.id
            if try first(#Predicate<V1.CategoryRecord> { $0.id == id }) == nil {
                context.insert(V1.CategoryRecord(id: id, createdMonth: value.createdMonth.ordinal,
                                                 isUserCreated: value.isUserCreated, createdAt: value.createdAt))
            }

        case .upsertCategoryRevision(let value):
            let id = value.id
            let record = try first(#Predicate<V1.CategoryRevisionRecord> { $0.id == id }) ?? {
                let new = V1.CategoryRevisionRecord(id: id, categoryID: value.categoryID,
                                                    effectiveMonth: value.effectiveMonth.ordinal, updatedAt: value.updatedAt)
                context.insert(new)
                return new
            }()
            record.name = value.name
            record.sortPosition = value.sortPosition
            record.kind = value.kind?.rawValue
            record.isActive = value.isActive
            record.updatedAt = value.updatedAt

        case .deleteCategoryRevision(let id, _):
            if let record = try first(#Predicate<V1.CategoryRevisionRecord> { $0.id == id }) { context.delete(record) }

        case .upsertStatus(let value):
            let key = V1.StatusRecord.key(paymentID: value.paymentID, month: value.month.ordinal)
            if let record = try first(#Predicate<V1.StatusRecord> { $0.key == key }) {
                record.status = value.status.rawValue
                record.confirmedAt = value.confirmedAt
            } else {
                context.insert(V1.StatusRecord(paymentID: value.paymentID, month: value.month.ordinal,
                                               status: value.status.rawValue, confirmedAt: value.confirmedAt))
            }

        case .deleteStatus(let statusKey):
            let key = V1.StatusRecord.key(paymentID: statusKey.paymentID, month: statusKey.month.ordinal)
            if let record = try first(#Predicate<V1.StatusRecord> { $0.key == key }) { context.delete(record) }

        case .upsertDismissal(let value):
            let key = value.contextKey
            if let record = try first(#Predicate<V1.DismissalRecord> { $0.contextKey == key }) {
                record.dismissedAt = value.dismissedAt
                record.lastSeenCount = value.lastSeenCount
            } else {
                context.insert(V1.DismissalRecord(contextKey: key, dismissedAt: value.dismissedAt, lastSeenCount: value.lastSeenCount))
            }
        }
    }

    private func first<T: PersistentModel>(_ predicate: Predicate<T>) throws -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func revision(from record: V1.PaymentRevisionRecord) -> PaymentRevision {
        var amount: Money?
        if let minor = record.amountMinorUnits, let code = record.currencyCode {
            amount = Money(minorUnits: minor, currencyCode: code)
        }
        return PaymentRevision(id: record.id, paymentID: record.paymentID, effectiveMonth: YearMonth(ordinal: record.effectiveMonth),
                               name: record.name, amount: amount, dueDay: record.dueDay.flatMap { DueDay($0) },
                               categoryID: record.categoryID, sortPosition: record.sortPosition,
                               isIncluded: record.isIncluded, updatedAt: record.updatedAt)
    }

    private static func revision(from record: V1.CategoryRevisionRecord) -> CategoryRevision {
        CategoryRevision(id: record.id, categoryID: record.categoryID, effectiveMonth: YearMonth(ordinal: record.effectiveMonth),
                         name: record.name, sortPosition: record.sortPosition, kind: record.kind.flatMap { ReportingKind(rawValue: $0) },
                         isActive: record.isActive, updatedAt: record.updatedAt)
    }
}
