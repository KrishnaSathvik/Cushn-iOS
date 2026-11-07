import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearance") private var appearance = AppearanceSetting.system.rawValue
    @AppStorage(AppModel.defaultCurrencyKey) private var storedCurrency = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    header("Appearance")
                }
                Section {
                    Picker("Default currency", selection: Binding(
                        get: { storedCurrency.isEmpty ? model.defaultCurrency : storedCurrency },
                        set: { storedCurrency = $0 }
                    )) {
                        ForEach(CurrencyOptions.options(including: model.defaultCurrency), id: \.self) { code in
                            Text("\(code) · \(CurrencyOptions.displayName(code))").tag(code)
                        }
                    }
                } header: {
                    header("Currency")
                }
                remindersSection
                Section {
                    HStack(spacing: 14) {
                        CushnMark(theme: .goldMark(for: colorScheme), height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cushn").font(CushnFont.rowTitle)
                            Text("See what's due. Mark what's done.")
                                .font(CushnFont.secondary)
                                .foregroundStyle(CushnColor.secondaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                        .monospacedDigit()
                        .accessibilityIdentifier("versionRow")
                    // App Review requires a privacy policy link inside the app. These open in Safari. Cushn itself makes no requests.
                    webLink("Privacy Policy", "https://cushn.app/privacy", id: "privacyLink")
                    webLink("Support", "https://cushn.app/support", id: "supportLink")
                } header: {
                    header("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(CushnColor.surface)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        let reminders = model.reminders
        let isDenied = reminders.authorization == .denied
        Section {
            Toggle("Payment reminders", isOn: Binding(
                get: { reminders.preferences.isEnabled && reminders.authorization == .allowed },
                set: { isOn in
                    reminders.update { $0.isEnabled = isOn }
                    if isOn { Task { await reminders.requestPermission() } }
                }
            ))
            .disabled(isDenied)
            .tint(CushnColor.brandGold)
            .accessibilityIdentifier("remindersToggle")
            // These only mean something once alerts are on, so they don't show on beneath a switch that's off.
            if reminders.preferences.isEnabled && reminders.authorization == .allowed {
                Toggle("3 days before", isOn: Binding(
                    get: { reminders.preferences.threeDaysBefore },
                    set: { isOn in reminders.update { $0.threeDaysBefore = isOn } }
                ))
                .tint(CushnColor.brandGold)
                .accessibilityIdentifier("remindersThreeDays")
                Toggle("On the due date", isOn: Binding(
                    get: { reminders.preferences.dueToday },
                    set: { isOn in reminders.update { $0.dueToday = isOn } }
                ))
                .tint(CushnColor.brandGold)
                .accessibilityIdentifier("remindersDueToday")
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("remindersTime")
            }
            if isDenied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .foregroundStyle(CushnColor.primaryText)
                .accessibilityIdentifier("remindersOpenSettings")
            }
        } header: {
            header("Reminders")
        }
    }

    private func webLink(_ title: String, _ address: String, id: String) -> some View {
        Button(title) {
            if let url = URL(string: address) { openURL(url) }
        }
        .foregroundStyle(CushnColor.primaryText)
        .accessibilityHint("Opens in Safari")
        .accessibilityIdentifier(id)
    }

    private var reminderTime: Binding<Date> {
        let calendar = Calendar.current
        return Binding(
            get: {
                let preferences = model.reminders.preferences
                return calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: preferences.hour, minute: preferences.minute)) ?? .now
            },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                model.reminders.update {
                    $0.hour = parts.hour ?? 9
                    $0.minute = parts.minute ?? 0
                }
            }
        )
    }

    /// The system's header color falls short of the audit on 2x screens.
    private func header(_ title: String) -> some View {
        Text(title)
            .font(CushnFont.groupTitle)
            .foregroundStyle(CushnColor.heading)
            .textCase(nil)
    }
}
