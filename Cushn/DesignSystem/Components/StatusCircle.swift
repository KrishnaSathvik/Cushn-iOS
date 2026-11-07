import SwiftUI

/// The trailing status control. Shape carries the status, so nothing depends on color alone.
struct StatusCircle: View {
    let status: PaymentStatus
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var glyphSize = 24

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyphSize, weight: .regular))
                .foregroundStyle(color)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: status)
        .accessibilityLabel(accessibilityLabel)
    }

    private var symbol: String { Self.symbol(for: status) }

    static func symbol(for status: PaymentStatus) -> String {
        switch status {
        case .unconfirmed: "circle"
        case .paid: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        }
    }

    private var color: Color {
        switch status {
        case .unconfirmed: CushnColor.openCircle
        case .paid: CushnColor.primaryText
        case .skipped: CushnColor.mutedMark
        }
    }
}
