import Foundation

enum PaymentStatus: String, Codable, Sendable, CaseIterable {
    case unconfirmed, paid, skipped
}

/// How a category's amounts count in "estimated expenses". Scheduled totals always include everything.
enum ReportingKind: String, Codable, Sendable, CaseIterable {
    case expense, creditRepayment, investment, transfer, unclassified
}

struct PaymentIdentity: Hashable, Codable, Sendable, Identifiable {
    let id: UUID
    let createdMonth: YearMonth
    let createdAt: Date
}

/// A sparse change effective from a month. Nil fields inherit from earlier revisions, so an edit
/// of one field can't overwrite other fields in later months. A payment has at most one revision per month.
struct PaymentRevision: Hashable, Codable, Sendable, Identifiable {
    let id: UUID
    let paymentID: UUID
    let effectiveMonth: YearMonth
    var name: String?
    var amount: Money?
    var dueDay: DueDay?
    var categoryID: UUID?
    var sortPosition: Int?
    var isIncluded: Bool?
    var updatedAt: Date
}

struct CategoryIdentity: Hashable, Codable, Sendable, Identifiable {
    let id: UUID
    let createdMonth: YearMonth
    let isUserCreated: Bool
    let createdAt: Date
}

/// A sparse category change, following the same rules as `PaymentRevision`.
struct CategoryRevision: Hashable, Codable, Sendable, Identifiable {
    let id: UUID
    let categoryID: UUID
    let effectiveMonth: YearMonth
    var name: String?
    var sortPosition: Int?
    var kind: ReportingKind?
    var isActive: Bool?
    var updatedAt: Date
}

struct StatusKey: Hashable, Codable, Sendable {
    let paymentID: UUID
    let month: YearMonth
}

/// An explicit user-recorded status for one month. No row means Unconfirmed.
struct PaymentMonthStatus: Hashable, Codable, Sendable {
    let paymentID: UUID
    let month: YearMonth
    var status: PaymentStatus
    var confirmedAt: Date
    var key: StatusKey { StatusKey(paymentID: paymentID, month: month) }
}

/// Records that a review prompt was dismissed. Never touches payment statuses.
struct ReviewDismissal: Hashable, Codable, Sendable {
    let contextKey: String
    var dismissedAt: Date
    var lastSeenCount: Int
}

/// Built-in default categories. IDs are fixed so that seeding stays idempotent.
enum SeedCategory: Int, CaseIterable, Sendable {
    case creditCards, subscriptions, housing, utilities, insurance, investments, transfers, other

    var id: UUID {
        UUID(uuidString: String(format: "C0000000-0000-4000-8000-%012d", rawValue + 1))!
    }

    var title: String {
        switch self {
        case .creditCards: "Credit Cards"
        case .subscriptions: "Subscriptions"
        case .housing: "Housing"
        case .utilities: "Utilities"
        case .insurance: "Insurance"
        case .investments: "Investments"
        case .transfers: "Transfers"
        case .other: "Other"
        }
    }

    var kind: ReportingKind {
        switch self {
        case .creditCards: .creditRepayment
        case .subscriptions, .housing, .utilities, .insurance: .expense
        case .investments: .investment
        case .transfers: .transfer
        case .other: .unclassified
        }
    }
}
