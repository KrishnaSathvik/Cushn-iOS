import Foundation

struct MonthRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let amount: Money
    let nominalDueDay: DueDay
    let dueDate: CalendarDay
    let categoryID: UUID
    let reportingKind: ReportingKind
    let status: PaymentStatus
    let confirmedAt: Date?
}

struct MonthCategory: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let kind: ReportingKind
    let isUserCreated: Bool
    var isOther: Bool { id == SeedCategory.other.id }
}

struct MonthSection: Identifiable, Equatable, Sendable {
    let category: MonthCategory
    let rows: [MonthRow]
    var id: UUID { category.id }
    var title: String { category.title }
}

/// Totals are per currency. Amounts in different currencies are never added together.
struct CurrencyTotals: Identifiable, Equatable, Sendable {
    let currencyCode: String
    var scheduled: Int64 = 0
    var markedPaid: Int64 = 0
    var unconfirmed: Int64 = 0
    var skipped: Int64 = 0
    var id: String { currencyCode }
}

/// An immutable view of a month's list.
struct MonthView: Equatable, Sendable {
    let month: YearMonth
    /// Sections shown on Home: those with rows, plus user-created ones even when empty.
    let sections: [MonthSection]
    /// Every category active in this month, in order, including empty defaults.
    let allCategories: [MonthCategory]
    let totals: [CurrencyTotals]

    var rows: [MonthRow] { sections.flatMap(\.rows) }
    func row(_ id: UUID) -> MonthRow? { rows.first { $0.id == id } }
}

/// Pure projection of a month from the ledger. Never mutates storage, so browsing can't change data.
enum MonthProjector {
    static func project(month: YearMonth, ledger: Ledger) -> MonthView {
        let categories = activeCategories(month: month, ledger: ledger)
        let activeIDs = Set(categories.map(\.id))
        let kinds = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.kind) })

        var rowsByCategory: [UUID: [(position: Int, createdAt: Date, row: MonthRow)]] = [:]
        for identity in ledger.payments.values {
            guard let state = ledger.resolvedPayment(identity.id, at: month), state.isIncluded else { continue }
            // A row whose section was removed in this month is shown under Other.
            let categoryID = activeIDs.contains(state.categoryID) ? state.categoryID : SeedCategory.other.id
            let status = ledger.statuses[StatusKey(paymentID: identity.id, month: month)]
            let row = MonthRow(
                id: identity.id,
                name: state.name,
                amount: state.amount,
                nominalDueDay: state.dueDay,
                dueDate: state.dueDay.resolved(in: month),
                categoryID: categoryID,
                reportingKind: kinds[categoryID] ?? .unclassified,
                status: status?.status ?? .unconfirmed,
                confirmedAt: status?.confirmedAt
            )
            rowsByCategory[categoryID, default: []].append((state.sortPosition, identity.createdAt, row))
        }

        let sections: [MonthSection] = categories.compactMap { category in
            let rows = (rowsByCategory[category.id] ?? []).sorted { a, b in
                if a.position != b.position { return a.position < b.position }
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                return a.row.id.uuidString < b.row.id.uuidString
            }.map(\.row)
            guard !rows.isEmpty || category.isUserCreated else { return nil }
            return MonthSection(category: category, rows: rows)
        }

        return MonthView(month: month, sections: sections, allCategories: categories,
                         totals: totals(for: sections.flatMap(\.rows)))
    }

    private static func activeCategories(month: YearMonth, ledger: Ledger) -> [MonthCategory] {
        ledger.categories.values.compactMap { identity -> (Int, MonthCategory)? in
            guard let state = ledger.resolvedCategory(identity.id, at: month), state.isActive else { return nil }
            return (state.sortPosition, MonthCategory(id: identity.id, title: state.name, kind: state.kind,
                                                      isUserCreated: identity.isUserCreated))
        }
        .sorted { a, b in a.0 != b.0 ? a.0 < b.0 : a.1.id.uuidString < b.1.id.uuidString }
        .map(\.1)
    }

    private static func totals(for rows: [MonthRow]) -> [CurrencyTotals] {
        var byCurrency: [String: CurrencyTotals] = [:]
        for row in rows {
            let code = row.amount.currencyCode
            var totals = byCurrency[code] ?? CurrencyTotals(currencyCode: code)
            totals.scheduled += row.amount.minorUnits
            switch row.status {
            case .paid: totals.markedPaid += row.amount.minorUnits
            case .unconfirmed: totals.unconfirmed += row.amount.minorUnits
            case .skipped: totals.skipped += row.amount.minorUnits
            }
            byCurrency[code] = totals
        }
        return byCurrency.values.sorted { $0.currencyCode < $1.currencyCode }
    }
}
