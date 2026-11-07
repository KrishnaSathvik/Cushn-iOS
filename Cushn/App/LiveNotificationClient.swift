import Foundation
import UserNotifications

/// The only file that talks to iOS notifications.
@MainActor
final class LiveNotificationClient: NotificationClient {
    private let center = UNUserNotificationCenter.current()
    private let delegate: Delegate

    /// `onOpen` runs when the person taps a delivered reminder.
    init(onOpen: @escaping @MainActor @Sendable (_ id: String, _ paymentID: UUID, _ month: YearMonth) -> Void,
         onPresent: @escaping @MainActor @Sendable () -> Void) {
        delegate = Delegate(onOpen: onOpen, onPresent: onPresent)
        center.delegate = delegate
    }

    func authorization() async -> ReminderAuthorization {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let status: ReminderAuthorization = switch settings.authorizationStatus {
                case .notDetermined: .notDetermined
                case .denied: .denied
                case .authorized, .provisional, .ephemeral: .allowed
                @unknown default: .denied
                }
                continuation.resume(returning: status)
            }
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    func add(_ request: ReminderRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = ["paymentID": request.paymentID.uuidString, "month": request.month.ordinal]
        // No time zone on purpose: the components stay local, so 9:00 AM is 9:00 AM after travel or a clock change.
        let parts = DateComponents(year: request.fireDay.year, month: request.fireDay.month, day: request.fireDay.day,
                                   hour: request.hour, minute: request.minute)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let system = UNNotificationRequest(identifier: request.id, content: content, trigger: trigger)
        try? await center.add(system)
    }

    func remove(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
        let onOpen: @MainActor @Sendable (String, UUID, YearMonth) -> Void
        let onPresent: @MainActor @Sendable () -> Void

        init(onOpen: @escaping @MainActor @Sendable (String, UUID, YearMonth) -> Void, onPresent: @escaping @MainActor @Sendable () -> Void) {
            self.onOpen = onOpen
            self.onPresent = onPresent
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            let request = response.notification.request
            let info = request.content.userInfo
            if let text = info["paymentID"] as? String, let paymentID = UUID(uuidString: text), let ordinal = info["month"] as? Int {
                let (id, month, onOpen) = (request.identifier, YearMonth(ordinal: ordinal), onOpen)
                Task { @MainActor in onOpen(id, paymentID, month) }
            }
            completionHandler()
        }

        /// A reminder that comes due while the app is open still shows, and reaches the inbox straight away.
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            let onPresent = onPresent
            Task { @MainActor in onPresent() }
            completionHandler([.banner, .list, .sound])
        }
    }
}
