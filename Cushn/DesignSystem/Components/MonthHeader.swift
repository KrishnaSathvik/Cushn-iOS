import SwiftUI

extension EnvironmentValues {
    /// Whether the month header scrolls with the list rather than staying pinned above it.
    @Entry var monthHeaderScrolls = false
}

/// The pixel C, which opens Settings, then the month and year as one control that opens the month selector. Shared by
/// all tabs, so the title sits at the same height on each and Settings is reachable from each.
struct MonthHeader<Trailing: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.coachesMonthTitle) private var coachesMonthTitle
    @State private var showingPicker = false
    private let trailing: Trailing
    private let showsLogo: Bool

    init(showsLogo: Bool = true, @ViewBuilder trailing: () -> Trailing) {
        self.showsLogo = showsLogo
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                logo
                title
                Spacer(minLength: 8)
                trailing
            }
            // Larger text moves the title to its own line. The logo stays, because it's the way to Settings.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    logo
                    Spacer(minLength: 8)
                    trailing
                }
                title
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CushnSpacing.inset)
        .padding(.vertical, 4)
        .background(CushnColor.canvas)
        .sheet(isPresented: $showingPicker) { MonthPickerSheet() }
    }

    @ViewBuilder
    private var logo: some View {
        if showsLogo {
            // The target is wider than the mark, so this pulls the mark back onto the page margin.
            SettingsLogoButton().padding(.leading, -SettingsLogoButton.sideInset)
        }
    }

    /// For use as a list's first row at accessibility text sizes, where a pinned header would take over the screen.
    var asListRow: some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(CushnColor.canvas)
    }

    private var title: some View {
        Button { showingPicker = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(DateText.monthName(model.selectedMonth))
                        .cushnScreenTitle()
                        .foregroundStyle(CushnColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down")
                        .font(CushnFont.glyph)
                        .foregroundStyle(CushnColor.secondaryText)
                }
                Text(String(model.selectedMonth.year))
                    .font(CushnFont.secondary)
                    .foregroundStyle(CushnColor.secondaryText)
            }
            .frame(minHeight: CushnSpacing.touchTarget)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if coachesMonthTitle {
                    Rectangle().fill(CushnColor.brandGold).frame(height: 3).offset(y: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DateText.monthYear(model.selectedMonth))
        .accessibilityHint("Choose a month")
        .accessibilityIdentifier("monthTitle")
        // VoiceOver users can flick up or down a month without opening the selector.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.shiftMonth(by: 1)
            case .decrement: model.shiftMonth(by: -1)
            @unknown default: break
            }
        }
    }
}

extension MonthHeader where Trailing == EmptyView {
    init(showsLogo: Bool = true) {
        self.init(showsLogo: showsLogo) { EmptyView() }
    }
}

/// A quiet text action whose whole 44pt height responds, not just its letters.
struct CushnTextButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CushnFont.supportingEmphasis)
                .foregroundStyle(CushnColor.primaryText)
                .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The header's pixel C. A first-use hint explains it, since a logo doesn't announce what it does.
struct SettingsLogoButton: View {
    /// How far the 44pt target extends past the mark on each side.
    static let sideInset: CGFloat = 11

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.coachesSettingsLogo) private var isCoached

    var body: some View {
        Button { model.showingSettings = true } label: {
            CushnMark(theme: .goldMark(for: colorScheme), height: 26)
                .frame(width: CushnSpacing.touchTarget, height: CushnSpacing.touchTarget)
                .contentShape(Rectangle())
                .overlay {
                    if isCoached {
                        Circle().strokeBorder(CushnColor.primaryText, lineWidth: 2).frame(width: 40, height: 40)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cushn settings")
        .accessibilityHint("Opens Settings")
        .accessibilityIdentifier("settingsLogo")
    }
}

/// Twelve months and a year stepper. Choosing a month goes there and closes the sheet. Only changes which month is
/// shown, so browsing can't alter any data.
struct MonthPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var year = 2026
    @State private var review: ReviewRoute?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    yearStepper
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(1...12, id: \.self) { number in
                            if let month = YearMonth(year: year, month: number) { cell(month) }
                        }
                    }
                    if model.selectedMonth != model.currentMonth {
                        CushnTextButton("Go to \(DateText.monthYear(model.currentMonth))") { choose(model.currentMonth) }
                            .accessibilityIdentifier("goToCurrentMonth")
                    }
                    // A review note dismissed on Home stays reachable here, next to the months it's about.
                    ForEach(ReviewService.allPrompts(ledger: model.store.ledger, today: model.today)) { prompt in
                        CushnTextButton("Review \(DateText.monthName(prompt.month)) (\(prompt.count))") {
                            review = ReviewRoute(month: prompt.month)
                        }
                    }
                }
                .padding(.horizontal, CushnSpacing.inset)
                .padding(.bottom, 8)
            }
            .background(CushnColor.canvas)
            .navigationTitle("Select month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(440), .large])
        .onAppear { year = model.selectedMonth.year }
        .sheet(item: $review) { ReviewSheet(route: $0) }
    }

    private var yearStepper: some View {
        HStack(spacing: 0) {
            stepper("chevron.left", label: "Previous year", id: "previousYear", enabled: year > YearMonth.origin.year) { year -= 1 }
            Text(String(year))
                .font(CushnFont.sectionTitle)
                .monospacedDigit()
                .foregroundStyle(CushnColor.primaryText)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pickerYear")
            stepper("chevron.right", label: "Next year", id: "nextYear", enabled: year < YearMonth.latest.year) { year += 1 }
        }
    }

    private func stepper(_ symbol: String, label: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(enabled ? CushnColor.primaryText : CushnColor.secondaryText)
                .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func cell(_ month: YearMonth) -> some View {
        let isSelected = month == model.selectedMonth
        let isCurrent = month == model.currentMonth
        return Button { choose(month) } label: {
            Text(DateText.shortMonthName(month))
                .font(isSelected ? CushnFont.rowTitle : CushnFont.body)
                .foregroundStyle(isSelected ? CushnColor.canvas : CushnColor.primaryText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(isSelected ? CushnColor.primaryText : CushnColor.surface,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if isCurrent && !isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(CushnColor.primaryText, lineWidth: 2)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DateText.monthYear(month) + (isCurrent ? ", current month" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("monthCell.\(month.month)")
    }

    private func choose(_ month: YearMonth) {
        model.selectedMonth = month
        dismiss()
    }
}
