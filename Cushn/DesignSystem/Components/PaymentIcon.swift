import SwiftUI
import UIKit

/// The brand's bundled icon on a quiet tile when the name matches one. Anything else gets a symbol or letter on a
/// colored tile, with the color chosen from the name. Every tile is the same size, so rows stay aligned.
struct PaymentIcon: View {
    let name: String
    @ScaledMetric private var size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    init(name: String, size: CGFloat = CushnSpacing.iconSize) {
        self.name = name
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        let content = BrandMatcher.iconContent(for: name)
        let fallback = FallbackIconColor.color(for: name)
        ZStack {
            if case .artwork = content { CushnColor.surface } else { fallback.tile.color }
            switch content {
            case .artwork(let icon):
                // Asks for the view's appearance, which can differ from the system's on a themed screen.
                if let logo = UIImage(named: "brand-\(icon)", in: nil,
                                      compatibleWith: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)) {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .padding(BrandCatalog.fullBleedIcons.contains(icon) ? 0 : size * 0.14)
                }
            case .symbol(let symbol):
                Image(systemName: symbol)
                    .symbolVariant(.fill)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(fallback.glyph.color)
            case .monogram(let letter):
                Text(letter)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(fallback.glyph.color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay {
            // Keeps a tile that fills its space from melting into a similar background: a white logo on the light
            // canvas, or an amber tile on the gold onboarding theme.
            if showsEdge(content) {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .strokeBorder(CushnColor.primaryText.opacity(0.12), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private func showsEdge(_ content: PaymentIconContent) -> Bool {
        if case .artwork(let icon) = content { return BrandCatalog.fullBleedIcons.contains(icon) }
        return true
    }
}
