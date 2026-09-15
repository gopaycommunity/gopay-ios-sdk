//
//  ChargeResponseDecodingTests.swift
//  sdkTests
//
//  Pins the decoding of the charge response, in particular the tolerance for the `return_url`
//  the gateway omits from the charge block nested in `GET /payments/{id}`.
//
//  The encoding side of these models lives in `ChargeModelsTests` in sdkTests.swift.
//

import Testing
import Foundation
@testable import sdk

// Serialized because the warning tests swap the shared hook while they decode.
@Suite(.serialized)
struct ChargeResponseDecodingTests {

    /// The shape the gateway actually returns inside `Payment-Details.charge`: no `return_url`,
    /// even though its own spec marks the field required. Decoding has to survive it, because
    /// failing here would take the payment state down with it.
    @Test func decode_chargeWithoutReturnUrlKeepsTheStateAndNilsTheField() throws {
        let json = """
        { "id": "51", "state": "ACTION_REQUIRED", "href": "https://gate.gopay.com/api/payments/1/charge" }
        """

        let charge = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))

        #expect(charge.id == "51")
        #expect(charge.state == .actionRequired)
        #expect(charge.returnUrl == nil)
        #expect(charge.action == nil)
        #expect(charge.paymentInstrument == nil)
        #expect(charge.failReason == nil)
    }

    /// A `return_url` that is present still decodes verbatim, so the fallback cannot mask it.
    @Test func decode_chargeWithReturnUrlKeepsIt() throws {
        let json = """
        {
          "id": "51",
          "state": "SUCCEEDED",
          "return_url": "gopaysdk://charge-return",
          "action": { "action_type": "EMV3DS", "state": "CHALLENGE_REQUIRED", "redirect_url": "https://3ds.example/step" }
        }
        """

        let charge = try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))

        #expect(charge.returnUrl == "gopaysdk://charge-return")
        #expect(charge.state == .succeeded)
        #expect(charge.action?.redirectUrl == "https://3ds.example/step")
    }

    /// The substitution is worth telling the integrator about, so the charge endpoints report it.
    @Test func decode_missingReturnUrlIsReportedOnAChargeResponse() throws {
        let json = #"{ "id": "51", "state": "ACTION_REQUIRED" }"#

        let reported = withCapturedWarnings {
            _ = try? JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))
        }

        #expect(reported.count == 1)
        #expect(reported.first?.contains("return_url") == true)
        #expect(reported.first?.contains("51") == true)
    }

    /// An empty string is the one value the field must never carry: `url.hasPrefix("")` is true
    /// for every URL. It decodes as `nil` like an omission and is reported as its own case.
    @Test func decode_blankReturnUrlDecodesAsNilAndIsReported() throws {
        for blank in ["", "   ", "\\n"] {
            let json = #"{ "id": "51", "state": "ACTION_REQUIRED", "return_url": "\#(blank)" }"#

            var charge: ChargePaymentResponse?
            let reported = withCapturedWarnings {
                charge = try? JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))
            }

            #expect(charge?.state == .actionRequired)
            #expect(charge?.returnUrl == nil)
            #expect(reported.count == 1)
            #expect(reported.first?.contains("blank return_url") == true)
        }
    }

    /// The charge block nested in `GET /payments/{id}` never carries the field, so warning there
    /// would fire on every status read and drown out the case worth seeing.
    @Test func decode_missingReturnUrlIsSilentInsideAPaymentDetails() throws {
        let json = """
        {
          "id": "9295213404",
          "state": "PAID",
          "amount": 1000,
          "currency": "CZK",
          "charge": { "id": "51", "state": "SUCCEEDED", "href": "https://gate.gopay.com/x" }
        }
        """

        var details: PaymentDetails?
        let reported = withCapturedWarnings {
            details = try? JSONDecoder().decode(PaymentDetails.self, from: Data(json.utf8))
        }

        #expect(details?.charge?.returnUrl == nil)
        #expect(details?.charge?.state == .succeeded)
        #expect(reported.isEmpty)
    }

    /// A present value reports nothing, so the hook cannot become background noise.
    @Test func decode_presentReturnUrlReportsNothing() throws {
        let json = #"{ "id": "51", "state": "SUCCEEDED", "return_url": "gopaysdk://charge-return" }"#

        let reported = withCapturedWarnings {
            _ = try? JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))
        }

        #expect(reported.isEmpty)
    }

    /// Swaps the decoder's warning hook for the duration of `work` and returns what it collected.
    private func withCapturedWarnings(_ work: () -> Void) -> [String] {
        let original = ChargePaymentResponse.reportMissingField
        defer { ChargePaymentResponse.reportMissingField = original }

        var collected: [String] = []
        ChargePaymentResponse.reportMissingField = { collected.append($0) }
        work()
        return collected
    }

    /// The fields the spec really does require stay required: a charge without `state` is still
    /// a decoding failure rather than a silently half-built value.
    @Test func decode_chargeWithoutStateStillFails() {
        let json = #"{ "id": "51" }"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChargePaymentResponse.self, from: Data(json.utf8))
        }
    }
}
