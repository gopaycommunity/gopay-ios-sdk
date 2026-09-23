//
//  ThemeShowcase.swift
//  example
//
//  The three themes the picker offers, written as Swift values the way a host would write them.
//  Default is the SDK untouched; Dark and Red carry the palettes the GoPay web card form ships,
//  so the same design can be compared across the web, iOS and Android.
//

import SwiftUI
import GopaySDK

/// The demo's themes, in the order the picker shows them.
struct ThemeShowcase {
    static let shared = ThemeShowcase()

    /// Theme names in picker order, matching the Android demo.
    let names = ["Default", "Dark", "Red"]

    private let themes: [String: GopayCardFormTheme] = [
        "Default": GopayCardFormTheme(),
        "Dark": dark,
        "Red": red
    ]

    /// The named theme, or the SDK defaults when the name is unknown.
    func theme(named name: String) -> GopayCardFormTheme {
        themes[name] ?? GopayCardFormTheme()
    }

    // MARK: - The web card form's palettes

    private static let dark = GopayCardFormTheme(
        labelColor: Color(hex: 0x94A3B8),
        labelFontSize: 11,
        labelFontWeight: 600,
        labelUppercase: true,
        inputTextColor: Color(hex: 0xE2E8F0),
        inputFontSize: 14,
        placeholderColor: Color(hex: 0x64748B),
        // Stated outright, not left to the default: the web ships these palettes with an underline,
        // which Android renders natively and iOS does not, and an unstated style would have the two
        // demos draw different shapes from identical values.
        inputBorderStyle: .underline,
        inputBorderColor: Color(hex: 0x334155),
        inputBorderWidth: 1,
        inputBackgroundColor: .clear,
        inputPaddingVertical: 6,
        inputPaddingHorizontal: 12,
        inputBorderRadius: 0,
        inputErrorBorderColor: Color(hex: 0xEA3C55),
        errorTextColor: Color(hex: 0xF87171),
        errorFontSize: 11,
        errorMinHeight: 14,
        groupSpacing: 16,
        fieldSpacing: 4,
        formPadding: 16,
        formBackgroundColor: Color(hex: 0x1A1F2E)
    )

    private static let red = GopayCardFormTheme(
        labelColor: Color(hex: 0xC8102E),
        labelFontSize: 11,
        labelFontWeight: 600,
        labelUppercase: true,
        inputTextColor: Color(hex: 0x4B5E68),
        inputFontSize: 14,
        placeholderColor: Color(hex: 0x64748B),
        // Stated outright, not left to the default: the web ships these palettes with an underline,
        // which Android renders natively and iOS does not, and an unstated style would have the two
        // demos draw different shapes from identical values.
        inputBorderStyle: .underline,
        inputBorderColor: Color(hex: 0xC8102E),
        inputBorderWidth: 1,
        inputBackgroundColor: .clear,
        inputPaddingVertical: 6,
        inputPaddingHorizontal: 12,
        inputBorderRadius: 0,
        inputErrorBorderColor: Color(hex: 0xEA3C55),
        errorTextColor: Color(hex: 0xCC0000),
        errorFontSize: 11,
        errorMinHeight: 14,
        groupSpacing: 16,
        fieldSpacing: 4,
        formPadding: 16,
        formBackgroundColor: .clear
    )
}

private extension Color {
    /// The palettes are quoted from the web card form, so they read best as the hex it uses.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
