import SwiftUI

struct ReviewRoute: Identifiable, Hashable {
    let month: YearMonth
    var id: Int { month.ordinal }
}

/// A small inline note. It doesn't block the list, and dismissing it changes no payment.
struct ReviewStrip: View {
    let prompt: ReviewPrompt
    let onReview: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onReview) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.count == 1 ? "1 payment still needs a check" : "\(prompt.count) payments still need a check")
                        .font(CushnFont.groupTitle)
                        .foregroundStyle(CushnColor.primaryText)
                    // At accessibility sizes the headline alone keeps the note compact; the review has the detail.
                    if !typeSize.isAccessibilitySize {
                        Text(detail)
                            .font(CushnFont.secondary)
                            .foregroundStyle(CushnColor.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the review")
            .accessibilityIdentifier("reviewStrip")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(CushnFont.glyph)
                    .foregroundStyle(CushnColor.secondaryText)
                    .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss review note")
            .accessibilityIdentifier("dismissReview")
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .background(CushnColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detail: String {
        let name = DateText.monthName(prompt.month)
        let verb = prompt.count == 1 ? "This was" : "These were"
        let helper = prompt.count == 1 ? "hasn't" : "haven't"
        return "\(verb) due in \(name) and \(helper) been marked paid."
    }
}

/// A month's past-due, not-yet-marked rows. The list is fixed when opened, so a row
/// doesn't disappear under the user's finger the moment it's marked.
struct ReviewSheet: View {
    let route: ReviewRoute
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rowIDs: [UUID] = []
    @State private var detail: DetailRoute?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        PaymentRowView(row: row, month: route.month, detail: $detail)
                            .cushnListRow()
                    }
                } footer: {
                    Text("Mark what you paid, skip what you didn't, or leave anything as it is. Changes apply to \(DateText.monthName(route.month)) only.")
                        .font(CushnFont.secondary)
                        .foregroundStyle(CushnColor.secondaryText)
                        .padding(.top, 8)
                        .cushnSectionHeaderInsets()
                }
                .listSectionSeparator(.hidden)
            }
            .listStyle(.plain)
            .navigationTitle("\(DateText.monthName(route.month)) review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .paymentDetailSheet($detail)
        .onAppear {
            rowIDs = ReviewService.rows(month: route.month, ledger: model.store.ledger, today: model.today).map(\.id)
        }
    }

    private var rows: [MonthRow] {
        let view = model.store.view(for: route.month)
        return rowIDs.compactMap { view.row($0) }
    }
}
