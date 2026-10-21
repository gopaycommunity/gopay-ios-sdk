//
//  SharedApiTests.swift
//  sdkTests
//
//  Pins the API both SDKs share since 2.2 (GPMOB-160): the card charges as one call each with
//  the browser data optional, and the wallet under the shared names next to the platform ones.
//  An alias is one body and one delegating name, so each alias has one test that it does what
//  the platform name does, not a copy of that name's tests.
//

import Testing
import Foundation
@testable import sdk

extension SessionNetworkTests {

    private var ownBrowserData: BrowserData {
        BrowserData(
            language: "cs-CZ", timezone: -60, screenWidth: 1170, screenHeight: 2532, colorDepth: 24,
            userAgent: "ua-of-the-caller", javascriptEnabled: true
        )
    }

    private func sentCharge() throws -> (instrument: [String: Any], input: [String: Any], browser: [String: Any]) {
        let charge = try #require(StubURLProtocol.requests(forPathSuffix: "/charge").first)
        let instrument = try #require(charge.jsonBody?["payment_instrument"] as? [String: Any])
        let input = try #require(instrument["input"] as? [String: Any])
        let browser = try #require(instrument["browser_data"] as? [String: Any])
        return (instrument, input, browser)
    }

    // MARK: Card charges as one call

    @Test func chargeWithCardTokenSendsTheTokenAndTheCallersBrowserData() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()

        let response = try await session.chargeWithCardToken(
            "tok", browserData: ownBrowserData, challengePreference: .noChallengePreferred
        )

        #expect(response.id == "ch_1")
        let sent = try sentCharge()
        #expect(sent.input["input_type"] as? String == "CARD_TOKEN")
        #expect(sent.input["card_token"] as? String == "tok")
        #expect(sent.instrument["challenge_preference"] as? String == "NO_CHALLENGE_PREFERRED")
        #expect(sent.browser["user_agent"] as? String == "ua-of-the-caller")
        // Completed by the charge like any other request.
        #expect(sent.browser["ip"] as? String == "192.0.2.42")
    }

    @Test func chargeWithEncryptedCardSendsThePayload() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()

        _ = try await session.chargeWithEncryptedCard("jwe", browserData: ownBrowserData)

        let sent = try sentCharge()
        #expect(sent.input["input_type"] as? String == "ENCRYPTED_CARD")
        #expect(sent.input["payload"] as? String == "jwe")
        #expect(sent.instrument["challenge_preference"] == nil)
    }

    /// What the device would hand over, by the seam the session resolves it through: the real
    /// `BrowserData.deviceDefault()` needs a WKWebView for the User-Agent, which no unit test here
    /// starts.
    private func deviceBrowserData() -> BrowserData {
        BrowserData(
            language: "cs-CZ", timezone: -60, screenWidth: 1170, screenHeight: 2532, colorDepth: 24,
            userAgent: "ua-of-the-device", javascriptEnabled: true
        )
    }

    /// Without browser data the charge takes the device's, as the Apple Pay charge always has:
    /// every field goes out, completed by the charge like any other.
    @Test func chargeWithCardTokenWithoutBrowserDataUsesTheDevices() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()
        let device = deviceBrowserData()
        await session.useDeviceBrowserData { device }

        _ = try await session.chargeWithCardToken("tok")

        let sent = try sentCharge()
        #expect(Set(sent.browser.keys) == [
            "language", "timezone", "screen_width", "screen_height", "color_depth",
            "user_agent", "accept_header", "javascript_enabled", "ip"
        ])
        #expect(sent.browser["user_agent"] as? String == "ua-of-the-device")
        #expect(sent.browser["screen_width"] as? Int == 1170)
        #expect(sent.browser["ip"] as? String == "192.0.2.42")
    }

    @Test func chargeWithEncryptedCardWithoutBrowserDataUsesTheDevices() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()
        let device = deviceBrowserData()
        await session.useDeviceBrowserData { device }

        _ = try await session.chargeWithEncryptedCard("jwe")

        let sent = try sentCharge()
        #expect(sent.input["payload"] as? String == "jwe")
        #expect(sent.browser["user_agent"] as? String == "ua-of-the-device")
        #expect(sent.browser["ip"] as? String == "192.0.2.42")
    }

    /// The helper is `charge(_:)` with the request built for the caller, so it fails as that
    /// does: a closed session throws before any request, and the failure is reported once.
    @Test func chargeWithCardTokenFailsLikeChargeAndReportsOnce() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        await session.close()

        await #expect(throws: GopaySDKError.self) { try await session.chargeWithCardToken("tok", browserData: ownBrowserData) }

        #expect(reported.codes == [.authPaymentSessionClosed])
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/charge") == 0)
    }

    // MARK: The wallet under the shared names

    @Test func getWalletInfoReadsWhatGetApplePayInfoReads() async throws {
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.hasSuffix("apple-pay/app-info") { return (200, json(applePayAppInfoJSON(networks: ["visa", "masterCard"]))) }
            return (404, Data())
        }
        let session = try await makeSession()

        let shared = try await session.getWalletInfo()
        let platform = try await session.getApplePayInfo()

        #expect(shared.merchantIdentifier == platform.merchantIdentifier)
        #expect(shared.applePayPaymentRequest.supportedNetworks == ["visa", "masterCard"])
        #expect(StubURLProtocol.requestCount(forPathSuffix: "apple-pay/app-info") == 2)
    }

    /// The alias ends exactly where the platform call ends, and is reported once like it.
    @Test func chargeWithWalletEndsLikeChargeWithApplePay() async throws {
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.hasSuffix("apple-pay/app-info") { return (403, json(["message": "Apple Pay in-app is not enabled"])) }
            return (404, Data())
        }
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        var shared: GopaySDKError?
        var platform: GopaySDKError?
        do { _ = try await session.chargeWithWallet(browserData: ownBrowserData) } catch let error as GopaySDKError { shared = error }
        do { _ = try await session.chargeWithApplePay(browserData: ownBrowserData) } catch let error as GopaySDKError { platform = error }

        #expect(shared?.code == .networkClientError)
        #expect(shared?.code == platform?.code)
        #expect(shared?.httpStatus == platform?.httpStatus)
        #expect(reported.codes == [.networkClientError, .networkClientError])
    }

    @Test func isWalletAvailableAnswersAsCanUseApplePayDoes() async {
        let shared = await GopaySDK.isWalletAvailable()
        #expect(shared == GopaySDK.canUseApplePay())
    }
}
