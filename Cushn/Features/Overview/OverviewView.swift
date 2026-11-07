import Charts
import SwiftUI

/// Figures from user-entered amounts and user-recorded statuses. Labels never imply bank-verified spending.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monthHeaderScrolls) private var headerScrolls

    private var month: YearMonth { model.selectedMonth }
    private var overviews: [CurrencyOverview] {
        let store = model.store
        return AnalyticsService.overview(for: store.view(for: month), previous: store.view(for: month.previous))
    }

    /// Read-only projections of earlier months, which browsing and charting can't change.
    private func trend(_ currencyCode: String) -> [MonthlyTrend.Point] {
        let store = model.store
        return MonthlyTrend.points(endingIn: month) { earlier in
            store.view(for: earlier).totals.first { $0.currencyCode == currencyCode }?.scheduled ?? 0
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                let data = overviews
                if !headerScrolls || data.isEmpty { MonthHeader() }
                if data.isEmpty {
                    Text("Nothing scheduled in \(DateText.monthName(month)).")
                        .font(CushnFont.body)
                        .foregroundStyle(CushnColor.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if headerScrolls { MonthHeader() }
                            VStack(alignment: .leading, spacing: CushnSpacing.group + 16) {
                                // Each currency stands alone, so amounts in different currencies are never combined.
                                ForEach(data) { overview in
                                    CurrencyOverviewBlock(overview: overview, trend: trend(overview.currencyCode), month: month,
                                                          showsCurrencyTitle: data.count > 1, showsInfo: overview.id == data.first?.id)
                                }
                            }
                            .padding(.horizontal, CushnSpacing.inset)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .background(CushnColor.canvas)
        }
    }
}

/// One total, then progress, where the payments go, and how the month compares. Each number says something different.
private struct CurrencyOverviewBlock: View {
    let overview: CurrencyOverview
    let trend: [MonthlyTrend.Point]
    let month: YearMonth
    let showsCurrencyTitle: Bool
    let showsInfo: Bool
    @State private var showingInfo = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var presentation: OverviewPresentation { OverviewPresentation(overview: overview) }

    private func money(_ minor: Int64) -> String {
        Money(minorUnits: minor, currencyCode: overview.currencyCode).formatted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CushnSpacing.group + 4) {
            summary
            progress
            OverviewDivider()
            paymentTypes
            OverviewDivider()
            comparison
        }
        .sheet(isPresented: $showingInfo) { OverviewInfoSheet() }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsCurrencyTitle {
                Text(CurrencyOptions.displayName(overview.currencyCode))
                    .font(CushnFont.sectionTitle)
                    .foregroundStyle(CushnColor.heading)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)
            }
            HStack(spacing: 4) {
                Text("Total scheduled")
                    .font(CushnFont.supporting)
                    .foregroundStyle(CushnColor.secondaryText)
                    .accessibilityHidden(true)
                if showsInfo {
                    Button { showingInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(CushnFont.supporting)
                            .foregroundStyle(CushnColor.secondaryText)
                            .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -10)
                    .accessibilityLabel("About these figures")
                    .accessibilityIdentifier("overviewInfo")
                }
            }
            Text(money(overview.totals.scheduled))
                .cushnHeroAmount()
                .foregroundStyle(CushnColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel("Total scheduled, \(money(overview.totals.scheduled))")
                .accessibilityIdentifier("scheduledTotal")
            if overview.totals.scheduled > 0,
               let yearly = Money(minorUnits: overview.totals.scheduled, currencyCode: overview.currencyCode).yearlyEstimate {
                Text("About \(yearly.formatted()) a year")
                    .font(CushnFont.supporting)
                    .monospacedDigit()
                    .foregroundStyle(CushnColor.secondaryText)
                    .accessibilityIdentifier("yearlyEstimate")
            }
        }
    }

    // MARK: Progress

    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverviewHeading("Payment progress")
            Text("\(overview.paidCount) of \(overview.rowCount) marked paid")
                .font(CushnFont.supporting)
                .monospacedDigit()
                .foregroundStyle(CushnColor.secondaryText)
            if presentation.showsProgressBar {
                // Measures amounts, while the line above counts payments. Paid first, so the gold grows from the left.
                AmountBar(segments: [
                    .init(id: "paid", value: overview.totals.markedPaid, color: PaymentStatus.paid.overviewColor),
                    .init(id: "open", value: overview.totals.unconfirmed, color: PaymentStatus.unconfirmed.overviewColor),
                    .init(id: "skipped", value: overview.totals.skipped, color: PaymentStatus.skipped.overviewColor),
                ], domain: overview.totals.scheduled, height: 14)
                .padding(.top, 2)
            }
            if presentation.showsStatusBreakdown {
                statusFigures.padding(.top, 8)
            }
        }
    }

    /// Three columns while the amounts fit, otherwise one line each.
    private var statusFigures: some View {
        let figures = [
            StatusFigure(status: .paid, title: "Marked paid", value: money(overview.totals.markedPaid)),
            StatusFigure(status: .unconfirmed, title: "Unconfirmed", value: money(overview.totals.unconfirmed)),
            StatusFigure(status: .skipped, title: "Skipped", value: money(overview.totals.skipped)),
        ]
        return ViewThatFits(in: .horizontal) {
            // Natural widths, spread across the line, so a long amount takes the room it needs.
            HStack(alignment: .top, spacing: 12) {
                StatusFigureColumn(figure: figures[0])
                Spacer(minLength: 0)
                StatusFigureColumn(figure: figures[1])
                Spacer(minLength: 0)
                StatusFigureColumn(figure: figures[2])
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(figures) { figure in
                    HStack(spacing: 8) {
                        StatusGlyph(status: figure.status)
                        ValueLine {
                            Text(figure.title).foregroundStyle(CushnColor.primaryText)
                        } value: {
                            Text(figure.value).monospacedDigit().foregroundStyle(CushnColor.primaryText)
                        }
                    }
                    .font(CushnFont.supporting)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Payment types

    @ViewBuilder
    private var paymentTypes: some View {
        let slices = presentation.typeSlices
        VStack(alignment: .leading, spacing: 14) {
            OverviewHeading("Where your payments go")
            // At accessibility sizes the lines need the width, and they carry every value, so the donut steps aside.
            if presentation.showsTypeChart, !typeSize.isAccessibilitySize {
                HStack(spacing: 20) {
                    TypeDonut(slices: slices).frame(width: 112, height: 112)
                    typeLines(slices)
                }
            } else {
                typeLines(slices)
            }
        }
    }

    private func typeLines(_ slices: [OverviewPresentation.TypeSlice]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(slices) { slice in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(slice.kind.color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    ValueLine {
                        Text(slice.kind.title)
                            .foregroundStyle(CushnColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } value: {
                        Text(money(slice.amount)).monospacedDigit().foregroundStyle(CushnColor.primaryText)
                    }
                }
                .font(CushnFont.supporting)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("typeLine.\(slice.kind.title)")
            }
        }
    }

    // MARK: Comparison

    @ViewBuilder
    private var comparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverviewHeading("Compared with previous months")
            if MonthlyTrend.isMeaningful(trend) {
                if let comparisonText {
                    Text(comparisonText)
                        .font(CushnFont.supporting)
                        .monospacedDigit()
                        .foregroundStyle(CushnColor.secondaryText)
                        .accessibilityIdentifier("comparisonLine")
                }
                TrendChart(points: trend, month: month, currencyCode: overview.currencyCode)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No comparison yet")
                        .font(CushnFont.supportingEmphasis)
                        .foregroundStyle(CushnColor.primaryText)
                    Text("Your monthly trend will appear when there's another month of payments.")
                        .font(CushnFont.secondary)
                        .foregroundStyle(CushnColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("trendEmpty")
            }
        }
    }

    private var comparisonText: String? {
        let previousName = DateText.monthName(month.previous)
        switch presentation.comparisonLine {
        case nil:
            return nil
        case .same:
            return "Same as \(previousName)"
        case .change(let delta, let percent):
            let sign = delta > 0 ? "+" : "−"
            let change = money(abs(delta))
            let share = percent.map { " (\(sign)\(abs($0).formatted(.number.precision(.fractionLength(0...1))))%)" } ?? ""
            return "\(sign)\(change)\(share) vs. \(previousName)"
        }
    }
}

/// The explanations that used to sit on the page.
private struct OverviewInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    note("Your own record", "These figures come from amounts you entered and what you marked. Cushn doesn't see your bank, so they aren't verified spending.")
                    note("Total scheduled", "Everything on this month's list, whatever its status.")
                    note("A year", "This month's list multiplied by 12. It's an estimate, and real months can differ when payments change or are skipped.")
                    note("Estimated expenses", "Card repayments, investments and transfers aren't counted as expenses. Change how a section counts in its “Counts as” setting.")
                    note("Progress", "The bar measures amounts. The count above it measures payments, so the two can differ.")
                }
                .padding(.horizontal, CushnSpacing.inset)
                .padding(.vertical, 8)
            }
            .background(CushnColor.canvas)
            .navigationTitle("About these figures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(CushnFont.groupTitle)
                .foregroundStyle(CushnColor.heading)
            Text(text)
                .font(CushnFont.supporting)
                .foregroundStyle(CushnColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OverviewHeading: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(CushnFont.sectionTitle)
            .foregroundStyle(CushnColor.heading)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct OverviewDivider: View {
    var body: some View {
        Rectangle().fill(CushnColor.hairline).frame(height: 1).accessibilityHidden(true)
    }
}

/// Gold for marked paid, light gray for unconfirmed, darker gray for skipped.
private extension PaymentStatus {
    var overviewColor: Color {
        switch self {
        case .paid: CushnColor.brandGold
        case .unconfirmed: CushnColor.track
        case .skipped: CushnColor.mutedMark
        }
    }
}

/// One fixed color per type, so a type looks the same from month to month whatever its share.
private extension OverviewPresentation.TypeKind {
    var title: String {
        switch self {
        case .expenses: "Estimated expenses"
        case .cardRepayments: "Card repayments"
        case .investmentsAndTransfers: "Investments and transfers"
        case .other: "Other"
        }
    }

    var color: Color {
        switch self {
        case .expenses: CushnColor.brandGold
        case .cardRepayments: CushnColor.primaryText
        case .investmentsAndTransfers: CushnColor.mutedMark
        case .other: CushnColor.track
        }
    }
}

/// The same marks as a row's status circle, tinted to match the bar. The shape carries the status, not the color.
private struct StatusGlyph: View {
    let status: PaymentStatus

    var body: some View {
        Group {
            if status == .paid {
                Image(systemName: StatusCircle.symbol(for: status))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color(hex: 0x111111), CushnColor.brandGold)
            } else {
                Image(systemName: StatusCircle.symbol(for: status))
                    .foregroundStyle(status == .skipped ? CushnColor.mutedMark : CushnColor.openCircle)
            }
        }
        .font(CushnFont.supporting)
        .accessibilityHidden(true)
    }
}

private struct StatusFigure: Identifiable {
    let status: PaymentStatus
    let title: String
    let value: String
    var id: String { title }
}

private struct StatusFigureColumn: View {
    let figure: StatusFigure

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                StatusGlyph(status: figure.status)
                Text(figure.title)
                    .font(CushnFont.secondary)
                    .foregroundStyle(CushnColor.secondaryText)
            }
            Text(figure.value)
                .font(CushnFont.metric)
                .monospacedDigit()
                .foregroundStyle(CushnColor.primaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A horizontal bar drawn with Swift Charts. The text beside it carries the numbers, so it's hidden from VoiceOver.
private struct AmountBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Int64
        let color: Color
    }

    private struct Span: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let color: Color
    }

    let segments: [Segment]
    let domain: Int64
    let height: CGFloat

    /// Lays the segments end to end, leaving a sliver between neighbors.
    private var spans: [Span] {
        let total = Double(max(domain, 1))
        let gap = total * 0.006
        var position = 0.0
        return segments.filter { $0.value > 0 }.map { segment in
            let end = position + Double(segment.value)
            defer { position = end }
            return Span(id: segment.id, start: position, end: max(position, end - gap), color: segment.color)
        }
    }

    var body: some View {
        Chart(spans) { span in
            BarMark(xStart: .value("Start", span.start), xEnd: .value("End", span.end))
                .foregroundStyle(span.color)
                .cornerRadius(4)
        }
        .chartXScale(domain: 0...Double(max(domain, 1)))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Shares of the month by type. The lines beside it carry every value, so it's hidden from VoiceOver.
private struct TypeDonut: View {
    let slices: [OverviewPresentation.TypeSlice]

    var body: some View {
        Chart(slices) { slice in
            SectorMark(angle: .value("Amount", Double(slice.amount)), innerRadius: .ratio(0.64), angularInset: 1.5)
                .foregroundStyle(slice.kind.color)
                .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

/// Scheduled totals month by month, with the selected month in gold. Each bar carries its own figure, so no axis is needed.
private struct TrendChart: View {
    let points: [MonthlyTrend.Point]
    let month: YearMonth
    let currencyCode: String

    private var largest: Double { Double(points.map(\.scheduled).max() ?? 1) }

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("Month", DateText.shortMonthName(point.month)), y: .value("Scheduled", Double(point.scheduled)), width: .fixed(36))
                .foregroundStyle(point.month == month ? CushnColor.brandGold : CushnColor.track)
                .cornerRadius(4)
                // VoiceOver steps through the bars with exact amounts, where the labels on screen are rounded.
                .accessibilityLabel(DateText.monthName(point.month))
                .accessibilityValue(Money(minorUnits: point.scheduled, currencyCode: currencyCode).formatted())
                .annotation(position: .top, spacing: 4) {
                    Text(Money(minorUnits: point.scheduled, currencyCode: currencyCode).compactFormatted())
                        .font(.caption2.weight(point.month == month ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(point.month == month ? CushnColor.primaryText : CushnColor.secondaryText)
                        .fixedSize()
                }
        }
        // Headroom for the figures above the tallest bar.
        .chartYScale(domain: 0...(largest * 1.25))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(CushnFont.secondary).foregroundStyle(CushnColor.secondaryText)
            }
        }
        .chartLegend(.hidden)
        .frame(height: 124)
    }
}

/// A label and amount on one line, stacked at accessibility sizes so an amount never breaks across lines.
private struct ValueLine<Label: View, Value: View>: View {
    @ViewBuilder let label: Label
    @ViewBuilder let value: Value
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                label
                value.lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                label
                Spacer(minLength: 8)
                // A long label wraps. The amount never does.
                value.lineLimit(1).layoutPriority(1)
            }
        }
    }
}
