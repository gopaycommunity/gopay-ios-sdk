//
//  CardFormValidationTests.swift
//  sdkTests
//
//  The card number the form accepts: 16 digits that pass the Luhn check, as on Android
//  (GPMOB-192). The lengths of the fields are as they were.
//

import Testing
@testable import sdk

struct CardFormValidationTests {

    private func data(card: String) -> GopayCardFormData {
        GopayCardFormData(cardNumber: card, expirationMonth: "12", expirationYear: "99", cvv: "123")
    }

    @Test(arguments: ["4111111111111111", "5555555555554444", "4444444444444448"])
    func aSixteenDigitNumberPassingLuhnIsValid(card: String) {
        #expect(data(card: card).isCardNumberValid)
        #expect(data(card: card).isValid)
    }

    @Test(arguments: ["4111111111111112", "5555555555554445", "1234567812345678"])
    func aSixteenDigitNumberFailingLuhnIsInvalid(card: String) {
        #expect(!data(card: card).isCardNumberValid)
        #expect(!data(card: card).isValid)
    }

    /// The length stays as it was: 16 digits, whatever the check digit says.
    @Test(arguments: ["4222222222222", "378282246310005", "4111111111111111110"])
    func aNumberOfAnotherLengthIsInvalidEvenWhenItPassesLuhn(card: String) {
        #expect(GopayCardFormData.passesLuhn(card))
        #expect(!data(card: card).isCardNumberValid)
    }

    /// The focus leaves the number only at 16 digits that pass the check, as on Android.
    @Test(arguments: [
        ("4111111111111111", true),
        ("4111111111111112", false),
        ("411111111111111", false),
    ])
    func theFocusMovesOnOnlyAtSixteenDigitsPassingLuhn(digits: String, movesOn: Bool) {
        #expect(GopayCardFormData.completesCardNumber(digits) == movesOn)
    }

    @Test func theLuhnCheckMatchesKnownNumbers() {
        #expect(GopayCardFormData.passesLuhn("79927398713"))
        #expect(!GopayCardFormData.passesLuhn("79927398710"))
    }
}
