//
//  sdkTests.swift
//  sdkTests
//
//  Tests for the per-payment session SDK surface. Network calls are intercepted by
//  `StubURLProtocol`, so no real backend is needed.
//

import Testing
import Foundation
@testable import sdk

// MARK: - Test helpers

/// Builds a JWT with a given `exp` value (or none). Unsigned — only the payload matters here.
private func makeJWT(exp: TimeInterval?) -> String {
    let header = ["alg": "none", "typ": "JWT"]
    let payload: [String: Any] = exp.map { ["exp": $0] } ?? [:]
    func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let h = base64url((try? JSONSerialization.data(withJSONObject: header)) ?? Data())
    let p = base64url((try? JSONSerialization.data(withJSONObject: payload)) ?? Data())
    return "\(h).\(p).sig"
}

private func validToken() -> String { makeJWT(exp: Date().timeIntervalSince1970 + 3600) }

private func json(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

private let stubBaseURL = "https://stub.test/"

private func stubbedClient() -> DefaultNetworkClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return DefaultNetworkClient(baseURL: stubBaseURL, configuration: config)
}

private func tokenResponse() -> (Int, Data) {
    (200, json(["access_token": validToken(), "token_type": "bearer", "expires_in": 900]))
}

/// A `URLProtocol` that serves responses from a test-supplied handler and records request paths.
final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) -> (status: Int, body: Data)

    private static let lock = NSLock()
    private static var _handler: Handler?
    private static var _paths: [String] = []
    /// Artificial per-request delay (seconds), to widen single-flight windows.
    private static var _delay: TimeInterval = 0

    static func reset(delay: TimeInterval = 0, handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
        _paths = []
        _delay = delay
    }

    static func requestCount(forPathSuffix suffix: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return _paths.filter { $0.hasSuffix(suffix) }.count
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lock.lock()
        StubURLProtocol._paths.append(request.url?.path ?? "")
        let handler = StubURLProtocol._handler
        let delay = StubURLProtocol._delay
        StubURLProtocol.lock.unlock()

        if delay > 0 { Thread.sleep(forTimeInterval: delay) }

        guard let handler = handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "stub", code: -1))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - JwtUtils

struct JwtUtilsTests {
    @Test func expirationSeconds_validToken_returnsExp() {
        let exp = (Date().timeIntervalSince1970 + 1234).rounded()
        #expect(JwtUtils.expirationSeconds(jwt: makeJWT(exp: exp)) == exp)
    }

    @Test func expirationSeconds_noExpClaim_returnsZero() {
        #expect(JwtUtils.expirationSeconds(jwt: makeJWT(exp: nil)) == 0)
    }

    @Test func expirationSeconds_malformedToken_returnsZero() {
        #expect(JwtUtils.expirationSeconds(jwt: "not.a.jwt") == 0)
        #expect(JwtUtils.expirationSeconds(jwt: "garbage") == 0)
    }
}

// MARK: - Charge request encoding

struct ChargeModelsTests {
    @Test func chargePaymentRequest_encodesToPaymentChargeInputShape() throws {
        let request = ChargePaymentRequest.cardToken(
            "tok_123",
            browserData: BrowserData(
                language: "cs-CZ", timezone: -60,
                screenWidth: 1170, screenHeight: 2532, colorDepth: 24
            ),
            challengePreference: .auto,
            returnUrl: "https://merchant.example/return"
        )

        let data = try JSONEncoder().encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(dict["return_url"] as? String == "https://merchant.example/return")
        let instrument = dict["payment_instrument"] as! [String: Any]
        #expect(instrument["payment_instrument"] as? String == "PAYMENT_CARD")
        #expect(instrument["challenge_preference"] as? String == "AUTO")

        let input = instrument["input"] as! [String: Any]
        #expect(input["input_type"] as? String == "CARD_TOKEN")
        #expect(input["card_token"] as? String == "tok_123")
        // Apple Pay-only fields are omitted for a CARD_TOKEN input.
        #expect(input["signature"] == nil)

        let browser = instrument["browser_data"] as! [String: Any]
        #expect(browser["screen_width"] as? Int == 1170)
        #expect(browser["color_depth"] as? Int == 24)
    }

    @Test func applePayInput_encodesAppleFieldsAndOmitsCardToken() throws {
        let request = ChargePaymentRequest.applePay(
            data: "d", signature: "s", version: "EC_v1",
            header: ApplePayHeader(ephemeralPublicKey: "epk", publicKeyHash: "pkh", transactionId: "tx"),
            browserData: BrowserData(language: "en", timezone: 0, screenWidth: 1, screenHeight: 1, colorDepth: 24)
        )
        let dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        let input = (dict["payment_instrument"] as! [String: Any])["input"] as! [String: Any]
        #expect(input["input_type"] as? String == "APPLE_PAY")
        #expect(input["version"] as? String == "EC_v1")
        #expect((input["header"] as! [String: Any])["transactionId"] as? String == "tx")
        #expect(input["card_token"] == nil)
    }
}

// MARK: - PaymentSession + GopaySDK (network)
//
// Serialized: every test here drives the shared `StubURLProtocol` global state, so they must not
// run in parallel (Swift Testing parallelizes by default).

@Suite(.serialized)
struct SessionNetworkTests {

    private func makeSession() async throws -> PaymentSession {
        let client = stubbedClient()
        return try await PaymentSession.create(
            paymentId: "p1", paymentSecret: "secret", scope: "payment:charge",
            authApi: AuthAPI(client: client), client: client, onClose: { _ in }
        )
    }

    @Test func eagerAuth_thenGetStatus_succeeds() async throws {
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.contains("/payments/") {
                return (200, json(["id": "p1", "state": "CREATED", "amount": 1000, "currency": "CZK"]))
            }
            return (404, Data())
        }

        let session = try await makeSession()
        let details = try await session.getStatus()
        #expect(details.id == "p1")
        #expect(details.state == .created)
        #expect(details.amount == 1000)
        #expect(StubURLProtocol.requestCount(forPathSuffix: "oauth2/token") == 1)
    }

    @Test func eagerAuth_badCredentials_throwsCredentialsInvalid() async throws {
        StubURLProtocol.reset { _ in (401, json(["error": "invalid_client"])) }
        do {
            _ = try await makeSession()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentCredentialsInvalid)
        }
    }

    @Test func staleToken_401_reauthenticatesOnceThenRetries() async throws {
        var statusCalls = 0
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.contains("/payments/") {
                statusCalls += 1
                return statusCalls == 1
                    ? (401, Data("{}".utf8))
                    : (200, json(["id": "p1", "state": "PAID", "amount": 1000, "currency": "CZK"]))
            }
            return (404, Data())
        }

        let session = try await makeSession()
        let details = try await session.getStatus()
        #expect(details.state == .paid)
        // 1 eager + 1 re-auth after the 401.
        #expect(StubURLProtocol.requestCount(forPathSuffix: "oauth2/token") == 2)
    }

    @Test func persistent401_throwsTokenExpired() async throws {
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            return (401, Data("{}".utf8))
        }

        let session = try await makeSession()
        do {
            _ = try await session.getStatus()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentTokenExpired)
        }
    }

    @Test func concurrentReauth_isSingleFlighted() async throws {
        StubURLProtocol.reset(delay: 0.1) { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.contains("/payments/") {
                return (200, json(["id": "p1", "state": "CREATED", "amount": 1, "currency": "CZK"]))
            }
            return (404, Data())
        }

        let session = try await makeSession() // 1 token call (eager)
        await session.invalidateToken()

        // Fire several concurrent calls that all need a fresh token.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { _ = try? await session.getStatus() }
            }
            await group.waitForAll()
        }

        // Eager (1) + exactly one single-flighted re-auth (1) == 2.
        #expect(StubURLProtocol.requestCount(forPathSuffix: "oauth2/token") == 2)
    }

    @Test func close_thenReauth_throwsSessionClosed() async throws {
        StubURLProtocol.reset { _ in tokenResponse() }
        let session = try await makeSession()
        await session.close()
        await session.invalidateToken()
        do {
            _ = try await session.reauthenticate()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentSessionClosed)
        }
    }

    // MARK: GopaySDK registry + public key

    private func sdk(clientId: String? = nil, shareableKey: String? = nil) -> GopaySDK {
        let config = GopaySDKConfig(
            environment: .development(baseURL: stubBaseURL),
            clientId: clientId,
            shareableKey: shareableKey
        )
        return GopaySDK(config: config, networkClient: stubbedClient())
    }

    @Test func startPaymentSession_duplicate_throwsAlreadyExists() async throws {
        StubURLProtocol.reset { _ in tokenResponse() }
        let sdk = sdk()

        let first = try await sdk.startPaymentSession(paymentId: "dup", paymentSecret: "s")
        do {
            _ = try await sdk.startPaymentSession(paymentId: "dup", paymentSecret: "s")
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentSessionAlreadyExists)
        }

        // After closing, a new session can be started for the same id.
        await first.close()
        let again = try await sdk.startPaymentSession(paymentId: "dup", paymentSecret: "s")
        let looked = await sdk.getPaymentSession("dup")
        #expect(looked === again)
        await again.close()
        let gone = await sdk.getPaymentSession("dup")
        #expect(gone == nil)
    }

    @Test func getPublicEncryptionKey_missingShareableKey_throws() async throws {
        StubURLProtocol.reset { _ in (200, Data()) }
        let sdk = sdk() // no clientId / shareableKey

        do {
            _ = try await sdk.getPublicEncryptionKey()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authShareableKeyMissing)
        }
    }

    @Test func getPublicEncryptionKey_cachesAndSingleFlights() async throws {
        let jwkJSON: [String: Any] = [
            "kty": "RSA", "kid": "key_1", "use": "enc",
            "alg": "RSA-OAEP-256", "n": "abc", "e": "AQAB"
        ]
        StubURLProtocol.reset(delay: 0.1) { req in
            (req.url?.path.hasSuffix("cards/public-key") ?? false) ? (200, json(jwkJSON)) : (404, Data())
        }
        let sdk = sdk(clientId: "c", shareableKey: "k")

        // Concurrent first fetches single-flight to one network call...
        async let a = sdk.getPublicEncryptionKey()
        async let b = sdk.getPublicEncryptionKey()
        let first = try await a
        let second = try await b
        #expect(first.kid == "key_1")
        #expect(second.kid == "key_1")

        // ...and a later call is served from cache (still one network call total).
        _ = try await sdk.getPublicEncryptionKey()
        #expect(StubURLProtocol.requestCount(forPathSuffix: "cards/public-key") == 1)
    }
}
