//
//  sdkTests.swift
//  sdkTests
//
//  Tests for the per-payment session SDK surface. Network calls are intercepted by
//  `StubURLProtocol`, so no real backend is needed.
//

import Testing
import Foundation
import CryptoKit
import Security
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

func json(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

let stubBaseURL = "https://stub.test/"

func stubbedClient(requestTimeout: TimeInterval = GopayConfig.defaultRequestTimeout) -> DefaultNetworkClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return DefaultNetworkClient(baseUrl: stubBaseURL, configuration: config, requestTimeout: requestTimeout)
}

func tokenResponse() -> (Int, Data) {
    (200, json(["access_token": validToken(), "token_type": "bearer", "expires_in": 900]))
}

/// A request as the stub saw it: its path, headers and body, in the order requests arrived.
struct RecordedRequest {
    let path: String
    let headers: [String: String]
    let body: Data
    var method = "GET"
    var timeoutInterval: TimeInterval = 0

    func header(_ name: String) -> String? { headers[name] }

    /// The body parsed as a JSON object, or `nil` when it is empty or not an object.
    var jsonBody: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

/// A `URLProtocol` that serves responses from a test-supplied handler and records every request.
final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) -> (status: Int, body: Data)

    /// Handler status that makes the stub fail the request at the transport level instead of
    /// answering it, with the `transportError` of ``reset(delay:headers:transportError:handler:)``:
    /// a dropped connection unless a test picks another.
    static let transportFailure = -1

    private static let lock = NSLock()
    private static var storedHandler: Handler?
    private static var recordedRequests: [RecordedRequest] = []
    /// Requests to a path with this suffix are never answered, see ``holdAnswers(forPathSuffix:)``.
    private static var heldPathSuffix: String?
    /// Paths of the requests the loading system stopped before they were answered, in order.
    private static var stopped: [String] = []
    /// Artificial per-request delay (seconds), to widen single-flight windows.
    private static var storedDelay: TimeInterval = 0
    /// Extra response headers every answer carries, such as the gateway's `Date`.
    private static var storedHeaders: [String: String] = [:]
    /// What a ``transportFailure`` fails with.
    private static var storedTransportError = URLError.Code.networkConnectionLost
    /// Holds every answer until the test opens it, see ``holdAnswers()``.
    private static var storedGate: StubGate?

    static func reset(
        delay: TimeInterval = 0,
        headers: [String: String] = [:],
        transportError: URLError.Code = .networkConnectionLost,
        handler: @escaping Handler
    ) {
        lock.lock(); defer { lock.unlock() }
        storedHandler = handler
        recordedRequests = []
        heldPathSuffix = nil
        stopped = []
        storedDelay = delay
        storedHeaders = headers
        storedTransportError = transportError
        storedGate?.open()
        storedGate = nil
    }

    /// Holds every request that arrives from now on, recorded but unanswered, until
    /// ``releaseAnswers()``. For the tests that cancel a call while its request is in flight: they
    /// wait for the request to be recorded, cancel, and release, so the cancellation lands in
    /// flight however slow the machine is. A fixed delay only does that while the test's own
    /// steps take less time than the delay.
    static func holdAnswers() {
        lock.lock(); defer { lock.unlock() }
        storedGate?.open()
        storedGate = StubGate()
    }

    /// Answers the held requests and every one after them.
    static func releaseAnswers() {
        lock.lock(); defer { lock.unlock() }
        storedGate?.open()
        storedGate = nil
    }

    static func requestCount(forPathSuffix suffix: String) -> Int {
        requests(forPathSuffix: suffix).count
    }

    static func requests(forPathSuffix suffix: String) -> [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return recordedRequests.filter { $0.path.hasSuffix(suffix) }
    }

    /// Paths of every request so far, in arrival order.
    static var paths: [String] {
        lock.lock(); defer { lock.unlock() }
        return recordedRequests.map(\.path)
    }

    /// Leaves every request to a path ending in `suffix` unanswered until it times out or is
    /// cancelled, a gateway that does not answer. Until the next ``reset(delay:headers:transportError:handler:)``.
    static func holdAnswers(forPathSuffix suffix: String) {
        lock.lock(); defer { lock.unlock() }
        heldPathSuffix = suffix
    }

    /// Paths of the requests stopped before an answer, a cancelled one among them.
    static var stoppedPaths: [String] {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lock.lock()
        let path = request.url?.path ?? ""
        StubURLProtocol.recordedRequests.append(RecordedRequest(
            path: path,
            headers: request.allHTTPHeaderFields ?? [:],
            body: StubURLProtocol.readBody(of: request),
            method: request.httpMethod ?? "GET",
            timeoutInterval: request.timeoutInterval
        ))
        if let held = StubURLProtocol.heldPathSuffix, path.hasSuffix(held) {
            StubURLProtocol.lock.unlock()
            return
        }
        answered = true
        let handler = StubURLProtocol.storedHandler
        let delay = StubURLProtocol.storedDelay
        let headers = StubURLProtocol.storedHeaders
        let transportError = StubURLProtocol.storedTransportError
        let gate = StubURLProtocol.storedGate
        StubURLProtocol.lock.unlock()

        gate?.wait()
        // Kept on purpose: it widens the single-flight windows of the tests that ask for it, and a
        // slow runner only widens them further.
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }

        guard let handler = handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "stub", code: -1))
            return
        }
        let (status, body) = handler(request)
        if status == StubURLProtocol.transportFailure {
            client?.urlProtocol(self, didFailWithError: URLError(transportError))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil,
            headerFields: headers.merging(["Content-Type": "application/json"]) { stub, _ in stub }
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Called once a request ends, answered or not; only an unanswered one is recorded.
    override func stopLoading() {
        StubURLProtocol.lock.lock(); defer { StubURLProtocol.lock.unlock() }
        guard !answered else { return }
        StubURLProtocol.stopped.append(request.url?.path ?? "")
    }

    /// Whether this request is being answered, set in `startLoading` and read in `stopLoading`,
    /// which may run on different threads; both under ``lock``.
    private var answered = false

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

/// Holds the stub's answers on the URL loading thread until it is opened. Opens by itself after
/// half a minute, so a test that never releases it does not hang the run.
final class StubGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isOpen = false

    func wait() {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(30)
        while !isOpen, condition.wait(until: deadline) {}
    }

    func open() {
        condition.lock(); defer { condition.unlock() }
        isOpen = true
        condition.broadcast()
    }
}

extension GopaySDK {
    /// This SDK, made to wait for each session's init-session request before the start returns.
    /// Every SDK the suites build over the shared stub uses it: a request left running in the
    /// background would otherwise reach the stub after the next test has reset it, and block the
    /// URL loading thread behind answers that test holds (`holdAnswers()`).
    func waitingForInitSession() -> GopaySDK {
        waitsForInitSession = true
        return self
    }
}

/// A flag the stub's handler reads from the URL loading thread.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false

    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// A counter the stub's handler can bump from the URL loading thread.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// Adds one and returns the new count.
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}

/// Answers like the gateway, but holds every token renewal after the first until the test calls
/// ``release()``. It ignores cancellation, so the answer arrives whatever the session does
/// meanwhile.
final class HeldTokenClient: AsyncHTTPClient, @unchecked Sendable {
    let baseUrl = stubBaseURL
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var tokenCalls = 0
    private var holding = false

    var isHolding: Bool {
        lock.lock(); defer { lock.unlock() }
        return holding
    }

    func release() { gate.signal() }

    func makeURL(path: String) -> URL? { URL(string: baseUrl + path) }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        if url.path.hasSuffix("oauth2/token") {
            lock.lock()
            tokenCalls += 1
            let held = tokenCalls > 1
            holding = held
            lock.unlock()
            if held {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        self.gate.wait()
                        continuation.resume()
                    }
                }
            }
            return (tokenResponse().1, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let body = json(["id": "p1", "state": "CREATED", "amount": 1, "currency": "CZK", "order_number": "o1", "gw_url": "https://gw.example/p", "customer": ["email": "a@b.c"]])
        return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

// MARK: - Test encryption key

/// A throwaway RSA-2048 key pair: the public half goes to the stub as the merchant's JWK, the
/// private half opens the JWE the SDK builds from it so the tests can read the claims.
struct TestEncryptionKey {
    let privateKey: SecKey
    let publicJWKJSON: Data

    init() throws {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecAttrIsPermanent as String: false,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(key),
              let der = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error?.takeRetainedValue() ?? NSError(domain: "test", code: -1)
        }
        privateKey = key

        // PKCS#1: RSAPublicKey ::= SEQUENCE { INTEGER n, INTEGER e }
        let bytes = [UInt8](der)
        var i = 0
        func readLength() -> Int {
            let first = Int(bytes[i]); i += 1
            guard first & 0x80 != 0 else { return first }
            var length = 0
            for _ in 0..<(first & 0x7F) { length = length << 8 | Int(bytes[i]); i += 1 }
            return length
        }
        func readInteger() -> Data {
            precondition(bytes[i] == 0x02, "expected DER INTEGER"); i += 1
            var length = readLength()
            // Skip the sign padding byte DER adds when the high bit of the value is set.
            if bytes[i] == 0x00 { i += 1; length -= 1 }
            defer { i += length }
            return Data(bytes[i..<(i + length)])
        }
        precondition(bytes[i] == 0x30, "expected DER SEQUENCE"); i += 1
        _ = readLength()

        let jwk: [String: Any] = [
            "kty": "RSA", "kid": "key_test", "use": "enc", "alg": "RSA-OAEP-256",
            "n": Self.base64url(readInteger()), "e": Self.base64url(readInteger()),
        ]
        publicJWKJSON = try JSONSerialization.data(withJSONObject: jwk)
    }

    /// Opens a compact JWE (RSA-OAEP-256 + A256GCM) and returns its payload as a JSON object.
    func decryptClaims(_ jwe: String) throws -> [String: Any] {
        let parts = jwe.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5,
              let encryptedKey = Self.base64urlDecode(parts[1]),
              let iv = Self.base64urlDecode(parts[2]),
              let ciphertext = Self.base64urlDecode(parts[3]),
              let tag = Self.base64urlDecode(parts[4]) else {
            throw NSError(domain: "test", code: -2)
        }
        var error: Unmanaged<CFError>?
        guard let cek = SecKeyCreateDecryptedData(
            privateKey, .rsaEncryptionOAEPSHA256, encryptedKey as CFData, &error
        ) as Data? else {
            throw error?.takeRetainedValue() ?? NSError(domain: "test", code: -3)
        }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
        let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: cek), authenticating: Data(parts[0].utf8))
        return (try JSONSerialization.jsonObject(with: plaintext) as? [String: Any]) ?? [:]
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64urlDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
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
            challengePreference: .auto
        )

        let data = try JSONEncoder().encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Payment-Charge-Input carries the instrument only; return_url belongs to the payment.
        #expect(Set(dict.keys) == ["payment_instrument"])
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

    @Test func browserDataEncodesIpUnderItsSpecName() throws {
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

    @Test func detectedBrowserDataDecodesTheGatewayResponse() throws {
        let detected = try JSONDecoder().decode(BrowserDataDetected.self, from: browserDataDetectedFixture)
        #expect(detected.ip == "192.0.2.42")
        #expect(detected.userAgent == "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148")
        #expect(detected.acceptHeader == "{\"accept\":\"application/json\",\"accept-language\":\"cs-CZ,cs;q=0.9\"}")
    }

    @Test func fillingBrowserDataTakesOnlyTheMissingFields() throws {
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
    @Test func fillingBrowserDataNeverTakesTheUserAgentFromTheAnswer() throws {
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
        #expect(Set(dict.keys) == ["payment_instrument"])
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
        #expect(Set(dict.keys) == ["payment_instrument"])
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

    func makeSession(
        shareableKey: String? = "shareable",
        requestTimeout: TimeInterval = GopayConfig.defaultRequestTimeout
    ) async throws -> PaymentSession {
        let client = stubbedClient(requestTimeout: requestTimeout)
        return try await PaymentSession.create(
            paymentId: "p1", paymentSecret: "secret", scope: "payment:charge",
            authApi: AuthAPI(client: client),
            publicApi: PublicAPI(client: client, clientId: "client", shareableKey: shareableKey),
            client: client, callbacks: SessionCallbacks(onClose: { _ in
                // Created outside the SDK, so there is no registry entry for the close to drop.
            })
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
    static func gatewayHandler(browserDataStatus: Int = 200) -> StubURLProtocol.Handler {
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

    @Test func aChargeFetchesBrowserDataWithTheWebViewUserAgentAndSendsItAll() async throws {
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

    @Test func aChargeKeepsCallerValuesAndSkipsTheFetchWhenComplete() async throws {
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

    @Test func aBrowserDataHttpErrorFailsTheChargeWithoutSendingIt() async throws {
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

    @Test func aBrowserDataTransportFailureFailsTheChargeAsNetworkIOError() async throws {
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

    @Test func aChargeWithoutShareableKeyFailsBeforeAnyRequest() async throws {
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
    @Test func aChargeKeepsThePreferenceAndTokenNextToBrowserData() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()

        _ = try await session.charge(.cardToken(
            "tok",
            browserData: Self.deviceBrowserData,
            challengePreference: .noChallengePreferred
        ))

        let charge = try #require(StubURLProtocol.requests(forPathSuffix: "/charge").first)
        let body = try #require(charge.jsonBody)
        #expect(body["return_url"] == nil)
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
    @Test func aChargeWithoutUserAgentFetchesUnderTheWebViewUserAgent() async throws {
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
    @Test func aChargeWithIpAndAcceptHeaderButNoUserAgentSkipsTheFetch() async throws {
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
    @Test func aChargeOnAClosedSessionThrowsSessionClosedBeforeAnyRequest() async throws {
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

    /// Every method of a closed session that would send a request fails the same way and sends
    /// nothing: the payment endpoints, the browser data fetch under the shareable key, the
    /// charges, the polling and the wallet flow before it shows anything. Only the 3DS screen,
    /// which sends nothing on the session, still runs; the Android SDK draws the same line.
    @Test func everyPublicMethodOfAClosedSessionThrowsAuth013() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()
        await session.close()
        let pathsBefore = StubURLProtocol.paths

        let calls: [(String, () async throws -> Void)] = [
            ("getStatus", { _ = try await session.getStatus() }),
            ("charge", { _ = try await session.charge(.cardToken("tok", browserData: Self.deviceBrowserData)) }),
            ("chargeWithCardToken", { _ = try await session.chargeWithCardToken("tok", browserData: Self.deviceBrowserData) }),
            ("chargeWithEncryptedCard", { _ = try await session.chargeWithEncryptedCard("jwe", browserData: Self.deviceBrowserData) }),
            ("completeBrowserData", { _ = try await session.completeBrowserData(Self.deviceBrowserData) }),
            ("getChargeState", { _ = try await session.getChargeState() }),
            ("awaitChargeState", { _ = try await session.awaitChargeState() }),
            ("getQrPaymentInfo", { _ = try await session.getQrPaymentInfo() }),
            ("getApplePayInfo", { _ = try await session.getApplePayInfo() }),
            ("getWalletInfo", { _ = try await session.getWalletInfo() }),
            ("chargeWithApplePay", { _ = try await session.chargeWithApplePay(browserData: Self.deviceBrowserData) }),
            ("chargeWithWallet", { _ = try await session.chargeWithWallet(browserData: Self.deviceBrowserData) }),
        ]
        for (name, call) in calls {
            do {
                try await call()
                Issue.record("\(name) should fail on a closed session")
            } catch let error as GopaySDKError {
                #expect(error.code == .authPaymentSessionClosed, "\(name)")
            } catch {
                Issue.record("\(name) threw \(error) instead of a GopaySDKError")
            }
        }
        #expect(StubURLProtocol.paths == pathsBefore)
    }

    /// A token that arrives after `close()` is not kept, and the call that waited for it ends
    /// with AUTH_013. The client holds the renewal's answer until the session is closed and
    /// ignores the cancellation, so the answer really lands in a closed session.
    @Test func aTokenThatArrivesAfterCloseIsNotKept() async throws {
        let client = HeldTokenClient()
        let session = try await PaymentSession.create(
            paymentId: "p1", paymentSecret: "secret", scope: "payment:charge",
            authApi: AuthAPI(client: client),
            publicApi: PublicAPI(client: client, clientId: "client", shareableKey: "shareable"),
            client: client, callbacks: SessionCallbacks(onClose: { _ in
                // Created outside the SDK, so there is no registry entry for the close to drop.
            })
        )
        await session.invalidateToken()

        let call = Task { try await session.getStatus() }
        await settle(until: client.isHolding)
        #expect(client.isHolding)
        await session.close()
        client.release()

        do {
            _ = try await call.value
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentSessionClosed)
        } catch {
            Issue.record("expected AUTH_013, got \(error)")
        }
        let token = await session.currentToken()
        #expect(token == nil)
    }

    @Test func completeBrowserDataReturnsWhatTheChargeWouldSend() async throws {
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

    @Test func everyOtherRequestKeepsTheSdkUserAgent() async throws {
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
                return (200, json(["id": "p1", "state": "CREATED", "amount": 1000, "currency": "CZK", "order_number": "o1", "gw_url": "https://gw.example/p", "customer": ["email": "a@b.c"]]))
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
                    : (200, json(["id": "p1", "state": "PAID", "amount": 1000, "currency": "CZK", "order_number": "o1", "gw_url": "https://gw.example/p", "customer": ["email": "a@b.c"]]))
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
                return (200, json(["id": "p1", "state": "CREATED", "amount": 1, "currency": "CZK", "order_number": "o1", "gw_url": "https://gw.example/p", "customer": ["email": "a@b.c"]]))
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
            _ = try await session.authenticate()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentSessionClosed)
        }
    }

    // MARK: GopaySDK registry

    private func sdk(clientId: String? = nil, shareableKey: String? = nil) -> GopaySDK {
        let config = GopayConfig(
            environment: .development(baseUrl: stubBaseURL),
            clientId: clientId,
            shareableKey: shareableKey
        )
        return GopaySDK(config: config, networkClient: stubbedClient()).waitingForInitSession()
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
}
