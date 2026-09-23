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
        theme: GopayCardFormTheme = GopayCardFormTheme(),
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

    /// How tall the whole form lays out, for checking what the padding around a field adds.
    private func hostedFormHeight(
        theme: GopayCardFormTheme,
        sizeCategory: ContentSizeCategory = .large
    ) -> CGFloat {
        let host = UIHostingController(
            rootView: GopayCardForm(theme: theme, locale: "en").environment(\.sizeCategory, sizeCategory)
        )
        return host.sizeThatFits(in: CGSize(width: 380, height: CGFloat.greatestFiniteMagnitude)).height
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
            let expected = GopayCardFormTheme().inputUIFont(for: category).pointSize
            let rendered = hostedFields(sizeCategory: category).first?.font?.pointSize

            #expect(rendered == expected, "at \(category) the field should render at \(expected)pt")
        }
    }

    /// A document can ask for a field of no height; it says nothing, so it is read as unset.
    @Test func aZeroOrNegativeMinimumHeightIsReadAsUnset() {
        var zero = GopayCardFormTheme()
        zero.inputHeight = 0
        var negative = GopayCardFormTheme()
        negative.inputHeight = -40

        let natural = hostedFormHeight(theme: GopayCardFormTheme())
        #expect(hostedFormHeight(theme: zero) == natural)
        #expect(hostedFormHeight(theme: negative) == natural)
    }

    /// `inputHeight` is the smallest height of the input, with the vertical padding inside it
    /// rather than on top of it, which is how Android reads the same key. A minimum under what the
    /// field already needs changes nothing.
    @Test func aMinimumHeightRaisesTheFieldButNeverLowersIt() {
        var tall = GopayCardFormTheme()
        tall.inputHeight = 80
        var short = GopayCardFormTheme()
        short.inputHeight = 1

        let natural = hostedFormHeight(theme: GopayCardFormTheme())
        #expect(hostedFormHeight(theme: short) == natural)
        // Two rows of fields, so each point of minimum above the natural height counts twice.
        #expect(hostedFormHeight(theme: tall) > natural)
        var taller = tall
        taller.inputHeight = 100
        #expect(hostedFormHeight(theme: taller) == hostedFormHeight(theme: tall) + 40)
    }

    /// The padding lives inside the minimum rather than being added on top of it, so raising it
    /// under a minimum that already dominates does not make the form any taller.
    @Test func theVerticalPaddingSitsInsideAMinimumHeight() {
        var tight = GopayCardFormTheme()
        tight.inputHeight = 80
        tight.inputPaddingVertical = 0
        var padded = tight
        padded.inputPaddingVertical = 12

        #expect(hostedFormHeight(theme: padded) == hostedFormHeight(theme: tight))

        // With no minimum to absorb it, the same padding does add to the form.
        var noMinimum = GopayCardFormTheme()
        noMinimum.inputPaddingVertical = 0
        var noMinimumPadded = noMinimum
        noMinimumPadded.inputPaddingVertical = 12
        #expect(hostedFormHeight(theme: noMinimumPadded) == hostedFormHeight(theme: noMinimum) + 48)
    }

    /// A negative padding is reachable from code and would pull the text out of its own field.
    @Test func aNegativePaddingIsReadAsNone() {
        var negative = GopayCardFormTheme()
        negative.inputPaddingVertical = -20
        negative.inputPaddingHorizontal = -20
        var none = GopayCardFormTheme()
        none.inputPaddingVertical = 0
        none.inputPaddingHorizontal = 0

        #expect(hostedFormHeight(theme: negative) == hostedFormHeight(theme: none))
    }

    /// The point of the change: a reader on a large text size gets a taller field, not a cropped one.
    @Test func aMinimumHeightStillGrowsWithTheTextSize() {
        var tall = GopayCardFormTheme()
        tall.inputHeight = 60

        let normal = hostedFormHeight(theme: tall)
        let large = hostedFormHeight(theme: tall, sizeCategory: .accessibilityExtraExtraLarge)

        #expect(large > normal, "the field grows with the text instead of cropping it")
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
