import SwiftUI

/// Three short pages for new users. The logo and controls stay still while the pages move between them.
struct OnboardingView: View {
    let theme: CushnBrandTheme
    let month: YearMonth
    let onFinish: () -> Void

    @State private var page = 0
    @State private var checklist: AppModel?
    @State private var statuses: (model: AppModel, target: UUID)?
    @State private var rollover: AppModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private static let pageCount = 3

    private var isLastPage: Bool { page == Self.pageCount - 1 }

    /// Built once, up front, so no page draws empty for a frame.
    init(theme: CushnBrandTheme, month: YearMonth, onFinish: @escaping () -> Void) {
        self.theme = theme
        self.month = month
        self.onFinish = onFinish
        _checklist = State(initialValue: try? OnboardingSample.checklist(month: month))
        _statuses = State(initialValue: try? OnboardingSample.statuses(month: month))
        _rollover = State(initialValue: try? OnboardingSample.rollover(month: month))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $page) {
                OnboardingPage(theme: theme, headline: "Your monthly payments, organized.",
                               message: "Cards, subscriptions, rent, bills. Each one takes a name, an amount and a due day.",
                               layout: .textFirst) {
                    if let checklist { ChecklistDemo(model: checklist, theme: theme, month: month) }
                }
                .tag(0)
                OnboardingPage(theme: theme, headline: "See what's due.\nMark what's done.",
                               message: "Mark what you've paid, skip what you're not paying, and see what's left.",
                               layout: .textLastCentered) {
                    if let statuses { StatusDemo(sample: statuses, theme: theme, month: month) }
                }
                .tag(1)
                OnboardingPage(theme: theme, headline: "A fresh checklist every month.",
                               message: "Your list carries forward by itself, and every month keeps its own marks.",
                               layout: .textFirst) {
                    if let rollover { RolloverDemo(model: rollover, theme: theme, month: month) }
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomBar
        }
        .background(theme.background.ignoresSafeArea())
        .environment(\.colorScheme, theme.colorScheme)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                CushnMark(theme: theme, height: 30)
                Text("Cushn")
                    .font(CushnFont.groupTitle)
                    .foregroundStyle(theme.title)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button("Skip", action: onFinish)
                .font(CushnFont.action)
                .foregroundStyle(theme.title)
                .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                .opacity(isLastPage ? 0 : 1)
                .disabled(isLastPage)
                .accessibilityHidden(isLastPage)
                .accessibilityIdentifier("onboardingSkip")
        }
        .padding(.horizontal, CushnSpacing.inset)
        .padding(.top, 12)
    }

    /// At accessibility text sizes the primary action takes its own line, so its label is never cut off.
    private var bottomBar: some View {
        VStack(spacing: 4) {
            if typeSize.isAccessibilitySize { primaryButton(minWidth: .infinity) }
            HStack(spacing: 8) {
                Button("Back") { go(to: page - 1) }
                    .font(CushnFont.action)
                    .foregroundStyle(theme.title)
                    .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget, alignment: .leading)
                    .opacity(page == 0 ? 0 : 1)
                    .disabled(page == 0)
                    .accessibilityHidden(page == 0)
                    .accessibilityIdentifier("onboardingBack")
                Spacer(minLength: 0)
                progress
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize { primaryButton(minWidth: 148) }
            }
        }
        .padding(.horizontal, CushnSpacing.inset)
        .padding(.bottom, 12)
    }

    private func primaryButton(minWidth: CGFloat) -> some View {
        Button(isLastPage ? "Get Started" : "Next") {
            if isLastPage { onFinish() } else { go(to: page + 1) }
        }
        .buttonStyle(CushnPrimaryButtonStyle(fill: theme.buttonFill, text: theme.buttonText, minWidth: minWidth))
        .accessibilityIdentifier(isLastPage ? "onboardingStart" : "onboardingNext")
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                // Square, a quiet echo of the C's pixels.
                Rectangle()
                    .fill(theme.title.opacity(index == page ? 1 : 0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(minHeight: CushnSpacing.touchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(Self.pageCount)")
        .accessibilityIdentifier("onboardingProgress")
    }

    private func go(to target: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page = target }
    }
}

/// One page's words and demonstration. The two sit close together as one composition, with any spare height outside
/// them. Pages arrange them differently, and scroll only when large text needs it.
private struct OnboardingPage<Demo: View>: View {
    enum Layout { case textFirst, textLastCentered }

    let theme: CushnBrandTheme
    let headline: String
    let message: String
    let layout: Layout
    @ViewBuilder let demo: Demo

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: layout == .textFirst ? .leading : .center, spacing: 0) {
                    switch layout {
                    case .textFirst:
                        words.padding(.top, 20)
                        demo.padding(.top, CushnSpacing.group)
                        Spacer(minLength: 16)
                    case .textLastCentered:
                        Spacer(minLength: 16)
                        demo
                        words.padding(.top, CushnSpacing.group)
                        Spacer(minLength: 16)
                    }
                }
                .padding(.horizontal, CushnSpacing.inset)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var words: some View {
        let alignment: TextAlignment = layout == .textFirst ? .leading : .center
        return VStack(alignment: layout == .textFirst ? .leading : .center, spacing: 8) {
            // Each line is its own text, so a headline can choose where it breaks and still wrap at large sizes.
            VStack(alignment: layout == .textFirst ? .leading : .center, spacing: 0) {
                ForEach(headline.components(separatedBy: "\n"), id: \.self) { Text($0) }
            }
            .font(CushnFont.headline)
            .foregroundStyle(theme.title)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headline.replacingOccurrences(of: "\n", with: " "))
            .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(CushnFont.supporting)
                .foregroundStyle(theme.secondary)
        }
        .multilineTextAlignment(alignment)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Text that swaps without changing height, so nothing around it moves when it does.
private struct ReservedCaption: View {
    let options: [String]
    let current: String
    let theme: CushnBrandTheme
    let identifier: String
    var alignment: Alignment = .leading

    var body: some View {
        ZStack {
            ForEach(options, id: \.self) { option in
                Text(option)
                    .font(CushnFont.secondary)
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .opacity(option == current ? 1 : 0)
                    .accessibilityHidden(option != current)
                    .accessibilityIdentifier(option == current ? identifier : "")
            }
        }
    }
}

// MARK: Page 1: what goes in

/// A grid of payments above a small piece of the real list. Tapping one shows the section it lands in, the way Home does.
private struct ChecklistDemo: View {
    let model: AppModel
    let theme: CushnBrandTheme
    let month: YearMonth
    @State private var selectedName = "Netflix"
    @State private var detail: DetailRoute?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    /// The most rows any sample section has. Shorter sections keep this height, so nothing moves between tiles.
    private static let visibleRows = 3

    var body: some View {
        let sections = model.store.view(for: month).sections
        let rows = sections.flatMap(\.rows)
        let section = sections.first { $0.rows.contains { $0.name == selectedName } }
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(rows) { row in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { selectedName = row.name }
                    } label: {
                        PaymentIcon(name: row.name, size: 56)
                            .padding(4)
                            .overlay {
                                if row.name == selectedName {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(theme.title, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.name)
                    .accessibilityHint("Shows its section")
                    .accessibilityAddTraits(row.name == selectedName ? .isSelected : [])
                    .accessibilityIdentifier("sampleTile.\(row.name)")
                }
            }
            if let section {
                SamplePanel {
                    Text(section.title)
                        .font(CushnFont.sectionTitle)
                        .foregroundStyle(CushnColor.heading)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("sampleSection")
                    ForEach(section.rows.prefix(Self.visibleRows)) { row in
                        PaymentRowView(row: row, month: month, detail: $detail, opensDetails: false, isCompact: true)
                    }
                    if let spare = section.rows.first {
                        ForEach(0..<max(Self.visibleRows - section.rows.count, 0), id: \.self) { _ in
                            PaymentRowView(row: spare, month: month, detail: $detail, opensDetails: false, isCompact: true)
                                .hidden()
                                .accessibilityHidden(true)
                        }
                    }
                }
                .environment(model)
            }
        }
    }
}

/// The surface a real row sits on, so its gray text keeps its contrast on any theme's background.
private struct SamplePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CushnColor.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CushnColor.hairline, lineWidth: 1) }
    }
}

// MARK: Page 2: one payment, three states

private struct StatusDemo: View {
    let sample: (model: AppModel, target: UUID)
    let theme: CushnBrandTheme
    let month: YearMonth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var row: MonthRow? { sample.model.store.view(for: month).rows.first { $0.id == sample.target } }

    var body: some View {
        let status = row?.status ?? .unconfirmed
        VStack(spacing: 20) {
            if let row {
                VStack(spacing: 10) {
                    PaymentIcon(name: row.name, size: 72)
                    VStack(spacing: 2) {
                        Text(row.name)
                            .font(CushnFont.sectionTitle)
                            .foregroundStyle(theme.title)
                        Text("\(row.amount.formatted()) · Due \(DateText.monthDay(row.dueDate, wide: false))")
                            .font(CushnFont.supporting)
                            .monospacedDigit()
                            .foregroundStyle(theme.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Button {
                _ = sample.model.tapStatusCircle(id: sample.target, month: month)
            } label: {
                Image(systemName: StatusCircle.symbol(for: status))
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(theme.title)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .frame(width: 88, height: 88)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: status)
            .accessibilityLabel(status == .paid ? "Undo paid for Netflix" : "Mark Netflix paid")
            .accessibilityValue(status.rawValue)
            .accessibilityIdentifier("statusCircle.Netflix")

            let optionLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
            optionLayout {
                ForEach(PaymentStatus.allCases, id: \.self) { option in
                    Button {
                        set(option)
                    } label: {
                        Text(title(option))
                            .font(CushnFont.groupTitle)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                            .foregroundStyle(option == status ? theme.background : theme.title)
                            .frame(maxWidth: .infinity, minHeight: CushnSpacing.touchTarget)
                            .background(option == status ? theme.title : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == status ? .isSelected : [])
                    .accessibilityIdentifier("statusOption.\(option.rawValue)")
                }
            }
            ReservedCaption(options: PaymentStatus.allCases.map(caption), current: caption(status), theme: theme,
                            identifier: "statusDemoCaption", alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }

    private func set(_ status: PaymentStatus) {
        sample.model.attempt { try sample.model.store.setStatus(status, id: sample.target, month: month) }
    }

    private func title(_ status: PaymentStatus) -> String {
        switch status {
        case .unconfirmed: "Still due"
        case .paid: "Paid"
        case .skipped: "Skipped"
        }
    }

    private func caption(_ status: PaymentStatus) -> String {
        switch status {
        case .unconfirmed: "Tap the circle when you've paid it."
        case .paid: "Your own record. Cushn never moves money."
        case .skipped: "Not this month. It's back next month."
        }
    }
}

// MARK: Page 3: two months side by side

/// Both months at once, so the behavior shows without any tapping. A tap in one month leaves the other alone.
private struct RolloverDemo: View {
    let model: AppModel
    let theme: CushnBrandTheme
    let month: YearMonth
    @Environment(\.dynamicTypeSize) private var typeSize

    private var nextMonth: YearMonth { month.adding(months: 1) }

    var body: some View {
        let first = model.store.view(for: month).rows
        let second = model.store.view(for: nextMonth).rows
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        VStack(alignment: .leading, spacing: 20) {
            layout {
                column(month, rows: first, slots: second, key: "first")
                column(nextMonth, rows: second, slots: second, key: "second")
            }
            Text("Tap a circle in \(DateText.monthName(month)). \(DateText.monthName(nextMonth)) stays as it is, and \(second.last?.name ?? "the new payment") never appears in the earlier month.")
                .font(CushnFont.secondary)
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `slots` keeps each payment on the same line in both columns, leaving a gap where a month doesn't have it.
    private func column(_ target: YearMonth, rows: [MonthRow], slots: [MonthRow], key: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The month you're in carries the heavy rule, so the two columns read as now and next.
            let isCurrent = target == month
            Text(DateText.monthName(target))
                .font(CushnFont.metric)
                .foregroundStyle(isCurrent ? theme.title : theme.secondary)
                .accessibilityAddTraits(.isHeader)
            Text("\(rows.filter { $0.status == .paid }.count) of \(rows.count) marked")
                .font(CushnFont.secondary)
                .monospacedDigit()
                .foregroundStyle(theme.secondary)
                .padding(.bottom, 8)
            Rectangle()
                .fill(isCurrent ? theme.title : theme.secondary.opacity(0.5))
                .frame(height: 2)
                .padding(.bottom, 4)
            ForEach(slots) { slot in
                if let row = rows.first(where: { $0.id == slot.id }) {
                    line(row, month: target, key: key)
                } else {
                    Color.clear.frame(height: CushnSpacing.touchTarget + 8).accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ row: MonthRow, month target: YearMonth, key: String) -> some View {
        HStack(spacing: 6) {
            PaymentIcon(name: row.name, size: 24)
            Text(row.name)
                .font(CushnFont.supporting)
                .foregroundStyle(theme.title)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Button {
                _ = model.tapStatusCircle(id: row.id, month: target)
            } label: {
                Image(systemName: StatusCircle.symbol(for: row.status))
                    .font(.title3)
                    .foregroundStyle(theme.title)
                    .frame(width: 36, height: CushnSpacing.touchTarget)
                    .frame(minWidth: CushnSpacing.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.status == .paid ? "Undo paid for" : "Mark") \(row.name)\(row.status == .paid ? "" : " paid") in \(DateText.monthName(target))")
            .accessibilityValue(row.status.rawValue)
            .accessibilityIdentifier("rollover.\(key).\(row.name)")
        }
        .padding(.vertical, 4)
    }
}
