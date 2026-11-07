import Foundation
import Testing
import UIKit
@testable import Cushn

/// Computes WCAG contrast from the real token values, in every appearance.
@Suite struct TokenContrastTests {
    func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// (name, foreground, background) for light, dark, and both Increase Contrast variants.
    func pairs(_ fg: ColorToken, on bg: ColorToken) -> [(UInt32, UInt32)] {
        [(fg.light, bg.light), (fg.dark, bg.dark),
         (fg.lightHighContrast ?? fg.light, bg.lightHighContrast ?? bg.light),
         (fg.darkHighContrast ?? fg.dark, bg.darkHighContrast ?? bg.dark)]
    }

    @Test(arguments: [CushnTokens.primaryText, CushnTokens.secondaryText, CushnTokens.attention, CushnTokens.destructive, CushnTokens.heading])
    func textMeetsAAOnBothBackgrounds(token: ColorToken) {
        for background in [CushnTokens.canvas, CushnTokens.surface] {
            for (fg, bg) in pairs(token, on: background) {
                #expect(contrast(fg, bg) >= 4.5, "\(String(fg, radix: 16)) on \(String(bg, radix: 16))")
            }
        }
    }

    @Test func goldControlsReachControlContrastWithIncreaseContrast() throws {
        let gold = try #require(CushnTokens.brandGold.lightHighContrast)
        #expect(contrast(gold, CushnTokens.canvas.light) >= 3)
        #expect(contrast(gold, CushnTokens.surface.light) >= 3)
        #expect(contrast(gold, 0x111111) >= 4.5, "The Add button's plus stays readable")
    }

    @Test(arguments: [CushnTokens.openCircle, CushnTokens.mutedMark])
    func statusMarksMeetControlContrastOnCanvas(token: ColorToken) {
        for (fg, bg) in pairs(token, on: CushnTokens.canvas) {
            #expect(contrast(fg, bg) >= 3, "\(String(fg, radix: 16)) on \(String(bg, radix: 16))")
        }
    }
}

/// Prints what the process actually sees, to confirm a simulator setting took effect before relying on a run.
@Suite struct AccessibilitySettingProbe {
    @Test @MainActor func reportSettings() {
        print("PROBE reduceMotion=\(UIAccessibility.isReduceMotionEnabled) darkerColors=\(UIAccessibility.isDarkerSystemColorsEnabled) contrast=\(UITraitCollection.current.accessibilityContrast.rawValue)")
    }
}
