import SwiftUI

extension View {
    func paymentDetailSheet(_ route: Binding<DetailRoute?>, onDismiss: (() -> Void)? = nil) -> some View {
        sheet(item: route, onDismiss: onDismiss) { PaymentDetailSheet(route: $0) }
    }
}

/// Row tap destination: details plus Edit, status actions and Remove. Nothing here needs a swipe.
struct PaymentDetailSheet: View {
    let route: DetailRoute
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmingRemove = false

    /// Tall enough to show every action, including Remove, without scrolling at standard text sizes.
    /// A fixed height, because a fraction of a small phone's screen left Remove below the fold.
    private static let compactDetent = PresentationDetent.height(640)

    private var row: MonthRow? { model.store.view(for: route.month).row(route.paymentID) }

    var body: some View {
        NavigationStack {
            Group {
                if let row { content(row) }
            }
            .navigationTitle(DateText.monthYear(route.month))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([Self.compactDetent, .large])
        .sheet(isPresented: $editing) {
            if let row { PaymentEditorSheet(mode: .edit(row: row, month: route.month)) }
        }
        .presentationBackground(CushnColor.surface)
    }

    private func content(_ row: MonthRow) -> some View {
        List {
            Section {
                HStack(spacing: 12) {
                    PaymentIcon(name: row.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(CushnFont.metric)
                            .accessibilityIdentifier("detailName")
                        Text(row.amount.formatted())
                            .font(CushnFont.supporting)
                            .monospacedDigit()
                            .foregroundStyle(CushnColor.secondaryText)
                            .accessibilityIdentifier("detailAmount")
                        if row.amount.minorUnits > 0, let yearly = row.amount.yearlyEstimate {
                            Text("About \(yearly.formatted()) a year")
                                .font(CushnFont.secondary)
                                .monospacedDigit()
                                .foregroundStyle(CushnColor.secondaryText)
                                .accessibilityIdentifier("detailYearly")
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                LabeledContent("Due", value: dueText(row))
                LabeledContent("Status", value: statusText(row))
                    .accessibilityIdentifier("detailStatus")
            }
            .listRowBackground(CushnColor.canvas)
            Section {
                statusActions(row)
                Button { editing = true } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .accessibilityIdentifier("editAction")
            }
            .tint(CushnColor.primaryText)
            .listRowBackground(CushnColor.canvas)
            Section {
                Button(role: .destructive) { confirmingRemove = true } label: {
                    Label("Remove", systemImage: "trash")
                        .foregroundStyle(CushnColor.destructive)
                }
                .accessibilityIdentifier("removeAction")
            }
            .listRowBackground(CushnColor.canvas)
        }
        .listSectionSpacing(16)
        .scrollContentBackground(.hidden)
        // An alert, not a dialog: on iOS 26 a dialog's popover has no Cancel and cuts off this text at large sizes.
        .alert(removeTitle, isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                model.attempt { try model.store.remove(id: row.id, month: route.month) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removeMessage(row))
        }
    }

    @ViewBuilder
    private func statusActions(_ row: MonthRow) -> some View {
        switch row.status {
        case .unconfirmed:
            action("Mark paid", symbol: "checkmark.circle", id: "markPaidAction", .paid)
            action("Skip this month", symbol: "minus.circle", id: "skipAction", .skipped)
        case .paid:
            action("Undo paid", symbol: "arrow.uturn.backward.circle", id: "undoPaidAction", .unconfirmed)
            action("Skip this month", symbol: "minus.circle", id: "skipAction", .skipped)
        case .skipped:
            action("Undo skip", symbol: "arrow.uturn.backward.circle", id: "undoSkipAction", .unconfirmed)
            action("Mark paid", symbol: "checkmark.circle", id: "markPaidAction", .paid)
        }
    }

    private func action(_ title: String, symbol: String, id: String, _ status: PaymentStatus) -> some View {
        Button {
            model.attempt { try model.store.setStatus(status, id: route.paymentID, month: route.month) }
        } label: {
            Label(title, systemImage: symbol)
        }
        .accessibilityIdentifier(id)
    }

    private func dueText(_ row: MonthRow) -> String {
        let date = DateText.monthDay(row.dueDate, wide: true)
        return row.dueDate.day < row.nominalDueDay.value ? "\(date) (last day of the month)" : date
    }

    private func statusText(_ row: MonthRow) -> String {
        switch row.status {
        case .unconfirmed: return "Not marked paid"
        case .skipped: return "Skipped for \(DateText.monthName(route.month))"
        case .paid:
            guard let at = row.confirmedAt else { return "Marked paid" }
            return "Marked paid \(DateText.monthDay(at, wide: false))"
        }
    }

    private var removeTitle: String { "Remove from \(DateText.monthName(route.month)) onward?" }

    private func removeMessage(_ row: MonthRow) -> String {
        let created = model.store.ledger.payments[row.id]?.createdMonth
        if created == route.month { return "It wasn't in any earlier month." }
        return "\(DateText.monthName(route.month.previous)) and earlier months stay in your history."
    }
}
