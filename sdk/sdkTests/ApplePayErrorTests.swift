//
//  ApplePayErrorTests.swift
//  sdkTests
//
//  Pins the Apple Pay error contract: a wallet that cannot be used is PAYMENT_004, and a token
//  the SDK cannot read, or an empty one as the iOS Simulator returns, is PAYMENT_003.
//

import Testing
import Foundation
import PassKit
@testable import sdk

/// A token carrying the given payment data.
private final class StubToken: PKPaymentToken {
    private let data: Data
    init(paymentData: Data) {
        self.data = paymentData
        super.init()
    }
    override var paymentData: Data { data }
}

private final class StubPayment: PKPayment {
    private let stubToken: PKPaymentToken
    init(paymentData: Data) {
        self.stubToken = StubToken(paymentData: paymentData)
        super.init()
    }
    override var token: PKPaymentToken { stubToken }
}

/// The `apple-pay/app-info` body the gateway answers with, offering the given card networks.
func applePayAppInfoJSON(networks: [String] = ["visa"]) -> [String: Any] {
    [
        "merchantIdentifier": "merchant.test",
        "applePayPaymentRequest": [
            "merchantCapabilities": ["supports3DS"], "supportedNetworks": networks,
            "countryCode": "CZ", "currencyCode": "CZK", "paymentSummaryItems": []
        ]
    ]
}

/// ``applePayAppInfoJSON(networks:)`` decoded the way the SDK reads it.
func applePayAppInfo(networks: [String] = ["visa"]) throws -> GopayApplePayAppInfoResponse {
    try JSONDecoder().decode(GopayApplePayAppInfoResponse.self, from: json(applePayAppInfoJSON(networks: networks)))
}

/// Waits until everything already queued on the main queue has run.
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

@MainActor
struct ApplePayErrorTests {

    @Test func aPaymentWithoutAUsableNetworkIsUnavailable() throws {
        var results: [Result<ChargePaymentResponse, Error>] = []
        let coordinator = GopayApplePayCoordinator(
            appInfo: try applePayAppInfo(networks: ["unknownNetwork"]),
            charge: { _, _ in Issue.record("nothing should be charged") },
            completion: { results.append($0) }
        )

        coordinator.start()

        #expect(results.count == 1)
        guard case .failure(let error as GopaySDKError) = results.first else {
            Issue.record("expected a GopaySDKError, got \(results)")
            return
        }
        #expect(error.code == .paymentMethodUnavailable)
    }

    @Test(arguments: [Data(), Data("not json".utf8), Data(#"{"version":"EC_v1"}"#.utf8)])
    func aTokenWithoutUsableDataIsAProcessingFailure(paymentData: Data) throws {
        let info = try applePayAppInfo(networks: ["visa"])
        let coordinator = GopayApplePayCoordinator(
            appInfo: info,
            charge: { _, _ in Issue.record("an unusable token must not be charged") },
            completion: { _ in }
        )
        var sheetStatus: PKPaymentAuthorizationStatus?

        coordinator.paymentAuthorizationController(
            PKPaymentAuthorizationController(paymentRequest: GopayApplePayCoordinator.makePaymentRequest(from: info)),
            didAuthorizePayment: StubPayment(paymentData: paymentData),
            handler: { sheetStatus = $0.status }
        )

        #expect(sheetStatus == .failure)
        guard case .failure(let error as GopaySDKError) = coordinator.resultOnceTheSheetCloses() else {
            Issue.record("expected the token failure to be the result")
            return
        }
        #expect(error.code == .paymentProcessingFailed)
    }

    /// The Simulator case gets a message that says what to do about it.
    @Test func anEmptyTokenNamesTheSimulator() {
        do {
            _ = try GopayApplePayCoordinator.mapToken(StubToken(paymentData: Data()))
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .paymentProcessingFailed)
            #expect(error.message.contains("Simulator"))
        } catch {
            Issue.record("expected a GopaySDKError, got \(error)")
        }
    }

    @Test func aReadableTokenIsMapped() throws {
        let token = StubToken(paymentData: Data("""
        {"version":"EC_v1","data":"d","signature":"s",
         "header":{"ephemeralPublicKey":"epk","publicKeyHash":"pkh","transactionId":"tx"}}
        """.utf8))

        let fields = try GopayApplePayCoordinator.mapToken(token)

        #expect(fields.data == "d")
        #expect(fields.signature == "s")
        #expect(fields.version == "EC_v1")
        #expect(fields.header.transactionId == "tx")
    }
}
