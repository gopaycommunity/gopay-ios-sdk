//
//  CheckoutTheme.swift
//  example
//
//  Design tokens for the demo e-shop. Defined in code (rather than an asset catalog) so the whole
//  checkout is readable in one place, and so the `GopayCardFormTheme` handed to `GopayCardForm`
//  visibly derives from the same palette — that's the point of the theming demo.
//

import SwiftUI
import GopaySDK

enum CheckoutTheme {

    // MARK: - Palette

    /// Brand green — buttons, selection, success.
    static let accent = dynamic(light: 0x0B8A4B, dark: 0x34D07A)
    /// Text on top of `accent`.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x07130C)
    /// Primary text.
    static let ink = dynamic(light: 0x101418, dark: 0xF2F4F7)
    /// Secondary text.
    static let inkMuted = dynamic(light: 0x6B7280, dark: 0x98A2B3)
    /// Page background.
    static let canvas = dynamic(light: 0xF4F5F7, dark: 0x0B0D10)
    /// Card / sheet background.
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x16191E)
    /// Subtle fill for tiles and disabled chips.
    static let surfaceSunken = dynamic(light: 0xF0F1F4, dark: 0x1E222A)
    /// Hairline separators and borders.
    static let hairline = dynamic(light: 0xE4E7EC, dark: 0x2A2F38)
    static let danger = dynamic(light: 0xD92D20, dark: 0xF97066)
    static let warning = dynamic(light: 0xB54708, dark: 0xFDB022)

    // MARK: - Metrics

    static let gutter: CGFloat = 16
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14

    // MARK: - SDK card form theme

    /// Handed to `GopayCardForm` so the SDK's inputs sit in the eshop's design language rather
    /// than the SDK defaults.
    static var cardForm: GopayCardFormTheme {
        GopayCardFormTheme(
            textColor: ink,
            backgroundColor: surfaceSunken,
            borderColor: hairline,
            focusedBorderColor: accent,
            errorColor: danger,
            borderWidth: 1,
            cornerRadius: controlRadius,
            font: .system(size: 16, weight: .medium, design: .rounded),
            labelFont: .system(size: 12, weight: .semibold),
            spacing: 14,
            textFieldPadding: 14
        )
    }

    // MARK: - Helpers

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Reusable building blocks

/// A rounded elevated container — the checkout's only structural primitive.
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = CheckoutTheme.gutter
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckoutTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: CheckoutTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CheckoutTheme.cardRadius, style: .continuous)
                    .stroke(CheckoutTheme.hairline, lineWidth: 1)
            )
    }
}

/// Full-width primary action.
struct PrimaryButtonStyle: ButtonStyle {
    var background: Color = CheckoutTheme.accent
    var foreground: Color = CheckoutTheme.onAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: CheckoutTheme.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(CheckoutTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(CheckoutTheme.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: CheckoutTheme.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
