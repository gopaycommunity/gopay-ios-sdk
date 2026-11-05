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
        mode: GopayCardFormErrors.Mode = .live(submitAttempted: false),
        cardEdited: Bool = true,
        expEdited: Bool = true,
        cvvEdited: Bool = true,
        cardLeft: Bool = false,
        expLeft: Bool = false,
        cvvLeft: Bool = false
    ) -> GopayCardFormErrors {
        GopayCardFormErrors(
            data: data,
            strings: strings,
            mode: mode,
            cardNumberEdited: cardEdited,
            expirationEdited: expEdited,
            cvvEdited: cvvEdited,
            cardNumberWasLeft: cardLeft,
            expirationWasLeft: expLeft,
            cvvWasLeft: cvvLeft
        )
    }

    // A card that is fully valid and in the future.
    private var validData: GopayCardFormData {
        GopayCardFormData(cardNumber: "4444444444444448", expirationMonth: "12", expirationYear: "99", cvv: "123")
    }

    private var invalidData: GopayCardFormData {
        GopayCardFormData(cardNumber: "1234", expirationMonth: "13", expirationYear: "20", cvv: "1")
    }

    // MARK: - Live mode
    //
    // The rule both SDKs share: an error shows once the field is typed out and still fails, once
    // the user has left it, or once a submit ran; never for an empty field, never mid-typing.

    /// Typed out: 16 digits failing the Luhn check, a past date. Neither is something more typing
    /// would fix.
    private var typedOutButInvalid: GopayCardFormData {
        GopayCardFormData(cardNumber: "4444444444444449", expirationMonth: "12", expirationYear: "20", cvv: "123")
    }

    /// Partway through every field.
    private var beingTyped: GopayCardFormData {
        GopayCardFormData(cardNumber: "4444", expirationMonth: "1", expirationYear: "", cvv: "1")
    }

    @Test func liveKeepsQuietWhileAFieldIsStillBeingTyped() {
        let errors = make(data: beingTyped)
        #expect(errors.cardNumber == nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    @Test func liveFlagsAFieldOnceItHoldsItsFullLengthAndStillFails() {
        let errors = make(data: typedOutButInvalid, strings: GopayLocales.cs)
        #expect(errors.cardNumber == GopayLocales.cs.panErrorPattern)
        #expect(errors.expiration == GopayLocales.cs.expErrorPattern)
        #expect(errors.cvv == nil, "a typed-out CVV is valid")
    }

    @Test func liveFlagsAFieldOnceTheUserHasLeftIt() {
        let errors = make(data: beingTyped, strings: GopayLocales.cs, cardLeft: true, expLeft: true, cvvLeft: true)
        #expect(errors.cardNumber == GopayLocales.cs.panErrorPattern)
        #expect(errors.expiration == GopayLocales.cs.expErrorPattern)
        #expect(errors.cvv == GopayLocales.cs.cvvErrorPattern)
    }

    /// Leaving one field flags that field only; the others are still being typed.
    @Test func liveFlagsOnlyTheFieldTheUserHasLeft() {
        let errors = make(data: beingTyped, strings: GopayLocales.cs, cardLeft: true)
        #expect(errors.cardNumber == GopayLocales.cs.panErrorPattern)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    @Test func liveFlagsEveryEditedFieldOnceASubmitRanNeverAnEmptyOne() {
        let partial = GopayCardFormData(cardNumber: "4444", expirationMonth: "", expirationYear: "", cvv: "12")
        let errors = make(data: partial, strings: GopayLocales.cs, mode: .live(submitAttempted: true), expEdited: false)
        #expect(errors.cardNumber == GopayLocales.cs.panErrorPattern)
        #expect(errors.expiration == nil, "empty: no required message in live")
        #expect(errors.cvv == GopayLocales.cs.cvvErrorPattern)
    }

    @Test func liveMessagesFollowTheSelectedLocale() {
        let data = GopayCardFormData(cardNumber: "1234")
        #expect(make(data: data, strings: GopayLocales.de, cardLeft: true).cardNumber == GopayLocales.de.panErrorPattern)
        #expect(make(data: data, strings: GopayLocales.fr, cardLeft: true).cardNumber == GopayLocales.fr.panErrorPattern)
    }

    @Test func liveShowsNothingForValidFields() {
        let errors = make(data: validData, mode: .live(submitAttempted: true), cardLeft: true, expLeft: true, cvvLeft: true)
        #expect(errors.cardNumber == nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    @Test func liveNeverFlagsAnEmptyField() {
        let errors = make(data: GopayCardFormData(), mode: .live(submitAttempted: true), cardLeft: true, expLeft: true, cvvLeft: true)
        #expect(errors.cardNumber == nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    @Test func liveLeavesAFieldNobodyTypedIntoAlone() {
        let errors = make(data: invalidData, mode: .live(submitAttempted: true),
                          cardEdited: false, expEdited: false, cvvEdited: false, cardLeft: true, expLeft: true, cvvLeft: true)
        #expect(errors.cardNumber == nil)
        #expect(errors.expiration == nil)
        #expect(errors.cvv == nil)
    }

    @Test func liveFlagsOnlyTheFieldThatFails() {
        let data = GopayCardFormData(cardNumber: "1234", expirationMonth: "12", expirationYear: "99", cvv: "123")
        let errors = make(data: data, cardLeft: true, expLeft: true, cvvLeft: true)
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
