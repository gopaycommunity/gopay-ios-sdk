//
//  CheckoutViewModelTests.swift
//  exampleTests
//
//  A second tap queues its own task before the disabled button renders, so the busy check inside
//  the view model is what keeps one payment from going out twice.
//

import Foundation
import Testing
@testable import example
@testable import GopaySDK

@MainActor
struct CheckoutViewModelTests {

    /// Stands in for the gateway in memory: answers the session's token request and counts
    /// every other request, which it refuses. Nothing leaves the process.
    final class RecordingClient: AsyncHTTPClient, @unchecked Sendable {
        let baseUrl = "https://gateway.invalid/"
        private(set) var paymentRequests = 0

        func makeURL(path: String) -> URL? { URL(string: baseUrl + path) }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            guard request.url?.path.hasSuffix("/oauth2/token") == true else {
                // A stopper, not a faithful gateway answer: the SDK would wrap a transport error
                // in a GopaySDKError, but these tests only count that the request was attempted.
                paymentRequests += 1
                throw URLError(.notConnectedToInternet)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = try JSONSerialization.data(withJSONObject: [
                "access_token": Self.token(expiringIn: 3600), "token_type": "bearer", "expires_in": 3600
            ])
            return (body, response)
        }

        private static func token(expiringIn seconds: TimeInterval) -> String {
            let payload = try! JSONSerialization.data(withJSONObject: ["exp": Date().timeIntervalSince1970 + seconds])
            let encoded = payload.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return "eyJhbGciOiJub25lIn0.\(encoded).signature"
        }
    }

    /// While a payment is running, a second `pay()` leaves it alone: no new payment on the
    /// backend, no card submitted, the banner as it was, and the busy state still held.
    @Test func payWhileBusyReturnsAtOnce() async {
        let model = CheckoutViewModel()
        model.busyLabel = "Authorizing…"
        model.banner = "Payment cancelled. Pick a method and try again."

        await model.pay()

        #expect(model.busyLabel == "Authorizing…")
        #expect(model.banner == "Payment cancelled. Pick a method and try again.")
        #expect(model.paymentId == nil)
        #expect(model.session == nil)
        #expect(model.outcome == nil)
        #expect(model.qrDetails == nil)
    }

    /// A banner belongs to the method it was raised for: picking another method takes it down,
    /// picking the same one again does not.
    @Test func pickingAnotherMethodClearsTheBanner() {
        let model = CheckoutViewModel()
        model.selectedMethod = .applePay
        model.banner = "Payment cancelled. Pick a method and try again."

        model.selectedMethod = .applePay
        #expect(model.banner == "Payment cancelled. Pick a method and try again.")

        model.selectedMethod = .card
        #expect(model.banner == nil)
    }

    /// A charge whose state could not be read is not headed as one the bank has not confirmed:
    /// the bank was not asked. A pending charge without a message keeps "Payment pending".
    @Test func unreadStateHasItsOwnHeading() {
        let unread = CheckoutViewModel.Outcome(
            state: .unknown, response: nil, message: "Couldn't check the payment: [NETWORK_004] offline"
        )
        #expect(unread.isUnread)
        #expect(unread.resultTitle == "Couldn't check the payment")
        #expect(unread.resultSubtitle.hasPrefix("The payment was sent, but we couldn't read its state"))

        let pending = CheckoutViewModel.Outcome(state: .processing, response: nil, message: nil)
        #expect(!pending.isUnread)
        #expect(pending.resultTitle == "Payment pending")

        let failed = CheckoutViewModel.Outcome(state: .failed, response: nil, message: "declined")
        #expect(!failed.isUnread)
        #expect(failed.resultTitle == "Payment failed")
    }

    /// The same for Refresh on the pending screen, with a session in place so it is the busy
    /// check that stops it, not the missing session.
    @Test func refreshWhileBusyReturnsAtOnce() async throws {
        let client = RecordingClient()
        let session = try await PaymentSession.create(
            paymentId: "p1",
            paymentSecret: "secret",
            scope: PaymentSession.defaultScope,
            authApi: AuthAPI(client: client),
            publicApi: PublicAPI(client: client, clientId: "client", shareableKey: "shareable"),
            client: client,
            callbacks: SessionCallbacks(onClose: { _ in })
        )
        let model = CheckoutViewModel()
        model.session = session
        model.busyLabel = "Authorizing…"
        model.banner = "Payment cancelled. Pick a method and try again."

        await model.refreshChargeState()

        #expect(model.busyLabel == "Authorizing…")
        #expect(model.banner == "Payment cancelled. Pick a method and try again.")
        #expect(model.outcome == nil)
        #expect(client.paymentRequests == 0)
    }
}
