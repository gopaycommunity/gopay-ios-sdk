//
//  CardBrandsTests.swift
//  sdkTests
//
//  The brands the card form accepts, `CardBrand`, and what the form does with a number of any
//  other: the same as with a number that fails the Luhn check (GPMOB-202). The one test of the
//  patterns; when GoPay refines them, this table changes with them. The Android SDK tests the
//  same numbers.
//

import Testing
import Foundation
@testable import sdk

struct CardBrandsTests {

    /// Sixteen digits that start with `prefix` and pass the Luhn check; a whole number as it is.
    static func number(_ prefix: String) -> String {
        if prefix.count == 16 { return prefix }
        let body = prefix.padding(toLength: 15, withPad: "0", startingAt: 0)
        return (0...9).map { "\(body)\($0)" }.first { GopayCardFormData.passesLuhn($0) }!
    }

    static let accepted: [(prefix: String, brand: CardBrand)] = [
        ("4444444444444448", .visa),
        ("4532015112830366", .visa),
        ("4", .visa),
        ("4026", .visaElectron),
        ("417500", .visaElectron),
        ("4405", .visaElectron),
        ("4508", .visaElectron),
        ("4844", .visaElectron),
        ("4913", .visaElectron),
        ("4917", .visaElectron),
        ("5555555555554444", .mastercard),
        ("51", .mastercard),
        ("55", .mastercard),
        ("222100", .mastercard),
        ("23", .mastercard),
        ("26", .mastercard),
        ("271999", .mastercard),
        ("272099", .mastercard),
        ("50", .maestro),
        ("56", .maestro),
        ("59", .maestro),
        ("600", .maestro),
        ("60115", .maestro),
        ("61", .maestro),
        ("622125", .maestro),
        ("63", .maestro),
        ("643", .maestro),
        ("6759", .maestro),
    ]

    static let refused: [(prefix: String, name: String)] = [
        ("60110", "Discover"),
        ("644", "Discover"),
        ("65", "Discover"),
        ("622126", "UnionPay"),
        ("3528", "JCB"),
        ("2200", "Mir"),
        ("222099", "below the Mastercard range"),
        ("2721", "above the Mastercard range"),
        ("1", "UATP"),
        ("9792", "Troy"),
    ]

    /// Sixteen digits of an accepted brand that fail the Luhn check.
    private static let failsLuhn = "4532015112830365"

    private func data(card: String) -> GopayCardFormData {
        GopayCardFormData(cardNumber: card, expirationMonth: "12", expirationYear: "99", cvv: "123")
    }

    @Test func aNumberOfAnAcceptedBrandIsThatBrandAndPassesTheForm() {
        for (prefix, brand) in Self.accepted {
            let digits = Self.number(prefix)
            #expect(CardBrand.of(digits) == brand, "\(prefix)")
            #expect(data(card: digits).isCardNumberValid, "\(prefix)")
            #expect(data(card: digits).isValid, "\(prefix)")
            #expect(GopayCardFormData.completesCardNumber(digits), "\(prefix)")
        }
    }

    @Test func visaElectronIsTriedBeforeVisa() {
        #expect(Array(CardBrand.allCases.prefix(2)) == [.visaElectron, .visa])
        #expect(CardBrand.visa.matches(Self.number("4026")))
    }

    @Test func aNumberOfAnyOtherBrandHasNoBrandAndFailsLikeANumberThatFailsTheLuhnCheck() {
        #expect(!data(card: Self.failsLuhn).isCardNumberValid)

        for (prefix, name) in Self.refused {
            let digits = Self.number(prefix)
            #expect(GopayCardFormData.passesLuhn(digits), "\(name)")
            #expect(CardBrand.of(digits) == nil, "\(name)")
            #expect(!data(card: digits).isCardNumberValid, "\(name)")
            #expect(!data(card: digits).isValid, "\(name)")
        }
    }

    /// The pattern's digits are ASCII: a digit of another script starts no brand.
    @Test func aDigitOfAnotherScriptStartsNoBrand() {
        #expect(CardBrand.of("٤444444444444448") == nil)
    }

    /// A card number is made of `0` to `9`. Digits of another script are numbers to
    /// `Character.isNumber` and to the Luhn check, so behind an ASCII first digit they would pass
    /// the brand's pattern too, and the JWE would carry a number the gateway cannot read.
    @Test(arguments: [
        "4٤٤٤٤٤٤٤٤٤٤٤٤٤٤٨",   // an ASCII 4, then Arabic-Indic digits
        "4444444444444４４８", // full-width digits at the end
        "44444444４４444448",
    ])
    func aCardNumberWithDigitsOfAnotherScriptIsNotValid(card: String) {
        let digits = card.filter(\.isNumber)
        #expect(digits.count == 16)
        #expect(GopayCardFormData.passesLuhn(digits), "a number to the Luhn check")
        #expect(CardBrand.of(digits) == .visa, "and to the brand's pattern, by its first digit")
        #expect(!GopayCardFormData.completesCardNumber(digits))
        #expect(!data(card: card).isCardNumberValid)
        #expect(!data(card: card).isValid)
        #expect(data(card: card).isCardNumberTypedOut, "sixteen digits, so the form shows its error")
    }

    @Test func theFocusStaysInTheCardNumberWhenItsBrandIsNotAccepted() {
        // The form moves the focus to the expiration on completesCardNumber alone.
        for (prefix, name) in Self.refused {
            #expect(!GopayCardFormData.completesCardNumber(Self.number(prefix)), "\(name)")
        }
        #expect(!GopayCardFormData.completesCardNumber("4444"), "still being typed")
        #expect(!GopayCardFormData.completesCardNumber(Self.failsLuhn), "fails the Luhn check")
    }

    @Test func theFormShowsTheMessageOfAnInvalidNumberForABrandItDoesNotAccept() {
        let strings = GopayLocales.cs
        func error(_ digits: String, _ mode: GopayCardFormErrors.Mode) -> String? {
            GopayCardFormErrors(
                data: GopayCardFormData(cardNumber: digits, expirationMonth: "12", expirationYear: "30", cvv: "123"),
                strings: strings,
                mode: mode,
                cardNumberEdited: true, expirationEdited: true, cvvEdited: true,
                cardNumberWasLeft: false, expirationWasLeft: false, cvvWasLeft: false
            ).cardNumber
        }

        for (prefix, name) in Self.refused {
            let digits = Self.number(prefix)
            // At the same moment as a Luhn failure: once the number is whole in `.live`, on the
            // submit otherwise.
            #expect(error(digits, .live(submitAttempted: false)) == strings.panErrorPattern, "\(name)")
            #expect(error(digits, .onSubmit(attempted: true)) == strings.panErrorPattern, "\(name)")
            #expect(error(digits, .onSubmit(attempted: false)) == nil, "\(name)")
        }
        #expect(error(Self.failsLuhn, .live(submitAttempted: false)) == strings.panErrorPattern)
    }

    /// The operational data sees the field as it sees a mistyped number: started, not complete.
    @Test func theCardFormStepsSeeAnUnsupportedBrandAsANumberNotFinished() {
        #expect(data(card: Self.number("60110")).progressStates.pan == .partial)
        #expect(data(card: Self.failsLuhn).progressStates.pan == .partial)
        #expect(data(card: Self.number("4")).progressStates.pan == .complete)
    }

    @Test func theSubmitOfABrandTheFormDoesNotAcceptIsValidation007AndKeepsTheCard() async {
        // A gateway nothing may reach.
        let gateway = ScriptedGateway { _ in (500, "") }
        let sdk = GopaySDK(
            config: GopayConfig(environment: .development(baseUrl: gateway.baseUrl), clientId: "c", shareableKey: "k"),
            networkClient: gateway
        )

        for (prefix, name) in Self.refused {
            sdk.updateCardFormData(data(card: Self.number(prefix)), formId: "brands-test")

            await #expect("\(name)") {
                try await sdk.submitCardForm(formId: "brands-test")
            } throws: { error in
                guard let error = error as? GopaySDKError else { return false }
                return error.code == .validationInvalidInput
                    && error.code.rawValue == "VALIDATION_007"
                    && error.message == GopaySDKErrors.invalidCardFormData
            }

            #expect(sdk.internalCardFormData["brands-test"]?.cardNumber == Self.number(prefix), "\(name)")
        }
        #expect(gateway.requests.isEmpty, "nothing is fetched or encrypted for a refused card")
    }
}
