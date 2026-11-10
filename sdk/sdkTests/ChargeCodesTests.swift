//
//  ChargeCodesTests.swift
//  sdkTests
//
//  Pins the two codes of their own the SDK gives the gateway's answers on a payment (GPMOB-198):
//  PAYMENT_012 for an HTTP 404 on a charge, the charge state and the payment status, PAYMENT_013
//  for an HTTP 409 on a charge. Every other status, and a 404 or 409 on any other call, keeps its
//  NETWORK_* code. The Android SDK pins the same table.
//

import Testing
import Foundation
@testable import sdk

/// One call, the endpoint the gateway fails, its status and the code the call must throw.
struct GatewayStatusCase: CustomTestStringConvertible, Sendable {
    let name: String
    let failingPath: String
    let status: Int
    let code: GopaySDKError.Code
    let call: @Sendable (PaymentSession) async throws -> Void

    var testDescription: String { "\(name) HTTP \(status) → \(code.rawValue)" }
}

/// Browser data with the gateway's fields filled in, so a charge goes out without the fetch.
private let filledBrowserData = BrowserData(
    language: "cs-CZ", timezone: -60, screenWidth: 1170, screenHeight: 2532, colorDepth: 24,
    userAgent: "ua", acceptHeader: "{}", javascriptEnabled: true, ip: "192.0.2.42"
)

/// Browser data without them, so a charge fetches them first.
private let deviceBrowserData = BrowserData(
    language: "cs-CZ", timezone: -60, screenWidth: 1170, screenHeight: 2532, colorDepth: 24, userAgent: "ua"
)

private let gatewayStatusCases: [GatewayStatusCase] = [
    GatewayStatusCase(name: "charge", failingPath: "/payments/p1/charge", status: 404, code: .paymentNotFound) {
        _ = try await $0.charge(.encryptedCard("jwe", browserData: filledBrowserData))
    },
    GatewayStatusCase(name: "charge", failingPath: "/payments/p1/charge", status: 409, code: .paymentChargeAlreadyExists) {
        _ = try await $0.charge(.encryptedCard("jwe", browserData: filledBrowserData))
    },
    GatewayStatusCase(name: "chargeWithEncryptedCard", failingPath: "/payments/p1/charge", status: 409, code: .paymentChargeAlreadyExists) {
        _ = try await $0.chargeWithEncryptedCard("jwe", browserData: filledBrowserData)
    },
    GatewayStatusCase(name: "chargeWithEncryptedCard", failingPath: "/payments/p1/charge", status: 404, code: .paymentNotFound) {
        _ = try await $0.chargeWithEncryptedCard("jwe", browserData: filledBrowserData)
    },
    GatewayStatusCase(name: "chargeWithCardToken", failingPath: "/payments/p1/charge", status: 409, code: .paymentChargeAlreadyExists) {
        _ = try await $0.chargeWithCardToken("token", browserData: filledBrowserData)
    },
    GatewayStatusCase(name: "chargeWithCardToken", failingPath: "/payments/p1/charge", status: 404, code: .paymentNotFound) {
        _ = try await $0.chargeWithCardToken("token", browserData: filledBrowserData)
    },
    GatewayStatusCase(name: "charge", failingPath: "/payments/p1/charge", status: 400, code: .networkClientError) {
        _ = try await $0.charge(.encryptedCard("jwe", browserData: filledBrowserData))
    },
    GatewayStatusCase(name: "charge", failingPath: "/payments/p1/charge", status: 500, code: .networkServerError) {
        _ = try await $0.charge(.encryptedCard("jwe", browserData: filledBrowserData))
    },
    GatewayStatusCase(name: "getChargeState", failingPath: "/payments/p1/charge", status: 404, code: .paymentNotFound) {
        _ = try await $0.getChargeState()
    },
    // The gateway never answers the read with a 409; if it did, it would be no charge conflict.
    GatewayStatusCase(name: "getChargeState", failingPath: "/payments/p1/charge", status: 409, code: .networkClientError) {
        _ = try await $0.getChargeState()
    },
    GatewayStatusCase(name: "getStatus", failingPath: "/payments/p1", status: 404, code: .paymentNotFound) {
        _ = try await $0.getStatus()
    },
    GatewayStatusCase(name: "getStatus", failingPath: "/payments/p1", status: 403, code: .networkClientError) {
        _ = try await $0.getStatus()
    },
    // Not calls on the payment itself: their 404 stays NETWORK_002.
    GatewayStatusCase(name: "getQrPaymentInfo", failingPath: "qr-payment/info", status: 404, code: .networkClientError) {
        _ = try await $0.getQrPaymentInfo()
    },
    GatewayStatusCase(name: "getApplePayInfo", failingPath: "apple-pay/app-info", status: 404, code: .networkClientError) {
        _ = try await $0.getWalletInfo()
    },
    GatewayStatusCase(name: "completeBrowserData", failingPath: "cards/browser-data", status: 404, code: .networkClientError) {
        _ = try await $0.completeBrowserData(deviceBrowserData)
    },
    // The browser data a charge fetches first: the charge is never sent, and the code is the fetch's.
    GatewayStatusCase(name: "charge, browser data", failingPath: "cards/browser-data", status: 404, code: .networkClientError) {
        _ = try await $0.charge(.encryptedCard("jwe", browserData: deviceBrowserData))
    },
]

/// The gateway's error body on the failing endpoint; everything else answers as it should.
private func serveGatewayStatus(_ status: Int, on failingPath: String) {
    StubURLProtocol.reset { req in
        let path = req.url?.path ?? ""
        if path.hasSuffix("oauth2/token") { return tokenResponse() }
        if path.hasSuffix(failingPath) {
            return (status, json(["error": "GATEWAY_ERROR", "message": "Answer \(status)"]))
        }
        if path.hasSuffix("cards/browser-data") {
            return (200, json(["ip": "192.0.2.42", "user_agent": "ua", "accept_header": "{}"]))
        }
        if path.hasSuffix("/charge") { return (200, json(["id": "ch_1", "state": "REQUESTED"])) }
        return (500, Data())
    }
}

// Part of the serialized `SessionNetworkTests`: every test here shares the one stub.
extension SessionNetworkTests {

    @Test(arguments: gatewayStatusCases)
    func aGatewayStatusOnAPaymentCallHasItsOwnCode(_ testCase: GatewayStatusCase) async throws {
        serveGatewayStatus(testCase.status, on: testCase.failingPath)
        let session = try await makeSession()

        do {
            try await testCase.call(session)
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == testCase.code)
            #expect(error.httpStatus == testCase.status)
            #expect(error.gatewayError?.message == "Answer \(testCase.status)")
            #expect(error.message.contains("HTTP \(testCase.status): Answer \(testCase.status)"))
        }
        if testCase.failingPath == "cards/browser-data" {
            #expect(StubURLProtocol.requestCount(forPathSuffix: "/charge") == 0)
        } else {
            #expect(StubURLProtocol.requestCount(forPathSuffix: testCase.failingPath) == 1, "no retry")
        }
    }

    /// The new codes reach `errorCallback` once each, like the `NETWORK_002` they replace.
    @Test(arguments: [(404, GopaySDKError.Code.paymentNotFound), (409, .paymentChargeAlreadyExists)])
    func aChargeConflictOrMissingPaymentIsReportedOnce(status: Int, code: GopaySDKError.Code) async throws {
        serveGatewayStatus(status, on: "/payments/p1/charge")
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        await #expect(throws: GopaySDKError.self) {
            try await session.chargeWithEncryptedCard("jwe", browserData: filledBrowserData)
        }

        #expect(reported.codes == [code])
    }
}
