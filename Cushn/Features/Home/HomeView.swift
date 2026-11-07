import SwiftUI

struct AddContext: Identifiable {
    let id = UUID()
    let month: YearMonth
    let categoryID: UUID?
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monthHeaderScrolls) private var headerScrolls
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var addContext: AddContext?
    @State private var detail: DetailRoute?
    @State private var review: ReviewRoute?
    @State private var showingOrganize = false
    @State private var editingSection: SectionRoute?
    @State private var showingNotifications = false
    /// Home shows just its section names, ready to drag, in place of the list.
    @State private var reorderingSections = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var month: YearMonth { model.selectedMonth }
    private var monthView: MonthView { model.store.view(for: month) }

    /// The review shows only on the current month, one message at a time.
    private var prompt: ReviewPrompt? {
        guard month == model.currentMonth else { return nil }
        return ReviewService.activePrompt(ledger: model.store.ledger, today: model.today)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !headerScrolls {
                    MonthHeader {
                        notificationsButton
                        addButton
                    }
                }
                if reorderingSections { reorderList } else { list }
            }
            .background(CushnColor.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let hint = activeHint {
                    CoachMark(hint: hint) { finish(hint) }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: activeHint)
            .environment(\.coachedStatusRow, activeHint == .status ? monthView.rows.first?.id : nil)
            .environment(\.coachesMonthTitle, activeHint == .months)
            .environment(\.coachesSettingsLogo, activeHint == .settings)
            // The title stays level with the other tabs by sharing a line with these actions. When the header
            // scrolls away (landscape and accessibility text), they keep their place in the fixed toolbar.
            .toolbar {
                if headerScrolls {
                    ToolbarItem(placement: .topBarLeading) { SettingsLogoButton() }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        notificationsButton
                        addButton
                    }
                }
            }
            .toolbar(headerScrolls ? .automatic : .hidden, for: .navigationBar)
            .toolbarBackground(CushnColor.canvas, for: .navigationBar)
        }
        .onChange(of: addContext?.id) { _, id in if id != nil { finish(.add) } }
        .onChange(of: detail) { _, route in if route != nil { finish(.more) } }
        .onChange(of: model.selectedMonth) { _, _ in finish(.months) }
        .onChange(of: monthView.rows.filter { $0.status != .unconfirmed }.count) { old, new in
            if new > old { finish(.status) }
        }
        .onChange(of: model.selectedTab) { _, _ in reorderingSections = false }
        .onChange(of: model.showingSettings) { _, isShowing in if isShowing { finish(.settings) } }
        .onChange(of: model.settingsCloseCount) { _, _ in openPendingRoute() }
        .onChange(of: model.pendingPaymentRoute) { _, _ in openPendingRoute() }
        .onAppear(perform: openPendingRoute)
        .sheet(item: $addContext, onDismiss: openPendingRoute) { context in
            PaymentEditorSheet(mode: .add(month: context.month, categoryID: context.categoryID))
        }
        .paymentDetailSheet($detail, onDismiss: openPendingRoute)
        .sheet(item: $review, onDismiss: openPendingRoute) { ReviewSheet(route: $0) }
        .sheet(isPresented: $showingOrganize, onDismiss: openPendingRoute) { OrganizeSheet(month: month) }
        .sheet(item: $editingSection, onDismiss: openPendingRoute) { SectionEditorSheet(categoryID: $0.id, month: month) }
        .sheet(isPresented: $showingNotifications, onDismiss: openPendingRoute) { NotificationsView() }
    }

    /// Opens a payment asked for by the inbox or a reminder. The inbox makes way for it. Any other open sheet could
    /// hold unsaved typing, so the payment waits until that sheet closes.
    private func openPendingRoute() {
        guard let route = model.pendingPaymentRoute else { return }
        if showingNotifications {
            showingNotifications = false
            return
        }
        guard addContext == nil, detail == nil, review == nil, editingSection == nil, !showingOrganize, !model.showingSettings else { return }
        model.pendingPaymentRoute = nil
        detail = route
    }

    private var activeHint: FirstUseHint? {
        model.firstUse.activeHint(paymentCount: monthView.rows.count)
    }

    private func finish(_ hint: FirstUseHint) {
        model.firstUse.finish(hint, wasShowing: activeHint == hint)
    }

    private var notificationsButton: some View {
        let unread = model.reminders.unreadCount
        return Button { showingNotifications = true } label: {
            actionIcon("bell", label: unread == 0 ? "Notifications" : "Notifications, \(unread) unread")
                .overlay {
                    if unread > 0 { UnreadDot().offset(x: 8, y: -9) }
                }
        }
        .accessibilityIdentifier("notificationsBell")
    }

    private var addButton: some View {
        Button { addContext = AddContext(month: month, categoryID: nil) } label: {
            // The main action, and the header's one use of the brand color. Near-black reads on gold in both appearances.
            Image(systemName: "plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(hex: 0x111111))
                .frame(width: 30, height: 30)
                .background(CushnColor.brandGold, in: Circle())
                .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                .contentShape(Rectangle())
                .accessibilityLabel("Add payment")
                .overlay {
                    if activeHint == .add {
                        Circle().strokeBorder(CushnColor.primaryText, lineWidth: 2).frame(width: 38, height: 38)
                    }
                }
        }
        .accessibilityIdentifier("addPayment")
    }

    private func actionIcon(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(CushnColor.primaryText)
            .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var list: some View {
        let sections = monthView.sections
        List {
            if headerScrolls { MonthHeader(showsLogo: false).asListRow }
            if let prompt {
                ReviewStrip(prompt: prompt) {
                    review = ReviewRoute(month: prompt.month)
                } onDismiss: {
                    model.attempt { try model.store.recordDismissal(ReviewService.dismissal(of: prompt, now: model.store.clock.now)) }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: CushnSpacing.inset, bottom: 8, trailing: CushnSpacing.inset))
                .listRowSeparator(.hidden)
                .listRowBackground(CushnColor.canvas)
            } else if activeHint == nil, model.reminders.offersPermissionPrompt {
                ReminderPermissionStrip {
                    Task { await model.reminders.requestPermission() }
                } onDismiss: {
                    model.reminders.dismissPrompt()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: CushnSpacing.inset, bottom: 8, trailing: CushnSpacing.inset))
                .listRowSeparator(.hidden)
                .listRowBackground(CushnColor.canvas)
            }
            let visibleIDs = sections.map(\.id)
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        PaymentRowView(row: row, month: month, detail: $detail)
                            .cushnListRow()
                    }
                } header: {
                    SectionHeader(
                        title: section.title,
                        count: section.rows.count,
                        canReorder: sections.count > 1,
                        moveUpTarget: SectionOrdering.neighbor(of: section.id, in: visibleIDs, movingDown: false),
                        moveDownTarget: SectionOrdering.neighbor(of: section.id, in: visibleIDs, movingDown: true),
                        onAdd: { addContext = AddContext(month: month, categoryID: section.id) },
                        onEdit: { editingSection = SectionRoute(id: section.id) },
                        onManage: { showingOrganize = true },
                        onMove: { moveSection(section.id, to: $0) },
                        onReorder: { setReordering(true) }
                    )
                    .cushnSectionHeaderInsets()
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(4)
        .environment(\.defaultMinListHeaderHeight, 1)
        .scrollContentBackground(.hidden)
        .background(CushnColor.canvas)
        .overlay {
            if sections.isEmpty {
                EmptyMonthView()
            }
        }
    }

    // MARK: Section reordering

    /// The native list reorder: drag handles, a lifted row, a clear gap at the landing place, auto-scrolling, and
    /// VoiceOver's own move actions. Rows collapse away so even a long list's sections are a short drag apart.
    private var reorderList: some View {
        let sections = monthView.sections
        return VStack(alignment: .leading, spacing: 0) {
            // Large text gives the title its own line, so no word has to break.
            ViewThatFits(in: .horizontal) {
                HStack {
                    reorderTitle.fixedSize()
                    Spacer(minLength: 8)
                    reorderDone
                }
                VStack(alignment: .leading, spacing: 0) {
                    reorderTitle
                    reorderDone
                }
            }
            .padding(.horizontal, CushnSpacing.inset)
            List {
                Section {
                    ForEach(sections) { section in
                        HStack(spacing: 6) {
                            Text(section.title)
                                .font(CushnFont.rowTitle)
                                .foregroundStyle(CushnColor.primaryText)
                            if !typeSize.isAccessibilitySize {
                                Text("\(section.rows.count)")
                                    .font(CushnFont.supporting)
                                    .monospacedDigit()
                                    .foregroundStyle(CushnColor.secondaryText)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("reorderRow.\(section.title)")
                        .listRowBackground(CushnColor.canvas)
                        .listRowInsets(EdgeInsets(top: 0, leading: CushnSpacing.inset, bottom: 0, trailing: 8))
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                    .onMove { source, destination in
                        var visible = sections.map(\.id)
                        visible.move(fromOffsets: source, toOffset: destination)
                        let order = SectionOrdering.placing(visible, in: monthView.allCategories.map(\.id))
                        model.attempt { try model.store.reorderCategories(order, month: month) }
                    }
                }
                .listSectionSeparator(.hidden, edges: .bottom)
                .listSectionSeparatorTint(CushnColor.hairline)
                // A row rather than a footer, which the system paints in its own color in dark mode.
                Text("Applies from \(DateText.monthName(month)) onward. Earlier months stay as they are.")
                    .font(CushnFont.secondary)
                    .foregroundStyle(CushnColor.secondaryText)
                    .listRowBackground(CushnColor.canvas)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: CushnSpacing.inset, bottom: 8, trailing: CushnSpacing.inset))
                    .accessibilityIdentifier("reorderNote")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
    }

    private var reorderTitle: some View {
        Text("Reorder sections")
            .font(CushnFont.sectionTitle)
            .foregroundStyle(CushnColor.heading)
            .accessibilityAddTraits(.isHeader)
    }

    private var reorderDone: some View {
        CushnTextButton("Done") { setReordering(false) }
            .accessibilityIdentifier("reorderDone")
    }

    private func setReordering(_ isOn: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { reorderingSections = isOn }
    }

    /// Takes effect from the selected month onward. Earlier months keep their order.
    private func moveSection(_ id: UUID, to target: UUID) {
        let order = monthView.allCategories.map(\.id)
        let moved = SectionOrdering.move(id, to: target, in: order)
        guard moved != order else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            model.attempt { try model.store.reorderCategories(moved, month: month) }
        }
    }
}

struct SectionRoute: Identifiable {
    let id: UUID
}

/// A section's heading. Tapping the title opens the section's options, and the handle opens Reorder, so scrolling and
/// ordinary taps never move anything.
struct SectionHeader: View {
    let title: String
    let count: Int
    let canReorder: Bool
    let moveUpTarget: UUID?
    let moveDownTarget: UUID?
    let onAdd: () -> Void
    let onEdit: () -> Void
    let onManage: () -> Void
    let onMove: (UUID) -> Void
    let onReorder: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Button("Edit section", systemImage: "pencil", action: onEdit)
                if let moveUpTarget {
                    Button("Move up", systemImage: "arrow.up") { onMove(moveUpTarget) }
                }
                if let moveDownTarget {
                    Button("Move down", systemImage: "arrow.down") { onMove(moveDownTarget) }
                }
                Button("All sections", systemImage: "list.bullet", action: onManage)
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(CushnFont.sectionTitle)
                        .foregroundStyle(CushnColor.heading)
                        .textCase(nil)
                        .multilineTextAlignment(.leading)
                    Text("\(count)")
                        .font(CushnFont.supporting)
                        .monospacedDigit()
                        .foregroundStyle(CushnColor.secondaryText)
                }
                .frame(minHeight: CushnSpacing.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // One heading for VoiceOver: "Credit Cards, 13 payments", with a single-step alternative to Reorder.
            .accessibilityLabel("\(title), \(count == 1 ? "1 payment" : "\(count) payments")")
            .accessibilityHint("Section options")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("sectionHeader.\(title)")
            .accessibilityActions {
                if let moveUpTarget {
                    Button("Move up") { onMove(moveUpTarget) }
                }
                if let moveDownTarget {
                    Button("Move down") { onMove(moveDownTarget) }
                }
            }
            Spacer(minLength: 0)
            if canReorder { reorderHandle }
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(CushnFont.glyph)
                    .foregroundStyle(CushnColor.secondaryText)
                    .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add payment to \(title)")
        }
        // Sticky headers need an opaque backing that reaches the screen edges, or rows show through while scrolling.
        .background { CushnColor.canvas.padding(.horizontal, -CushnSpacing.inset) }
    }

    private var reorderHandle: some View {
        Button(action: onReorder) {
            Image(systemName: "line.3.horizontal")
                .font(CushnFont.glyph)
                .foregroundStyle(CushnColor.secondaryText)
                .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reorder sections")
        .accessibilityIdentifier("reorderHandle.\(title)")
    }
}

struct EmptyMonthView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            CushnMark(theme: .goldMark(for: colorScheme), height: 40)
                .padding(.bottom, 4)
            Text("Nothing here yet. Add your first payment.")
                .font(CushnFont.body)
                .foregroundStyle(CushnColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(CushnSpacing.inset)
    }
}
