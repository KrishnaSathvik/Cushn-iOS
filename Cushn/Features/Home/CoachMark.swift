import SwiftUI

extension EnvironmentValues {
    /// The row whose status circle a first-use hint is pointing at.
    @Entry var coachedStatusRow: UUID?
    /// Whether a first-use hint is pointing at the month title.
    @Entry var coachesMonthTitle = false
    /// Whether a first-use hint is pointing at the logo, which opens Settings.
    @Entry var coachesSettingsLogo = false
}

/// A small first-use note beneath the list. It covers nothing and blocks nothing, and any action can come first.
struct CoachMark: View {
    let hint: FirstUseHint
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(CushnColor.brandGold)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(hint.title)
                    .font(CushnFont.groupTitle)
                    .foregroundStyle(CushnColor.primaryText)
                Text(hint.message)
                    .font(CushnFont.secondary)
                    .foregroundStyle(CushnColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("coachMark.\(hint.rawValue)")
            .padding(.vertical, 2)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(CushnFont.glyph)
                    .foregroundStyle(CushnColor.secondaryText)
                    .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
            .accessibilityIdentifier("dismissCoachMark")
        }
        .padding(.leading, 14)
        .padding(.vertical, 6)
        .padding(.trailing, 2)
        .background(CushnColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, CushnSpacing.inset)
        .padding(.vertical, 8)
        .onAppear {
            AccessibilityNotification.Announcement("\(hint.title). \(hint.message)").post()
        }
    }
}
