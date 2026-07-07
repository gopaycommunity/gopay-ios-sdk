//
//  GopayCardFormErrorsTests.swift
//  sdkTests
//
//  Tests for the inline validation-error display rules used by GopayCardForm.
//

import Testing
import Foundation
@testable import sdk

struct GopayCardFormErrorsTests {

    private func make(
        data: GopayCardFormData,
        strings: GopayLocaleStrings = GopayLocales.en,
        mode: GopayCardFormErrors.Mode = .live,
        cardEdited: Bool = true,
        expEdited: Bool = true,
        cvvEdited: Bool = true
    ) -> GopayCardFormErrors {
        GopayCardFormErrors(
            data: data,
            strings: strings,
            mode: mode,
            cardNumberEdited: cardEdited,
            expirationEdited: expEdited,
            cvvEdited: cvvEdited
        )
    }

    // A card that is fully valid and in the future.
    private var validData: GopayCardFormData {
        GopayCardFormData(cardNumber: "4444333322221111", expirationMonth: "12", expirationYear: "99", cvv: "123")
    }

    private var invalidData: GopayCardFormData {
        GopayCardFormData(cardNumber: "1234", expirationMonth: "13", expirationYear: "20", cvv: "1")
    }

    // MARK: - Live mode

    @Test func live_invalidEditedFields_returnLocalizedMessages() {
        let errors = make(data: invalidData, strings: GopayLocales.cs, mode: .live)
        #expect(errors.cardNumber == GopayLocales.cs.panErrorPattern)
        #expect(errors.expiration == GopayLocales.cs.expErrorPattern)
        #expect(errors.cvv == GopayLocales.cs.cvvErrorPattern)
    }

    @Test func live_messagesFollowSelectedLocale() {
        let data = GopayCardFormData(cardNumber: "1234")
        #expect(make(data: data, strings: GopayLocales.de).cardNumber == GopayLocales.de.panErrorPattern)
        #expect(make(data: data, strings: GopayLocales.fr).cardNumber == GopayLocales.fr.panErrorPattern)
    }

    @Test func live_validFields_returnNoErrors() {
        let errors = make(data: validData, mode: .live)
        #expect(errors.cardNumber == nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    @Test func live_emptyFields_returnNoErrors() {
        let errors = make(data: GopayCardFormData(), mode: .live)
        #expect(errors.cardNumber == nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    @Test func live_notEdited_returnsNoErrorEvenWhenInvalid() {
        let errors = make(data: invalidData, mode: .live, cardEdited: false, expEdited: false, cvvEdited: false)
        #expect(errors.cardNumber == nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    @Test func live_perFieldIndependence_onlyInvalidCardShows() {
        let data = GopayCardFormData(cardNumber: "1234", expirationMonth: "12", expirationYear: "99", cvv: "123")
        let errors = make(data: data, mode: .live)
        #expect(errors.cardNumber != nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    // MARK: - Hidden mode

    @Test func hidden_suppressesAllErrors() {
        let errors = make(data: invalidData, mode: .hidden)
        #expect(errors.cardNumber == nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    // MARK: - onSubmit mode

    @Test func onSubmit_notAttempted_returnsNoErrors() {
        let errors = make(data: invalidData, mode: .onSubmit(attempted: false))
        #expect(errors.cardNumber == nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    @Test func onSubmit_attempted_showsErrorsRegardlessOfEdited() {
        // Not edited, but a submit was attempted — errors must still surface.
        let errors = make(data: invalidData, strings: GopayLocales.cs,
                          mode: .onSubmit(attempted: true),
                          cardEdited: false, expEdited: false, cvvEdited: false)
        #expect(errors.cardNumber == GopayLocales.cs.panErrorPattern)
        #expect(errors.expiration == GopayLocales.cs.expErrorPattern)
        #expect(errors.cvv == GopayLocales.cs.cvvErrorPattern)
    }

    @Test func onSubmit_attempted_emptyFieldsSurfaceRequiredMessage() {
        let errors = make(data: GopayCardFormData(), strings: GopayLocales.cs,
                          mode: .onSubmit(attempted: true))
        #expect(errors.cardNumber == GopayLocales.cs.requiredErrorMessage)
        #expect(errors.expiration == GopayLocales.cs.requiredErrorMessage)
        #expect(errors.cvv == GopayLocales.cs.requiredErrorMessage)
    }

    @Test func onSubmit_attempted_validForm_returnsNoErrors() {
        let errors = make(data: validData, mode: .onSubmit(attempted: true))
        #expect(errors.cardNumber == nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }
}
