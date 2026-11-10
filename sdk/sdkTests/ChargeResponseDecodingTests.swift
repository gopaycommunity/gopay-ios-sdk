//
//  ChargeResponseDecodingTests.swift
//  sdkTests
//
//  Pins the decoding of the charge response: the `return_url` GoPay is removing from it is not
//  read since 3.0, so a charge decodes the same with it, without it, or with a blank one.
//
//  The encoding side of these models lives in `ChargeModelsTests` in sdkTests.swift.
//

import Testing
import Foundation
@testable import sdk

struct ChargeResponseDecodingTests {

    /// No `return_url`, as a charge comes once GoPay has removed it and as `Payment-Details.charge`
    /// always came. Decoding has to survive it, because failing here would take the payment state
    /// down with it.
    @Test func aChargeWithoutReturnUrlDecodes() throws {
        let json = """
        { "id": "51", "state": "ACTION_REQUIRED", "href": "https://gate.gopay.com/api/payments/1/charge" }
        """

        let charge = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))

        #expect(charge.id == "51")
        #expect(charge.state == .actionRequired)
        #expect(charge.action == nil)
        #expect(charge.paymentInstrument == nil)
        #expect(charge.failReason == nil)
    }

    /// A `return_url` a gateway still sends is ignored, whatever it holds, and the rest decodes.
    @Test(arguments: ["gopaysdk://charge-return", "", "   ", " https://shop.example/r "])
    func aReturnUrlInTheChargeIsIgnored(value: String) throws {
        let json = """
        {
          "id": "51",
          "state": "SUCCEEDED",
          "return_url": "\(value)",
          "action": { "action_type": "EMV3DS", "state": "CHALLENGE_REQUIRED", "redirect_url": "https://3ds.example/step" }
        }
        """

        let charge = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))

        #expect(charge.state == .succeeded)
        #expect(charge.action?.redirectUrl == "https://3ds.example/step")
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

        #expect(details.charge?.state == .succeeded)
    }

    /// The demo console prints responses through `Encodable`; a `return_url` the gateway sent
    /// does not go back out, since the model no longer holds it.
    @Test func aChargeEncodesWithoutReturnUrl() throws {
        let charge = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(#"{ "id": "1", "state": "SUCCEEDED", "return_url": "https://shop.example/r" }"#.utf8))

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(charge)) as? [String: Any]

        #expect(encoded?["return_url"] == nil)
        #expect(encoded?["state"] as? String == "SUCCEEDED")
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
