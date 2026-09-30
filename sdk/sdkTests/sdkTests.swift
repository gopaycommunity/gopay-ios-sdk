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

/// A request as the stub saw it: its path, headers and body, in the order requests arrived.
struct RecordedRequest {
    let path: String
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? { headers[name] }

    /// The body parsed as a JSON object, or `nil` when it is empty or not an object.
    var jsonBody: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

/// A `URLProtocol` that serves responses from a test-supplied handler and records every request.
final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) -> (status: Int, body: Data)

    /// Handler status that makes the stub fail the request at the transport level, the way a
    /// dropped connection would, instead of answering it.
    static let transportFailure = -1

    private static let lock = NSLock()
    private static var _handler: Handler?
    private static var _requests: [RecordedRequest] = []
    /// Artificial per-request delay (seconds), to widen single-flight windows.
    private static var _delay: TimeInterval = 0

    static func reset(delay: TimeInterval = 0, handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
        _requests = []
        _delay = delay
    }

    static func requestCount(forPathSuffix suffix: String) -> Int {
        requests(forPathSuffix: suffix).count
    }

    static func requests(forPathSuffix suffix: String) -> [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests.filter { $0.path.hasSuffix(suffix) }
    }

    /// Paths of every request so far, in arrival order.
    static var paths: [String] {
        lock.lock(); defer { lock.unlock() }
        return _requests.map(\.path)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lock.lock()
        StubURLProtocol._requests.append(RecordedRequest(
            path: request.url?.path ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            body: StubURLProtocol.readBody(of: request)
        ))
        let handler = StubURLProtocol._handler
        let delay = StubURLProtocol._delay
        StubURLProtocol.lock.unlock()

        if delay > 0 { Thread.sleep(forTimeInterval: delay) }

        guard let handler = handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "stub", code: -1))
            return
        }
        let (status, body) = handler(request)
        if status == StubURLProtocol.transportFailure {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` hands the protocol a body stream, not `httpBody`, so the bytes are read back
    /// from whichever of the two is set.
    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
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
        // Not set, so not sent: the session fills it in before the charge goes out.
        #expect(browser["ip"] == nil)
    }

    @Test func browserData_encodesIpUnderItsSpecName() throws {
        let data = try JSONEncoder().encode(BrowserData(
            language: "cs-CZ", timezone: -60, screenWidth: 1170, screenHeight: 2532, colorDepth: 24,
            userAgent: "ua", acceptHeader: "{\"accept\":\"*/*\"}", javascriptEnabled: true, ip: "192.0.2.42"
        ))
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["ip"] as? String == "192.0.2.42")
        #expect(dict["user_agent"] as? String == "ua")
        #expect(dict["accept_header"] as? String == "{\"accept\":\"*/*\"}")
        #expect(dict["javascript_enabled"] as? Bool == true)
    }

    @Test func browserDataDetected_decodesTheGatewayResponse() throws {
        let detected = try JSONDecoder().decode(BrowserDataDetected.self, from: browserDataDetectedFixture)
        #expect(detected.ip == "192.0.2.42")
        #expect(detected.userAgent == "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148")
        #expect(detected.acceptHeader == "{\"accept\":\"application/json\",\"accept-language\":\"cs-CZ,cs;q=0.9\"}")
    }

    @Test func browserData_filled_takesOnlyTheMissingFields() throws {
        let detected = try JSONDecoder().decode(BrowserDataDetected.self, from: browserDataDetectedFixture)
        let own = BrowserData(
            language: "en", timezone: 0, screenWidth: 1, screenHeight: 1, colorDepth: 24,
            userAgent: "own-ua", acceptHeader: nil, javascriptEnabled: nil, ip: "198.51.100.7"
        )
        let filled = own.filled(from: detected)
        #expect(filled.ip == "198.51.100.7")
        #expect(filled.userAgent == "own-ua")
        #expect(filled.acceptHeader == detected.acceptHeader)
        #expect(filled.javascriptEnabled == true)
        #expect(filled.language == "en")
    }

    /// The echo is never the source of `user_agent`: a nil one stays nil here, the session fills
    /// it in from the WebView before the fetch.
    @Test func browserData_filled_neverTakesTheUserAgentFromTheAnswer() throws {
        let detected = try JSONDecoder().decode(BrowserDataDetected.self, from: browserDataDetectedFixture)
        let bare = BrowserData(language: "en", timezone: 0, screenWidth: 1, screenHeight: 1, colorDepth: 24)
        let filled = bare.filled(from: detected)
        #expect(filled.userAgent == nil)
        #expect(filled.ip == detected.ip)
        #expect(filled.acceptHeader == detected.acceptHeader)
    }
}

/// `GET /cards/browser-data` as the gateway answers it, User-Agent echoed from the request.
private let browserDataDetectedFixture = Data("""
{
  "ip": "192.0.2.42",
  "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
  "accept_header": "{\\"accept\\":\\"application/json\\",\\"accept-language\\":\\"cs-CZ,cs;q=0.9\\"}"
}
""".utf8)


struct ChargeInputEncodingTests {
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

    @Test func encryptedCardInput_encodesPayloadAndOmitsCardToken() throws {
        let request = ChargePaymentRequest.encryptedCard(
            "jwe.compact.string",
            browserData: BrowserData(language: "en", timezone: 0, screenWidth: 1, screenHeight: 1, colorDepth: 24),
            challengePreference: .auto
        )
        let dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        // The deployed gateway rejects a request-level return_url, so charges must not send one.
        #expect(dict["return_url"] == nil)
        let instrument = dict["payment_instrument"] as! [String: Any]
        #expect(instrument["challenge_preference"] as? String == "AUTO")

        let input = instrument["input"] as! [String: Any]
        #expect(input["input_type"] as? String == "ENCRYPTED_CARD")
        #expect(input["payload"] as? String == "jwe.compact.string")
        // Fields from other variants are omitted for an ENCRYPTED_CARD input.
        #expect(input["card_token"] == nil)
        #expect(input["signature"] == nil)
    }
}

// MARK: - PaymentSession + GopaySDK (network)
//
// Serialized: every test here drives the shared `StubURLProtocol` global state, so they must not
// run in parallel (Swift Testing parallelizes by default).

@Suite(.serialized)
struct SessionNetworkTests {

    private func makeSession(shareableKey: String? = "shareable") async throws -> PaymentSession {
        let client = stubbedClient()
        return try await PaymentSession.create(
            paymentId: "p1", paymentSecret: "secret", scope: "payment:charge",
            authApi: AuthAPI(client: client),
            publicApi: PublicAPI(client: client, clientId: "client", shareableKey: shareableKey),
            client: client, onClose: { _ in }
        )
    }

    // MARK: Charge completes browser_data

    private static let webViewUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    /// The device-side browser data as `BrowserData.deviceDefault()` builds it: no ip, no accept
    /// header, the WebView User-Agent. Built by hand because the real one needs a WKWebView.
    private static let deviceBrowserData = BrowserData(
        language: "cs-CZ", timezone: -60, screenWidth: 1170, screenHeight: 2532, colorDepth: 24,
        userAgent: webViewUA, javascriptEnabled: true
    )

    /// Answers the token, the browser data (echoing the request's User-Agent like the gateway) and
    /// the charge; anything else is a 404.
    private static func gatewayHandler(browserDataStatus: Int = 200) -> StubURLProtocol.Handler {
        { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.hasSuffix("cards/browser-data") {
                return (browserDataStatus, json([
                    "ip": "192.0.2.42",
                    "user_agent": req.value(forHTTPHeaderField: "User-Agent") ?? "",
                    "accept_header": "{\"accept\":\"application/json\"}"
                ]))
            }
            if path.hasSuffix("/charge") { return (200, json(["id": "ch_1", "state": "REQUESTED"])) }
            return (404, Data())
        }
    }

    @Test func charge_fetchesBrowserDataWithTheWebViewUserAgentAndSendsItAll() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()

        let response = try await session.charge(
            .encryptedCard("jwe", browserData: Self.deviceBrowserData, challengePreference: .auto)
        )
        #expect(response.id == "ch_1")

        // The browser data went out first, authorized with the shareable key and carrying the
        // WebView User-Agent rather than the SDK's own.
        let fetch = try #require(StubURLProtocol.requests(forPathSuffix: "cards/browser-data").first)
        #expect(fetch.header("User-Agent") == Self.webViewUA)
        #expect(fetch.header("Authorization") == gopayBasicAuthHeader(user: "client", secret: "shareable"))
        #expect(StubURLProtocol.paths.firstIndex { $0.hasSuffix("cards/browser-data") }!
            < StubURLProtocol.paths.firstIndex { $0.hasSuffix("/charge") }!)

        // The charge carries every Browser-Data field the spec requires.
        let charge = try #require(StubURLProtocol.requests(forPathSuffix: "/charge").first)
        let browser = try #require((charge.jsonBody?["payment_instrument"] as? [String: Any])?["browser_data"] as? [String: Any])
        #expect(Set(browser.keys) == [
            "language", "timezone", "screen_width", "screen_height", "color_depth",
            "user_agent", "accept_header", "javascript_enabled", "ip"
        ])
        #expect(browser["ip"] as? String == "192.0.2.42")
        #expect(browser["user_agent"] as? String == Self.webViewUA)
        #expect(browser["accept_header"] as? String == "{\"accept\":\"application/json\"}")
        #expect(browser["javascript_enabled"] as? Bool == true)
        #expect(browser["language"] as? String == "cs-CZ")
    }

    @Test func charge_keepsCallerValuesAndSkipsTheFetchWhenComplete() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()

        let own = BrowserData(
            language: "en", timezone: 0, screenWidth: 1, screenHeight: 1, colorDepth: 24,
            userAgent: "own-ua", acceptHeader: "own-accept", javascriptEnabled: nil, ip: "198.51.100.7"
        )
        _ = try await session.charge(.cardToken("tok", browserData: own))

        #expect(StubURLProtocol.requestCount(forPathSuffix: "cards/browser-data") == 0)
        let charge = try #require(StubURLProtocol.requests(forPathSuffix: "/charge").first)
        let browser = try #require((charge.jsonBody?["payment_instrument"] as? [String: Any])?["browser_data"] as? [String: Any])
        #expect(browser["ip"] as? String == "198.51.100.7")
        #expect(browser["user_agent"] as? String == "own-ua")
        #expect(browser["accept_header"] as? String == "own-accept")
        // The one field filled without asking: the challenge WebView runs JavaScript.
        #expect(browser["javascript_enabled"] as? Bool == true)
    }

    @Test func charge_browserDataHttpError_failsTheChargeWithoutSendingIt() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler(browserDataStatus: 503))
        let session = try await makeSession()

        do {
            _ = try await session.charge(.cardToken("tok", browserData: Self.deviceBrowserData))
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .networkServerError)
            #expect(error.httpStatus == 503)
            #expect(error.message.hasPrefix("Failed to charge payment: browser data could not be fetched"))
            #expect((error.underlying as? GopaySDKError)?.code == .networkServerError)
        }
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/charge") == 0)
    }

    @Test func charge_browserDataTransportFailure_failsTheChargeAsNetworkIOError() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler(browserDataStatus: StubURLProtocol.transportFailure))
        let session = try await makeSession()

        do {
            _ = try await session.charge(.cardToken("tok", browserData: Self.deviceBrowserData))
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .networkIOError)
            #expect(error.httpStatus == nil)
            #expect(error.message.hasPrefix("Failed to charge payment: browser data could not be fetched"))
            #expect((error.underlying as? URLError)?.code == .networkConnectionLost)
        }
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/charge") == 0)
    }

    @Test func charge_withoutShareableKey_failsBeforeAnyRequest() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession(shareableKey: nil)

        do {
            _ = try await session.charge(.cardToken("tok", browserData: Self.deviceBrowserData))
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authShareableKeyMissing)
        }
        #expect(StubURLProtocol.requestCount(forPathSuffix: "cards/browser-data") == 0)
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/charge") == 0)
    }

    /// A charge is rebuilt around the completed browser data; nothing else may fall out of it.
    @Test func charge_keepsThePreferenceReturnUrlAndTokenNextToBrowserData() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()

        _ = try await session.charge(.cardToken(
            "tok",
            browserData: Self.deviceBrowserData,
            challengePreference: .noChallengePreferred,
            returnUrl: "https://shop.example/return"
        ))

        let charge = try #require(StubURLProtocol.requests(forPathSuffix: "/charge").first)
        let body = try #require(charge.jsonBody)
        #expect(body["return_url"] as? String == "https://shop.example/return")
        let instrument = try #require(body["payment_instrument"] as? [String: Any])
        #expect(instrument["payment_instrument"] as? String == "PAYMENT_CARD")
        #expect(instrument["challenge_preference"] as? String == "NO_CHALLENGE_PREFERRED")
        let input = try #require(instrument["input"] as? [String: Any])
        #expect(input["input_type"] as? String == "CARD_TOKEN")
        #expect(input["card_token"] as? String == "tok")
        #expect((instrument["browser_data"] as? [String: Any])?["ip"] as? String == "192.0.2.42")
    }

    /// A hand-built BrowserData without a User-Agent must not go out under the SDK's HTTP
    /// client's: the gateway would echo that into user_agent and the issuer would see one
    /// browser in the AReq and another in the challenge.
    @Test func charge_withoutUserAgent_fetchesUnderTheWebViewUserAgent() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()
        let bare = BrowserData(language: "cs-CZ", timezone: -60, screenWidth: 1170, screenHeight: 2532, colorDepth: 24)

        _ = try await session.charge(.cardToken("tok", browserData: bare))

        let fetch = try #require(StubURLProtocol.requests(forPathSuffix: "cards/browser-data").first)
        let sentUA = try #require(fetch.header("User-Agent"))
        #expect(sentUA != "GoPay iOS SDK \(GopaySDK.version)")
        #expect(sentUA.hasPrefix("Mozilla/5.0"))
        let charge = try #require(StubURLProtocol.requests(forPathSuffix: "/charge").first)
        let browser = try #require((charge.jsonBody?["payment_instrument"] as? [String: Any])?["browser_data"] as? [String: Any])
        #expect(browser["user_agent"] as? String == sentUA)
    }

    /// The fetch is decided after the User-Agent is filled in: ip and accept_header on their own
    /// are enough to skip it, and the charge still goes out under the WebView's User-Agent. The
    /// Android SDK orders the two steps the same way.
    @Test func charge_withIpAndAcceptHeaderButNoUserAgent_skipsTheFetch() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()
        let own = BrowserData(
            language: "en", timezone: 0, screenWidth: 1, screenHeight: 1, colorDepth: 24,
            acceptHeader: "own-accept", ip: "198.51.100.7"
        )

        _ = try await session.charge(.cardToken("tok", browserData: own))

        #expect(StubURLProtocol.requestCount(forPathSuffix: "cards/browser-data") == 0)
        let charge = try #require(StubURLProtocol.requests(forPathSuffix: "/charge").first)
        let browser = try #require((charge.jsonBody?["payment_instrument"] as? [String: Any])?["browser_data"] as? [String: Any])
        #expect(browser["ip"] as? String == "198.51.100.7")
        #expect(browser["accept_header"] as? String == "own-accept")
        let userAgent = try #require(browser["user_agent"] as? String)
        #expect(userAgent != "GoPay iOS SDK \(GopaySDK.version)")
        #expect(userAgent.hasPrefix("Mozilla/5.0"))
    }

    /// The closure is checked before the browser data step, which runs under the shareable key:
    /// otherwise a closed session without that key reports AUTH_011 instead of AUTH_013, after
    /// one more request to the gateway.
    @Test func charge_onAClosedSession_throwsSessionClosedBeforeAnyRequest() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession(shareableKey: nil)
        await session.close()

        do {
            _ = try await session.charge(.cardToken("tok", browserData: Self.deviceBrowserData))
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentSessionClosed)
        }
        #expect(StubURLProtocol.requestCount(forPathSuffix: "cards/browser-data") == 0)
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/charge") == 0)
    }

    @Test func completeBrowserData_returnsWhatTheChargeWouldSend() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()

        let completed = try await session.completeBrowserData(Self.deviceBrowserData)
        #expect(completed.ip == "192.0.2.42")
        #expect(completed.userAgent == Self.webViewUA)
        #expect(completed.acceptHeader == "{\"accept\":\"application/json\"}")

        // Passed on unchanged, the charge does not ask again.
        _ = try await session.charge(.cardToken("tok", browserData: completed))
        #expect(StubURLProtocol.requestCount(forPathSuffix: "cards/browser-data") == 1)
    }

    @Test func send_keepsTheSdkUserAgentOnEveryOtherRequest() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        _ = try await makeSession()
        let token = try #require(StubURLProtocol.requests(forPathSuffix: "oauth2/token").first)
        #expect(token.header("User-Agent") == "GoPay iOS SDK \(GopaySDK.version)")
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
