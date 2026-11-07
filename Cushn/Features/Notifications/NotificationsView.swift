import SwiftUI

/// History of reminders. The checklist stays the source of truth: nothing here changes a payment.
struct NotificationsView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", unread = "Unread"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var filter = Filter.all

    private var reminders: ReminderCenter { model.reminders }
    private var visible: [InboxEntry] {
        filter == .all ? reminders.entries : reminders.entries.filter { !$0.isRead }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("notificationsFilter")
                    .listRowInsets(EdgeInsets(top: 4, leading: CushnSpacing.inset, bottom: 8, trailing: CushnSpacing.inset))
                    .listRowSeparator(.hidden)
                    .listRowBackground(CushnColor.canvas)
                    // Lives here rather than in the toolbar, where large text squeezed the title to "Notificati…".
                    if reminders.unreadCount > 0 {
                        HStack {
                            Spacer(minLength: 0)
                            Button { reminders.markAllRead() } label: {
                                Text("Mark All Read")
                                    .font(CushnFont.supportingEmphasis)
                                    .foregroundStyle(CushnColor.primaryText)
                                    .frame(minHeight: CushnSpacing.touchTarget)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("markAllRead")
                        }
                            .listRowInsets(EdgeInsets(top: 0, leading: CushnSpacing.inset, bottom: 0, trailing: CushnSpacing.inset))
                            .listRowSeparator(.hidden)
                            .listRowBackground(CushnColor.canvas)
                    }
                }
                ForEach(visible) { entry in
                    NotificationRow(entry: entry) {
                        reminders.markRead(entry.id)
                        // A stale item stays put: it never opens a different payment or another month's record.
                        if model.store.view(for: entry.month).row(entry.paymentID) != nil {
                            model.openPayment(entry.paymentID, month: entry.month)
                            dismiss()
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: CushnSpacing.inset, bottom: 0, trailing: 8))
                    .listRowBackground(CushnColor.canvas)
                    .swipeActions {
                        Button("Dismiss", role: .destructive) { reminders.dismiss(entry.id) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(CushnColor.canvas)
            .overlay {
                if visible.isEmpty { emptyState }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .toolbarBackground(CushnColor.canvas, for: .navigationBar)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(filter == .all ? "No notifications yet" : "You're all caught up")
                .font(CushnFont.metric)
                .foregroundStyle(CushnColor.primaryText)
            Text(filter == .all ? "Reminders about upcoming payments appear here." : "Nothing unread right now.")
                .font(CushnFont.supporting)
                .foregroundStyle(CushnColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(CushnSpacing.inset)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notificationsEmpty")
    }
}

private struct NotificationRow: View {
    let entry: InboxEntry
    let onOpen: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let row = model.store.view(for: entry.month).row(entry.paymentID)
        let status = InboxText.status(row: row, entry: entry, today: model.today)
        let detail = InboxText.detail(row: row, entry: entry, today: model.today)
        HStack(spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    PaymentIcon(name: entry.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(entry.isRead ? CushnFont.body : CushnFont.rowTitle.weight(.semibold))
                            .foregroundStyle(CushnColor.primaryText)
                        Text(status)
                            .font(CushnFont.supporting)
                            .foregroundStyle(CushnColor.primaryText)
                        Text(detail)
                            .font(CushnFont.secondary)
                            .monospacedDigit()
                            .foregroundStyle(CushnColor.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if !entry.isRead { UnreadDot() }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.isRead ? "" : "Unread. ")\(entry.name), \(status), \(detail)")
            .accessibilityHint(row == nil ? "" : "Opens this payment")
            .accessibilityIdentifier("notification.\(entry.name)")

            // Everything a swipe does is here too.
            Menu {
                if !entry.isRead {
                    Button("Mark as Read") { model.reminders.markRead(entry.id) }
                }
                Button("Dismiss", role: .destructive) { model.reminders.dismiss(entry.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(CushnFont.glyph)
                    .foregroundStyle(CushnColor.secondaryText)
                    .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(entry.name)")
            .accessibilityIdentifier("notificationOptions.\(entry.name)")
        }
    }
}

/// The restrained gold mark for something unread. The thin ring keeps it visible on white.
struct UnreadDot: View {
    var body: some View {
        Circle()
            .fill(CushnColor.brandGold)
            .overlay { Circle().strokeBorder(CushnColor.primaryText, lineWidth: 1) }
            .frame(width: 9, height: 9)
            .accessibilityHidden(true)
    }
}

/// A one-time offer shown on Home after a payment exists. Declining changes nothing else in the app.
struct ReminderPermissionStrip: View {
    let onTurnOn: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Get a reminder before payments are due")
                    .font(CushnFont.groupTitle)
                    .foregroundStyle(CushnColor.primaryText)
                Text("3 days before and on the due date. You can change this in Settings.")
                    .font(CushnFont.secondary)
                    .foregroundStyle(CushnColor.secondaryText)
                Button("Turn On", action: onTurnOn)
                    .font(CushnFont.groupTitle)
                    .foregroundStyle(CushnColor.primaryText)
                    .frame(minHeight: CushnSpacing.touchTarget)
                    .accessibilityIdentifier("reminderPromptTurnOn")
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(CushnFont.glyph)
                    .foregroundStyle(CushnColor.secondaryText)
                    .frame(minWidth: CushnSpacing.touchTarget, minHeight: CushnSpacing.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
            .accessibilityIdentifier("reminderPromptDismiss")
        }
        .padding(.leading, 14)
        .padding(.top, 12)
        .padding(.trailing, 4)
        .background(CushnColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminderPrompt")
    }
}
