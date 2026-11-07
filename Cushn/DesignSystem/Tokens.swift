import SwiftUI

/// One color token's values in light and dark, with optional Increase Contrast variants.
struct ColorToken: Sendable {
    let light: UInt32
    let dark: UInt32
    var lightHighContrast: UInt32?
    var darkHighContrast: UInt32?

    var color: Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            let hex = traits.userInterfaceStyle == .dark
                ? (high ? (darkHighContrast ?? dark) : dark)
                : (high ? (lightHighContrast ?? light) : light)
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

enum CushnTokens {
    static let canvas = ColorToken(light: 0xFFFFFF, dark: 0x111111)
    static let surface = ColorToken(light: 0xF5F5F5, dark: 0x1B1B1B)
    static let primaryText = ColorToken(light: 0x111111, dark: 0xF7F7F7)
    /// Slightly darker than the brand's #737373, which falls short of AA on the light surface.
    static let secondaryText = ColorToken(light: 0x6E6E6E, dark: 0xA0A0A0, lightHighContrast: 0x3C3C3C, darkHighContrast: 0xD0D0D0)
    static let hairline = ColorToken(light: 0xEAEAEA, dark: 0x2D2D2D, lightHighContrast: 0x8A8A8A, darkHighContrast: 0x7A7A7A)
    /// The unfilled part of Overview bars: visible on the canvas without competing with the ink.
    static let track = ColorToken(light: 0xD4D4D4, dark: 0x3C3C3C, lightHighContrast: 0x8A8A8A, darkHighContrast: 0x7A7A7A)
    static let openCircle = ColorToken(light: 0x8E8E8E, dark: 0x707070, lightHighContrast: 0x5A5A5A, darkHighContrast: 0xB0B0B0)
    static let mutedMark = ColorToken(light: 0x7A7A7A, dark: 0x8A8A8A, lightHighContrast: 0x5A5A5A, darkHighContrast: 0xB0B0B0)
    /// Restrained amber for past due. Always paired with text, never an alarm red.
    static let attention = ColorToken(light: 0x8A5A00, dark: 0xD9A441)
    /// Section headings on every screen. The brand gold in dark, and a deeper gold in light, where the brand gold
    /// can't carry text on white. The month title and totals stay in primary text, so they keep the top of the hierarchy.
    static let heading = ColorToken(light: 0x8A6100, dark: 0xF4C542, lightHighContrast: 0x6E4D00, darkHighContrast: 0xFFD766)
    /// Calendar dots by how many payments fall on a day. The number of dots and VoiceOver's count say the same thing.
    static let dayLoadOne = ColorToken(light: 0x2E9E5B, dark: 0x4CC27A)
    static let dayLoadTwo = ColorToken(light: 0xE3A900, dark: 0xF4C542)
    static let dayLoadMany = ColorToken(light: 0xD93A2F, dark: 0xFF6B60)
    /// Remove actions. The system red falls short of AA for text on the white canvas.
    static let destructive = ColorToken(light: 0xB3261E, dark: 0xFF6B60)
    /// The brand accent. A fill behind or beside ink, never text: it can't carry contrast on white.
    /// Increase Contrast darkens it on light backgrounds, so controls such as toggles reach 3:1.
    static let brandGold = ColorToken(light: 0xF4C542, dark: 0xF4C542, lightHighContrast: 0xA87B00)
}

/// Colors for payments with no brand artwork. The name picks the pair, so the list looks varied while a payment
/// keeps its color across launches and months. It says nothing about the company, and no brand mark is drawn.
struct FallbackIconColor: Sendable {
    let tile: ColorToken
    let glyph: ColorToken

    /// Tile and symbol are always different hues, and each pair works on both the light and dark canvas.
    static let palette: [FallbackIconColor] = [
        pair(tile: 0x1A6B43, glyph: 0xFFD95A), // green, yellow
        pair(tile: 0x2458D3, glyph: 0x9CF2D4), // blue, mint
        pair(tile: 0x5F33C6, glyph: 0xFFCBA6), // violet, peach
        pair(tile: 0xF0654E, glyph: 0x0F1C4D), // coral, navy
        pair(tile: 0x0A6569, glyph: 0xFFD1E3), // teal, pink
        pair(tile: 0xF5B82E, glyph: 0x3B2A9E), // amber, indigo
        pair(tile: 0xEE5E9E, glyph: 0x1F124F), // pink, deep indigo
        pair(tile: 0x1D2F7A, glyph: 0xFF9F8A), // navy, coral
        pair(tile: 0x6E1F6B, glyph: 0xA6F0C6), // plum, mint
        pair(tile: 0x58B7F5, glyph: 0x6B1230), // sky, maroon
        pair(tile: 0x7FD88F, glyph: 0x3A1C7A), // mint, purple
        pair(tile: 0xF08337, glyph: 0x032A30), // orange, deep teal
        pair(tile: 0xBE2146, glyph: 0xC6EBFF), // crimson, ice blue
        pair(tile: 0xB9A6F5, glyph: 0x0F4A2E), // lavender, forest
        pair(tile: 0xFFE066, glyph: 0x8A1538), // yellow, maroon
        pair(tile: 0x3CCFCF, glyph: 0x4A1248), // aqua, plum
    ]

    private static func pair(tile: UInt32, glyph: UInt32) -> FallbackIconColor {
        FallbackIconColor(tile: ColorToken(light: tile, dark: tile), glyph: ColorToken(light: glyph, dark: glyph))
    }

    /// FNV-1a rather than `hashValue`, which changes on every launch.
    static func index(for name: String) -> Int {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 0xCBF29CE484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001B3
        }
        return Int((hash ^ (hash >> 32)) % UInt64(palette.count))
    }

    static func color(for name: String) -> FallbackIconColor { palette[index(for: name)] }
}

enum CushnColor {
    static let canvas = CushnTokens.canvas.color
    static let surface = CushnTokens.surface.color
    static let primaryText = CushnTokens.primaryText.color
    static let secondaryText = CushnTokens.secondaryText.color
    static let hairline = CushnTokens.hairline.color
    static let track = CushnTokens.track.color
    static let openCircle = CushnTokens.openCircle.color
    static let mutedMark = CushnTokens.mutedMark.color
    static let attention = CushnTokens.attention.color
    static let destructive = CushnTokens.destructive.color
    static let brandGold = CushnTokens.brandGold.color
    static let heading = CushnTokens.heading.color

    static func dayLoad(_ load: CalendarLayout.DayLoad) -> Color {
        switch load {
        case .one: CushnTokens.dayLoadOne.color
        case .two: CushnTokens.dayLoadTwo.color
        case .many: CushnTokens.dayLoadMany.color
        }
    }
}

enum CushnSpacing {
    static let inset: CGFloat = 20
    static let rowVertical: CGFloat = 12
    static let touchTarget: CGFloat = 44
    static let iconSize: CGFloat = 32
    /// Between the groups of a page, such as Overview's blocks.
    static let group: CGFloat = 28
}

/// The app's type roles. All San Francisco and all scale with Dynamic Type, so a screen names what its text is, not a size.
enum CushnFont {
    /// Onboarding headlines.
    static let headline = Font.title.weight(.bold)
    /// Section headings on every tab.
    static let sectionTitle = Font.title3.weight(.semibold)
    /// A figure that sits under a small label, such as Overview's Paid and Unconfirmed amounts.
    static let metric = Font.headline
    /// Headings inside a grouped form or sheet.
    static let groupTitle = Font.subheadline.weight(.semibold)
    /// Payment names, and anything else a list is scanned by.
    static let rowTitle = Font.body.weight(.medium)
    static let rowAmount = Font.body.weight(.medium)
    static let body = Font.body
    /// Text buttons such as Skip and Back.
    static let action = Font.body.weight(.medium)
    /// Labels and values that support a row or figure.
    static let supporting = Font.subheadline
    static let supportingEmphasis = Font.subheadline.weight(.medium)
    /// Dates, notes and captions.
    static let secondary = Font.footnote
    /// Small glyphs in icon buttons.
    static let glyph = Font.footnote.weight(.semibold)
}

private struct ScaledTitleFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let limit: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, limit: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
        self.limit = limit
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(size, limit), weight: weight))
    }
}

extension View {
    /// The month title. Sits between the system's title and large title, and stops growing at a size that still fits a phone's width.
    func cushnScreenTitle() -> some View { modifier(ScaledTitleFont(size: 31, limit: 56, weight: .bold)) }

    /// The one large figure on a page. Tabular, so it doesn't shift as the amount changes.
    func cushnHeroAmount() -> some View {
        modifier(ScaledTitleFont(size: 40, limit: 64, weight: .bold)).monospacedDigit()
    }
}
