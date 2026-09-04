//
//  GopayCardFormThemeTests.swift
//  sdkTests
//
//  Pins the public shape of GopayCardFormTheme: the defaults, which are the web card form's, the
//  hex bridge used for JSON themes, the CSS font weight mapping, the tolerant decoder, and the
//  geometry rules of the underline, the collapsed borders and the focus ring.
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
        #expect(theme.inputLineHeight == nil)
        #expect(theme.inputLetterSpacing == nil)
        #expect(theme.inputHeight == nil)
        #expect(theme.inputBorderStyle == .underline)
        #expect(theme.inputBorderWidth == 1)
        #expect(theme.inputPaddingVertical == 6)
        #expect(theme.inputPaddingHorizontal == 0)
        #expect(theme.inputBorderRadius == 0)
        #expect(theme.inputBorderCollapse == false)
        #expect(theme.focusRingWidth == nil)
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
        #expect(theme.focusGradientStart == Color(gopayHex: "#19c7d6"))
        #expect(theme.focusGradientEnd == Color(gopayHex: "#1899d6"))
        #expect(theme.inputErrorBorderColor == .red)
        #expect(theme.errorTextColor == .red)
        #expect(theme.formBackgroundColor == .clear)
        #expect(theme.placeholderColor == nil)
        #expect(theme.focusRingColor == nil)
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

        #expect(theme.borderColor(isFocused: false, hasError: false) == .gray)
    }

    @Test func borderColor_invalidUnfocusedFieldUsesTheErrorColor() {
        var theme = GopayCardFormTheme()
        theme.inputErrorBorderColor = .orange

        #expect(theme.borderColor(isFocused: false, hasError: true) == .orange)
    }

    @Test func borderColor_focusWinsOverError() {
        var theme = GopayCardFormTheme()
        theme.focusGradientStart = .green
        theme.inputErrorBorderColor = .orange

        #expect(theme.borderColor(isFocused: true, hasError: true) == .green)
        #expect(theme.borderColor(isFocused: true, hasError: false) == .green)
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

    // MARK: - Underline

    @Test func underline_followsTheRoundedBottomCornersInsideTheInput() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let line = GopayInputUnderline(radius: 8, lineWidth: 2).path(in: rect).boundingRect

        // The stroke stays inside the input and climbs each corner up to where the arc ends.
        #expect(line.minX == 1)
        #expect(line.maxX == 99)
        #expect(line.maxY == 39)
        #expect(line.minY == 32)
    }

    @Test func underline_isAStraightLineWithoutARadius() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let line = GopayInputUnderline(radius: 0, lineWidth: 1).path(in: rect).boundingRect

        #expect(line.minX == 0)
        #expect(line.maxX == 100)
        #expect(line.height == 0)
        #expect(line.minY == 39.5)
    }

    @Test func underline_capsAnOversizedRadiusLikeABrowser() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let line = GopayInputUnderline(radius: 999, lineWidth: 1).path(in: rect).boundingRect

        // A pill: the arcs reach half the height and meet the straight run in the middle.
        #expect(abs(line.minY - 20) < 0.001)
        #expect(abs(line.minX - 0.5) < 0.001)
    }

    @Test func errorSpacing_fallsBackToFieldSpacing() {
        var theme = GopayCardFormTheme()
        theme.fieldSpacing = 6

        #expect(theme.resolvedErrorSpacing == 6)

        theme.errorSpacing = 3
        #expect(theme.resolvedErrorSpacing == 3)
    }

    // MARK: - Collapsed borders

    private func edges(
        _ position: GopayCollapsedInputPosition,
        _ layoutDirection: LayoutDirection = .leftToRight,
        rowsTouch: Bool = true,
        bottomRowTouches: Bool = true
    ) -> GopayCollapsedBorderEdges {
        gopayCollapsedBorderEdges(
            position: position,
            layoutDirection: layoutDirection,
            rowsTouch: rowsTouch,
            bottomRowTouches: bottomRowTouches
        )
    }

    /// Mirrors the Android `sharedEdges_areDrawnExactlyOnce`.
    @Test func sharedEdges_areDrawnExactlyOnce() {
        let top = edges(.top)
        let start = edges(.bottomStart)
        let end = edges(.bottomEnd)

        // The top field owns the line it shares with the row below.
        #expect(top.drawBottom)
        #expect(!start.drawTop)
        #expect(!end.drawTop)

        // The leading field owns the line between the two bottom fields.
        #expect(start.drawRight)
        #expect(!end.drawLeft)
    }

    /// Mirrors the Android `radius_roundsOnlyTheOuterCornersOfTheBlock`.
    @Test func radius_roundsOnlyTheOuterCornersOfTheBlock() {
        let top = edges(.top)
        let start = edges(.bottomStart)
        let end = edges(.bottomEnd)

        #expect(top.roundTopLeft && top.roundTopRight)
        #expect(!(top.roundBottomLeft || top.roundBottomRight))
        #expect(start.roundBottomLeft)
        #expect(!(start.roundBottomRight || start.roundTopLeft || start.roundTopRight))
        #expect(end.roundBottomRight)
        #expect(!(end.roundBottomLeft || end.roundTopLeft || end.roundTopRight))
    }

    /// Mirrors the Android `bottomRow_mirrorsInRightToLeftLayouts`.
    @Test func bottomRow_mirrorsInRightToLeftLayouts() {
        let start = edges(.bottomStart, .rightToLeft)
        let end = edges(.bottomEnd, .rightToLeft)

        // The leading field is on the right.
        #expect(start.roundBottomRight)
        #expect(!start.roundBottomLeft)
        // The trailing field is on the left and draws the outer left edge of the block.
        #expect(end.roundBottomLeft)
        #expect(end.drawLeft)
        // The shared line is left to the leading field.
        #expect(!end.drawRight)
    }

    @Test func fieldsThatDoNotTouch_drawAFullFrame() {
        let start = edges(.bottomStart, rowsTouch: false, bottomRowTouches: false)
        let end = edges(.bottomEnd, rowsTouch: false, bottomRowTouches: false)
        let top = edges(.top, rowsTouch: false, bottomRowTouches: false)

        // Nothing is shared, so no field is missing a side.
        for field in [top, start, end] {
            #expect(field.drawTop && field.drawBottom && field.drawLeft && field.drawRight)
        }
        // A standalone field rounds all four of its corners.
        let everyCorner: UIRectCorner = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        #expect(top.corners == everyCorner)
        #expect(start.corners == everyCorner)
        #expect(end.corners == everyCorner)
    }

    @Test func aGapInOneDirectionOnlyKeepsTheOtherSeamShared() {
        // Rows apart, bottom row still flush: only the line between the two bottom fields merges.
        let start = edges(.bottomStart, rowsTouch: false, bottomRowTouches: true)
        let end = edges(.bottomEnd, rowsTouch: false, bottomRowTouches: true)

        #expect(start.drawTop)
        #expect(end.drawTop)
        #expect(start.drawRight)
        #expect(!end.drawLeft)
    }

    @Test func seamCover_repaintsTheWholeOfEverySharedLine() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let cover = GopayCollapsedSeamCover(lineWidth: 2, edges: edges(.bottomEnd)).path(in: rect)

        // The CVV shares its top line with the card number and its left line with the expiration.
        // The neighbour draws that line inside itself at the full width, so the cover reaches the
        // whole two points above and left of the field, around the corner.
        let bounds = cover.boundingRect
        #expect(bounds.minY == -2)
        #expect(bounds.minX == -2)
        #expect(bounds.maxX == rect.maxX)
        #expect(bounds.maxY == rect.maxY)
        #expect(cover.contains(CGPoint(x: -1.5, y: -1.5)))
        #expect(!cover.contains(CGPoint(x: 50, y: 20)))
    }

    @Test func seamCover_isEmptyForAFieldThatOwnsEveryLineItShares() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let top = GopayCollapsedSeamCover(lineWidth: 2, edges: edges(.top)).path(in: rect)
        let apart = GopayCollapsedSeamCover(
            lineWidth: 2,
            edges: edges(.bottomEnd, rowsTouch: false, bottomRowTouches: false)
        ).path(in: rect)

        #expect(top.isEmpty)
        #expect(apart.isEmpty)
    }

    @Test func seamCover_stopsAtAnOwnedOuterEdge() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        // The expiration shares only its top line; its own left edge is the outside of the block.
        let cover = GopayCollapsedSeamCover(lineWidth: 2, edges: edges(.bottomStart)).path(in: rect)

        #expect(cover.boundingRect == CGRect(x: 0, y: -2, width: 100, height: 2))
    }

    @Test func rowsTouch_onlyWhenNothingOpensAGapBetweenThem() {
        var theme = GopayCardFormTheme()
        theme.groupSpacing = 0
        theme.labelHidden = true
        theme.errorMinHeight = 0
        #expect(theme.collapsedRowsTouch(cardNumberError: nil))
        #expect(theme.collapsedBottomRowTouches)

        theme.labelHidden = false
        #expect(!theme.collapsedRowsTouch(cardNumberError: nil))
        // A visible label sits above the bottom row, not between its two fields.
        #expect(theme.collapsedBottomRowTouches)

        theme.labelHidden = true
        theme.errorMinHeight = 14
        #expect(!theme.collapsedRowsTouch(cardNumberError: nil))

        theme.errorMinHeight = 0
        theme.groupSpacing = 16
        #expect(!theme.collapsedRowsTouch(cardNumberError: nil))
        #expect(!theme.collapsedBottomRowTouches)
    }

    /// The gap follows what is on screen, not only the theme: a live error under the card number
    /// sits between the rows for as long as it shows.
    @Test func rowsTouch_opensWhileAnErrorShowsUnderTheCardNumber() {
        var theme = GopayCardFormTheme()
        theme.groupSpacing = 0
        theme.labelHidden = true
        theme.errorMinHeight = 0

        #expect(theme.collapsedRowsTouch(cardNumberError: nil))
        #expect(!theme.collapsedRowsTouch(cardNumberError: "Invalid card number"))
        #expect(theme.rendersErrorSlot(for: "Invalid card number"))
        #expect(!theme.rendersErrorSlot(for: nil))
        // An empty message draws nothing, so it must not open the block for an invisible gap.
        #expect(!theme.rendersErrorSlot(for: ""))
        #expect(theme.collapsedRowsTouch(cardNumberError: ""))

        theme.errorMinHeight = 14
        #expect(theme.rendersErrorSlot(for: nil))
    }

    @Test func focusRing_needsBothHalvesAndAPositiveWidth() {
        var theme = GopayCardFormTheme()
        #expect(theme.resolvedFocusRing == nil)

        theme.focusRingWidth = 6
        #expect(theme.resolvedFocusRing == nil, "a width without a color draws nothing")

        theme.focusRingColor = .green
        #expect(theme.resolvedFocusRing?.width == 6)

        theme.focusRingWidth = 0
        #expect(theme.resolvedFocusRing == nil, "a zero width draws nothing")

        theme.focusRingWidth = -4
        #expect(theme.resolvedFocusRing == nil, "a negative width draws nothing")
    }

    @Test func cornerRadii_applyOnlyToTheSelectedCornersAndCapOnShortSides() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let radii = GopayCornerRadii(radius: 8, corners: [.topLeft, .bottomRight], in: rect)

        #expect(radii.topLeft == 8)
        #expect(radii.bottomRight == 8)
        #expect(radii.topRight == 0)
        #expect(radii.bottomLeft == 0)

        let capped = GopayCornerRadii(radius: 100, corners: .allCorners, in: rect)
        #expect(capped.topLeft == 20)

        // A hostile radius cannot invert a side.
        let negative = GopayCornerRadii(radius: -8, corners: .allCorners, in: rect)
        #expect(negative.topLeft == 0)
    }

    @Test func collapsedBorder_drawsOnlyTheEdgesTheInputOwns() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let blank = GopayCollapsedBorderEdges(
            drawTop: false, drawBottom: false, drawLeft: false, drawRight: false,
            roundTopLeft: false, roundTopRight: false, roundBottomRight: false, roundBottomLeft: false
        )
        var topOnlyEdges = blank
        topOnlyEdges.drawTop = true
        var bottomOnlyEdges = blank
        bottomOnlyEdges.drawBottom = true

        // The line is drawn at the full border width, centered half a width inside the cell, so
        // the whole stroke lies within the field as it does on Android and on the web.
        let topOnly = GopayCollapsedInputBorder(radius: 0, lineWidth: 2, edges: topOnlyEdges).path(in: rect)
        #expect(!topOnly.isEmpty)
        #expect(topOnly.boundingRect.height == 0)
        #expect(topOnly.boundingRect.minY == rect.minY + 1)
        #expect(GopayCollapsedInputBorder(radius: 0, lineWidth: 2, edges: topOnlyEdges).strokeWidth == 2)

        let bottomOnly = GopayCollapsedInputBorder(radius: 0, lineWidth: 2, edges: bottomOnlyEdges).path(in: rect)
        #expect(bottomOnly.boundingRect.minY == rect.maxY - 1)

        #expect(GopayCollapsedInputBorder(radius: 0, lineWidth: 2, edges: blank).path(in: rect).isEmpty)
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
        theme.focusGradientStart = try #require(Color(gopayHex: "#19c7d6"))
        theme.focusGradientEnd = try #require(Color(gopayHex: "#1899d6"))
        theme.inputBackgroundColor = try #require(Color(gopayHex: "#1a1f2e80"))
        theme.formBackgroundColor = .clear

        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(GopayCardFormTheme.self, from: data)

        #expect(decoded.labelColor.gopayHex == "#4B5E68")
        #expect(decoded.inputBorderColor.gopayHex == "#698492")
        #expect(decoded.focusGradientStart.gopayHex == "#19C7D6")
        #expect(decoded.focusGradientEnd.gopayHex == "#1899D6")
        #expect(decoded.inputBackgroundColor.gopayHex == "#1A1F2E80")
        #expect(decoded.formBackgroundColor.gopayHex == "transparent")
    }

    @Test func encode_writesEveryValueAndSkipsTheUnsetOnes() throws {
        let data = try JSONEncoder().encode(GopayCardFormTheme.standard)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["inputBorderStyle"] as? String == "underline")
        #expect(json["groupSpacing"] as? Double == 16)
        #expect(json["fontFamily"] == nil)
        #expect(json["focusRingWidth"] == nil)
        #expect(json["placeholderColor"] == nil)
        #expect(json["inputLineHeight"] == nil)
    }

    // MARK: - Decoding a web theme

    /// The DEFAULT_CARD_FORM_THEME preset the web SDK ships, submit* and errorHidden keys and all.
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
          "focusRingWidth": -3,
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
        #expect(theme.focusRingWidth == nil)
        #expect(theme.errorSpacing == nil)
        #expect(theme.labelLineHeight == nil)
    }

    @Test func decode_letterSpacingMayBeNegative() throws {
        let json = "{ \"labelLetterSpacing\": -0.5, \"inputLetterSpacing\": -1 }"
        let theme = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))

        #expect(theme.labelLetterSpacing == -0.5)
        #expect(theme.inputLetterSpacing == -1)
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
          "inputBorderCollapse": 1,
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
        #expect(theme.inputBorderCollapse == standard.inputBorderCollapse)
        #expect(theme.fontFamily == nil)
        #expect(theme.groupSpacing == 20)
        #expect(theme.inputBorderColor.gopayHex == "#698492")
    }

    @Test func decode_nullKeepsTheDefaultWithoutAWarning() throws {
        var reported: [String] = []
        let previous = GopayCardFormTheme.reportDroppedKey
        defer { GopayCardFormTheme.reportDroppedKey = previous }
        GopayCardFormTheme.reportDroppedKey = { reported.append($0) }

        let json = "{ \"placeholderColor\": null, \"inputLetterSpacing\": null }"
        let theme = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))

        #expect(theme.placeholderColor == nil)
        #expect(theme.inputLetterSpacing == nil)
        #expect(!reported.contains { $0.contains("placeholderColor") || $0.contains("inputLetterSpacing") })
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

    @Test func boxedBorderInset_neverEatsTheWholeField() {
        var theme = GopayCardFormTheme()
        let field = CGSize(width: 200, height: 40)

        theme.inputBorderWidth = 2
        #expect(theme.boxedBorderInset(in: field) == 1)

        // Past the field's smaller side the inset would leave no rectangle to stroke.
        theme.inputBorderWidth = 400
        #expect(theme.boxedBorderInset(in: field) == 20)
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
        brand.inputLineHeight = 24
        brand.inputLetterSpacing = 1
        brand.inputHeight = 56
        brand.placeholderColor = .orange
        brand.focusRingWidth = 3
        brand.focusRingColor = .green
        brand.errorSpacing = 9

        // Doubled delimiters: the value itself contains a "# sequence.
        let merged = brand.applying(##"{"focusGradientStart": "#19c7d6"}"##)

        #expect(merged.focusGradientStart == Color(gopayHex: "#19c7d6"))
        #expect(merged.labelColor == brand.labelColor)
        #expect(merged.inputBorderRadius == brand.inputBorderRadius)
        #expect(merged.groupSpacing == brand.groupSpacing)
        #expect(merged.fontFamily == brand.fontFamily)
        #expect(merged.labelLineHeight == brand.labelLineHeight)
        #expect(merged.labelLetterSpacing == brand.labelLetterSpacing)
        #expect(merged.inputFontWeight == brand.inputFontWeight)
        #expect(merged.inputLineHeight == brand.inputLineHeight)
        #expect(merged.inputLetterSpacing == brand.inputLetterSpacing)
        #expect(merged.inputHeight == brand.inputHeight)
        #expect(merged.placeholderColor == brand.placeholderColor)
        #expect(merged.focusRingWidth == brand.focusRingWidth)
        #expect(merged.focusRingColor == brand.focusRingColor)
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
          "inputLineHeight": true,
          "formBackgroundColor": "#12",
          "labelLetterSpacing": "wide",
          "labelUppercase": true
        }
        """
        _ = try JSONDecoder().decode(GopayCardFormTheme.self, from: Data(json.utf8))

        for key in ["inputFontWeight", "inputLineHeight", "formBackgroundColor", "labelLetterSpacing"] {
            #expect(reported.filter { $0.contains("\"\(key)\"") }.count == 1, "\(key) reported once")
        }
        #expect(!reported.contains { $0.contains("labelUppercase") })
    }
}
