import SwiftUI

struct DetailRoute: Identifiable, Hashable {
    let paymentID: UUID
    let month: YearMonth
    var id: String { "\(paymentID.uuidString)|\(month.ordinal)" }
}

/// A flat payment row. Status changes only the trailing glyph: never the text, opacity or position.
struct PaymentRowView: View {
    let row: MonthRow
    let month: YearMonth
    @Binding var detail: DetailRoute?
    /// False for sample rows, whose body isn't tappable.
    var opensDetails = true
    /// Tighter vertical padding, for the miniature lists in onboarding.
    var isCompact = false
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.coachedStatusRow) private var coachedStatusRow

    var body: some View {
        let text = RowPresentation(row: row, today: model.today)
        HStack(spacing: 4) {
            if opensDetails {
                Button { detail = DetailRoute(paymentID: row.id, month: month) } label: {
                    content(text).contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text.accessibilityLabel)
                .accessibilityHint("Shows details")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("paymentRow.\(row.name)")
            } else {
                content(text)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(text.accessibilityLabel)
                    .accessibilityIdentifier("sampleRow.\(row.name)")
            }

            StatusCircle(status: row.status, accessibilityLabel: text.statusActionLabel) {
                if model.tapStatusCircle(id: row.id, month: month) {
                    detail = DetailRoute(paymentID: row.id, month: month)
                }
            }
            .accessibilityIdentifier("statusCircle.\(row.name)")
            .accessibilityValue(row.status.rawValue)
            .overlay {
                if coachedStatusRow == row.id {
                    Circle()
                        .strokeBorder(CushnColor.brandGold, lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ text: RowPresentation) -> some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            if !typeSize.isAccessibilitySize {
                PaymentIcon(name: row.name)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(CushnFont.rowTitle)
                    .foregroundStyle(CushnColor.primaryText)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                    .multilineTextAlignment(.leading)
                Text(text.dueLine)
                    .font(CushnFont.secondary)
                    .foregroundStyle(text.isPastDue ? CushnColor.attention : CushnColor.secondaryText)
                if typeSize.isAccessibilitySize {
                    amount(text)
                }
            }
            Spacer(minLength: 8)
            if !typeSize.isAccessibilitySize {
                amount(text)
            }
        }
        .padding(.vertical, isCompact ? 5 : CushnSpacing.rowVertical)
    }

    private func amount(_ text: RowPresentation) -> some View {
        Text(text.amountText)
            .font(CushnFont.rowAmount)
            .monospacedDigit()
            .foregroundStyle(CushnColor.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
    }
}

/// Press feedback that only tints the background, so row text keeps full opacity.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? CushnColor.surface : .clear)
    }
}

extension View {
    /// Aligns a section title with the rows below it.
    func cushnSectionHeaderInsets() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: CushnSpacing.inset, bottom: 0, trailing: 8))
    }

    /// Flat row styling shared by every payment list.
    func cushnListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: CushnSpacing.inset, bottom: 0, trailing: 8))
            .listRowBackground(CushnColor.canvas)
            .listRowSeparatorTint(CushnColor.hairline)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
