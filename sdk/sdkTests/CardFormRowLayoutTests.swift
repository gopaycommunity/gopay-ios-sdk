//
//  CardFormRowLayoutTests.swift
//  sdkTests
//
//  Pins the invariant the row height exists for: the three inputs end up the same height however
//  they are themed, even though a masked field measures its bullets lower than digits. Measured
//  on a hosted form rather than recomputed, so the assertion cannot drift with the arithmetic.
//

import Testing
import SwiftUI
import UIKit
@testable import sdk

@MainActor
struct CardFormRowLayoutTests {

    /// Lays the form out in a window and returns the text fields in the order they appear.
    private func hostedFields(
        theme: GopayCardFormTheme = .standard,
        sizeCategory: ContentSizeCategory = .large
    ) -> [UITextField] {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 380, height: 400))
        window.rootViewController = UIHostingController(
            rootView: GopayCardForm(theme: theme, locale: "en")
                .environment(\.sizeCategory, sizeCategory)
        )
        window.isHidden = false
        window.layoutIfNeeded()

        var found: [UITextField] = []
        func walk(_ view: UIView) {
            if let field = view as? UITextField { found.append(field) }
            view.subviews.forEach(walk)
        }
        walk(window)
        return found
    }

    @Test func theThreeInputsEndUpTheSameHeight() {
        let fields = hostedFields()

        #expect(fields.count == 3, "card number, expiration and CVV")
        let heights = Set(fields.map { $0.bounds.height })
        #expect(heights.count == 1, "one height across the row, got \(heights.sorted())")
    }

    /// The masked field is the one that would come out short if it were left to itself.
    @Test func theMaskedFieldMatchesThePlainOnes() {
        let fields = hostedFields()
        guard let secure = fields.first(where: { $0.isSecureTextEntry }),
              let plain = fields.first(where: { !$0.isSecureTextEntry }) else {
            Issue.record("expected one masked and at least one plain field")
            return
        }

        #expect(secure.bounds.height == plain.bounds.height)
        // Left to itself the masked field measures lower, which is the whole reason for the rule.
        #expect(secure.intrinsicContentSize.height < plain.intrinsicContentSize.height)
    }

    @Test func theRowStaysEvenWithATallerFontAndAtALargerTextSize() {
        var large = GopayCardFormTheme()
        large.inputFontSize = 28

        for fields in [hostedFields(theme: large), hostedFields(sizeCategory: .accessibilityLarge)] {
            #expect(Set(fields.map { $0.bounds.height }).count == 1)
        }
    }

    /// The text in the field follows the same text size as the box around it, so a preview or a
    /// host that overrides the category gets both, not one of each.
    @Test func theInputFontFollowsTheEnvironmentsTextSize() {
        for category in [ContentSizeCategory.large, .accessibilityLarge] {
            let expected = GopayCardFormTheme.standard.inputUIFont(for: category).pointSize
            let rendered = hostedFields(sizeCategory: category).first?.font?.pointSize

            #expect(rendered == expected, "at \(category) the field should render at \(expected)pt")
        }
    }

    /// A document can ask for a field of no height; obeying it would put the digits outside the
    /// field, over the label and the error line.
    @Test func aZeroOrNegativeFixedHeightIsReadAsUnset() {
        var zero = GopayCardFormTheme()
        zero.inputHeight = 0
        var negative = GopayCardFormTheme()
        negative.inputHeight = -40

        let natural = hostedFields().first?.bounds.height ?? 0
        #expect(hostedFields(theme: zero).first?.bounds.height == natural)
        #expect(hostedFields(theme: negative).first?.bounds.height == natural)
    }

    /// A width past the field would inset `strokeBorder` out of existence and lose the border.
    @Test func anAbsurdBorderWidthStillLeavesTheFieldStanding() {
        var huge = GopayCardFormTheme()
        huge.inputBorderWidth = 10_000

        let fields = hostedFields(theme: huge)
        #expect(fields.count == 3)
        #expect(Set(fields.map { $0.bounds.height }).count == 1)
        #expect((fields.first?.bounds.height ?? 0) > 0)
    }

    /// The height follows the environment's category, not the device's, so a preview or a host
    /// that overrides it gets fields that match its labels.
    @Test func theRowGrowsWithTheEnvironmentsTextSize() {
        let small = hostedFields(sizeCategory: .small).first?.bounds.height ?? 0
        let large = hostedFields(sizeCategory: .accessibilityExtraLarge).first?.bounds.height ?? 0

        #expect(large > small)
    }
}
