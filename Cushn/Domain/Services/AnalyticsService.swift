import Foundation

struct CategoryBreakdown: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    var scheduled: Int64
    var markedPaid: Int64
}

/// Amounts by how they count as money flowing out. Every scheduled amount lands in exactly one bucket.
struct FlowBreakdown: Equatable, Sendable {
    var estimatedExpenses: Int64 = 0
    var creditRepayments: Int64 = 0
    var investments: Int64 = 0
    var transfers: Int64 = 0
    var unclassified: Int64 = 0
}

/// Same metric, same currency, consecutive months.
struct MetricComparison: Equatable, Sendable {
    let current: Int64
    let previous: Int64
    var delta: Int64 { current - previous }
    /// Nil when the previous value is zero, because there's no valid denominator.
    var percent: Double? { previous == 0 ? nil : Double(delta) / Double(previous) * 100 }
    var isNew: Bool { previous == 0 && current > 0 }
}

/// A month's figures for one currency, based only on user-entered amounts and user-recorded statuses.
struct CurrencyOverview: Identifiable, Equatable, Sendable {
    let totals: CurrencyTotals
    let rowCount: Int
    let paidCount: Int
    let categories: [CategoryBreakdown]
    let flows: FlowBreakdown
    let scheduledComparison: MetricComparison
    var currencyCode: String { totals.currencyCode }
    var id: String { currencyCode }
}

enum AnalyticsService {
    static func overview(for view: MonthView, previous: MonthView) -> [CurrencyOverview] {
        view.totals.map { totals in
            let code = totals.currencyCode
            let rows = view.rows.filter { $0.amount.currencyCode == code }

            let categories: [CategoryBreakdown] = view.sections.compactMap { section in
                let sectionRows = section.rows.filter { $0.amount.currencyCode == code }
                guard !sectionRows.isEmpty else { return nil }
                return CategoryBreakdown(
                    id: section.id,
                    title: section.title,
                    scheduled: sectionRows.reduce(0) { $0 + $1.amount.minorUnits },
                    markedPaid: sectionRows.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount.minorUnits }
                )
            }

            var flows = FlowBreakdown()
            for row in rows {
                switch row.reportingKind {
                case .expense: flows.estimatedExpenses += row.amount.minorUnits
                case .creditRepayment: flows.creditRepayments += row.amount.minorUnits
                case .investment: flows.investments += row.amount.minorUnits
                case .transfer: flows.transfers += row.amount.minorUnits
                case .unclassified: flows.unclassified += row.amount.minorUnits
                }
            }

            let previousScheduled = previous.totals.first { $0.currencyCode == code }?.scheduled ?? 0
            return CurrencyOverview(
                totals: totals,
                rowCount: rows.count,
                paidCount: rows.filter { $0.status == .paid }.count,
                categories: categories,
                flows: flows,
                scheduledComparison: MetricComparison(current: totals.scheduled, previous: previousScheduled)
            )
        }
    }
}
