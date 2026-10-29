//
//  CardFormAutofillTests.swift
//  sdkTests
//
//  The card number and the expiration stay out of the system's autofill unless the host opts in
//  with allowsAutofill, the CVV never takes part, and the fields keep what the keyboard and
//  VoiceOver already had: no autocorrection, no spell checking, a masked CVV, a readable label.
//

import Testing
import SwiftUI
import UIKit
@testable import sdk

@MainActor
struct CardFormAutofillTests {

    /// Lays the form out in a window and returns the card number, expiration and CVV fields.
    private func hostedFields(_ form: GopayCardForm) -> [UITextField] {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 380, height: 400))
        window.rootViewController = UIHostingController(rootView: form)
        window.isHidden = false
        window.layoutIfNeeded()

        return textFields(in: window)
    }

    @Test func autofillIsOffByDefault() throws {
        let fields = hostedFields(GopayCardForm(locale: "en"))
        try #require(fields.count == 3)
        #expect(fields.allSatisfy { $0.textContentType == nil })
    }

    @Test func allowingAutofillDeclaresTheCardNumberAndTheExpiration() throws {
        let fields = hostedFields(GopayCardForm(locale: "en", allowsAutofill: true))
        try #require(fields.count == 3)
        #expect(fields[0].textContentType == .creditCardNumber)
        if #available(iOS 17.0, *) {
            #expect(fields[1].textContentType == .creditCardExpiration)
        } else {
            #expect(fields[1].textContentType == nil)
        }
        #expect(fields[2].textContentType == nil)
    }

    /// Autofill, like a paste, hands the expiration over in one piece, often with a four-digit year.
    @Test(arguments: ["12/2027", "122027", "12/27"])
    func aWholeExpirationKeepsTheTwoDigitYear(inserted: String) throws {
        let fields = hostedFields(GopayCardForm(locale: "en", allowsAutofill: true))
        try #require(fields.count == 3)
        let expiration = fields[1]
        _ = expiration.delegate?.textField?(
            expiration, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: inserted
        )
        #expect(expiration.text == "12/27")
    }

    @Test(arguments: [false, true])
    func keyboardNeverCorrectsOrChecksTheFields(allowsAutofill: Bool) throws {
        let fields = hostedFields(GopayCardForm(locale: "en", allowsAutofill: allowsAutofill))
        try #require(fields.count == 3)
        #expect(fields.allSatisfy { $0.autocorrectionType == .no && $0.spellCheckingType == .no })
    }

    @Test func onlyTheCvvIsMasked() throws {
        let fields = hostedFields(GopayCardForm(locale: "en"))
        try #require(fields.count == 3)
        #expect(fields.map(\.isSecureTextEntry) == [false, false, true])
    }

    @Test func hiddenLabelsStayReadableToVoiceOver() throws {
        var theme = GopayCardFormTheme()
        theme.labelHidden = true
        let strings = GopayLocales.resolve("en")
        let fields = hostedFields(GopayCardForm(theme: theme, locale: "en"))
        try #require(fields.count == 3)
        #expect(fields.map(\.accessibilityLabel) == [strings.panLabel, strings.expLabel, strings.cvvLabel])
    }
}
