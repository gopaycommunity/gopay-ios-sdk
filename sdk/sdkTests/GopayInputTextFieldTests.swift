//
//  GopayInputTextFieldTests.swift
//  sdkTests
//
//  Pins the sizing of the UITextField behind the card form inputs: the three fields of a row have
//  to end up the same height whatever they show.
//

import Testing
import UIKit
@testable import sdk

@MainActor
struct GopayInputTextFieldTests {

    private func field(font: UIFont, secure: Bool, text: String) -> GopayInputTextField {
        let field = GopayInputTextField()
        field.font = font
        field.isSecureTextEntry = secure
        field.text = text
        return field
    }

    @Test func secureAndPlainFieldsShareOneHeight() {
        for font in [
            UIFont.preferredFont(forTextStyle: .body),
            UIFont.systemFont(ofSize: 20, weight: .bold),
            UIFont(name: "Georgia", size: 14)!
        ] {
            let plain = field(font: font, secure: false, text: "12/34")
            let secure = field(font: font, secure: true, text: "123")
            let empty = field(font: font, secure: true, text: "")

            #expect(plain.intrinsicContentSize.height == secure.intrinsicContentSize.height)
            #expect(plain.intrinsicContentSize.height == empty.intrinsicContentSize.height)
            #expect(plain.intrinsicContentSize.height == GopayInputTextField.height(for: font))
        }
    }

    /// At the body text style the custom height matches what a plain `UITextField` measures, so
    /// the sizing rule only equalizes the fields and does not shift them on its own.
    @Test func defaultFontKeepsTheSystemTextFieldHeight() {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let system = UITextField()
        system.font = font
        system.text = "1234"

        #expect(field(font: font, secure: false, text: "1234").intrinsicContentSize.height
            == system.intrinsicContentSize.height)
    }

    @Test func heightGrowsWithTheFont() {
        #expect(GopayInputTextField.height(for: .systemFont(ofSize: 34))
            > GopayInputTextField.height(for: .systemFont(ofSize: 17)))
    }
}
