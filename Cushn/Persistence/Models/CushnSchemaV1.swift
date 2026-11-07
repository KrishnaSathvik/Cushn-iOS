import Foundation
import SwiftData

/// Schema version 1. Later schema changes get a new `VersionedSchema` and a stage in `CushnMigrationPlan`.
/// Records have no relationships, which keeps a future CloudKit evaluation open.
enum CushnSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [PaymentRecord.self, PaymentRevisionRecord.self, CategoryRecord.self,
         CategoryRevisionRecord.self, StatusRecord.self, DismissalRecord.self]
    }

    @Model final class PaymentRecord {
        @Attribute(.unique) var id: UUID
        var createdMonth: Int
        var createdAt: Date

        init(id: UUID, createdMonth: Int, createdAt: Date) {
            self.id = id
            self.createdMonth = createdMonth
            self.createdAt = createdAt
        }
    }

    @Model final class PaymentRevisionRecord {
        @Attribute(.unique) var id: UUID
        var paymentID: UUID
        var effectiveMonth: Int
        var name: String?
        var amountMinorUnits: Int64?
        var currencyCode: String?
        var dueDay: Int?
        var categoryID: UUID?
        var sortPosition: Int?
        var isIncluded: Bool?
        var updatedAt: Date

        init(id: UUID, paymentID: UUID, effectiveMonth: Int, updatedAt: Date) {
            self.id = id
            self.paymentID = paymentID
            self.effectiveMonth = effectiveMonth
            self.updatedAt = updatedAt
        }
    }

    @Model final class CategoryRecord {
        @Attribute(.unique) var id: UUID
        var createdMonth: Int
        var isUserCreated: Bool
        var createdAt: Date

        init(id: UUID, createdMonth: Int, isUserCreated: Bool, createdAt: Date) {
            self.id = id
            self.createdMonth = createdMonth
            self.isUserCreated = isUserCreated
            self.createdAt = createdAt
        }
    }

    @Model final class CategoryRevisionRecord {
        @Attribute(.unique) var id: UUID
        var categoryID: UUID
        var effectiveMonth: Int
        var name: String?
        var sortPosition: Int?
        var kind: String?
        var isActive: Bool?
        var updatedAt: Date

        init(id: UUID, categoryID: UUID, effectiveMonth: Int, updatedAt: Date) {
            self.id = id
            self.categoryID = categoryID
            self.effectiveMonth = effectiveMonth
            self.updatedAt = updatedAt
        }
    }

    /// `key` is the logical identity (payment + month), so duplicates can't exist.
    @Model final class StatusRecord {
        @Attribute(.unique) var key: String
        var paymentID: UUID
        var month: Int
        var status: String
        var confirmedAt: Date

        init(paymentID: UUID, month: Int, status: String, confirmedAt: Date) {
            key = Self.key(paymentID: paymentID, month: month)
            self.paymentID = paymentID
            self.month = month
            self.status = status
            self.confirmedAt = confirmedAt
        }

        static func key(paymentID: UUID, month: Int) -> String { "\(paymentID.uuidString)|\(month)" }
    }

    @Model final class DismissalRecord {
        @Attribute(.unique) var contextKey: String
        var dismissedAt: Date
        var lastSeenCount: Int

        init(contextKey: String, dismissedAt: Date, lastSeenCount: Int) {
            self.contextKey = contextKey
            self.dismissedAt = dismissedAt
            self.lastSeenCount = lastSeenCount
        }
    }
}
