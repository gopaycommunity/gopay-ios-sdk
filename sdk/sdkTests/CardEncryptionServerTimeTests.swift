//
//  CardEncryptionServerTimeTests.swift
//  sdkTests
//
//  The card JWE takes its `iat` / `exp` from the gateway's `Date` header on
//  `GET /cards/public-key`, fetched afresh for every encryption (GPMOB-155).
//

import Testing
import Foundation
@testable import sdk

// MARK: - Date header parsing

/// One input of the table both SDKs run their `Date` parser over, and what it should read as.
struct HTTPDateCase: CustomTestStringConvertible, Sendable {
    let header: String
    /// Unix seconds, or `nil` when the header has to be refused.
    let seconds: Int?

    var testDescription: String { "\"\(header)\"" }
}

/// Shared with the Android `HttpDateTest`; a change here belongs there as well.
let httpDateCases: [HTTPDateCase] = [
    HTTPDateCase(header: "Wed, 30 Sep 2026 17:34:17 GMT", seconds: 1_790_789_657),
    HTTPDateCase(header: "Thu, 29 Feb 2024 12:00:00 GMT", seconds: 1_709_208_000),
    HTTPDateCase(header: "Sun, 29 Feb 2032 12:00:00 GMT", seconds: 1_961_668_800),
    HTTPDateCase(header: "Thu, 01 Jan 1970 00:00:00 GMT", seconds: 0),
    // Obsolete forms RFC 9110 lets a recipient read; the gateway does not send them.
    HTTPDateCase(header: "Wednesday, 30-Sep-26 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Wed Sep 30 17:34:17 2026", seconds: nil),
    // Zones other than the literal GMT.
    HTTPDateCase(header: "Wed, 30 Sep 2026 17:34:17 +0000", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 17:34:17 UTC", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 17:34:17 CET", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 17:34:17 gmt", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 17:34:17 GMTX", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 17:34:17", seconds: nil),
    // Dates and times that do not exist.
    HTTPDateCase(header: "Wed, 31 Sep 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Sun, 29 Feb 2026 12:00:00 GMT", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 24:00:00 GMT", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 17:34:60 GMT", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 25:34:17 GMT", seconds: nil),
    // A day of the week that does not match the date.
    HTTPDateCase(header: "Thu, 30 Sep 2026 17:34:17 GMT", seconds: nil),
    // Shapes the pattern refuses.
    HTTPDateCase(header: "Wed, 30 Sept 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Foo 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "wed, 30 sep 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "WED, 30 SEP 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Thu, 1 Oct 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Wed, 1 Oct 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 7:34:17 GMT", seconds: nil),
    HTTPDateCase(header: " Wed, 30 Sep 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 17:34:17 GMT ", seconds: nil),
    HTTPDateCase(header: "Wed,  30 Sep 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Wed 30 Sep 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 26 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 02026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "Wed, 30 Sep 2026 17:34:17 GMT trailing", seconds: nil),
    HTTPDateCase(header: "Wed, ٣٠ Sep 2026 17:34:17 GMT", seconds: nil),
    HTTPDateCase(header: "yesterday", seconds: nil),
    HTTPDateCase(header: "1790789657", seconds: nil),
    HTTPDateCase(header: "", seconds: nil),
]

struct HTTPDateParsingTests {
    @Test(arguments: httpDateCases)
    func eachHeaderReadsAsTheTableSays(_ testCase: HTTPDateCase) {
        let parsed = parseHTTPDate(testCase.header).map { Int($0.timeIntervalSince1970) }
        #expect(parsed == testCase.seconds)
    }

    @Test func aMissingHeaderReadsAsNoTime() {
        #expect(parseHTTPDate(nil) == nil)
    }
}

// MARK: - Encryption against the stub
//
// An extension of `SessionNetworkTests`, like the card form lifecycle tests, so these join its
// `@Suite(.serialized)` and never race other tests for the shared `StubURLProtocol` state.

extension SessionNetworkTests {

    private static let serverDateHeader = "Wed, 30 Sep 2026 17:34:17 GMT"
    private static let serverSeconds = 1_790_789_657

    private func encryptionSDK(
        clientId: String? = "c",
        shareableKey: String? = "k",
        debugLogging: Bool = false
    ) -> GopaySDK {
        let client: DefaultNetworkClient = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            return DefaultNetworkClient(baseURL: "https://stub.test/", configuration: configuration)
        }()
        let config = GopaySDKConfig(
            environment: .development(baseURL: "https://stub.test/"),
            clientId: clientId,
            shareableKey: shareableKey,
            enableDebugLogging: debugLogging
        )
        return GopaySDK(config: config, networkClient: client)
    }

    private var card: GopayCardData {
        GopayCardData(cardPan: "4444333322221111", expMonth: "12", expYear: "30", cvv: "123")
    }

    private func serveKey(_ key: TestEncryptionKey, headers: [String: String], delay: TimeInterval = 0) {
        StubURLProtocol.reset(delay: delay, headers: headers) { req in
            (req.url?.path.hasSuffix("cards/public-key") ?? false) ? (200, key.publicJWKJSON) : (404, Data())
        }
    }

    @Test func theJweTakesItsIatFromTheDateHeader() async throws {
        let key = try TestEncryptionKey()
        // A fixed past date: the gateway's clock and the device's are a long way apart, as they
        // are on a device whose clock is set wrong.
        serveKey(key, headers: ["Date": Self.serverDateHeader])
        let sdk = encryptionSDK()

        let claims = try key.decryptClaims(try await sdk.encryptCardData(card))

        #expect(claims["iat"] as? Int == Self.serverSeconds)
        #expect(claims["exp"] as? Int == Self.serverSeconds + 600)
        #expect((claims["jti"] as? String)?.hasPrefix("ios-") == true)
        #expect(claims["client_id"] as? String == "c")
    }

    @Test func theJweFollowsAServerClockAnHourAheadOfTheDevice() async throws {
        let key = try TestEncryptionKey()
        let serverTime = Date().addingTimeInterval(3600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        serveKey(key, headers: ["Date": formatter.string(from: serverTime)])
        let sdk = encryptionSDK()

        let claims = try key.decryptClaims(try await sdk.encryptCardData(card))

        #expect(claims["iat"] as? Int == Int(serverTime.timeIntervalSince1970))
        #expect(claims["exp"] as? Int == Int(serverTime.timeIntervalSince1970) + 600)
    }

    @Test func everyEncryptionFetchesTheKeyAgain() async throws {
        let key = try TestEncryptionKey()
        serveKey(key, headers: ["Date": Self.serverDateHeader])
        let sdk = encryptionSDK()

        _ = try await sdk.encryptCardData(card)
        _ = try await sdk.encryptCardData(card)

        #expect(StubURLProtocol.requestCount(forPathSuffix: "cards/public-key") == 2)
    }

    @Test func concurrentEncryptionsEachFetchTheirOwnKey() async throws {
        let key = try TestEncryptionKey()
        serveKey(key, headers: ["Date": Self.serverDateHeader], delay: 0.1)
        let sdk = encryptionSDK()

        async let a = sdk.encryptCardData(card)
        async let b = sdk.encryptCardData(card)
        _ = try await (a, b)

        #expect(StubURLProtocol.requestCount(forPathSuffix: "cards/public-key") == 2)
    }

    @Test func withoutADateHeaderTheJweUsesTheDeviceClockAndWarns() async throws {
        let key = try TestEncryptionKey()
        serveKey(key, headers: [:])
        let sdk = encryptionSDK(debugLogging: true)
        var warnings: [String] = []
        sdk.warnSink = { warnings.append($0) }

        let before = Int(Date().timeIntervalSince1970)
        let claims = try key.decryptClaims(try await sdk.encryptCardData(card))
        let after = Int(Date().timeIntervalSince1970)

        let iat = try #require(claims["iat"] as? Int)
        #expect((before...after).contains(iat))
        #expect(claims["exp"] as? Int == iat + 600)
        #expect(warnings == [GopaySDK.missingDateWarning])
    }

    @Test func anUnreadableDateHeaderFallsBackToTheDeviceClockAndWarns() async throws {
        let key = try TestEncryptionKey()
        serveKey(key, headers: ["Date": "Wed, 30 Sep 2026 19:34:17 +0200"])
        let sdk = encryptionSDK(debugLogging: true)
        var warnings: [String] = []
        sdk.warnSink = { warnings.append($0) }

        let before = Int(Date().timeIntervalSince1970)
        let claims = try key.decryptClaims(try await sdk.encryptCardData(card))
        let after = Int(Date().timeIntervalSince1970)

        let iat = try #require(claims["iat"] as? Int)
        #expect((before...after).contains(iat))
        #expect(claims["exp"] as? Int == iat + 600)
        #expect(warnings == [GopaySDK.missingDateWarning])
    }

    @Test func aUsableDateHeaderLogsNoWarning() async throws {
        let key = try TestEncryptionKey()
        serveKey(key, headers: ["Date": Self.serverDateHeader])
        let sdk = encryptionSDK(debugLogging: true)
        var warnings: [String] = []
        sdk.warnSink = { warnings.append($0) }

        _ = try await sdk.encryptCardData(card)

        #expect(warnings.isEmpty)
    }

    @Test func missingCredentialsFailWithoutARequest() async throws {
        StubURLProtocol.reset { _ in (200, Data()) }
        let sdk = encryptionSDK(clientId: nil, shareableKey: nil)

        do {
            _ = try await sdk.encryptCardData(card)
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authShareableKeyMissing)
        }
        #expect(StubURLProtocol.paths.isEmpty)
    }

    @Test func aServerErrorOnTheKeyKeepsItsCode() async throws {
        StubURLProtocol.reset(headers: ["Date": Self.serverDateHeader]) { _ in (500, Data()) }
        let sdk = encryptionSDK()

        do {
            _ = try await sdk.encryptCardData(card)
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .networkServerError)
            #expect(error.httpStatus == 500)
        }
    }

    @Test func anEncryptionCancelledWhileTheKeyFetchFailsReportsNothing() async throws {
        StubURLProtocol.reset(delay: 0.3, headers: ["Date": Self.serverDateHeader]) { _ in (500, Data()) }
        var reported: [Error] = []
        let config = GopaySDKConfig(
            environment: .development(baseURL: "https://stub.test/"),
            clientId: "c",
            shareableKey: "k",
            errorCallback: { reported.append($0) }
        )
        let client: DefaultNetworkClient = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            return DefaultNetworkClient(baseURL: "https://stub.test/", configuration: configuration)
        }()
        let sdk = GopaySDK(config: config, networkClient: client)

        let encryption = Task { [card] in try await sdk.encryptCardData(card) }
        try await Task.sleep(nanoseconds: 100_000_000)
        encryption.cancel()

        await #expect(throws: CancellationError.self) { try await encryption.value }
        #expect(reported.isEmpty)
    }

    @Test func aSubmitCancelledDuringTheKeyFetchKeepsTheCardAndReportsNothing() async throws {
        let key = try TestEncryptionKey()
        serveKey(key, headers: ["Date": Self.serverDateHeader], delay: 0.3)
        var reported: [Error] = []
        let config = GopaySDKConfig(
            environment: .development(baseURL: "https://stub.test/"),
            clientId: "c",
            shareableKey: "k",
            errorCallback: { reported.append($0) }
        )
        let client: DefaultNetworkClient = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            return DefaultNetworkClient(baseURL: "https://stub.test/", configuration: configuration)
        }()
        let sdk = GopaySDK(config: config, networkClient: client)
        let formData = GopayCardFormData(
            cardNumber: "4444333322221111", expirationMonth: "12", expirationYear: "30", cvv: "123"
        )
        sdk.updateCardFormData(formData, formId: "f1")

        let submit = Task { try await sdk.submitCardForm(formId: "f1") }
        try await Task.sleep(nanoseconds: 100_000_000)
        submit.cancel()

        await #expect(throws: CancellationError.self) { try await submit.value }
        #expect(sdk.internalCardFormData["f1"] != nil)
        #expect(reported.isEmpty)
    }
}
