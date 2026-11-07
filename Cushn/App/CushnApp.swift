import SwiftUI

@main
struct CushnApp: App {
    @State private var startup = AppStartup.make()
    @AppStorage("appearance") private var appearance = AppearanceSetting.system.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                switch startup {
                case .ready(let model, let experience):
                    AppEntryView(model: model, experience: experience)
                case .failed:
                    StartupErrorView()
                }
            }
            .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch AppearanceSetting(rawValue: appearance) {
        case .light: .light
        case .dark: .dark
        default: nil
        }
    }
}

enum AppStartup {
    case ready(AppModel, LaunchExperience)
    case failed

    /// A store that can't open never leads to deleting it: the app says so and leaves the data alone.
    @MainActor
    static func make() -> AppStartup {
        do {
            #if DEBUG
            if let debug = try DebugLaunch.makeModel() { return .ready(debug, .make(for: debug)) }
            #endif
            let container = try CushnPersistence.makeContainer(url: CushnPersistence.defaultStoreURL())
            let repository = SwiftDataLedgerRepository(container: container)
            let store = try LedgerStore(repository: repository, clock: SystemClock())
            let inboxURL = try CushnPersistence.defaultStoreURL().deletingLastPathComponent().appending(path: "ReminderInbox.json")
            let model = makeLiveModel(store: store, defaults: .standard, inboxURL: inboxURL)
            return .ready(model, .make(for: model))
        } catch {
            return .failed
        }
    }
}

/// Connects a model to iOS notifications. Tapping a reminder marks its inbox item read and opens the payment.
@MainActor
func makeLiveModel(store: LedgerStore, defaults: UserDefaults?, inboxURL: URL?) -> AppModel {
    final class Box: @unchecked Sendable { weak var model: AppModel? }
    let box = Box()
    let client = LiveNotificationClient(onOpen: { _, paymentID, month in
        guard let model = box.model else { return }
        model.reminders.refreshInbox()
        model.reminders.markRead(InboxEntry.id(paymentID: paymentID, month: month))
        model.openPayment(paymentID, month: month)
    }, onPresent: {
        box.model?.reminders.requestReconcile()
    })
    let center = ReminderCenter(store: store, client: client, defaults: defaults, inboxURL: inboxURL)
    let model = AppModel(store: store, reminders: center)
    box.model = model
    return model
}

struct StartupErrorView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Cushn couldn't open your list").font(.headline)
            Text("Your data hasn't been changed. Try closing and reopening the app.")
                .font(.subheadline)
                .foregroundStyle(CushnColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(CushnSpacing.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CushnColor.canvas)
    }
}
