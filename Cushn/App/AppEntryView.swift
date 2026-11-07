import SwiftUI

/// What this launch shows before the checklist.
struct LaunchExperience {
    var theme: CushnBrandTheme
    var showsSplash = true
    var holdsSplash = false
    var showsOnboarding: Bool

    @MainActor
    static func make(for model: AppModel) -> LaunchExperience {
        var generator = SystemRandomNumberGenerator()
        let setting = AppearanceSetting(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        // The screen's trait, because no window exists yet to ask.
        let scheme = CushnBrandTheme.launchScheme(setting: setting, systemIsDark: UIScreen.main.traitCollection.userInterfaceStyle == .dark)
        let theme = CushnBrandTheme.random(for: scheme, using: &generator)
        #if DEBUG
        if let debug = DebugLaunch.experience(for: model, fallbackTheme: theme) { return debug }
        #endif
        let hasPayments = !model.store.ledger.payments.isEmpty
        return LaunchExperience(theme: theme, showsSplash: model.firstUse.resolveSplash(hasPayments: hasPayments),
                                showsOnboarding: model.firstUse.resolveOnboarding(hasPayments: hasPayments))
    }
}

/// Routes a launch to onboarding or Home, with the branded splash over whichever comes first.
/// The splash never takes touches, so the screen under it is usable straight away.
struct AppEntryView: View {
    let model: AppModel
    let experience: LaunchExperience
    @State private var showsSplash: Bool
    @State private var showsOnboarding: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, experience: LaunchExperience) {
        self.model = model
        self.experience = experience
        _showsSplash = State(initialValue: experience.showsSplash)
        _showsOnboarding = State(initialValue: experience.showsOnboarding)
    }

    var body: some View {
        ZStack {
            if showsOnboarding {
                OnboardingView(theme: experience.theme, month: model.currentMonth, onFinish: finishOnboarding)
                    .transition(.opacity)
            } else {
                RootView().environment(model).transition(.opacity)
            }
            if showsSplash {
                SplashView(theme: experience.theme, holds: experience.holdsSplash) { showsSplash = false }
                    .zIndex(1)
            }
        }
        // Onboarding's backgrounds don't follow the system appearance, so a system-colored clock could vanish on them.
        .statusBarHidden(showsOnboarding)
    }

    private func finishOnboarding() {
        model.firstUse.completeOnboarding()
        model.selectedTab = .home
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showsOnboarding = false }
    }
}
