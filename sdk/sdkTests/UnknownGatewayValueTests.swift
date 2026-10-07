//
//  UnknownGatewayValueTests.swift
//  sdkTests
//
//  Pins the tolerance for enum values the gateway adds after the SDK shipped: each response enum
//  decodes such a value as `unknown`, the rest of the response stays readable, and the original
//  value is reported for the debug log.
//

import Testing
import Foundation
@testable import sdk

// Serialized because the tests swap the shared hook while they decode.
@Suite(.serialized)
struct UnknownGatewayValueTests {

    /// Decodes `json` while collecting what the decoder reports as unknown.
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> (T, [String]) {
        var reports: [String] = []
        let original = UnknownGatewayValue.report
        UnknownGatewayValue.report = { reports.append($0) }
        defer { UnknownGatewayValue.report = original }
        let value = try JSONDecoder().decode(type, from: Data(json.utf8))
        return (value, reports)
    }

    @Test func aNewChargeStateKeepsTheRestOfTheCharge() throws {
        let (charge, reports) = try decode(ChargePaymentResponse.self, """
        { "id": "51", "state": "PARTIALLY_SETTLED", "return_url": "https://shop.example/back",
          "fail_reason": null }
        """)

        #expect(charge.state == .unknown)
        #expect(charge.id == "51")
        #expect(charge.returnUrl == "https://shop.example/back")
        #expect(reports.count == 1)
        #expect(reports.first?.contains("ChargeState") == true)
        #expect(reports.first == "Unknown ChargeState value \"PARTIALLY_SETTLED\" at $.state from the gateway, read as UNKNOWN; a newer SDK may know it")
    }

    @Test func aNewActionTypeAnd3dsStateKeepTheRedirect() throws {
        let (charge, reports) = try decode(ChargePaymentResponse.self, """
        { "id": "52", "state": "ACTION_REQUIRED", "return_url": "https://shop.example/back",
          "action": { "action_type": "SCA_APP", "state": "DECOUPLED",
                      "redirect_url": "https://3ds.example/step" } }
        """)

        #expect(charge.state == .actionRequired)
        #expect(charge.action?.actionType == .unknown)
        #expect(charge.action?.state == .unknown)
        #expect(charge.action?.redirectUrl == "https://3ds.example/step")
        #expect(reports.count == 2)
        #expect(reports.contains { $0.contains("ChargeActionType") && $0.contains("\"SCA_APP\"") })
        #expect(reports.contains { $0.contains("Emv3dsState") && $0.contains("\"DECOUPLED\" at $.action.state") })
    }

    @Test func aNewCardSchemeKeepsTheCardDetails() throws {
        let (charge, reports) = try decode(ChargePaymentResponse.self, """
        { "id": "53", "state": "SUCCEEDED", "return_url": "https://shop.example/back",
          "payment_instrument": { "payment_instrument": "PAYMENT_CARD",
            "details": { "input_type": "ENCRYPTED_CARD", "masked_pan": "675964******1234",
                         "scheme": "MAESTRO" } } }
        """)

        #expect(charge.state == .succeeded)
        #expect(charge.paymentInstrument?.details.scheme == .unknown)
        #expect(charge.paymentInstrument?.details.maskedPan == "675964******1234")
        #expect(reports.count == 1)
        #expect(reports.first?.contains("\"MAESTRO\"") == true)
    }

    @Test func aNewPaymentStateAndCurrencyKeepThePayment() throws {
        let (payment, reports) = try decode(PaymentDetails.self, """
        { "id": "p1", "state": "ON_HOLD", "amount": 1000, "currency": "CHF",
          "charge": { "id": "54", "state": "SUCCEEDED" } }
        """)

        #expect(payment.state == .unknown)
        #expect(payment.currency == .unknown)
        #expect(payment.amount == 1000)
        #expect(payment.charge?.state == .succeeded)
        #expect(reports.count == 2)
        #expect(reports.contains { $0.contains("PaymentState") && $0.contains("\"ON_HOLD\"") })
        #expect(reports.contains { $0.contains("Currency") && $0.contains("\"CHF\"") })
    }

    @Test func aNewCurrencyKeepsTheQrPayment() throws {
        let (qr, reports) = try decode(QrPaymentDetails.self, """
        { "amount": 500, "currency": "SEK", "qr_code": { "spayd": "SPD*1.0" } }
        """)

        #expect(qr.currency == .unknown)
        #expect(qr.qrCode?.spayd == "SPD*1.0")
        #expect(reports.count == 1)
    }

    /// Every value the SDK knows still decodes as itself, without a report.
    @Test func knownValuesDecodeAsThemselvesAndReportNothing() throws {
        let (charge, chargeReports) = try decode(ChargePaymentResponse.self, """
        { "id": "55", "state": "PROCESSING", "return_url": "https://shop.example/back",
          "action": { "action_type": "EMV3DS", "state": "CHALLENGE_REQUIRED" },
          "payment_instrument": { "payment_instrument": "PAYMENT_CARD",
            "details": { "input_type": "CARD_TOKEN", "scheme": "VISA" } } }
        """)
        let (payment, paymentReports) = try decode(PaymentDetails.self, """
        { "id": "p1", "state": "PAID", "amount": 1, "currency": "EUR" }
        """)

        #expect(charge.state == .processing)
        #expect(charge.action?.actionType == .emv3ds)
        #expect(charge.action?.state == .challengeRequired)
        #expect(charge.paymentInstrument?.details.scheme == .visa)
        #expect(payment.state == .paid)
        #expect(payment.currency == .eur)
        #expect(chargeReports.isEmpty)
        #expect(paymentReports.isEmpty)
    }

    /// A value that is not a string at all is still a broken response.
    @Test func aValueOfTheWrongTypeStillFailsTheDecode() {
        #expect(throws: DecodingError.self) {
            _ = try decode(ChargePaymentResponse.self, """
            { "id": "56", "state": 3, "return_url": "https://shop.example/back" }
            """)
        }
    }
}
