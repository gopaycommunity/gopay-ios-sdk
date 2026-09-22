//
//  GopayCardFormThemeTests.swift
//  sdkTests
//
//  Pins the public shape of GopayCardFormTheme: the defaults, the hex bridge used for JSON
//  themes, the CSS font weight mapping and the tolerant decoder.
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import sdk

// Serialized because two tests swap the shared dropped-key handler while they decode.
@Suite(.serialized)
struct GopayCardFormThemeTests {

    // MARK: - Defaults

    @Test func standard_matchesTheWebCardFormDefaults() {
        let theme = GopayCardFormTheme.standard

        #expect(theme.fontFamily == nil)
        #expect(theme.labelFontSize == 11)
        #expect(theme.labelFontWeight == 600)
        #expect(theme.labelLineHeight == nil)
        #expect(theme.labelUppercase == true)
        #expect(theme.labelLetterSpacing == nil)
        #expect(theme.labelHidden == false)
        #expect(theme.inputFontSize == 14)
        #expect(theme.inputFontWeight == nil)
        #expect(theme.inputHeight == nil)
        #expect(theme.inputBorderStyle == .underline)
        #expect(theme.inputBorderWidth == 1)
        #expect(theme.inputPaddingVertical == 6)
        #expect(theme.inputPaddingHorizontal == 0)
        #expect(theme.inputBorderRadius == 0)
        #expect(theme.errorFontSize == 11)
        #expect(theme.errorMinHeight == 14)
        #expect(theme.errorSpacing == nil)
        #expect(theme.groupSpacing == 16)
        #expect(theme.fieldSpacing == 4)
        #expect(theme.formPadding == 16)
    }

    @Test func standard_defaultColorsFollowTheSystemPalette() {
        let theme = GopayCardFormTheme.standard

        #expect(theme.labelColor == .primary)
        #expect(theme.inputTextColor == .primary)
        #expect(theme.inputBorderColor == Color(.separator))
        #expect(theme.inputBackgroundColor == .clear)
        #expect(theme.inputErrorBorderColor == .red)
        #expect(theme.errorTextColor == .red)
        #expect(theme.formBackgroundColor == .clear)
        #expect(theme.placeholderColor == nil)
    }

    // MARK: - Font weights

    @Test func fontWeight_mapsTheWholeCssScale() {
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

    @Test func fontWeight_roundsInBetweenValuesAndClampsOutOfRange() {
        #expect(GopayCardFormTheme.uiFontWeight(449) == .regular)
        #expect(GopayCardFormTheme.uiFontWeight(451) == .medium)
        #expect(GopayCardFormTheme.uiFontWeight(0) == .ultraLight)
        #expect(GopayCardFormTheme.uiFontWeight(-100) == .ultraLight)
        #expect(GopayCardFormTheme.uiFontWeight(5000) == .black)
    }

    // MARK: - Border state

    @Test func borderColor_restingFieldUsesTheBorderColor() {
        var theme = GopayCardFormTheme()
        theme.inputBorderColor = .gray

        #expect(theme.borderColor(hasError: false) == .gray)
    }

    @Test func borderColor_invalidFieldUsesTheErrorColor() {
        var theme = GopayCardFormTheme()
        theme.inputErrorBorderColor = .orange

        #expect(theme.borderColor(hasError: true) == .orange)
    }

    @Test func borderStyle_decodesBothWebValues() throws {
        let underline = try JSONDecoder().decode(
            GopayCardFormTheme.self,
            from: Data("{ \"inputBorderStyle\": \"underline\" }".utf8)
        )
        let boxed = try JSONDecoder().decode(
            GopayCardFormTheme.self,
            from: Data("{ \"inputBorderStyle\": \"boxed\" }".utf8)
        )

        #expect(underline.inputBorderStyle == .underline)
        #expect(boxed.inputBorderStyle == .boxed)
    }

    @Test func errorSpacing_fallsBackToFieldSpacing() {
        var theme = GopayCardFormTheme()
        theme.fieldSpacing = 6

        #expect(theme.resolvedErrorSpacing == 6)

        theme.errorSpacing = 3
        #expect(theme.resolvedErrorSpacing == 3)
    }

    // MARK: - Resolved fonts

    @Test func inputFont_followsTheThemedSizeAndWeight() {
        var theme = GopayCardFormTheme()
        theme.inputFontSize = 14
        theme.inputFontWeight = 600

        let font = theme.inputUIFont
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]

        #expect(font.pointSize == 14)
        #expect(traits?[.weight] as? CGFloat == UIFont.Weight.semibold.rawValue)
    }

    @Test func inputFont_defaultUsesTheWebSize() {
        #expect(GopayCardFormTheme.standard.inputUIFont.pointSize == 14)
    }

    @Test func labelFont_defaultUsesTheWebSize() {
        let font = GopayCardFormTheme.standard.labelUIFont(for: .large)
        #expect(font.pointSize == 11)
    }

    @Test func fontFamily_picksTheBoldFaceForHeavyWeightsAndTheRegularOneOtherwise() {
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

    @Test func fontFamily_fallsBackToTheSystemFontWhenTheAppHasNotRegisteredIt() {
        var theme = GopayCardFormTheme()
        theme.fontFamily = "NoSuchFontIsRegistered"

        #expect(theme.inputUIFont.familyName == UIFont.systemFont(ofSize: 17).familyName)
    }

    @Test func fontFamily_usesARegisteredFont() {
        var theme = GopayCardFormTheme()
        theme.fontFamily = "Georgia"

        #expect(theme.inputUIFont.familyName == "Georgia")
    }

    @Test func errorFont_usesTheThemedErrorSize() {
        var theme = GopayCardFormTheme()
        theme.errorFontSize = 11

        #expect(theme.errorUIFont(for: .large).pointSize == 11)
    }

    @Test func scaledCaptionLength_isTheIdentityAtTheDefaultCategory() {
        #expect(GopayCardFormTheme.standard.scaledCaptionLength(14, for: .large) == 14)
    }

    // MARK: - Hex bridge

    @Test func hex_parsesTheSupportedNotations() {
        #expect(Color(gopayHex: "#4b5e68")?.gopayHex == "#4B5E68")
        #expect(Color(gopayHex: "#fff") == Color(gopayHex: "#ffffff"))
        #expect(Color(gopayHex: "#fff0") == Color(gopayHex: "#ffffff00"))
        #expect(Color(gopayHex: "transparent") == .clear)
        #expect(Color(gopayHex: "#00000000")?.gopayHex == "transparent")
    }

    @Test func hex_rejectsMalformedValues() {
        #expect(Color(gopayHex: "#12345") == nil)
        #expect(Color(gopayHex: "rgb(1,2,3)") == nil)
        #expect(Color(gopayHex: "") == nil)
        // The leading # is required, as in CSS and as on Android.
        #expect(Color(gopayHex: "4b5e68") == nil)
        #expect(Color(gopayHex: "#-12345") == nil)
    }

    @Test func hex_roundTripsThroughEncodingAndDecoding() throws {
        var theme = GopayCardFormTheme()
        theme.labelColor = try #require(Color(gopayHex: "#4b5e68"))
        theme.inputBorderColor = try #require(Color(gopayHex: "#698492"))
        theme.inputErrorBorderColor = try #require(Color(gopayHex: "#ea3c55"))
        theme.errorTextColor = try #require(Color(gopayHex: "#cc0000"))
        theme.inputBackgroundColor = try #require(Color(gopayHex: "#1a1f2e80"))
        theme.formBackgroundColor = .clear

        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(GopayCardFormTheme.self, from: data)

        #expect(decoded.labelColor.gopayHex == "#4B5E68")
        #expect(decoded.inputBorderColor.gopayHex == "#698492")
        #expect(decoded.inputErrorBorderColor.gopayHex == "#EA3C55")
        #expect(decoded.errorTextColor.gopayHex == "#CC0000")
        #expect(decoded.inputBackgroundColor.gopayHex == "#1A1F2E80")
        #expect(decoded.formBackgroundColor.gopayHex == "transparent")
    }

    @Test func encode_writesEveryValueAndSkipsTheUnsetOnes() throws {
        let data = try JSONEncoder().encode(GopayCardFormTheme.standard)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["inputBorderStyle"] as? String == "underline")
        #expect(json["groupSpacing"] as? Double == 16)
        #expect(json["fontFamily"] == nil)
        #expect(json["inputHeight"] == nil)
        #expect(json["placeholderColor"] == nil)
        #expect(json["errorSpacing"] == nil)
    }

    // MARK: - Decoding a web theme

    /// The DEFAULT_CARD_FORM_THEME preset the web SDK ships, with every key this SDK does not
    /// carry: the submit set, errorHidden, and the focus gradient the cut left to the web.
    @Test func decode_appliesKnownKeysAndIgnoresWebOnlyOnes() throws {
        let json = """
        {
          "labelColor": "#4b5e68",
          "labelFontSize": 11,
          "labelFontWeight": 600,
          "labelUppercase": true,
          "inputTextColor": "#4b5e68",
          "inputFontSize": 14,
          "inputBorderColor": "#698492",
          "inputBorderWidth": 1,
          "inputBackgroundColor": "transparent",
          "inputPaddingVertical": 6,
          "inputBorderRadius": 0,
          "focusGradientStart": "#19C7D6",
          "focusGradientEnd": "#1899D6",
          "inputErrorBorderColor": "#ea3c55",
          "errorTextColor": "#cc0000",
          "errorFontSize": 11,
          "errorHidden": false,
          "groupSpacing": 16,
          "fieldSpacing": 4,
          "formPadding": 16,
          "formBackgroundColor": "transparent",
          "submitBackgroundColor": "#1899d6",
          "submitHoverBackgroundColor": "#1482ba",
          "submitDisabledBackgroundColor": "#a8b6bd",
          "submitTextColor": "#ffffff",
          "submitDisabledTextColor": "#ffffff",
          "submitBorderRadius": 4,
          "submitFontSize": 14
        }
        """

        let theme = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))

        #expect(theme.labelFontSize == 11)
        #expect(theme.labelFontWeight == 600)
        #expect(theme.labelUppercase == true)
        #expect(theme.inputFontSize == 14)
        #expect(theme.inputPaddingVertical == 6)
        #expect(theme.inputBorderRadius == 0)
        #expect(theme.inputBackgroundColor == .clear)
        #expect(theme.groupSpacing == 16)
        #expect(theme.formPadding == 16)
        #expect(theme.errorTextColor.gopayHex == "#CC0000")
    }

    @Test func decode_omittedKeysKeepTheirDefaults() throws {
        let json = "{ \"labelColor\": \"#c8102e\" }"
        let theme = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))

        #expect(theme.labelColor.gopayHex == "#C8102E")
        #expect(theme.inputPaddingVertical == GopayCardFormTheme.standard.inputPaddingVertical)
        #expect(theme.groupSpacing == GopayCardFormTheme.standard.groupSpacing)
        #expect(theme.inputBorderStyle == .underline)
    }

    @Test func decode_unknownBorderStyleFallsBackInsteadOfFailing() throws {
        let unknown = try JSONDecoder().decode(
            GopayCardFormTheme.self,
            from: Data("{ \"inputBorderStyle\": \"dashed\" }".utf8)
        )
        let cased = try JSONDecoder().decode(
            GopayCardFormTheme.self,
            from: Data("{ \"inputBorderStyle\": \"UNDERLINE\" }".utf8)
        )

        #expect(unknown.inputBorderStyle == .underline)
        #expect(cased.inputBorderStyle == .underline)
    }

    @Test func decode_negativeAndNonNumericLengthsFallBackToTheDefault() throws {
        let json = """
        {
          "inputPaddingVertical": -12,
          "inputBorderRadius": -8,
          "inputBorderWidth": -1,
          "groupSpacing": -16,
          "fieldSpacing": -4,
          "formPadding": -100,
          "errorMinHeight": -14,
          "labelFontSize": -11,
          "inputFontSize": -14,
          "errorFontSize": -11,
          "inputHeight": -40,
          "errorSpacing": -3,
          "labelLineHeight": -12,
          "inputPaddingHorizontal": "12px"
        }
        """

        let theme = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))
        let standard = GopayCardFormTheme.standard

        #expect(theme.inputPaddingVertical == standard.inputPaddingVertical)
        #expect(theme.inputPaddingHorizontal == standard.inputPaddingHorizontal)
        #expect(theme.inputBorderRadius == standard.inputBorderRadius)
        #expect(theme.inputBorderWidth == standard.inputBorderWidth)
        #expect(theme.groupSpacing == standard.groupSpacing)
        #expect(theme.fieldSpacing == standard.fieldSpacing)
        #expect(theme.formPadding == standard.formPadding)
        #expect(theme.errorMinHeight == standard.errorMinHeight)
        #expect(theme.labelFontSize == standard.labelFontSize)
        #expect(theme.inputFontSize == standard.inputFontSize)
        #expect(theme.errorFontSize == standard.errorFontSize)
        // The optional lengths simply stay unset rather than carrying a negative into layout.
        #expect(theme.inputHeight == nil)
        #expect(theme.errorSpacing == nil)
        #expect(theme.labelLineHeight == nil)
    }

    @Test func decode_letterSpacingMayBeNegative() throws {
        let json = "{ \"labelLetterSpacing\": -0.5 }"
        let theme = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))

        #expect(theme.labelLetterSpacing == -0.5)
    }

    @Test func decode_unparsableColorFallsBackToTheDefault() throws {
        let json = "{ \"labelColor\": \"not-a-color\" }"
        let theme = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))

        #expect(theme.labelColor == GopayCardFormTheme.standard.labelColor)
    }

    /// One bad value costs its own key only; the rest of the document still applies, the way a
    /// TypeScript warning about one property does not fail the build.
    @Test func decode_valueOfTheWrongTypeDropsOnlyThatKey() throws {
        let json = """
        {
          "labelFontWeight": "heavy",
          "labelFontSize": "12",
          "labelHidden": "yes",
          "labelColor": 4473924,
          "labelUppercase": 1,
          "fontFamily": 12,
          "groupSpacing": 20,
          "inputBorderColor": "#698492"
        }
        """

        let theme = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))
        let standard = GopayCardFormTheme.standard

        #expect(theme.labelFontWeight == standard.labelFontWeight)
        #expect(theme.labelFontSize == standard.labelFontSize)
        #expect(theme.labelHidden == standard.labelHidden)
        #expect(theme.labelColor == standard.labelColor)
        #expect(theme.labelUppercase == standard.labelUppercase)
        #expect(theme.fontFamily == nil)
        #expect(theme.groupSpacing == 20)
        #expect(theme.inputBorderColor.gopayHex == "#698492")
    }

    @Test func decode_nullKeepsTheDefaultWithoutAWarning() throws {
        var reported: [String] = []
        let previous = GopayCardFormTheme.reportDroppedKey
        defer { GopayCardFormTheme.reportDroppedKey = previous }
        GopayCardFormTheme.reportDroppedKey = { reported.append($0) }

        let json = "{ \"placeholderColor\": null, \"labelLetterSpacing\": null }"
        let theme = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))

        #expect(theme.placeholderColor == nil)
        #expect(theme.labelLetterSpacing == nil)
        #expect(!reported.contains { $0.contains("placeholderColor") || $0.contains("labelLetterSpacing") })
    }

    @Test func decode_fontWeightAcceptsTheCssKeywords() throws {
        let json = "{ \"labelFontWeight\": \"bold\", \"inputFontWeight\": \" Normal \" }"
        let theme = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))

        #expect(theme.labelFontWeight == 700)
        #expect(theme.inputFontWeight == 400)

        let fractional = try JSONDecoder().decode(
            GopayCardFormTheme.self,
            from: Data("{ \"labelFontWeight\": 450.0 }".utf8)
        )
        #expect(fractional.labelFontWeight == 450)

        let huge = try JSONDecoder().decode(
            GopayCardFormTheme.self,
            from: Data(#"{"labelFontWeight": 1e300, "inputFontWeight": -1e300}"#.utf8)
        )
        #expect(huge.labelFontWeight == 900)
        #expect(huge.inputFontWeight == 100)
    }

    @Test func errorReserve_holdsAtLeastOneLineOfTheErrorFont() {
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

    @Test func applying_keepsTheBaseForEveryKeyTheDocumentOmits() {
        var brand = GopayCardFormTheme()
        brand.labelColor = .purple
        brand.inputBorderRadius = 20
        brand.groupSpacing = 18
        // The optional keys too: falling back to their `nil` default would clear the brand's own
        // value instead of leaving it alone.
        brand.fontFamily = "Courier"
        brand.labelLineHeight = 21
        brand.labelLetterSpacing = 2
        brand.inputFontWeight = 700
        brand.inputHeight = 56
        brand.placeholderColor = .orange
        brand.errorSpacing = 9

        // Doubled delimiters: the value itself contains a "# sequence.
        let merged = brand.applying(##"{"inputBorderColor": "#19c7d6"}"##)

        #expect(merged.inputBorderColor == Color(gopayHex: "#19c7d6"))
        #expect(merged.labelColor == brand.labelColor)
        #expect(merged.inputBorderRadius == brand.inputBorderRadius)
        #expect(merged.groupSpacing == brand.groupSpacing)
        #expect(merged.fontFamily == brand.fontFamily)
        #expect(merged.labelLineHeight == brand.labelLineHeight)
        #expect(merged.labelLetterSpacing == brand.labelLetterSpacing)
        #expect(merged.inputFontWeight == brand.inputFontWeight)
        #expect(merged.inputHeight == brand.inputHeight)
        #expect(merged.placeholderColor == brand.placeholderColor)
        #expect(merged.errorSpacing == brand.errorSpacing)
    }

    @Test func applying_keepsTheBaseWhenTheDocumentCannotBeRead() {
        var brand = GopayCardFormTheme()
        brand.inputBorderRadius = 20

        #expect(brand.applying("not json").inputBorderRadius == 20)
        #expect(brand.applying("[]").inputBorderRadius == 20)
        #expect(brand.applying("null").inputBorderRadius == 20)
    }

    @Test func decode_dropsLengthsBeyondTheCeiling() throws {
        var reported: [String] = []
        let previous = GopayCardFormTheme.reportDroppedKey
        defer { GopayCardFormTheme.reportDroppedKey = previous }
        GopayCardFormTheme.reportDroppedKey = { reported.append($0) }

        let theme = try JSONDecoder().decode(
            GopayCardFormTheme.self,
            from: Data(#"{"inputHeight": 1e9, "inputBorderWidth": 1e12, "groupSpacing": 24}"#.utf8)
        )

        #expect(theme.inputHeight == nil)
        #expect(theme.inputBorderWidth == GopayCardFormTheme.standard.inputBorderWidth)
        #expect(theme.groupSpacing == 24)
        #expect(reported.contains { $0.contains("inputHeight") })
        #expect(reported.contains { $0.contains("inputBorderWidth") })
    }
    @Test func decode_reportsEveryDroppedKeyToTheHost() throws {
        var reported: [String] = []
        let previous = GopayCardFormTheme.reportDroppedKey
        defer { GopayCardFormTheme.reportDroppedKey = previous }
        GopayCardFormTheme.reportDroppedKey = { reported.append($0) }

        // Keys no other test drops, so a stray report from a neighbouring test cannot blur the counts.
        let json = """
        {
          "inputFontWeight": "heavy",
          "labelLineHeight": true,
          "formBackgroundColor": "#12",
          "labelLetterSpacing": "wide",
          "labelUppercase": true
        }
        """
        _ = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))

        for key in ["inputFontWeight", "labelLineHeight", "formBackgroundColor", "labelLetterSpacing"] {
            #expect(reported.filter { $0.contains("\"\(key)\"") }.count == 1, "\(key) reported once")
        }
        #expect(!reported.contains { $0.contains("labelUppercase") })
    }
}
