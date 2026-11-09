//
//  ChargeMayExistTests.swift
//  exampleTests
//
//  After a charge call fails, the demo reads the payment instead of offering a new one whenever a
//  charge may still be on it (GPMOB-198): the gateway has one already, it answered with a 5xx, or
//  no answer arrived at all. Anything else is a failure the user may retry. The Android demo has
//  the same rule.
//

import Testing
@testable import example
@testable import GopaySDK

struct ChargeMayExistTests {

    private func error(_ code: GopaySDKError.Code, status: Int? = nil) -> GopaySDKError {
        GopaySDKError(code, message: code.rawValue, httpStatus: status)
    }

    @Test func aChargeTheGatewayAlreadyHasMayExist() {
        #expect(error(.paymentChargeAlreadyExists, status: 409).chargeMayExist)
    }

    @Test func a5xxMayHaveLeftACharge() {
        #expect(error(.networkServerError, status: 503).chargeMayExist)
    }

    @Test(arguments: [GopaySDKError.Code.networkTimeout, .networkNoConnection, .networkSSLError, .networkIOError])
    func aTransportFailureWithoutAnAnswerMayHaveLeftACharge(code: GopaySDKError.Code) {
        #expect(error(code).chargeMayExist)
        #expect(!error(code, status: 200).chargeMayExist, "with an HTTP status the gateway answered")
    }

    @Test(arguments: [
        (GopaySDKError.Code.networkClientError, 400 as Int?),
        (.paymentNotFound, 404),
        (.authPaymentSessionClosed, nil),
        (.validationInvalidInput, nil),
        (.paymentCancelled, nil)
    ])
    func aRefusedChargeOrAMissingPaymentLeavesNoCharge(code: GopaySDKError.Code, status: Int?) {
        #expect(!error(code, status: status).chargeMayExist)
    }
}
