import Foundation
import Observation

enum ReminderAuthorization: Equatable, Sendable {
    /// Not asked yet, or this launch is one that must not touch iOS (demos and samples).
    case unknown, notDetermined, denied, allowed
}

/// The value handed to iOS. Keeps the system framework out of the scheduling logic.
struct ReminderRequest: Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let fireDay: CalendarDay
    let hour: Int
    let minute: Int
    let paymentID: UUID
    let month: YearMonth
}

@MainActor
protocol NotificationClient: AnyObject {
    func authorization() async -> ReminderAuthorization
    /// Returns whether alerts were allowed.
    func requestAuthorization() async -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ request: ReminderRequest) async
    func remove(identifiers: [String])
}

/// Used wherever a launch must never reach iOS, such as onboarding's sample lists and debug demos.
@MainActor
final class InertNotificationClient: NotificationClient {
    private let status: ReminderAuthorization
    init(status: ReminderAuthorization = .unknown) { self.status = status }
    func authorization() async -> ReminderAuthorization { status }
    func requestAuthorization() async -> Bool { false }
    func pendingIdentifiers() async -> [String] { [] }
    func add(_ request: ReminderRequest) async {}
    func remove(identifiers: [String]) {}
}

/// Keeps iOS's pending reminders and the inbox in step with the ledger, and owns the reminder preferences.
///
/// Inbox policy: every time the app looks (launch, foreground, any change), reminder moments that passed since the
/// last look update the one entry for that payment and month, for payments still unconfirmed at that moment of looking.
/// The first look only records the time, so updating never floods the inbox. An entry means the moment passed. It
/// doesn't mean iOS showed an alert, which the app can't know.
@Observable @MainActor
final class ReminderCenter {
    private enum Key {
        static let enabled = "cushn.reminders.enabled"
        static let threeDays = "cushn.reminders.threeDays"
        static let dueToday = "cushn.reminders.dueToday"
        static let hour = "cushn.reminders.hour"
        static let minute = "cushn.reminders.minute"
        static let promptDismissed = "cushn.reminders.promptDismissed"
    }

    private struct InboxFile: Codable {
        var lastLook: Date?
        var entries: [InboxEntry] = []
    }

    static let inboxLimit = 200

    private(set) var preferences: ReminderPreferences
    private(set) var authorization = ReminderAuthorization.unknown
    private(set) var entries: [InboxEntry] = []
    private(set) var promptDismissed: Bool

    @ObservationIgnored private let store: LedgerStore
    @ObservationIgnored private let client: any NotificationClient
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let inboxURL: URL?
    @ObservationIgnored private var lastLook: Date?
    @ObservationIgnored private var isReconciling = false
    @ObservationIgnored private var needsAnotherPass = false

    /// `defaults` and `inboxURL` are nil for throwaway instances, which then save nothing.
    init(store: LedgerStore, client: any NotificationClient, defaults: UserDefaults?, inboxURL: URL?) {
        self.store = store
        self.client = client
        self.defaults = defaults
        self.inboxURL = inboxURL
        var loaded = ReminderPreferences()
        if let defaults {
            if defaults.object(forKey: Key.enabled) != nil { loaded.isEnabled = defaults.bool(forKey: Key.enabled) }
            if defaults.object(forKey: Key.threeDays) != nil { loaded.threeDaysBefore = defaults.bool(forKey: Key.threeDays) }
            if defaults.object(forKey: Key.dueToday) != nil { loaded.dueToday = defaults.bool(forKey: Key.dueToday) }
            if defaults.object(forKey: Key.hour) != nil { loaded.hour = defaults.integer(forKey: Key.hour) }
            if defaults.object(forKey: Key.minute) != nil { loaded.minute = defaults.integer(forKey: Key.minute) }
        }
        preferences = loaded
        promptDismissed = defaults?.bool(forKey: Key.promptDismissed) ?? false
        // A damaged inbox file starts empty. It's separate from the payment store, so payments aren't affected.
        if let inboxURL, let data = try? Data(contentsOf: inboxURL),
           let file = try? JSONDecoder().decode(InboxFile.self, from: data) {
            lastLook = file.lastLook
            entries = file.entries
        }
    }

    var unreadCount: Int { entries.lazy.filter { !$0.isRead }.count }

    /// The one-time, skippable offer on Home. Waits for a payment, so the reason for asking is clear.
    var offersPermissionPrompt: Bool {
        authorization == .notDetermined && preferences.isEnabled && !promptDismissed && !store.ledger.payments.isEmpty
    }

    // MARK: Preferences and permission

    func update(_ change: (inout ReminderPreferences) -> Void) {
        change(&preferences)
        defaults?.set(preferences.isEnabled, forKey: Key.enabled)
        defaults?.set(preferences.threeDaysBefore, forKey: Key.threeDays)
        defaults?.set(preferences.dueToday, forKey: Key.dueToday)
        defaults?.set(preferences.hour, forKey: Key.hour)
        defaults?.set(preferences.minute, forKey: Key.minute)
        requestReconcile()
    }

    /// iOS shows its question only once. This does nothing unless that question is still open.
    func requestPermission() async {
        guard authorization == .notDetermined else { return }
        _ = await client.requestAuthorization()
        dismissPrompt()
        await reconcileNow()
    }

    func dismissPrompt() {
        promptDismissed = true
        defaults?.set(true, forKey: Key.promptDismissed)
    }

    // MARK: Inbox

    func markRead(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), !entries[index].isRead else { return }
        entries[index].readAt = store.clock.now
        saveInbox()
    }

    func markAllRead() {
        let now = store.clock.now
        for index in entries.indices where !entries[index].isRead { entries[index].readAt = now }
        saveInbox()
    }

    /// Removes the inbox line only. The payment and its status don't change.
    func dismiss(_ id: String) {
        entries.removeAll { $0.id == id }
        saveInbox()
    }

    /// Brings the inbox up to date. Runs synchronously, so opening from a notification can mark its entry read.
    func refreshInbox() {
        let now = store.clock.now
        defer {
            lastLook = max(lastLook ?? now, now)
            saveInbox()
        }
        guard let lastLook else { return }
        // In time order, so the latest moment for a payment and month is the one kept.
        let new = ReminderPlanner.occurred(after: lastLook, upTo: now, ledger: store.ledger,
                                           timeZone: store.clock.timeZone, preferences: preferences)
            .map(InboxEntry.init(reminder:))
        guard !new.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for entry in new { byID[entry.id] = entry }
        entries = Array(byID.values.sorted { a, b in
            a.occurredAt != b.occurredAt ? a.occurredAt > b.occurredAt : a.id < b.id
        }.prefix(Self.inboxLimit))
    }

    private func saveInbox() {
        guard let inboxURL else { return }
        // A failed save costs reminder history at worst, so it doesn't interrupt the person with an alert.
        try? FileManager.default.createDirectory(at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(InboxFile(lastLook: lastLook, entries: entries)) {
            try? data.write(to: inboxURL, options: .atomic)
        }
    }

    // MARK: Reconciling

    /// Coalesces bursts of changes. The last state always gets a pass.
    func requestReconcile() {
        guard !isReconciling else {
            needsAnotherPass = true
            return
        }
        Task { await reconcileNow() }
    }

    func reconcileNow() async {
        guard !isReconciling else {
            needsAnotherPass = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            needsAnotherPass = false
            await reconcileOnce()
        } while needsAnotherPass
    }

    private func reconcileOnce() async {
        authorization = await client.authorization()
        refreshInbox()
        let timeZone = store.clock.timeZone
        let plan = authorization == .allowed
            ? ReminderPlanner.upcoming(ledger: store.ledger, now: store.clock.now, timeZone: timeZone, preferences: preferences)
            : []
        let wanted = Set(plan.map(\.id))
        let stale = await client.pendingIdentifiers()
            .filter { $0.hasPrefix(PlannedReminder.identifierPrefix) && !wanted.contains($0) }
        if !stale.isEmpty { client.remove(identifiers: stale) }
        // Adding an existing identifier replaces it, so edits carry through and nothing doubles up.
        for reminder in plan {
            await client.add(ReminderRequest(id: reminder.id, title: reminder.title, body: reminder.body(timeZone: timeZone),
                                             fireDay: reminder.fireDay, hour: reminder.hour, minute: reminder.minute,
                                             paymentID: reminder.paymentID, month: reminder.month))
        }
    }

    #if DEBUG
    /// Lets demos and UI tests show real entries by pretending the last look was earlier.
    func debugBackdateLastLook(days: Int) {
        lastLook = store.clock.now.addingTimeInterval(-Double(days) * 86_400)
    }
    #endif
}
