//
//  GopayCardFormThemeTests.swift
//  sdkTests
//
//  Pins the public shape of GopayCardFormTheme: the defaults, the CSS font weight mapping and
//  the fonts and border colours it resolves.
//

import Testing
import SwiftUI
import UIKit
@testable import sdk

struct GopayCardFormThemeTests {

    // MARK: - Defaults

    /// An untouched form is an iOS form: system type, a plain bordered field, no uppercasing and
    /// no reserved error line. The web preset is a theme a host opts into, not the starting point.
    @Test func anUntouchedThemeIsThePlatformsOwnAppearance() {
        let theme = GopayCardFormTheme()

        #expect(theme.fontFamily == nil)
        #expect(theme.labelFontSize == 12)
        #expect(theme.labelFontWeight == 400)
        #expect(theme.labelLineHeight == nil)
        #expect(theme.labelUppercase == false)
        #expect(theme.labelLetterSpacing == nil)
        #expect(theme.labelHidden == false)
        #expect(theme.inputFontSize == 17)
        #expect(theme.inputFontWeight == nil)
        #expect(theme.inputHeight == nil)
        #expect(theme.inputBorderStyle == .boxed)
        #expect(theme.inputBorderWidth == 1)
        #expect(theme.inputPaddingVertical == 12)
        #expect(theme.inputPaddingHorizontal == 12)
        #expect(theme.inputBorderRadius == 5)
        #expect(theme.errorFontSize == 12)
        #expect(theme.errorMinHeight == 0)
        #expect(theme.errorSpacing == nil)
        #expect(theme.groupSpacing == 16)
        #expect(theme.fieldSpacing == 4)
        #expect(theme.formPadding == 0)
    }

    @Test("the default colors follow the system palette")
    func theDefaultColorsFollowTheSystemPalette() {
        let theme = GopayCardFormTheme()

        #expect(theme.labelColor == .primary)
        #expect(theme.inputTextColor == .primary)
        #expect(theme.inputBorderColor == Color(.separator))
        #expect(theme.inputBackgroundColor == .clear, "the host's own background shows through")
        #expect(theme.inputErrorBorderColor == .red)
        #expect(theme.errorTextColor == .red)
        #expect(theme.formBackgroundColor == .clear)
        #expect(theme.placeholderColor == nil)
    }

    // MARK: - Font weights

    @Test func fontWeightMapsTheWholeCssScale() {
        #expect(GopayCardFormTheme.uiFontWeight(100) == .ultraLight)
        #expect(GopayCardFormTheme.uiFontWeight(200) == .thin)
        #expect(GopayCardFormTheme.uiFontWeight(300) == .light)
        #expect(GopayCardFormTheme.uiFontWeight(400) == .regular)
        #expect(GopayCardFormTheme.uiFontWeight(500) == .medium)
        #expect(GopayCardFormTheme.uiFontWeight(600) == .semibold)
        #expect(GopayCardFormTheme.uiFontWeight(700) == .bold)
        #expect(GopayCardFormTheme.uiFontWeight(800) == .heavy)
        #expect(GopayCardFormTheme.uiFontWeight(900) == .black)
    }

    @Test func fontWeightRoundsInBetweenValuesAndClampsOutOfRange() {
        #expect(GopayCardFormTheme.uiFontWeight(449) == .regular)
        #expect(GopayCardFormTheme.uiFontWeight(451) == .medium)
        #expect(GopayCardFormTheme.uiFontWeight(0) == .ultraLight)
        #expect(GopayCardFormTheme.uiFontWeight(-100) == .ultraLight)
        #expect(GopayCardFormTheme.uiFontWeight(5000) == .black)
    }

    // MARK: - Border state

    @Test("borderColor: a resting field uses the border color")
    func borderColorRestingFieldUsesTheBorderColor() {
        var theme = GopayCardFormTheme()
        theme.inputBorderColor = .gray

        #expect(theme.borderColor(hasError: false) == .gray)
    }

    @Test("borderColor: an invalid field uses the error color")
    func borderColorInvalidFieldUsesTheErrorColor() {
        var theme = GopayCardFormTheme()
        theme.inputErrorBorderColor = .orange

        #expect(theme.borderColor(hasError: true) == .orange)
    }

    @Test func errorSpacingFallsBackToFieldSpacing() {
        var theme = GopayCardFormTheme()
        theme.fieldSpacing = 6

        #expect(theme.resolvedErrorSpacing == 6)

        theme.errorSpacing = 3
        #expect(theme.resolvedErrorSpacing == 3)
    }

    // MARK: - Resolved fonts

    @Test func inputFontFollowsTheThemedSizeAndWeight() {
        var theme = GopayCardFormTheme()
        theme.inputFontSize = 14
        theme.inputFontWeight = 600

        let font = theme.inputUIFont(for: .large)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]

        #expect(font.pointSize == 14)
        #expect(traits?[.weight] as? CGFloat == UIFont.Weight.semibold.rawValue)
    }

    /// Resolved for the same category the theme font asks for: `preferredFont` without a trait
    /// collection follows whatever text size the host device is set to, which would make the
    /// comparison depend on the machine the tests run on.
    private static let atLargeTextSize = UITraitCollection(preferredContentSizeCategory: .large)

    @Test func inputFontDefaultMatchesTheBodyTextStyle() {
        #expect(GopayCardFormTheme().inputUIFont(for: .large).pointSize
            == UIFont.preferredFont(forTextStyle: .body, compatibleWith: Self.atLargeTextSize).pointSize)
    }

    @Test func labelFontDefaultMatchesTheCaptionTextStyle() {
        #expect(GopayCardFormTheme().labelUIFont(for: .large).pointSize
            == UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: Self.atLargeTextSize).pointSize)
    }

    @Test func fontFamilyPicksTheBoldFaceForHeavyWeightsAndTheRegularOneOtherwise() {
        var theme = GopayCardFormTheme()
        theme.fontFamily = "Georgia"

        theme.labelFontWeight = 800
        let bold = theme.labelUIFont(for: .large)
        #expect(bold.familyName == "Georgia")
        #expect(bold.fontDescriptor.symbolicTraits.contains(.traitBold))

        theme.labelFontWeight = 400
        let regular = theme.labelUIFont(for: .large)
        #expect(regular.familyName == "Georgia")
        #expect(!regular.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    @Test func fontFamilyFallsBackToTheSystemFontWhenTheAppHasNotRegisteredIt() {
        var theme = GopayCardFormTheme()
        theme.fontFamily = "NoSuchFontIsRegistered"

        #expect(theme.inputUIFont(for: .large).familyName == UIFont.systemFont(ofSize: 17).familyName)
    }

    @Test func fontFamilyUsesARegisteredFont() {
        var theme = GopayCardFormTheme()
        theme.fontFamily = "Georgia"

        #expect(theme.inputUIFont(for: .large).familyName == "Georgia")
    }

    @Test func errorFontUsesTheThemedErrorSize() {
        var theme = GopayCardFormTheme()
        theme.errorFontSize = 11

        #expect(theme.errorUIFont(for: .large).pointSize == 11)
    }

    @Test func scaledCaptionLengthIsTheIdentityAtTheDefaultCategory() {
        #expect(GopayCardFormTheme().scaledCaptionLength(14, for: .large) == 14)
    }

    @Test func errorReserveHoldsAtLeastOneLineOfTheErrorFont() {
        var theme = GopayCardFormTheme()
        theme.errorFontSize = 20
        theme.errorMinHeight = 4
        // A whole rendered line, not the point size that names it, or the message still pushes
        // the form down when it appears.
        #expect(theme.reservedErrorHeight(for: .large) >= theme.errorUIFont(for: .large).lineHeight)

        theme.errorMinHeight = 40
        #expect(theme.reservedErrorHeight(for: .large) >= 40)

        theme.errorMinHeight = 0
        #expect(theme.reservedErrorHeight(for: .large) == 0, "no reserve means no slot")
    }
}
