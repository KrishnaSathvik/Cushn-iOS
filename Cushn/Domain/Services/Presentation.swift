import Foundation

/// Input state of the add/edit form. Requires exactly name, amount and due day.
struct PaymentForm: Equatable, Sendable {
    var name: String
    var amountText: String
    var currencyCode: String
    var dueDay: Int?
    var categoryID: UUID

    init(name: String = "", amountText: String = "", currencyCode: String, dueDay: Int? = nil, categoryID: UUID) {
        self.name = name
        self.amountText = amountText
        self.currencyCode = currencyCode
        self.dueDay = dueDay
        self.categoryID = categoryID
    }

    init(row: MonthRow, locale: Locale = .autoupdatingCurrent) {
        self.init(name: row.name, amountText: row.amount.editingText(locale: locale),
                  currencyCode: row.amount.currencyCode, dueDay: row.nominalDueDay.value, categoryID: row.categoryID)
    }

    func validated(locale: Locale = .autoupdatingCurrent) -> Result<PaymentDraft, PaymentFormErrors> {
        var errors = PaymentFormErrors()
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.name = "Enter a name" }

        var amount: Money?
        if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.amount = "Enter an amount"
        } else {
            do {
                amount = try Money.parse(amountText, currencyCode: currencyCode, locale: locale)
            } catch MoneyParseError.negative {
                errors.amount = "Amount can't be negative"
            } catch MoneyParseError.tooManyDecimals {
                let digits = Money.minorDigits(for: currencyCode)
                errors.amount = digits == 0 ? "\(currencyCode) doesn't use decimals" : "Use no more than \(digits) decimal places"
            } catch MoneyParseError.tooLarge {
                errors.amount = "That amount is too large"
            } catch {
                errors.amount = "Enter a valid amount"
            }
        }

        let day = dueDay.flatMap { DueDay($0) }
        if day == nil { errors.dueDay = "Choose a due day" }

        guard let amount, let day, errors.isEmpty else { return .failure(errors) }
        return .success(PaymentDraft(name: name, amount: amount, dueDay: day, categoryID: categoryID))
    }

    func errors(locale: Locale = .autoupdatingCurrent) -> PaymentFormErrors? {
        if case .failure(let errors) = validated(locale: locale) { return errors }
        return nil
    }
}

struct PaymentFormErrors: Error, Equatable, Sendable {
    var name: String?
    var amount: String?
    var dueDay: String?
    var isEmpty: Bool { name == nil && amount == nil && dueDay == nil }
}

/// Text for a payment row. "Past due" is presentation only, and copy never says "unpaid".
struct RowPresentation: Equatable, Sendable {
    let dueLine: String
    let isPastDue: Bool
    let amountText: String
    let accessibilityLabel: String
    let statusActionLabel: String

    init(row: MonthRow, today: CalendarDay, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        let date = row.dueDate.date(in: timeZone)
        let short = DateText.monthDay(date, locale: locale, timeZone: timeZone, wide: false)
        let wide = DateText.monthDay(date, locale: locale, timeZone: timeZone, wide: true)
        let state = ReviewService.dueState(of: row, today: today)
        let inCurrentMonth = row.dueDate.yearMonth == today.yearMonth

        isPastDue = inCurrentMonth && state == .pastDue
        if isPastDue {
            dueLine = "\(short) · Not marked paid"
        } else if inCurrentMonth && state == .dueToday {
            dueLine = "Due today"
        } else {
            dueLine = short
        }

        amountText = row.amount.formatted(locale: locale)
        let statusWord = switch row.status {
        case .unconfirmed: "unconfirmed"
        case .paid: "marked paid"
        case .skipped: "skipped"
        }
        accessibilityLabel = "\(row.name), due \(wide), \(amountText), \(statusWord)\(isPastDue ? ", past due" : "")"
        statusActionLabel = switch row.status {
        case .unconfirmed: "Mark \(row.name) paid"
        case .paid: "Undo paid for \(row.name)"
        case .skipped: "\(row.name) skipped, show options"
        }
    }
}

enum DateText {
    static func style(locale: Locale, timeZone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: .gregorian(in: timeZone), timeZone: timeZone)
    }

    static func monthDay(_ date: Date, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent, wide: Bool) -> String {
        date.formatted(style(locale: locale, timeZone: timeZone).month(wide ? .wide : .abbreviated).day())
    }

    static func monthDay(_ day: CalendarDay, wide: Bool) -> String {
        monthDay(day.date(in: .autoupdatingCurrent), wide: wide)
    }

    /// "Friday, November 6". Names the weekday, which the calendar grid only shows as a letter.
    static func weekdayMonthDay(_ day: CalendarDay) -> String {
        let timeZone = TimeZone.autoupdatingCurrent
        return day.date(in: timeZone).formatted(style(locale: .autoupdatingCurrent, timeZone: timeZone).weekday(.wide).month(.wide).day())
    }

    static func monthYear(_ month: YearMonth) -> String {
        let timeZone = TimeZone.autoupdatingCurrent
        let date = CalendarDay(year: month.year, month: month.month, day: 1).date(in: timeZone)
        return date.formatted(style(locale: .autoupdatingCurrent, timeZone: timeZone).month(.wide).year())
    }

    static func shortMonthName(_ month: YearMonth, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let date = CalendarDay(year: month.year, month: month.month, day: 1).date(in: timeZone)
        return date.formatted(style(locale: locale, timeZone: timeZone).month(.abbreviated))
    }

    static func monthName(_ month: YearMonth) -> String {
        let timeZone = TimeZone.autoupdatingCurrent
        let date = CalendarDay(year: month.year, month: month.month, day: 1).date(in: timeZone)
        return date.formatted(style(locale: .autoupdatingCurrent, timeZone: timeZone).month(.wide))
    }

    static func fullDate(_ day: CalendarDay) -> String {
        let timeZone = TimeZone.autoupdatingCurrent
        return day.date(in: timeZone).formatted(style(locale: .autoupdatingCurrent, timeZone: timeZone).month(.wide).day().year())
    }
}

enum CalendarLayout {
    /// Cells for a month grid. `nil` cells pad the first week. `firstWeekday` uses Calendar's numbering (1 = Sunday).
    static func cells(month: YearMonth, firstWeekday: Int) -> [CalendarDay?] {
        let utc = TimeZone(identifier: "UTC")!
        let first = CalendarDay(year: month.year, month: month.month, day: 1)
        let weekday = Calendar.gregorian(in: utc).component(.weekday, from: first.date(in: utc))
        let padding = (weekday - firstWeekday + 7) % 7
        let days = (1...month.dayCount).map { CalendarDay(year: month.year, month: month.month, day: $0) }
        return Array(repeating: nil, count: padding) + days.map(Optional.some)
    }

    /// How busy a day is, counting every payment on it whatever its status. It only sizes up the day: it says nothing
    /// about whether anything is late or paid, which the dots' shapes carry.
    enum DayLoad: Equatable, Sendable { case one, two, many }

    static func load(forPaymentCount count: Int) -> DayLoad? {
        switch count {
        case ...0: nil
        case 1: .one
        case 2: .two
        default: .many
        }
    }

    static func rowsByDay(_ view: MonthView) -> [CalendarDay: [MonthRow]] {
        Dictionary(grouping: view.rows, by: \.dueDate)
    }

    /// Up to three marks for a date cell. Open payments come first, so a busy day never looks finished while
    /// something on it is still unmarked.
    static func marks(for rows: [MonthRow]) -> [PaymentStatus] {
        let order: [PaymentStatus] = [.unconfirmed, .paid, .skipped]
        let statuses = rows.map(\.status)
        return Array(order.flatMap { status in statuses.filter { $0 == status } }.prefix(3))
    }
}

/// Where a moved section lands. Works on the month's full category order, which includes empty defaults
/// that Home doesn't show, so hidden sections keep their places relative to each other.
enum SectionOrdering {
    /// Moves `id` to the place `target` holds now: just after it when moving down, just before it when moving up.
    static func move(_ id: UUID, to target: UUID, in order: [UUID]) -> [UUID] {
        guard id != target, let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return order }
        var result = order
        result.remove(at: from)
        result.insert(id, at: to)
        return result
    }

    /// Puts Home's new visible order into the slots those sections held in the full order. Empty defaults that Home
    /// doesn't show stay exactly where they were.
    static func placing(_ visible: [UUID], in order: [UUID]) -> [UUID] {
        let shown = Set(visible)
        var next = visible.makeIterator()
        return order.map { shown.contains($0) ? (next.next() ?? $0) : $0 }
    }

    /// The visible neighbor a section would swap with, for Move Up and Move Down.
    static func neighbor(of id: UUID, in visible: [UUID], movingDown: Bool) -> UUID? {
        guard let index = visible.firstIndex(of: id) else { return nil }
        let other = index + (movingDown ? 1 : -1)
        return visible.indices.contains(other) ? visible[other] : nil
    }
}

/// The section chosen in the add sheet. The name suggests one until the user chooses, and after that it never changes
/// on its own. A section's Add button and every edit count as choosing, so saved payments are never reclassified.
struct CategoryChoice: Equatable, Sendable {
    private(set) var categoryID: UUID
    private(set) var isChosen: Bool

    /// `explicit` is the section whose Add button opened the sheet, if any.
    init(explicit: UUID?) {
        categoryID = explicit ?? SeedCategory.other.id
        isChosen = explicit != nil
    }

    init(saved: UUID) {
        categoryID = saved
        isChosen = true
    }

    /// `available` is the month's active sections. Going by ID keeps this right when a section has been renamed,
    /// and a suggested section that was removed falls back to Other rather than coming back.
    mutating func nameChanged(to name: String, available: [UUID]) {
        guard !isChosen else { return }
        let suggested = BrandMatcher.suggestedCategory(for: name).id
        categoryID = available.contains(suggested) ? suggested : SeedCategory.other.id
    }

    mutating func choose(_ id: UUID) {
        categoryID = id
        isChosen = true
    }

    /// Whether to label the section as suggested. Other is the fallback, not a suggestion.
    var isSuggestion: Bool { !isChosen && categoryID != SeedCategory.other.id }
}

/// What Overview shows for one currency's figures, so the screen simplifies when a chart would say nothing.
struct OverviewPresentation: Equatable, Sendable {
    let overview: CurrencyOverview

    /// One payment's figures are all the same number, so a split beneath it adds nothing.
    var showsStatusBreakdown: Bool { overview.rowCount > 1 }

    var showsProgressBar: Bool { overview.totals.scheduled > 0 }

    enum TypeKind: Equatable, Sendable { case expenses, cardRepayments, investmentsAndTransfers, other }

    struct TypeSlice: Identifiable, Equatable, Sendable {
        let kind: TypeKind
        let amount: Int64
        var id: TypeKind { kind }
    }

    /// The existing flow buckets, largest first, with investments and transfers read together. Every scheduled amount
    /// lands in exactly one, so the slices always add up to the total. Empty types are left out.
    var typeSlices: [TypeSlice] {
        let flows = overview.flows
        let slices = [
            TypeSlice(kind: .expenses, amount: flows.estimatedExpenses),
            TypeSlice(kind: .cardRepayments, amount: flows.creditRepayments),
            TypeSlice(kind: .investmentsAndTransfers, amount: flows.investments + flows.transfers),
            TypeSlice(kind: .other, amount: flows.unclassified),
        ]
        return slices.enumerated()
            .filter { $0.element.amount > 0 }
            .sorted { $0.element.amount != $1.element.amount ? $0.element.amount > $1.element.amount : $0.offset < $1.offset }
            .map(\.element)
    }

    /// A donut of one slice is just a ring.
    var showsTypeChart: Bool { typeSlices.count > 1 }

    enum ComparisonLine: Equatable, Sendable {
        case same
        case change(delta: Int64, percent: Double?)
    }

    /// Nil when the earlier month had nothing in this currency, including months before the first payment.
    var comparisonLine: ComparisonLine? {
        let comparison = overview.scheduledComparison
        guard comparison.previous > 0 else { return nil }
        return comparison.delta == 0 ? .same : .change(delta: comparison.delta, percent: comparison.percent)
    }
}

/// One metric across months: the total scheduled in one currency. Nothing else is mixed in, so bars are always comparable.
enum MonthlyTrend {
    struct Point: Identifiable, Equatable, Sendable {
        let month: YearMonth
        let scheduled: Int64
        var id: Int { month.ordinal }
    }

    /// Up to `count` months ending at `month`, oldest first. Months before the first amount are left out, so a new
    /// list doesn't show a row of empty bars. A zero after that stays, because it's a real month with nothing on it.
    static func points(endingIn month: YearMonth, count: Int = 6, scheduled: (YearMonth) -> Int64) -> [Point] {
        let months = (0..<count).map { month.adding(months: $0 - (count - 1)) }.filter { $0 >= .origin }
        let all = months.map { Point(month: $0, scheduled: scheduled($0)) }
        return Array(all.drop { $0.scheduled == 0 })
    }

    /// A chart needs two months with amounts to compare. Anything less gets the empty state instead of zero bars.
    static func isMeaningful(_ points: [Point]) -> Bool {
        points.filter { $0.scheduled > 0 }.count >= 2
    }
}

extension Money {
    /// This amount over twelve months, for a yearly estimate. Nil if it wouldn't fit, so no wrapped figure ever shows.
    var yearlyEstimate: Money? {
        let (yearly, overflowed) = minorUnits.multipliedReportingOverflow(by: 12)
        return overflowed ? nil : Money(minorUnits: yearly, currencyCode: currencyCode)
    }

    /// A short figure for a chart label, such as "$4.3K". Rows and totals keep the exact amount.
    func compactFormatted(locale: Locale = .autoupdatingCurrent) -> String {
        let major = Double(minorUnits) / pow(10, Double(Money.minorDigits(for: currencyCode)))
        return major.formatted(.currency(code: currencyCode).notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
    }
}
