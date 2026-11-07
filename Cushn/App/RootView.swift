import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSize

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "checklist", value: AppTab.home) { HomeView() }
            Tab("Overview", systemImage: "chart.bar", value: AppTab.overview) { OverviewView().hidingTabBarForAudit() }
            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) { CalendarTabView() }
        }
        // A pinned header takes over the screen at accessibility text sizes and in landscape.
        .environment(\.monthHeaderScrolls, typeSize.isAccessibilitySize || verticalSize == .compact)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshDate()
                model.reminders.requestReconcile()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            model.reminders.requestReconcile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            model.refreshDate()
            model.reminders.requestReconcile()
        }
        .task { await model.reminders.reconcileNow() }
        .sheet(isPresented: $model.showingSettings, onDismiss: model.settingsDidClose) { SettingsView() }
        .alert("Couldn't save", isPresented: Binding(get: { model.errorMessage != nil },
                                                     set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private extension View {
    /// Debug only: lets an accessibility audit see Overview with nothing passing behind the glass tab bar.
    @ViewBuilder
    func hidingTabBarForAudit() -> some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "cushnHideTabBar") {
            toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
