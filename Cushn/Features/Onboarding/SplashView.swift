import SwiftUI

/// The first branding someone sees: iOS's launch screen is a plain color, so the logo never appears alone. It fades in
/// over that color with the name and tagline, then fades away on its own.
struct SplashView: View {
    let theme: CushnBrandTheme
    var holds = false
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSize
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize = 36
    @State private var revealed = false
    @State private var leaving = false

    private static let fadeIn = 0.2
    /// Long enough to read the name and tagline. Nothing waits on this, because the screen beneath already works.
    private static let readingTime = 1.2
    private static let fadeOut = 0.25

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            theme.background
                .overlay { composition }
                .opacity(revealed ? 1 : 0)
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await run() }
    }

    private var composition: some View {
        // A hidden copy of the text above keeps the C at the exact center of the screen.
        VStack(spacing: 0) {
            wordmark.hidden()
            CushnMark(theme: theme, height: verticalSize == .compact ? 72 : 112)
                .padding(.vertical, verticalSize == .compact ? 14 : 28)
            wordmark
        }
    }

    private var wordmark: some View {
        VStack(spacing: 8) {
            Text("Cushn")
                .font(.system(size: min(wordmarkSize, 48), weight: .bold))
                .foregroundStyle(theme.title)
                .accessibilityIdentifier("splashWordmark")
            Text("See what's due. Mark what's done.")
                .font(CushnFont.supporting)
                .foregroundStyle(theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func run() async {
        withAnimation(reduceMotion ? nil : .easeOut(duration: Self.fadeIn)) { revealed = true }
        guard !holds else { return }
        try? await Task.sleep(for: .seconds((reduceMotion ? 0 : Self.fadeIn) + Self.readingTime))
        withAnimation(reduceMotion ? .linear(duration: 0.1) : .easeInOut(duration: Self.fadeOut)) { leaving = true }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.1 : Self.fadeOut))
        onFinished()
    }
}
