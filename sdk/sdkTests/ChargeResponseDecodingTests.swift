//
//  ChargeResponseDecodingTests.swift
//  sdkTests
//
//  Pins the decoding of the charge response, in particular the tolerance for the `return_url`
//  GoPay is removing from the charge response and never sent in the charge block nested in
//  `GET /payments/{id}`.
//
//  The encoding side of these models lives in `ChargeModelsTests` in sdkTests.swift.
//

import Testing
import Foundation
@testable import sdk

struct ChargeResponseDecodingTests {

    /// No `return_url`, as a charge comes once GoPay has removed it and as `Payment-Details.charge`
    /// always came, even though the spec marks the field required. Decoding has to survive it, because
    /// failing here would take the payment state down with it.
    @Test func aChargeWithoutReturnUrlKeepsTheStateAndNilsTheField() throws {
        let json = """
        { "id": "51", "state": "ACTION_REQUIRED", "href": "https://gate.gopay.com/api/payments/1/charge" }
        """

        let charge = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))

        #expect(charge.id == "51")
        #expect(charge.state == .actionRequired)
        #expect(charge.gatewayReturnUrl == nil)
        #expect(charge.action == nil)
        #expect(charge.paymentInstrument == nil)
        #expect(charge.failReason == nil)
    }

    /// A `return_url` that is present still decodes, for a gateway that sends it.
    @Test func aChargeWithReturnUrlKeepsIt() throws {
        let json = """
        {
          "id": "51",
          "state": "SUCCEEDED",
          "return_url": "gopaysdk://charge-return",
          "action": { "action_type": "EMV3DS", "state": "CHALLENGE_REQUIRED", "redirect_url": "https://3ds.example/step" }
        }
        """

        let charge = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))

        #expect(charge.gatewayReturnUrl == "gopaysdk://charge-return")
        #expect(charge.state == .succeeded)
        #expect(charge.action?.redirectUrl == "https://3ds.example/step")
    }

    /// An empty string is the one value the field must never carry: `url.hasPrefix("")` is true
    /// for every URL. It decodes as `nil` like an omission.
    @Test(arguments: ["", "   ", "\\n"])
    func aBlankReturnUrlDecodesAsNil(blank: String) throws {
        let json = #"{ "id": "51", "state": "ACTION_REQUIRED", "return_url": "\#(blank)" }"#

        let charge = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))

        #expect(charge.state == .actionRequired)
        #expect(charge.gatewayReturnUrl == nil)
    }

    /// Whitespace around the address would end up percent-encoded in the URL and the challenge
    /// would never match it, so it is dropped while decoding.
    @Test func aReturnUrlDecodesWithoutSurroundingWhitespace() throws {
        let json = #"{ "id": "51", "state": "ACTION_REQUIRED", "return_url": " https://shop.example/r " }"#

        let charge = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))

        #expect(charge.gatewayReturnUrl == "https://shop.example/r")
    }

    /// The charge nested in `GET /payments/{id}` decodes the same way.
    @Test func aChargeInsideAPaymentDetailsDecodesWithoutReturnUrl() throws {
        let json = """
        {
          "id": "9295213404",
          "state": "PAID",
          "amount": 1000,
          "currency": "CZK",
          "charge": { "id": "51", "state": "SUCCEEDED", "href": "https://gate.gopay.com/x" }
        }
        """

        let details = try JSONDecoder().decode(PaymentDetails.self, from: Data(json.utf8))

        #expect(details.charge?.gatewayReturnUrl == nil)
        #expect(details.charge?.state == .succeeded)
    }

    /// The demo console prints responses through `Encodable`; the field goes back out as it came.
    @Test func aChargeEncodesItsReturnUrlOnlyWhenItHadOne() throws {
        let with = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(#"{ "id": "1", "state": "SUCCEEDED", "return_url": "https://shop.example/r" }"#.utf8))
        let without = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(#"{ "id": "2", "state": "SUCCEEDED" }"#.utf8))

        let encodedWith = try JSONSerialization.jsonObject(with: JSONEncoder().encode(with)) as? [String: Any]
        let encodedWithout = try JSONSerialization.jsonObject(with: JSONEncoder().encode(without)) as? [String: Any]

        #expect(encodedWith?["return_url"] as? String == "https://shop.example/r")
        #expect(encodedWithout?["return_url"] == nil)
        #expect(encodedWithout?["state"] as? String == "SUCCEEDED")
    }

    /// The fields the spec really does require stay required: a charge without `state` is still
    /// a decoding failure rather than a silently half-built value.
    @Test func aChargeWithoutStateStillFailsToDecode() {
        let json = #"{ "id": "51" }"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))
        }
    }
}
