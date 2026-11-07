import SwiftUI

/// The four official logo treatments. One is chosen per cold launch and kept through the splash and onboarding.
/// It never touches the main app's appearance. Colors are sampled from the supplied artwork, so a mark and its
/// background are the pair the owner approved.
enum CushnBrandTheme: String, CaseIterable, Sendable {
    case goldOnWhite, blackOnWhite, blackOnGold, goldOnBlack

    struct Palette: Sendable {
        let background: UInt32
        let mark: UInt32
        let title: UInt32
        let secondary: UInt32
        let buttonFill: UInt32
        let buttonText: UInt32
    }

    var palette: Palette {
        switch self {
        case .goldOnWhite:
            Palette(background: 0xFFFFFF, mark: 0xF3BC2F, title: 0x111111, secondary: 0x5C5C5C, buttonFill: 0x111111, buttonText: 0xFFFFFF)
        case .blackOnWhite:
            Palette(background: 0xFFFFFF, mark: 0x0F0F0E, title: 0x111111, secondary: 0x5C5C5C, buttonFill: 0x111111, buttonText: 0xFFFFFF)
        case .blackOnGold:
            Palette(background: 0xFAC432, mark: 0x111010, title: 0x111111, secondary: 0x3D3000, buttonFill: 0x111111, buttonText: 0xFFFFFF)
        case .goldOnBlack:
            Palette(background: 0x0D0D0E, mark: 0xF9C439, title: 0xFFFFFF, secondary: 0xB8B8B8, buttonFill: 0xF9C439, buttonText: 0x111111)
        }
    }

    private var assetSuffix: String {
        switch self {
        case .goldOnWhite: "GoldWhite"
        case .blackOnWhite: "BlackWhite"
        case .blackOnGold: "BlackGold"
        case .goldOnBlack: "GoldBlack"
        }
    }

    /// The owner's image, unchanged, in the asset catalog.
    var logoAsset: String { "CushnLogo\(assetSuffix)" }
    /// The same mark with a transparent background, which is what the app draws so no square can show.
    var markAsset: String { "CushnMark\(assetSuffix)" }
    /// Controls and sample rows sit on this appearance, whatever the system setting is.
    var colorScheme: ColorScheme { self == .goldOnBlack ? .dark : .light }

    var background: Color { Color(hex: palette.background) }
    var title: Color { Color(hex: palette.title) }
    var secondary: Color { Color(hex: palette.secondary) }
    var buttonFill: Color { Color(hex: palette.buttonFill) }
    var buttonText: Color { Color(hex: palette.buttonText) }

    /// The gold mark that belongs on the main app's canvas in each appearance.
    static func goldMark(for scheme: ColorScheme) -> CushnBrandTheme {
        scheme == .dark ? .goldOnBlack : .goldOnWhite
    }

    /// A random theme in the appearance the app is about to use, so the first screens match the Home that follows.
    /// iOS decides light or dark, including switching at sunset for people on Automatic, so no clock is involved.
    static func random<Generator: RandomNumberGenerator>(for scheme: ColorScheme, using generator: inout Generator) -> CushnBrandTheme {
        allCases.filter { $0.colorScheme == scheme }.randomElement(using: &generator) ?? goldMark(for: scheme)
    }

    /// The appearance a launch will use: the choice in Settings if someone made one, otherwise the system's.
    static func launchScheme(setting: AppearanceSetting, systemIsDark: Bool) -> ColorScheme {
        switch setting {
        case .light: .light
        case .dark: .dark
        case .system: systemIsDark ? .dark : .light
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// The one filled button: onboarding's primary action and the empty state's Add.
struct CushnPrimaryButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color
    var minWidth: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(minWidth: minWidth == .infinity ? nil : minWidth, maxWidth: minWidth == .infinity ? .infinity : nil, minHeight: 50)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The pixel C sized by the C itself, not its image canvas, so it can be centered and aligned exactly.
struct CushnMark: View {
    let theme: CushnBrandTheme
    let height: CGFloat

    // The C's bounds inside the 1254pt source canvas.
    private static let canvas: CGFloat = 1254
    private static let bounds = CGRect(x: 216, y: 187, width: 759, height: 872)

    var body: some View {
        let scale = height / Self.bounds.height
        let full = Self.canvas * scale
        Image(theme.markAsset)
            .resizable()
            .interpolation(.high)
            .frame(width: full, height: full)
            .offset(x: (Self.canvas / 2 - Self.bounds.midX) * scale, y: (Self.canvas / 2 - Self.bounds.midY) * scale)
            .frame(width: Self.bounds.width * scale, height: height)
            .accessibilityHidden(true)
    }
}
