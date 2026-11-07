import Foundation

/// Derived presentation state. Never stored, and past due isn't proof that a payment wasn't made.
enum DueState: Equatable, Sendable {
    case upcoming, dueToday, pastDue, resolved
}

struct ReviewPrompt: Identifiable, Equatable, Sendable {
    enum Scope: String, Sendable { case previousMonth, currentMonth }
    let scope: Scope
    let month: YearMonth
    let count: Int
    var contextKey: String { "\(scope.rawValue)|\(month.ordinal)" }
    var id: String { contextKey }
}

/// Read-only rules for the optional review. Nothing here changes a payment status.
enum ReviewService {
    static func dueState(of row: MonthRow, today: CalendarDay) -> DueState {
        guard row.status == .unconfirmed else { return .resolved }
        if row.dueDate < today { return .pastDue }
        return row.dueDate == today ? .dueToday : .upcoming
    }

    static func rows(month: YearMonth, ledger: Ledger, today: CalendarDay) -> [MonthRow] {
        MonthProjector.project(month: month, ledger: ledger).rows.filter { dueState(of: $0, today: today) == .pastDue }
    }

    /// Every review with something to check, previous month first. Stays available after dismissal.
    static func allPrompts(ledger: Ledger, today: CalendarDay) -> [ReviewPrompt] {
        let current = today.yearMonth
        return [(ReviewPrompt.Scope.previousMonth, current.previous), (.currentMonth, current)].compactMap { scope, month in
            let count = rows(month: month, ledger: ledger, today: today).count
            return count > 0 ? ReviewPrompt(scope: scope, month: month, count: count) : nil
        }
    }

    /// The one prompt to show now, if any. A dismissed prompt returns only when more payments need a check.
    static func activePrompt(ledger: Ledger, today: CalendarDay) -> ReviewPrompt? {
        allPrompts(ledger: ledger, today: today).first { prompt in
            guard let dismissal = ledger.dismissals[prompt.contextKey] else { return true }
            return prompt.count > dismissal.lastSeenCount
        }
    }

    static func dismissal(of prompt: ReviewPrompt, now: Date) -> ReviewDismissal {
        ReviewDismissal(contextKey: prompt.contextKey, dismissedAt: now, lastSeenCount: prompt.count)
    }
}
