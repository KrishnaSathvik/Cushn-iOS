import Foundation
import Observation

/// Who sees onboarding. Someone with saved payments is never sent through it after an update.
enum OnboardingGate {
    enum Decision: Equatable { case show, skip, skipExistingUser }

    static func decision(completed: Bool, hasPayments: Bool) -> Decision {
        if completed { return .skip }
        return hasPayments ? .skipExistingUser : .show
    }
}

enum FirstUseHint: String, CaseIterable, Sendable {
    case add, status, more, months, settings

    var title: String {
        switch self {
        case .add: "Add your first payment"
        case .status: "Mark it paid"
        case .more: "Tap for more"
        case .months: "Every month, organized"
        case .settings: "Settings live here"
        }
    }

    var message: String {
        switch self {
        case .add: "Enter a name, amount, and due day."
        case .status: "Tap the circle when you've paid it."
        case .more: "Open a payment to edit, skip, or remove it."
        case .months: "Switch months to view your history."
        case .settings: "Tap the Cushn logo at the top for settings."
        }
    }
}

/// Which hint, if any, to show now. Hints appear one at a time, each only when it has something to point at.
/// After the user finishes one of the later hints, the next waits for another launch, so they never form a tour.
enum FirstUseGuide {
    static func next(seen: Set<FirstUseHint>, paymentCount: Int, finishedHintThisLaunch: Bool) -> FirstUseHint? {
        if paymentCount == 0 { return seen.contains(.add) ? nil : .add }
        guard !finishedHintThisLaunch else { return nil }
        return [FirstUseHint.status, .more, .months, .settings].first { !seen.contains($0) }
    }
}

/// Local first-use markers. These are preferences, so they live outside the payment store and never touch it.
@Observable @MainActor
final class FirstUseState {
    static let onboardingKey = "cushn.onboarding.completed"
    static let hintsKey = "cushn.hints.seen"
    static let splashKey = "cushn.splash.seen"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var seen: Set<FirstUseHint>
    private(set) var finishedHintThisLaunch = false
    var hintsEnabled: Bool

    init(defaults: UserDefaults = .standard, hintsEnabled: Bool = true) {
        self.defaults = defaults
        self.hintsEnabled = hintsEnabled
        seen = Set((defaults.stringArray(forKey: Self.hintsKey) ?? []).compactMap(FirstUseHint.init(rawValue:)))
    }

    var onboardingCompleted: Bool { defaults.bool(forKey: Self.onboardingKey) }

    func completeOnboarding() {
        defaults.set(true, forKey: Self.onboardingKey)
    }

    /// Returns whether the splash shows on this launch: only the first after download. Deleting the app clears this, so
    /// a new download shows it again. Someone updating with saved payments has already been through a first launch.
    func resolveSplash(hasPayments: Bool) -> Bool {
        defer { defaults.set(true, forKey: Self.splashKey) }
        return !defaults.bool(forKey: Self.splashKey) && !hasPayments
    }

    /// Returns whether onboarding should show on this launch, and retires first-use guidance for existing users.
    func resolveOnboarding(hasPayments: Bool) -> Bool {
        switch OnboardingGate.decision(completed: onboardingCompleted, hasPayments: hasPayments) {
        case .show:
            return true
        case .skip:
            return false
        case .skipExistingUser:
            completeOnboarding()
            seen = Set(FirstUseHint.allCases)
            saveHints()
            return false
        }
    }

    func activeHint(paymentCount: Int) -> FirstUseHint? {
        guard hintsEnabled else { return nil }
        return FirstUseGuide.next(seen: seen, paymentCount: paymentCount, finishedHintThisLaunch: finishedHintThisLaunch)
    }

    /// Records a hint as done, whether dismissed or made unnecessary because the user already did the thing.
    func finish(_ hint: FirstUseHint, wasShowing: Bool) {
        guard seen.insert(hint).inserted else { return }
        if wasShowing && hint != .add { finishedHintThisLaunch = true }
        saveHints()
    }

    func reset() {
        defaults.removeObject(forKey: Self.onboardingKey)
        defaults.removeObject(forKey: Self.hintsKey)
        defaults.removeObject(forKey: Self.splashKey)
        seen = []
        finishedHintThisLaunch = false
    }

    private func saveHints() {
        defaults.set(seen.map(\.rawValue).sorted(), forKey: Self.hintsKey)
    }
}
