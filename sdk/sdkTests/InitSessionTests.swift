//
//  InitSessionTests.swift
//  sdkTests
//
//  `POST /payments/{payment_id}/init-session` (GPMOB-194): sent once a session has started,
//  waited for by the start (GPMOB-206), and quiet whatever it gets back. The Android SDK
//  (GPMOB-195, GPMOB-207) runs the same cases.
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

    /// Browser data with the gateway's fields filled in, so a charge goes out without the fetch.
    private static let filledBrowserData = BrowserData(
        language: "cs-CZ", timezone: -60, screenWidth: 1170, screenHeight: 2532, colorDepth: 24,
        userAgent: "ua", acceptHeader: "{}", javascriptEnabled: true, ip: "192.0.2.42"
    )

    /// An SDK over the shared stub whose `errorCallback` collects into `reported`, with the
    /// device languages pinned to ``languages``.
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

    /// A token, the payment's status for any payment, and `initSession` for its init-session,
    /// given only once `gate`, when there is one, opens.
    private func initSessionGateway(_ initSession: InitSessionAnswer = .http(204), gate: StubGate? = nil) {
        StubURLProtocol.reset(transportError: initSession.transportError) { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.hasSuffix("/init-session") {
                gate?.wait()
                return (initSession.status, Data())
            }
            let id = path.split(separator: "/").last.map(String.init) ?? ""
            return (200, json(["id": id, "state": "CREATED", "amount": 1, "currency": "CZK", "order_number": "o1", "gw_url": "https://gw.example/p", "customer": ["email": "a@b.c"]]))
        }
    }

    // MARK: Request

    @Test func sendsOneInitSessionWithTheSessionTokenSDKAndDeviceLanguages() async throws {
        initSessionGateway()
        let reported = ReportedErrors()
        let sdk = initSessionSDK(reported)

        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
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

    /// The start does not end while the gateway sits on the init-session, and ends once it
    /// answers.
    @Test func theStartReturnsOnlyOnceTheInitSessionIsAnswered() async throws {
        let gate = StubGate()
        initSessionGateway(gate: gate)
        let reported = ReportedErrors()
        let sdk = initSessionSDK(reported)
        let returned = Flag()

        let start = Task {
            defer { returned.value = true }
            return try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        }
        await expectSettled(StubURLProtocol.requestCount(forPathSuffix: "/init-session") == 1)
        // The answer cannot have come: the stub's thread is still held in the gate.
        #expect(!returned.value)
        gate.open()
        let session = try await start.value

        #expect(returned.value)
        #expect(try await session.getStatus().id == "p1")
        #expect(reported.all.isEmpty)
        await session.close()
    }

    /// A charge made right after the start reaches the gateway only once the init-session has
    /// been answered: the stub notes, when the charge arrives, whether that answer has gone out.
    @Test func aChargeRightAfterTheStartGoesAfterTheInitSession() async throws {
        let gate = StubGate()
        let initSessionAnswered = Flag()
        let chargeCameAfterTheAnswer = Flag()
        let chargeArrived = Flag()
        let answeredWhenTheStartReturned = Flag()
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.hasSuffix("/init-session") {
                gate.wait()
                initSessionAnswered.value = true
                return (204, Data())
            }
            if path.hasSuffix("/charge") {
                chargeCameAfterTheAnswer.value = initSessionAnswered.value
                chargeArrived.value = true
            }
            // The payment for any other path, the charge too: not a charge, but only the order counts.
            return (200, json(["id": "p1", "state": "CREATED", "amount": 1, "currency": "CZK", "order_number": "o1", "gw_url": "https://gw.example/p", "customer": ["email": "a@b.c"]]))
        }
        let reported = ReportedErrors()
        let sdk = initSessionSDK(reported)

        let payment = Task {
            let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
            // A start that did not wait returns while the gate is still shut, however fast the
            // charge after it is.
            answeredWhenTheStartReturned.value = initSessionAnswered.value
            _ = try? await session.chargeWithCardToken("token", browserData: Self.filledBrowserData)
            return session
        }
        await expectSettled(StubURLProtocol.requestCount(forPathSuffix: "/init-session") == 1)
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/charge") == 0)
        gate.open()
        let session = try await payment.value

        #expect(answeredWhenTheStartReturned.value, "the start returned before the init-session was answered")
        #expect(chargeArrived.value)
        #expect(chargeCameAfterTheAnswer.value, "the charge overtook the init-session")
        await session.close()
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
        await #expect(throws: GopaySDKError.self) { _ = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s") }

        #expect(StubURLProtocol.requestCount(forPathSuffix: "/payments/p1/init-session") == 1)
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/payments/p2/init-session") == 1)
        #expect(reported.codes == [.authPaymentSessionAlreadyExists], "only the duplicate start itself")
    }

    /// Without `payment:read` the gateway would answer with a 403, so nothing is sent and the
    /// start has nothing to wait for.
    @Test func aScopeWithoutPaymentReadSendsNoneAndDoesNotWait() async throws {
        initSessionGateway()
        let reported = ReportedErrors()
        let sdk = initSessionSDK(reported)

        _ = try await sdk.startPaymentSession(paymentId: "p2", paymentSecret: "s", scope: "payment:read")
        // An init-session from here on is never answered: a start that sent one would wait out the
        // 10 s timeout and the count below would catch it.
        StubURLProtocol.holdAnswers(forPathSuffix: "/init-session")
        let chargeOnly = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s", scope: "payment:charge")

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

    @Test func closeDuringTheWaitCancelsTheInitSessionAndReturnsTheClosedSession() async throws {
        initSessionGateway()
        StubURLProtocol.holdAnswers(forPathSuffix: "/init-session")
        let reported = ReportedErrors()
        let probe = TelemetryProbe(clientId: "client")
        let sdk = initSessionSDK(reported, telemetry: probe.telemetry)

        let start = Task { try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s") }
        await expectSettled(StubURLProtocol.requestCount(forPathSuffix: "/init-session") == 1)
        await sdk.getPaymentSession("p1")?.close()
        // Ends with the cancellation, not with the request's 10 s timeout.
        let session = try await start.value

        #expect(await !session.holdsCredentials, "the start hands back the closed session")
        #expect(await sdk.getPaymentSession("p1") == nil)
        await expectSettled(StubURLProtocol.stoppedPaths == ["/payments/p1/init-session"])
        #expect(reported.all.isEmpty)
        let events = await probe.settledEvents(3)
        #expect(events.compactMap { ($0["navigation_type"] ?? $0["target"]) as? String } == [
            "/oauth2/token", "navigate", "leave",
        ], "a request given up on is neither an api_call nor an error")

        initSessionGateway()
        let again = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        #expect(reported.all.isEmpty)
        await again.close()
    }

    /// A caller that gives up has no session to close, so the start closes it: the payment is
    /// free for the next start.
    @Test func cancellingTheCallerDuringTheWaitClosesTheSessionAndThrowsTheCancellation() async throws {
        initSessionGateway()
        StubURLProtocol.holdAnswers(forPathSuffix: "/init-session")
        let reported = ReportedErrors()
        let probe = TelemetryProbe(clientId: "client")
        let sdk = initSessionSDK(reported, telemetry: probe.telemetry)

        let start = Task { try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s") }
        await expectSettled(StubURLProtocol.requestCount(forPathSuffix: "/init-session") == 1)
        start.cancel()
        let result = await start.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await sdk.getPaymentSession("p1") == nil)
        await expectSettled(StubURLProtocol.stoppedPaths == ["/payments/p1/init-session"])
        #expect(reported.all.isEmpty)
        let events = await probe.settledEvents(3)
        #expect(events.compactMap { ($0["navigation_type"] ?? $0["target"]) as? String } == [
            "/oauth2/token", "navigate", "leave",
        ], "a request given up on is neither an api_call nor an error")
        #expect(!events.contains { $0["event_type"] as? String == "js_event" })

        initSessionGateway()
        let again = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        #expect(reported.all.isEmpty)
        await again.close()
    }

    // MARK: Telemetry (a numeric payment id, which the telemetry reports as {id})

    @Test(arguments: [404, 409, 500])
    func anErrorStatusIsOnlyTheApiCall(_ status: Int) async throws {
        initSessionGateway(.http(status))
        let reported = ReportedErrors()
        let probe = TelemetryProbe(clientId: "client")
        let sdk = initSessionSDK(reported, telemetry: probe.telemetry)

        let session = try await sdk.startPaymentSession(paymentId: "3273103424", paymentSecret: "s")

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
