import SwiftUI

struct CalendarTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monthHeaderScrolls) private var headerScrolls
    @State private var selectedDay: CalendarDay?
    @State private var detail: DetailRoute?

    /// How much of the space under the header the month grid aims to fill, leaving the rest for the selected day.
    private static let gridShare: CGFloat = 0.56

    private var month: YearMonth { model.selectedMonth }
    private var view: MonthView { model.store.view(for: month) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !headerScrolls { MonthHeader { todayButton } }
                let byDay = CalendarLayout.rowsByDay(view)
                GeometryReader { geometry in
                    List {
                        if headerScrolls { MonthHeader { todayButton }.asListRow }
                        CalendarGrid(month: month, rowsByDay: byDay, today: model.today, selection: $selectedDay,
                                     targetHeight: headerScrolls ? 0 : geometry.size.height * Self.gridShare)
                            .listRowInsets(EdgeInsets(top: 28, leading: 12, bottom: 24, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(CushnColor.canvas)
                        selectedDayRows(byDay)
                    }
                    .listStyle(.plain)
                    .listSectionSpacing(0)
                    .environment(\.defaultMinListHeaderHeight, 1)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(CushnColor.canvas)
        }
        .paymentDetailSheet($detail)
        .onAppear(perform: resetSelection)
        .onChange(of: month) { _, _ in resetSelection() }
    }

    /// Appears once the view has moved away from today, and takes it back to the shared current month.
    @ViewBuilder
    private var todayButton: some View {
        if selectedDay != model.today {
            CushnTextButton("Today") {
                model.selectedMonth = model.currentMonth
                selectedDay = model.today
            }
            .accessibilityHint("Selects today")
            .accessibilityIdentifier("calendarToday")
        }
    }

    @ViewBuilder
    private func selectedDayRows(_ byDay: [CalendarDay: [MonthRow]]) -> some View {
        if let selectedDay {
            let rows = byDay[selectedDay] ?? []
            Section {
                if rows.isEmpty {
                    Text("Nothing due")
                        .font(CushnFont.supporting)
                        .foregroundStyle(CushnColor.secondaryText)
                        .accessibilityIdentifier("selectedDayEmpty")
                        .listRowSeparator(.hidden)
                        .listRowBackground(CushnColor.canvas)
                        .listRowInsets(EdgeInsets(top: 2, leading: CushnSpacing.inset, bottom: 4, trailing: CushnSpacing.inset))
                } else {
                    ForEach(rows) { row in
                        PaymentRowView(row: row, month: month, detail: $detail).cushnListRow()
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(CushnColor.hairline).frame(height: 1).padding(.bottom, 20).accessibilityHidden(true)
                    Text(DateText.weekdayMonthDay(selectedDay))
                        .font(CushnFont.sectionTitle)
                        .foregroundStyle(CushnColor.heading)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("selectedDayTitle")
                        .padding(.bottom, 8)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: CushnSpacing.inset, bottom: 0, trailing: CushnSpacing.inset))
                // Sticky, so this needs an opaque backing or rows show through while scrolling.
                .background { CushnColor.canvas.padding(.horizontal, -CushnSpacing.inset) }
            }
            .listSectionSeparator(.hidden)
        }
    }

    /// Selects today in the current month, otherwise the month's first due date.
    private func resetSelection() {
        if month == model.currentMonth {
            selectedDay = model.today
        } else {
            selectedDay = view.rows.map(\.dueDate).min()
        }
    }
}

private struct CalendarGrid: View {
    let month: YearMonth
    let rowsByDay: [CalendarDay: [MonthRow]]
    let today: CalendarDay
    @Binding var selection: CalendarDay?
    /// The height the grid spreads its weeks toward. Zero keeps them at their tightest.
    let targetHeight: CGFloat

    private var firstWeekday: Int { Calendar.autoupdatingCurrent.firstWeekday }

    private var weekdaySymbols: [String] {
        let symbols = Calendar.autoupdatingCurrent.veryShortStandaloneWeekdaySymbols
        return Array(symbols[(firstWeekday - 1)...] + symbols[..<(firstWeekday - 1)])
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    /// The selection circle grows with the text until it fills a phone-width column. Past that, digits shrink to fit it.
    @ScaledMetric(relativeTo: .body) private var scaledCircle: CGFloat = 38
    private var circle: CGFloat { min(scaledCircle, 46) }

    /// A day's circle, the gap and its marks.
    private var cellHeight: CGFloat { max(circle + 10, CushnSpacing.touchTarget) }
    private static let weekdayRowHeight: CGFloat = 34
    private static let weekSpacing: ClosedRange<CGFloat> = 6...24

    /// Spreads the month's weeks over the target height, so a four-week and a six-week month both look settled
    /// and a large phone isn't top-heavy, while a small one stays compact.
    private var weekSpacing: CGFloat {
        let weeks = (CalendarLayout.cells(month: month, firstWeekday: firstWeekday).count + 6) / 7
        guard weeks > 1 else { return Self.weekSpacing.lowerBound }
        let spare = (targetHeight - Self.weekdayRowHeight - CGFloat(weeks) * cellHeight) / CGFloat(weeks - 1)
        return min(max(spare, Self.weekSpacing.lowerBound), Self.weekSpacing.upperBound)
    }

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(CushnFont.secondary)
                        .foregroundStyle(CushnColor.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            LazyVGrid(columns: columns, spacing: weekSpacing) {
                ForEach(Array(CalendarLayout.cells(month: month, firstWeekday: firstWeekday).enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        dayCell(cell)
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let rows = rowsByDay[day] ?? []
        let isSelected = selection == day
        let isToday = day == today
        return Button { selection = day } label: {
            VStack(spacing: 4) {
                Text("\(day.day)")
                    .font(isToday || isSelected ? CushnFont.rowTitle.weight(.semibold) : CushnFont.body)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(isSelected ? CushnColor.canvas : CushnColor.primaryText)
                    .padding(4)
                    .frame(width: circle, height: circle)
                    .background {
                        if isSelected {
                            Circle().fill(CushnColor.primaryText)
                        } else if isToday {
                            Circle().strokeBorder(CushnColor.primaryText, lineWidth: 1)
                        }
                    }
                HStack(spacing: 3) {
                    let load = CalendarLayout.load(forPaymentCount: rows.count)
                    ForEach(Array(CalendarLayout.marks(for: rows).enumerated()), id: \.offset) { _, status in
                        mark(status, load: load)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: CushnSpacing.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(day, rows: rows, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendarDay.\(day.day)")
    }

    /// Shape carries the status, as on the row's circle: solid for paid, a ring for open, gray for skipped.
    /// Color carries how many payments the day has: green for one, yellow for two, red for three or more.
    @ViewBuilder
    private func mark(_ status: PaymentStatus, load: CalendarLayout.DayLoad?) -> some View {
        let color = load.map(CushnColor.dayLoad) ?? CushnColor.mutedMark
        switch status {
        case .paid: Circle().fill(color).frame(width: 6, height: 6)
        case .unconfirmed: Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 6, height: 6)
        case .skipped: Circle().fill(CushnColor.mutedMark).frame(width: 6, height: 6)
        }
    }

    private func accessibilityLabel(_ day: CalendarDay, rows: [MonthRow], isToday: Bool) -> String {
        let count = rows.count
        let due = count == 0 ? "nothing due" : (count == 1 ? "1 payment due" : "\(count) payments due")
        let paid = rows.filter { $0.status == .paid }.count
        let marked = paid == 0 ? "" : ", \(paid) marked paid"
        return "\(isToday ? "Today, " : "")\(DateText.monthDay(day, wide: true)), \(due)\(marked)"
    }
}
