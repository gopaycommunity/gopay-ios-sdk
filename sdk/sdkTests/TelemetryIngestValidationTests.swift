//
//  TelemetryIngestValidationTests.swift
//  sdkTests
//
//  Sends one event of every kind the SDK produces to a real ingest running in debug mode, which
//  answers an event its schema refuses with 400 and the reasons, and expects 204 for each. The
//  sandbox and production ingests answer 204 to anything, so they cannot be used for this.
//
//  Off unless the debug ingest's `/events` URL is given, e.g.
//  `TEST_RUNNER_GOPAY_TELEMETRY_VALIDATION_URL=https://…/events xcodebuild test …`.
//

import Testing
import Foundation
@testable import sdk

private let validationURL = ProcessInfo.processInfo.environment["GOPAY_TELEMETRY_VALIDATION_URL"].flatMap(URL.init(string:))

/// What the ingest answered, in arrival order.
private final class Answers: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [(status: Int?, body: String)] = []

    func append(_ status: Int?, _ data: Data?) {
        lock.lock()
        answers.append((status, data.flatMap { String(data: $0, encoding: .utf8) } ?? ""))
        lock.unlock()
    }

    var all: [(status: Int?, body: String)] {
        lock.lock(); defer { lock.unlock() }
        return answers
    }
}

@Suite(.enabled(if: validationURL != nil, "needs GOPAY_TELEMETRY_VALIDATION_URL"))
struct TelemetryIngestValidationTests {

    @Test func theIngestAcceptsEveryEventTheSdkSends() async throws {
        let answers = Answers()
        let telemetry = Telemetry(
            endpoint: try #require(validationURL),
            clientId: "ios-sdk-validation",
            origin: "cz.gopay.sdk.validation",
            onResponse: { answers.append($0, $1) }
        )
        let paymentId = "3273103424"
        let owner = NSObject()
        let charge = try JSONSerialization.data(withJSONObject: [
            "payment_instrument": [
                "payment_instrument": "PAYMENT_CARD",
                "input": ["input_type": "ENCRYPTED_CARD", "encrypted_card": "eyJhbGciOiJSU0EtT0FFUC0yNTYifQ.a.b.c.d"],
                "browser_data": ["ip": "192.0.2.1", "language": "cs-CZ", "javascript_enabled": true],
            ],
        ])
        let chargeResponse = try JSONSerialization.data(withJSONObject: [
            "id": "1", "state": "ACTION_REQUIRED", "action": ["redirect_url": "https://acs.test/c?creq=x"],
        ])

        telemetry.initialized()
        telemetry.apiCall(
            Telemetry.ApiCallRecord(
                method: "POST", path: "/oauth2/token", statusCode: 200, startedAt: Telemetry.now(),
                requestBody: .init(data: Data("grant_type=payment_credentials&scope=payment%3Acharge".utf8), contentType: "application/x-www-form-urlencoded"),
                responseBody: nil
            ),
            paymentId: paymentId
        )
        telemetry.sessionStarted(paymentId: paymentId)
        telemetry.cardFormReady(owner: owner)
        telemetry.cardFormSubmitted(owner: owner)
        telemetry.apiCall(
            Telemetry.ApiCallRecord(
                method: "POST", path: "/payments/\(paymentId)/charge", statusCode: 200, startedAt: Telemetry.now(),
                requestBody: .init(data: charge, contentType: "application/json"),
                responseBody: .init(data: chargeResponse, contentType: "application/json")
            ),
            paymentId: paymentId
        )
        telemetry.apiCall(
            Telemetry.ApiCallRecord(
                method: "GET", path: "/payments/\(paymentId)/charge", statusCode: 503, startedAt: Telemetry.now(),
                requestBody: nil,
                responseBody: .init(data: Data(#"{"error":"SERVICE_UNAVAILABLE"}"#.utf8), contentType: "application/json")
            ),
            paymentId: paymentId
        )
        telemetry.apiCall(
            Telemetry.ApiCallRecord(
                method: "GET", path: "/payments/\(paymentId)", statusCode: nil, startedAt: Telemetry.now(),
                requestBody: nil,
                responseBody: nil
            ),
            paymentId: paymentId
        )
        telemetry.verificationOpened(redirectURL: URL(string: "https://acs.test/challenge?creq=x")!, paymentId: paymentId)
        telemetry.cardFormUnmounted(owner: owner)
        telemetry.walletAvailability(caller: "chargeWithApplePay", available: true, startedAt: Telemetry.now(), paymentId: paymentId)
        telemetry.walletAvailability(caller: "isWalletAvailable", available: false, startedAt: Telemetry.now())
        telemetry.walletStep(.begin, status: .start, paymentId: paymentId)
        telemetry.walletSubmitted(paymentId: paymentId)
        telemetry.walletStep(.checkout, status: .start, paymentId: paymentId)
        telemetry.walletStep(.paymentAuthorized, status: .success, paymentId: paymentId, startedAt: Telemetry.now())
        telemetry.walletStep(.checkout, status: .failure, paymentId: paymentId, detail: "NETWORK_003", startedAt: Telemetry.now())
        telemetry.walletStep(.completePayment, status: .success, paymentId: paymentId, params: ["result": .string("failure")])
        telemetry.walletStep(.cancel, status: .info, paymentId: paymentId, startedAt: Telemetry.now())
        telemetry.error(GopaySDKError.transport(URLError(.notConnectedToInternet)), paymentId: paymentId)
        telemetry.error(GopaySDKError(.validationInvalidInput, message: "paymentId must not be empty"), paymentId: nil)
        telemetry.sessionClosed(paymentId: paymentId)
        let expected = 22

        for _ in 0..<300 where answers.all.count < expected {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let all = answers.all
        #expect(all.count == expected, "the ingest answered \(all.count) of \(expected); without a response check the network")
        for (index, answer) in all.enumerated() {
            #expect(answer.status == 204, "event \(index + 1): HTTP \(answer.status.map(String.init) ?? "none") \(answer.body)")
        }
    }
}
