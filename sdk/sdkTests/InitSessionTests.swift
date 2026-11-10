//
//  InitSessionTests.swift
//  sdkTests
//
//  `POST /payments/{payment_id}/init-session` (GPMOB-194): sent once a session has started, not
//  waited for, and quiet whatever it gets back. The Android SDK (GPMOB-195) runs the same cases.
//

import Testing
import Foundation
@testable import sdk

/// What the stub gateway answers the init-session with.
struct InitSessionAnswer: CustomTestStringConvertible, Sendable {
    let status: Int
    let transportError: URLError.Code

    static func http(_ status: Int) -> InitSessionAnswer {
        InitSessionAnswer(status: status, transportError: .networkConnectionLost)
    }

    static func noResponse(_ error: URLError.Code) -> InitSessionAnswer {
        InitSessionAnswer(status: StubURLProtocol.transportFailure, transportError: error)
    }

    var testDescription: String {
        status == StubURLProtocol.transportFailure ? "no response (\(transportError.rawValue))" : "HTTP \(status)"
    }
}

// Part of the serialized `SessionNetworkTests`: every SDK here is built over the shared stub.
extension SessionNetworkTests {

    private static let languages = ["cs-CZ", "cs", "en-GB"]

    /// An SDK over the shared stub whose `errorCallback` collects into `reported`, with the
    /// device languages pinned to ``languages``. Unlike the other suites' SDKs it does not wait
    /// for the init-session at the start: these tests wait for it themselves, or check that
    /// nothing does.
    private func initSessionSDK(_ reported: ReportedErrors, telemetry: Telemetry = .disabled) -> GopaySDK {
        let sdk = GopaySDK(
            config: GopayConfig(
                environment: .development(baseUrl: stubBaseURL),
                clientId: "client", shareableKey: "shareable",
                errorCallback: { reported.append($0) }
            ),
            networkClient: stubbedClient(),
            telemetry: telemetry
        )
        sdk.deviceLanguages = { Self.languages }
        return sdk
    }

    /// A token, the payment's status for any payment, and `initSession` for its init-session.
    private func initSessionGateway(_ initSession: InitSessionAnswer = .http(204)) {
        StubURLProtocol.reset(transportError: initSession.transportError) { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.hasSuffix("/init-session") { return (initSession.status, Data()) }
            let id = path.split(separator: "/").last.map(String.init) ?? ""
            return (200, json(["id": id, "state": "CREATED", "amount": 1, "currency": "CZK"]))
        }
    }

    // MARK: Request

    @Test func sendsOneInitSessionWithTheSessionTokenSDKAndDeviceLanguages() async throws {
        initSessionGateway()
        let reported = ReportedErrors()
        let sdk = initSessionSDK(reported)

        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        await session.initSessionTask?.value
        _ = try await session.getStatus()

        let sent = StubURLProtocol.requests(forPathSuffix: "/payments/p1/init-session")
        #expect(sent.count == 1)
        let request = try #require(sent.first)
        #expect(request.method == "POST")
        #expect(request.header("Content-Type") == "application/json")
        #expect(request.header("Accept-Language") == "cs-CZ,cs;q=0.9,en-GB;q=0.8")
        #expect(request.timeoutInterval == 10)
        #expect(request.jsonBody as? [String: String] == ["client_type": "SDK_IOS", "client_version": GopaySDK.version])
        let authorization = try #require(request.header("Authorization"))
        #expect(authorization.hasPrefix("Bearer "))
        #expect(StubURLProtocol.requests(forPathSuffix: "/payments/p1").first?.header("Authorization") == authorization)
        #expect(StubURLProtocol.paths.first?.hasSuffix("oauth2/token") == true, "the token comes first")
        #expect(reported.all.isEmpty)
    }

    /// `startPaymentSession` returns, and the session works, while the gateway sits on the
    /// init-session.
    @Test func doesNotWaitForTheInitSession() async throws {
        initSessionGateway()
        StubURLProtocol.holdAnswers(forPathSuffix: "/init-session")
        let reported = ReportedErrors()
        let sdk = initSessionSDK(reported)

        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        let status = try await session.getStatus()
        _ = try await session.getChargeState()

        #expect(status.id == "p1")
        // Still hanging: a start that waited would have seen it time out and be stopped.
        await expectSettled(StubURLProtocol.requestCount(forPathSuffix: "/init-session") == 1)
        #expect(StubURLProtocol.stoppedPaths.isEmpty)
        await session.close()
        await session.initSessionTask?.value
        await expectSettled(StubURLProtocol.stoppedPaths == ["/payments/p1/init-session"])
        #expect(reported.all.isEmpty)
    }

    // MARK: Failures are quiet

    @Test(arguments: [
        InitSessionAnswer.http(400), .http(403), .http(404), .http(409), .http(500),
        .noResponse(.networkConnectionLost), .noResponse(.notConnectedToInternet), .noResponse(.timedOut),
    ])
    func aFailedInitSessionReachesNoCallbackAndStopsNothing(_ answer: InitSessionAnswer) async throws {
        initSessionGateway(answer)
        let reported = ReportedErrors()
        let sdk = initSessionSDK(reported)

        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        await session.initSessionTask?.value
        let status = try await session.getStatus()

        #expect(status.id == "p1")
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/init-session") == 1, "no retry")
        #expect(reported.all.isEmpty)
        await session.close()
    }

    /// A 401 is not the session's token going stale for the payment: no second token exchange,
    /// and the next call goes with the same token.
    @Test func a401OnTheInitSessionLeavesTheSessionTokenAlone() async throws {
        initSessionGateway(.http(401))
        let reported = ReportedErrors()
        let sdk = initSessionSDK(reported)

        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        await session.initSessionTask?.value
        _ = try await session.getStatus()

        #expect(StubURLProtocol.requestCount(forPathSuffix: "oauth2/token") == 1)
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/init-session") == 1)
        let initSession = StubURLProtocol.requests(forPathSuffix: "/init-session").first?.header("Authorization")
        let read = StubURLProtocol.requests(forPathSuffix: "/payments/p1").first?.header("Authorization")
        #expect(initSession != nil)
        #expect(read == initSession)
        #expect(reported.all.isEmpty)
    }

    // MARK: Once per session

    @Test func twoPaymentsSendTwoAndADuplicateSessionNone() async throws {
        initSessionGateway()
        let reported = ReportedErrors()
        let sdk = initSessionSDK(reported)

        let first = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        let second = try await sdk.startPaymentSession(paymentId: "p2", paymentSecret: "s")
        await first.initSessionTask?.value
        await second.initSessionTask?.value
        await #expect(throws: GopaySDKError.self) { _ = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s") }

        #expect(StubURLProtocol.requestCount(forPathSuffix: "/payments/p1/init-session") == 1)
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/payments/p2/init-session") == 1)
        #expect(reported.codes == [.authPaymentSessionAlreadyExists], "only the duplicate start itself")
    }

    /// Without `payment:read` the gateway would answer with a 403, so nothing is sent.
    @Test func aScopeWithoutPaymentReadSendsNone() async throws {
        initSessionGateway()
        let reported = ReportedErrors()
        let sdk = initSessionSDK(reported)

        let chargeOnly = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s", scope: "payment:charge")
        let readOnly = try await sdk.startPaymentSession(paymentId: "p2", paymentSecret: "s", scope: "payment:read")
        await readOnly.initSessionTask?.value

        #expect(await chargeOnly.initSessionTask == nil)
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/payments/p1/init-session") == 0)
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/payments/p2/init-session") == 1)
        #expect(reported.all.isEmpty)
    }

    // MARK: Close

    /// `close()` before the request has left: the data task is cancelled without ever being
    /// started, and the call still ends, with the cancellation, instead of waiting forever for a
    /// completion that never comes.
    @Test func aRequestCancelledBeforeItLeavesIsNeverSent() async throws {
        initSessionGateway()
        let client = stubbedClient()
        var request = URLRequest(url: try #require(client.makeURL(path: "payments/p1/init-session")))
        request.httpMethod = "POST"
        let ended = Flag()
        let call = Task { () -> Error? in
            defer { ended.value = true }
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await client.send(request, cancellable: true)
                return nil
            } catch {
                return error
            }
        }

        await expectSettled(ended.value, "the cancelled call never ended")
        #expect(await call.value is CancellationError)
        #expect(StubURLProtocol.paths.isEmpty, "nothing reached the gateway")
    }

    @Test func closeCancelsAHangingInitSessionAndReportsNothing() async throws {
        initSessionGateway()
        StubURLProtocol.holdAnswers(forPathSuffix: "/init-session")
        let reported = ReportedErrors()
        let probe = TelemetryProbe(clientId: "client")
        let sdk = initSessionSDK(reported, telemetry: probe.telemetry)

        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        await expectSettled(StubURLProtocol.requestCount(forPathSuffix: "/init-session") == 1)
        await session.close()
        // Ends with the cancellation, not with the request's 10 s timeout.
        await session.initSessionTask?.value

        await expectSettled(StubURLProtocol.stoppedPaths == ["/payments/p1/init-session"])
        #expect(reported.all.isEmpty)
        let events = await probe.settledEvents(3)
        #expect(events.compactMap { ($0["navigation_type"] ?? $0["target"]) as? String } == [
            "/oauth2/token", "navigate", "leave",
        ], "a request given up on is neither an api_call nor an error")
    }

    // MARK: Telemetry (a numeric payment id, which the telemetry reports as {id})

    @Test(arguments: [404, 409, 500])
    func anErrorStatusIsOnlyTheApiCall(_ status: Int) async throws {
        initSessionGateway(.http(status))
        let reported = ReportedErrors()
        let probe = TelemetryProbe(clientId: "client")
        let sdk = initSessionSDK(reported, telemetry: probe.telemetry)

        let session = try await sdk.startPaymentSession(paymentId: "3273103424", paymentSecret: "s")
        await session.initSessionTask?.value

        let events = await probe.settledEvents(3)
        #expect(events.count == 3)
        let call = try #require(events.first { $0["target"] as? String == "/payments/{id}/init-session" })
        #expect(call["event_type"] as? String == "api_call")
        #expect(call["action"] as? String == "init-session")
        #expect(call["http_method"] as? String == "POST")
        #expect(call["status_code"] as? Int == status)
        #expect(call["payment_session_id"] as? String == "3273103424")
        #expect(!events.contains { $0["event_type"] as? String == "js_event" })
        await session.close()
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut])
    func noResponseIsANullStatusAndOneErrorEvent(_ transportError: URLError.Code) async throws {
        initSessionGateway(.noResponse(transportError))
        let reported = ReportedErrors()
        let probe = TelemetryProbe(clientId: "client")
        let sdk = initSessionSDK(reported, telemetry: probe.telemetry)

        let session = try await sdk.startPaymentSession(paymentId: "3273103424", paymentSecret: "s")
        await session.initSessionTask?.value

        let events = await probe.settledEvents(4)
        #expect(events.count == 4)
        let call = try #require(events.first { $0["target"] as? String == "/payments/{id}/init-session" })
        #expect(call["status_code"] is NSNull)
        let errors = events.filter { $0["event_type"] as? String == "js_event" }
        #expect(errors.count == 1)
        let code = try #require(errors.first?["function_name"] as? String)
        #expect(code == (transportError == .timedOut ? "NETWORK_001" : "NETWORK_004"))
        #expect(errors.first?["payment_session_id"] as? String == "3273103424")
        #expect(reported.all.isEmpty, "the error goes to the telemetry, not to the integrator")
        await session.close()
    }
}

// MARK: - Accept-Language

/// The value is the browser SDK's `buildAcceptLanguage` for the same list.
struct AcceptLanguageHeaderTests {

    @Test func oneLanguageGoesAlone() {
        #expect(acceptLanguageHeader(["cs-CZ"]) == "cs-CZ")
    }

    @Test func laterLanguagesFallByATenth() {
        #expect(acceptLanguageHeader(["cs-CZ", "cs", "en-GB"]) == "cs-CZ,cs;q=0.9,en-GB;q=0.8")
        // browser-sdk/tests/unit/browser-data.test.ts, and the Android AcceptLanguageTest.
        #expect(acceptLanguageHeader(["cs-CZ", "cs", "en"]) == "cs-CZ,cs;q=0.9,en;q=0.8")
    }

    @Test func theWeightStopsAtATenthFromTheTenthLanguageOn() {
        let languages = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"]
        // node: languages.map((l, i) => i === 0 ? l : `${l};q=${Math.max(1 - i * 0.1, 0.1).toFixed(1)}`).join(',')
        #expect(acceptLanguageHeader(languages)
            == "a,b;q=0.9,c;q=0.8,d;q=0.7,e;q=0.6,f;q=0.5,g;q=0.4,h;q=0.3,i;q=0.2,j;q=0.1,k;q=0.1,l;q=0.1")
    }

    @Test func duplicatesStay() {
        #expect(acceptLanguageHeader(["en", "en"]) == "en,en;q=0.9")
    }

    @Test func noLanguageFallsBackToTheCurrentOne() {
        #expect(acceptLanguageHeader([], fallback: "de-DE") == "de-DE")
        #expect(acceptLanguageHeader([]) == currentLanguageTag())
    }

    @Test func aTagThatCannotGoInAHeaderIsLeftOut() {
        #expect(acceptLanguageHeader(["čeština", "cs-CZ", "en;q=1", "", "-cs", "cs--CZ", "de-"]) == "cs-CZ")
        #expect(acceptLanguageHeader(["x;y", "cs-CZ", "ü", "en-GB"]) == "cs-CZ,en-GB;q=0.9", "weights follow what is left")
        #expect(acceptLanguageHeader(["čeština"], fallback: "sk-SK") == "sk-SK")
        #expect(acceptLanguageHeader(["cs-CZ", "čeština", "", "en"]) == "cs-CZ,en;q=0.9")
        #expect(acceptLanguageHeader(["x y"], fallback: "en-GB") == "en-GB")
        #expect(acceptLanguageHeader(["čeština"], fallback: "") == nil)
    }

    @Test func theCurrentLanguageIsABCP47Tag() {
        #expect(!currentLanguageTag().contains("_"))
        #expect(!currentLanguageTag().contains("@"))
    }
}
