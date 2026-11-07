import SwiftUI

/// Add and edit in one sheet that's only as tall as its fields. It grows when the day grid opens or an error shows, rises
/// with the keyboard, and goes full height at accessibility text sizes. Its content scrolls if a screen can't fit it.
struct PaymentEditorSheet: View {
    let mode: PaymentEditorView.Mode
    @State private var contentHeight: CGFloat = 300
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The navigation bar above the fields, and the home indicator below them.
    private static let chromeHeight: CGFloat = 84

    private var detents: Set<PresentationDetent> {
        typeSize.isAccessibilitySize ? [.large] : [.height(contentHeight + Self.chromeHeight)]
    }

    var body: some View {
        NavigationStack {
            PaymentEditorView(mode: mode, contentHeight: $contentHeight)
        }
        .presentationDetents(detents)
        .presentationBackground(CushnColor.canvas)
    }
}

/// Name, amount and due day are required. Currency and section have sensible values already.
struct PaymentEditorView: View {
    enum Mode {
        case add(month: YearMonth, categoryID: UUID?)
        case edit(row: MonthRow, month: YearMonth)
    }

    let mode: Mode
    @Binding var contentHeight: CGFloat
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var form: PaymentForm
    @State private var choice: CategoryChoice
    @State private var errors = PaymentFormErrors()
    @State private var showingDays = false
    @State private var showingSections = false
    @State private var confirmingDiscard = false
    @FocusState private var focus: Field?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let initialForm: PaymentForm

    private enum Field { case name, amount }

    init(mode: Mode, contentHeight: Binding<CGFloat>) {
        self.mode = mode
        _contentHeight = contentHeight
        let form: PaymentForm
        let choice: CategoryChoice
        switch mode {
        case .add(_, let categoryID):
            let currency = UserDefaults.standard.string(forKey: AppModel.defaultCurrencyKey)
                ?? Locale.autoupdatingCurrent.currency?.identifier ?? "USD"
            choice = CategoryChoice(explicit: categoryID)
            form = PaymentForm(currencyCode: currency, categoryID: choice.categoryID)
        case .edit(let row, _):
            form = PaymentForm(row: row)
            choice = CategoryChoice(saved: row.categoryID)
        }
        initialForm = form
        _form = State(initialValue: form)
        _choice = State(initialValue: choice)
    }

    private var month: YearMonth {
        switch mode {
        case .add(let month, _), .edit(_, let month): month
        }
    }

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
    }

    private var hasChanges: Bool { form != initialForm }

    private var categories: [MonthCategory] { model.store.view(for: month).allCategories }

    /// Explains what saving affects. Shown when it could surprise: always for edits, and for adds away from the current month.
    private var contextLabel: String? {
        let name = DateText.monthName(month)
        if !isAdding { return "Changes apply from \(name) onward. Earlier months stay as they are." }
        return month == model.currentMonth ? nil : "Adding from \(DateText.monthYear(month)) onward"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                nameField
                EditorDivider()
                amountField
                EditorDivider()
                dueDayField
                if showingDays {
                    DayGrid(selection: $form.dueDay) { showingDays = false }
                        .padding(.bottom, 8)
                }
                EditorDivider()
                sectionField
                if showingSections {
                    SectionChoices(sections: categories, selection: choice.categoryID) { id in
                        choice.choose(id)
                        form.categoryID = id
                        reveal { showingSections = false }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }
                if let contextLabel {
                    Text(contextLabel)
                        .font(CushnFont.secondary)
                        .foregroundStyle(CushnColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .accessibilityIdentifier("editorContext")
                }
            }
            .padding(.horizontal, CushnSpacing.inset)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(CushnColor.canvas)
        .navigationTitle(isAdding ? "New payment" : "Edit payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if hasChanges { confirmingDiscard = true } else { dismiss() }
                }
                .accessibilityIdentifier("cancelPayment")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isAdding ? "Add" : "Save", action: save)
                    .fontWeight(.semibold)
                    .accessibilityLabel(isAdding ? "Add payment" : "Save changes")
                    .accessibilityIdentifier("savePayment")
            }
        }
        // Typing shouldn't be lost to a stray swipe, so with changes the way out is Cancel, which asks first.
        .interactiveDismissDisabled(hasChanges)
        .alert(isAdding ? "Discard this payment?" : "Discard your changes?", isPresented: $confirmingDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .onAppear { if isAdding { focus = .name } }
        .onChange(of: form.name) { _, name in
            choice.nameChanged(to: name, available: categories.map(\.id))
            form.categoryID = choice.categoryID
            // Capitals can change under the cursor. A correction that changes the length waits for the field to
            // be left, or the cursor would jump mid-word.
            let corrected = BrandMatcher.correctedName(name)
            if corrected != name, corrected.count == name.count { form.name = corrected }
        }
        // The keyboard and the inline choices take turns, so the sheet never has to hold both.
        .onChange(of: focus) { old, field in
            if old == .name { correctName() }
            if field != nil {
                showingDays = false
                showingSections = false
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Name", text: $form.name)
                    .font(CushnFont.body)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .name)
                    .onSubmit { focus = .amount }
                    .accessibilityIdentifier("nameField")
                // Shows which icon the row will use as soon as the name matches one.
                if BrandMatcher.match(form.name)?.icon != nil, !typeSize.isAccessibilitySize {
                    PaymentIcon(name: form.name)
                        .accessibilityIdentifier("namePreviewIcon")
                }
            }
            .frame(minHeight: CushnSpacing.touchTarget + 4)
            fieldError(errors.name)
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Amount", text: $form.amountText)
                    .font(CushnFont.body)
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
                    .accessibilityIdentifier("amountField")
                Menu {
                    Picker("Currency", selection: $form.currencyCode) {
                        ForEach(CurrencyOptions.options(including: form.currencyCode, model.defaultCurrency), id: \.self) { code in
                            Text("\(code) · \(CurrencyOptions.displayName(code))").tag(code)
                        }
                    }
                } label: {
                    Text(form.currencyCode)
                        .font(CushnFont.supportingEmphasis)
                        .foregroundStyle(CushnColor.secondaryText)
                        .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Currency, \(CurrencyOptions.displayName(form.currencyCode))")
            }
            .frame(minHeight: CushnSpacing.touchTarget + 4)
            fieldError(errors.amount)
        }
    }

    private var dueDayField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                focus = nil
                reveal {
                    showingDays.toggle()
                    showingSections = false
                }
            } label: {
                adaptiveLayout {
                    Text("Due day")
                        .font(CushnFont.body)
                        .foregroundStyle(CushnColor.primaryText)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    HStack(spacing: 6) {
                        Text(form.dueDay.map(String.init) ?? "Choose")
                            .font(CushnFont.body)
                            .monospacedDigit()
                            .foregroundStyle(CushnColor.secondaryText)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(CushnFont.secondary)
                            .foregroundStyle(CushnColor.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: CushnSpacing.touchTarget + 4, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Due day")
            .accessibilityValue(form.dueDay.map(String.init) ?? "Not chosen")
            .accessibilityIdentifier("dueDayField")
            fieldError(errors.dueDay)
            if let day = form.dueDay, day > 28 {
                Text("In shorter months, this falls on the last day.")
                    .font(CushnFont.secondary)
                    .foregroundStyle(CushnColor.secondaryText)
                    .padding(.bottom, 8)
            }
        }
    }

    private var adaptiveLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())
    }

    private func reveal(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2), change)
    }

    /// Filled in quietly from the name. Tapping it opens the choices in place, as Due day does, and a choice made there stays.
    private var sectionField: some View {
        let title = categories.first { $0.id == choice.categoryID }?.title ?? SeedCategory.other.title
        return Button {
            focus = nil
            reveal {
                showingSections.toggle()
                showingDays = false
            }
        } label: {
            adaptiveLayout {
                Text("Section")
                    .font(CushnFont.body)
                    .foregroundStyle(CushnColor.primaryText)
                if !typeSize.isAccessibilitySize { Spacer() }
                HStack(spacing: 6) {
                    // At accessibility sizes the word would crowd out the section's name. VoiceOver still says it.
                    if choice.isSuggestion, !typeSize.isAccessibilitySize {
                        Text("Suggested")
                            .font(CushnFont.secondary)
                            .foregroundStyle(CushnColor.secondaryText)
                    }
                    Text(title)
                        .font(CushnFont.body)
                        .foregroundStyle(CushnColor.secondaryText)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(CushnFont.secondary)
                        .foregroundStyle(CushnColor.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: CushnSpacing.touchTarget + 4, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choice.isSuggestion ? "Section, suggested" : "Section")
        .accessibilityValue(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sectionPicker")
    }

    @ViewBuilder
    private func fieldError(_ message: String?) -> some View {
        if let message {
            Text(message)
                .font(CushnFont.secondary)
                .foregroundStyle(CushnColor.attention)
                .padding(.bottom, 8)
                .accessibilityIdentifier("fieldError")
        }
    }

    /// An edit that leaves the name alone keeps it exactly as saved, however it was written.
    private func correctName() {
        guard form.name != initialForm.name else { return }
        form.name = BrandMatcher.correctedName(form.name)
    }

    private func save() {
        correctName()
        switch form.validated() {
        case .failure(let failure):
            errors = failure
            if failure.dueDay != nil {
                focus = nil
                showingDays = true
            }
        case .success(let draft):
            errors = PaymentFormErrors()
            let store = model.store
            model.attempt {
                switch mode {
                case .add(let month, _): try store.add(draft, month: month)
                case .edit(let row, let month): try store.edit(id: row.id, draft, month: month)
                }
            }
            dismiss()
        }
    }
}

private struct EditorDivider: View {
    var body: some View {
        Rectangle().fill(CushnColor.hairline).frame(height: 1).accessibilityHidden(true)
    }
}

/// The month's sections as tappable names that wrap across lines, styled like the month selector. One tap chooses.
private struct SectionChoices: View {
    let sections: [MonthCategory]
    let selection: UUID
    let onChoose: (UUID) -> Void

    var body: some View {
        WrappingLayout(spacing: 8) {
            ForEach(sections) { section in
                let isSelected = section.id == selection
                Button { onChoose(section.id) } label: {
                    Text(section.title)
                        .font(isSelected ? CushnFont.supportingEmphasis : CushnFont.supporting)
                        .foregroundStyle(isSelected ? CushnColor.canvas : CushnColor.primaryText)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .frame(minHeight: CushnSpacing.touchTarget)
                        .background(isSelected ? CushnColor.primaryText : CushnColor.surface,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("sectionChoice.\(section.title)")
            }
        }
    }
}

/// Places views left to right and starts a new line when one won't fit. A view wider than the line gets the full width.
private struct WrappingLayout: Layout {
    let spacing: CGFloat

    private func frames(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (frames, y + lineHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = frames(subviews, width: width)
        return CGSize(width: width == .infinity ? (result.frames.map(\.maxX).max() ?? 0) : width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(subviews, width: bounds.width).frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }
}

/// Compact 1...31 grid: one tap chooses a day.
struct DayGrid: View {
    @Binding var selection: Int?
    let onChoose: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: Int { typeSize.isAccessibilitySize ? 4 : 7 }

    var body: some View {
        let days = Array(1...31)
        VStack(spacing: 2) {
            ForEach(Array(stride(from: 0, to: days.count, by: columns)), id: \.self) { start in
                HStack(spacing: 0) {
                    ForEach(days[start..<min(start + columns, days.count)], id: \.self) { dayButton($0) }
                    // Keeps the last row's cells the same width as the rows above.
                    ForEach(0..<(columns - min(columns, days.count - start)), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func dayButton(_ day: Int) -> some View {
        Button {
            selection = day
            onChoose()
        } label: {
            Text("\(day)")
                .font(selection == day ? CushnFont.rowTitle : CushnFont.body)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selection == day ? CushnColor.canvas : CushnColor.primaryText)
                .frame(maxWidth: .infinity, minHeight: CushnSpacing.touchTarget)
                .background(selection == day ? CushnColor.primaryText : .clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Day \(day)")
        .accessibilityAddTraits(selection == day ? .isSelected : [])
        .accessibilityIdentifier("day.\(day)")
    }
}
