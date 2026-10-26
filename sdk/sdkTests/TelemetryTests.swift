//
//  TelemetryTests.swift
//  sdkTests
//
//  The operational data the SDK sends: where it goes, the envelope and the event shapes the
//  ingest's schema accepts, the numbering, the budgets, and what the SDK's flows report. Uploads
//  are caught by `TelemetryIngestStub`, so nothing leaves the machine.
//

import Testing
import Foundation
import PassKit
@testable import sdk

// MARK: - Ingest stub

/// Answers every upload with 204, or fails it for an endpoint made with `failing: true`, and keeps
/// what arrived per endpoint. Each test makes its own endpoint, so suites running in parallel never
/// read each other's events.
final class TelemetryIngestStub: URLProtocol {
    struct Upload {
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    private static var uploads: [String: [Upload]] = [:]
    private static var failing: Set<String> = []

    static func makeEndpoint(failing: Bool = false) -> URL {
        let url = URL(string: "https://ingest.test/\(UUID().uuidString)/events")!
        if failing {
            lock.lock(); self.failing.insert(url.absoluteString); lock.unlock()
        }
        return url
    }

    static func uploads(to url: URL) -> [Upload] {
        lock.lock(); defer { lock.unlock() }
        return uploads[url.absoluteString] ?? []
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = Telemetry.sessionConfiguration()
        configuration.protocolClasses = [TelemetryIngestStub.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        let upload = Upload(headers: request.allHTTPHeaderFields ?? [:], body: Self.readBody(of: request))
        Self.lock.lock()
        Self.uploads[key, default: []].append(upload)
        let fails = Self.failing.contains(key)
        Self.lock.unlock()
        if fails {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// A telemetry instance wired to its own stub endpoint, and the events it sent.
struct TelemetryProbe {
    let endpoint: URL
    let telemetry: Telemetry

    init(clientId: String? = "client-1", failing: Bool = false, origin: String = "cz.example.shop") {
        endpoint = TelemetryIngestStub.makeEndpoint(failing: failing)
        telemetry = Telemetry(
            endpoint: endpoint,
            clientId: clientId,
            origin: origin,
            configuration: TelemetryIngestStub.configuration()
        )
    }

    var uploads: [TelemetryIngestStub.Upload] { TelemetryIngestStub.uploads(to: endpoint) }

    /// The events sent so far, once at least `count` have arrived, each checked against the
    /// ingest's schema on the way.
    func events(_ count: Int) async -> [[String: Any]] {
        for _ in 0..<500 where uploads.count < count {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let events = uploads.compactMap { upload -> [String: Any]? in
            let body = (try? JSONSerialization.jsonObject(with: upload.body)) as? [String: Any]
            #expect(body.map { Set($0.keys) } == ["event"], "the body is {\"event\": …} and nothing else")
            return body?["event"] as? [String: Any]
        }
        #expect(events.count >= count, "expected \(count) events, got \(events.count)")
        events.forEach(TelemetrySchema.check)
        return events
    }

    /// The events once nothing more is arriving, for the tests that count what was not sent.
    func settledEvents(_ count: Int) async -> [[String: Any]] {
        _ = await events(count)
        try? await Task.sleep(nanoseconds: 200_000_000)
        return await events(count)
    }
}

/// The ingest's schema as far as the SDK must honour it: per type, the keys it knows and the ones
/// it requires, plus the attribution rule. Any other key drops the whole event on the ingest.
enum TelemetrySchema {
    static let common: Set<String> = [
        "event_type", "payment_session_id", "shareable_key", "client_id", "sdk_instance_id", "seq",
        "sdk_version", "integration", "payment_method", "flow", "error_code", "trace_id", "transaction_id",
        "origin", "duration",
    ]
    static let byType: [String: (allowed: Set<String>, required: Set<String>)] = [
        "navigation": (["navigation_type", "target"], ["navigation_type", "target"]),
        "interaction": (["interaction_type", "element_id", "error_message"], ["interaction_type", "element_id"]),
        "api_call": (["action", "http_method", "target", "status_code", "req_body", "res_body"], ["target", "status_code"]),
        "js_event": (["function_name", "params", "return_value"], ["function_name"]),
    ]
    /// Keys whose value, when present, must not be empty.
    static let nonEmpty: Set<String> = [
        "payment_session_id", "client_id", "sdk_instance_id", "sdk_version", "integration", "payment_method",
        "flow", "error_code", "http_method",
    ]

    static func check(_ event: [String: Any]) {
        guard let type = event["event_type"] as? String, let shape = byType[type] else {
            Issue.record("unknown event_type in \(event)")
            return
        }
        let keys = Set(event.keys)
        #expect(keys.isSubset(of: common.union(shape.allowed)), "keys outside the schema: \(keys.subtracting(common.union(shape.allowed)))")
        #expect(shape.required.union(["event_type", "trace_id", "origin", "duration"]).isSubset(of: keys))
        #expect(keys.contains("client_id") || keys.contains("payment_session_id"), "no attribution key")
        for key in nonEmpty {
            if let value = event[key] {
                #expect((value as? String)?.isEmpty == false, "\(key) is empty")
            }
        }
        #expect((event["seq"] as? Int).map { $0 >= 1 } == true)
        #expect(event["duration"] is NSNull || event["duration"] is Int)
    }
}

// MARK: - Emitter

/// Not serialized: every test sends to an endpoint of its own. The ones that read the process-wide
/// count of charges in flight live with the charging tests in `SessionNetworkTests`.
struct TelemetryTests {

    @Test func goesToTheIngestOfTheEnvironmentAndNowhereForADevelopmentGateway() {
        #expect(GopayEnvironment.sandbox.telemetryURL?.absoluteString == "https://lx.sandbox.gopay.com/events")
        #expect(GopayEnvironment.production.telemetryURL?.absoluteString == "https://lx.gopay.com/events")
        #expect(GopayEnvironment.development(baseURL: "https://mock.test/").telemetryURL == nil)
        #expect(Telemetry(config: GopaySDKConfig(environment: .development(baseURL: "https://gw.sandbox.gopay.com/gp-gw/api/4.0/"))).endpoint == nil)
        #expect(Telemetry.disabled.endpoint == nil)
    }

    /// Nothing in the configuration reaches the telemetry's switch, because there is none.
    @Test(arguments: [false, true])
    func isNotTheIntegratorsToTurnOff(quiet: Bool) {
        let config = GopaySDKConfig(
            environment: .production,
            clientId: quiet ? nil : "c",
            shareableKey: quiet ? nil : "k",
            enableDebugLogging: !quiet,
            errorCallback: quiet ? nil : { _ in },
            locale: quiet ? nil : "en"
        )
        #expect(Telemetry(config: config).endpoint == GopayEnvironment.production.telemetryURL)
    }

    @Test func sendsInitAsANavigationEventWithTheEnvelope() async throws {
        let probe = TelemetryProbe()
        probe.telemetry.initialized()

        let event = try #require(await probe.events(1).first)
        #expect(event["event_type"] as? String == "navigation")
        #expect(event["navigation_type"] as? String == "init")
        #expect(event["target"] is NSNull)
        #expect(event["duration"] is NSNull, "null, not a fabricated zero")
        #expect(event["client_id"] as? String == "client-1")
        #expect(event["payment_session_id"] == nil, "absent before a session, never empty")
        #expect(event["sdk_instance_id"] as? String == probe.telemetry.instanceId)
        #expect(event["seq"] as? Int == 1)
        #expect(event["sdk_version"] as? String == GopaySDK.version)
        #expect(event["integration"] as? String == "ios-sdk")
        #expect(event["origin"] as? String == "cz.example.shop")
        #expect(event["transaction_id"] as? String == Telemetry.processTransactionId)

        let upload = try #require(probe.uploads.first)
        #expect(upload.headers["Content-Type"] == "application/json")
        #expect(upload.headers["User-Agent"] == "GoPay iOS SDK \(GopaySDK.version)")
        #expect(upload.headers["Authorization"] == nil)
    }

    @Test func numbersTheEventsKeepsTheTransactionAndMintsATraceForEach() async {
        let probe = TelemetryProbe()
        probe.telemetry.initialized()
        probe.telemetry.sessionStarted(paymentId: "3273103424")
        probe.telemetry.sessionClosed(paymentId: "3273103424")

        let events = await probe.events(3)
        #expect(events.compactMap { $0["seq"] as? Int } == [1, 2, 3])
        #expect(Set(events.compactMap { $0["transaction_id"] as? String }).count == 1)
        #expect(Set(events.compactMap { $0["trace_id"] as? String }).count == 3)
        #expect(events.compactMap { $0["navigation_type"] as? String } == ["init", "navigate", "leave"])
        #expect(events[1]["flow"] as? String == "attach")
        #expect(events[1]["payment_session_id"] as? String == "3273103424")
    }

    @Test func givesEachInstanceItsOwnIdAndNumbering() async {
        let first = TelemetryProbe()
        let second = TelemetryProbe()
        first.telemetry.initialized()
        second.telemetry.initialized()

        let a = await first.events(1)
        let b = await second.events(1)
        #expect(a.first?["seq"] as? Int == 1)
        #expect(b.first?["seq"] as? Int == 1)
        #expect(a.first?["sdk_instance_id"] as? String != b.first?["sdk_instance_id"] as? String)
    }

    /// The ingest drops an event with neither attribution key, so it is never sent, and a number is
    /// only spent on an event that went: a gap means a lost event and nothing else.
    @Test func leavesNoGapForAnEventItNeverSent() async {
        let probe = TelemetryProbe(clientId: nil)
        probe.telemetry.initialized()
        probe.telemetry.sessionStarted(paymentId: "p1")
        probe.telemetry.cardFormReady(owner: NSObject())
        probe.telemetry.sessionClosed(paymentId: "p1")

        let events = await probe.settledEvents(2)
        #expect(events.count == 2)
        #expect(events.compactMap { $0["seq"] as? Int } == [1, 2])
        #expect(events.compactMap { $0["navigation_type"] as? String } == ["navigate", "leave"])
    }

    /// A poll flood spends the api_call budget and nothing else: the lifecycle and the errors still
    /// go, and the numbering skips nothing that was dropped.
    @Test func keepsTheBudgetsApart() async {
        let probe = TelemetryProbe()
        for _ in 0..<205 {
            probe.telemetry.apiCall(
                method: "GET", path: "/payments/1/charge", statusCode: 200, startedAt: Telemetry.now(),
                requestBody: nil, requestContentType: nil, responseBody: nil, responseContentType: nil,
                paymentId: "1"
            )
        }
        probe.telemetry.sessionClosed(paymentId: "1")
        probe.telemetry.error(GopaySDKError(.paymentProcessingFailed, message: "no token"), paymentId: "1")

        let events = await probe.settledEvents(202)
        #expect(events.count == 202)
        #expect(events.filter { $0["event_type"] as? String == "api_call" }.count == 200)
        #expect(events.compactMap { $0["seq"] as? Int } == Array(1...202))
        #expect(events.contains { $0["navigation_type"] as? String == "leave" })
        #expect(events.contains { $0["function_name"] as? String == "PAYMENT_003" })
    }

    @Test func capsTheLifecycleSideToo() async {
        let probe = TelemetryProbe()
        for _ in 0..<80 { probe.telemetry.initialized() }
        probe.telemetry.walletStep(.begin, status: .start, paymentId: "1")

        let events = await probe.settledEvents(76)
        #expect(events.filter { $0["event_type"] as? String == "navigation" }.count == 75)
        #expect(events.last?["function_name"] as? String == "APPLE_PAY.begin")
    }

    @Test func sendsAnApiCallWithATemplateAndNullStatusWithoutAResponse() async throws {
        let probe = TelemetryProbe()
        probe.telemetry.apiCall(
            method: "GET", path: "/payments/3273103424/qr-payment/info?format=png", statusCode: nil,
            startedAt: Telemetry.now(), requestBody: nil, requestContentType: nil, responseBody: nil,
            responseContentType: nil, paymentId: "3273103424"
        )

        let event = try #require(await probe.events(1).first)
        #expect(event["event_type"] as? String == "api_call")
        #expect(event["target"] as? String == "/payments/{id}/qr-payment/info")
        #expect(event["action"] as? String == "info")
        #expect(event["http_method"] as? String == "GET")
        #expect(event["status_code"] is NSNull)
        #expect(event["duration"] is Int)
        #expect(event["req_body"] == nil && event["res_body"] == nil)
    }

    /// The ingest takes 16 KB per request; an event that would not fit goes without its bodies.
    @Test func dropsTheBodiesOfAnEventThatWouldNotFit() throws {
        let wide = String(repeating: "😀", count: 3000)
        let event = TelemetryEvent(
            clientId: "c", sdkInstanceId: "i", sdkVersion: "1", integration: "ios-sdk", traceId: "t",
            transactionId: "x", origin: "o",
            payload: .apiCall(action: "charge", httpMethod: "POST", target: "/payments/{id}/charge", statusCode: 400,
                              requestBody: wide, responseBody: wide)
        )

        let body = try #require(TelemetryTransport.fittingBody(of: event))
        #expect(body.count <= 16 * 1024)
        let sent = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["event"] as? [String: Any])
        #expect(sent["req_body"] == nil && sent["res_body"] == nil)
        #expect(sent["status_code"] as? Int == 400)

        var small = event
        small.payload = .apiCall(action: "charge", httpMethod: "POST", target: "/payments/{id}/charge", statusCode: 400,
                                 requestBody: "{}", responseBody: "{}")
        let kept = try #require(TelemetryTransport.fittingBody(of: small))
        #expect(String(data: kept, encoding: .utf8)?.contains("req_body") == true)
    }

    @Test func neverLetsAFailingIngestReachTheCaller() async {
        let probe = TelemetryProbe(failing: true)
        probe.telemetry.initialized()
        probe.telemetry.sessionStarted(paymentId: "1")

        // Both went, both failed, nothing was retried, and the numbering went on.
        let events = await probe.settledEvents(2)
        #expect(events.count == 2)
        #expect(events.compactMap { $0["seq"] as? Int } == [1, 2])
    }

    // MARK: Card form

    @Test func reportsTheCardFormFromReadyToSubmitWithoutItsContent() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        probe.telemetry.cardFormReady(owner: owner)
        probe.telemetry.cardFormSubmitted(owner: owner)

        let events = await probe.events(2)
        let ready = events[0], submit = events[1]
        #expect(ready["function_name"] as? String == "PAYMENT_CARD.ready")
        #expect(ready["duration"] is Int, "timed from the SDK's initialization")
        #expect(ready["flow"] as? String == "return-payload")

        // That a submit happened and when; nothing else, not a length, not a hash.
        #expect(Set(submit.keys) == [
            "event_type", "client_id", "sdk_instance_id", "seq", "sdk_version", "integration", "payment_method",
            "flow", "trace_id", "transaction_id", "origin", "duration", "interaction_type", "element_id",
        ])
        #expect(submit["interaction_type"] as? String == "submit")
        #expect(submit["element_id"] as? String == "card-form")
        #expect(submit["payment_method"] as? String == "card")
        #expect(submit["duration"] is Int)
    }

    @Test func timesASubmitWithoutAReadyAsNull() async throws {
        let probe = TelemetryProbe()
        probe.telemetry.cardFormSubmitted(owner: nil)
        let event = try #require(await probe.events(1).first)
        #expect(event["duration"] is NSNull)
    }

    // MARK: Wallet

    @Test func namesAWalletStepAfterTheMethodAndPutsItsOutcomeInParams() async throws {
        let probe = TelemetryProbe()
        probe.telemetry.walletStep(.begin, status: .start, paymentId: "1")
        probe.telemetry.walletStep(
            .paymentAuthorized, status: .failure, paymentId: "1", detail: "card 4111111111111111",
            startedAt: Telemetry.now()
        )
        probe.telemetry.walletStep(.completePayment, status: .success, paymentId: "1", params: ["result": .string("failure")])

        let events = await probe.events(3)
        #expect(events[0]["function_name"] as? String == "APPLE_PAY.begin")
        #expect(events[0]["params"] as? String == #"{"status":"start"}"#)
        #expect(events[0]["return_value"] as? String == "start")
        #expect(events[0]["duration"] is NSNull)
        #expect(events[1]["return_value"] as? String == "card [redacted]")
        #expect(events[1]["duration"] is Int)
        #expect(events[2]["params"] as? String == #"{"result":"failure","status":"success"}"#)
        #expect(events.allSatisfy { $0["payment_session_id"] as? String == "1" })
    }

    @Test func reportsAnAvailabilityAnswerEitherWayButARepeatedProbeOnlyOnAChange() async {
        let probe = TelemetryProbe()
        for available in [true, true, true, false, false, true] {
            probe.telemetry.walletAvailability(
                caller: "canUseApplePay", available: available, startedAt: Telemetry.now(), onlyWhenChanged: true
            )
        }

        let events = await probe.settledEvents(3)
        #expect(events.count == 3)
        #expect(events.compactMap { $0["return_value"] as? String } == ["available", "unsupported-device", "available"])
        #expect(events[1]["params"] as? String == #"{"available":false,"caller":"canUseApplePay"}"#)
        #expect(events.allSatisfy { $0["function_name"] as? String == "APPLE_PAY.readyToPay" })
    }

    @Test func sendsTheApplePaySubmitWithoutADuration() async throws {
        let probe = TelemetryProbe()
        probe.telemetry.walletSubmitted(paymentId: "1")
        let event = try #require(await probe.events(1).first)
        #expect(event["element_id"] as? String == "applepay-button")
        #expect(event["payment_method"] as? String == "applepay")
        #expect(event["duration"] is NSNull)
    }

    // MARK: 3DS

    @Test func reportsTheVerificationAsTheLeaveWithTheAcsButNotItsQuery() async throws {
        let probe = TelemetryProbe()
        probe.telemetry.verificationOpened(
            redirectURL: URL(string: "https://acs.example-bank.com/challenge?creq=SECRETCREQ")!, paymentId: "1"
        )
        let event = try #require(await probe.events(1).first)
        #expect(event["navigation_type"] as? String == "leave")
        #expect(event["flow"] as? String == "3ds-redirect")
        #expect(event["target"] as? String == "https://acs.example-bank.com/challenge")
    }

    // MARK: Errors

    @Test func reportsAnSdkErrorAsAJsEventWithAScrubbedMessage() async throws {
        let probe = TelemetryProbe()
        probe.telemetry.error(
            GopaySDKError(.validationInvalidInput, message: "card 4111111111111111 for jan@example.com"),
            paymentId: nil
        )

        let event = try #require(await probe.events(1).first)
        #expect(event["event_type"] as? String == "js_event")
        #expect(event["function_name"] as? String == "VALIDATION_007")
        #expect(event["error_code"] as? String == "VALIDATION_007")
        #expect(event["return_value"] as? String == "card [redacted] for [redacted]")
        #expect(event["duration"] is NSNull)
        #expect(event["params"] == nil)
    }

    /// The request already went as an `api_call` with its status; a second event would count it twice.
    @Test func leavesAGatewayHttpErrorToItsApiCall() async {
        let probe = TelemetryProbe()
        probe.telemetry.error(GopaySDKError(.networkServerError, message: "Failed: HTTP 503", httpStatus: 503), paymentId: "1")
        probe.telemetry.error(GopaySDKError(.authPaymentCredentialsInvalid, message: "rejected", httpStatus: 401), paymentId: "1")
        probe.telemetry.error(
            GopaySDKError(.paymentVerificationUnreachable, message: "The 3DS page: HTTP 404", httpStatus: 404), paymentId: "1"
        )

        let events = await probe.settledEvents(1)
        #expect(events.count == 1, "only the 3DS page's status is not a gateway answer")
        #expect(events.first?["function_name"] as? String == "PAYMENT_010")
        #expect(events.first?["params"] as? String == #"{"status":404}"#)
    }

    @Test func sendsOnlyTheTextTheSdkWrote() throws {
        let gateway = GopaySDKError(
            .networkClientError, message: "Failed to fetch browser data: HTTP 400: Customer jan@shop.cz unknown",
            httpStatus: 400, gatewayError: GopayGatewayError(message: "Customer jan@shop.cz unknown")
        )
        #expect(Telemetry.sdkAuthoredMessage(of: gateway) == "Failed to fetch browser data: HTTP 400")

        let charge = try JSONDecoder().decode(
            ChargePaymentResponse.self, from: Data(#"{"id":"1","state":"FAILED","fail_reason":"Card blocked by issuer"}"#.utf8)
        )
        let declined = GopaySDKError(.paymentDeclined, message: "Charge failed: Card blocked by issuer", chargeState: charge)
        #expect(Telemetry.sdkAuthoredMessage(of: declined) == "Charge failed")

        let offline = GopaySDKError.transport(URLError(.notConnectedToInternet))
        #expect(Telemetry.sdkAuthoredMessage(of: offline) == "The request got no HTTP response: io")
    }

    @Test func labelsAFailureByItsCodeOrTypeNeverItsMessage() {
        #expect(Telemetry.failureLabel(GopaySDKError(.paymentProcessingFailed, message: "x")) == "PAYMENT_003")
        #expect(Telemetry.failureLabel(URLError(.timedOut)) == "timeout")
        #expect(Telemetry.failureLabel(URLError(.cannotFindHost)) == "dns")
        #expect(Telemetry.failureLabel(URLError(.dnsLookupFailed)) == "dns")
        #expect(Telemetry.failureLabel(URLError(.networkConnectionLost)) == "io")
        #expect(Telemetry.failureLabel(CancellationError()) == "error")
        #expect(Telemetry.failureLabel(NSError(domain: "merchant.secret.domain", code: 1)) == "error")
    }

    // MARK: Debug line, budgets per session, attribution

    @Test func logsOneLineWithoutContentPerEventOnlyWithDebugLogging() async {
        let lines = Lines()
        let endpoint = TelemetryIngestStub.makeEndpoint()
        let debug = Telemetry(
            endpoint: endpoint, clientId: "c", debugLogging: true, debugSink: { lines.append($0) },
            configuration: TelemetryIngestStub.configuration()
        )
        let quiet = Telemetry(
            endpoint: TelemetryIngestStub.makeEndpoint(), clientId: "c", debugLogging: false,
            debugSink: { lines.append("quiet: \($0)") }, configuration: TelemetryIngestStub.configuration()
        )

        debug.initialized()
        debug.error(GopaySDKError(.validationInvalidInput, message: "card 4111111111111111"), paymentId: nil)
        quiet.initialized()
        for _ in 0..<300 where TelemetryIngestStub.uploads(to: endpoint).count < 2 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(lines.all == [
            "[GopaySDK] telemetry: navigation init",
            "[GopaySDK] telemetry: js_event VALIDATION_007",
        ])
    }

    /// The instance lives as long as the app, so a budget spent by earlier payments must not
    /// silence the next one.
    @Test func startsTheBudgetsOverWithEveryPaymentSession() async {
        let probe = TelemetryProbe()
        for _ in 0..<80 { probe.telemetry.initialized() }
        probe.telemetry.sessionStarted(paymentId: "p2")
        probe.telemetry.cardFormReady(owner: NSObject())
        for _ in 0..<80 { probe.telemetry.sessionClosed(paymentId: "p2") }

        let events = await probe.settledEvents(150)
        #expect(events.count == 150, "75 inits, then a new budget of 75 opened by the navigate")
        #expect(events.filter { $0["navigation_type"] as? String == "init" }.count == 75)
        #expect(events[75]["navigation_type"] as? String == "navigate")
        #expect(events.filter { $0["navigation_type"] as? String == "leave" }.count == 73)
        #expect(events.compactMap { $0["seq"] as? Int } == Array(1...150))
    }

    /// An event with no payment of its own belongs to the last session started and not closed,
    /// as on Android and in the browser SDK.
    @Test func attributesAnEventWithoutAPaymentToTheLastOpenSession() async {
        let probe = TelemetryProbe(clientId: nil)
        probe.telemetry.cardFormReady(owner: NSObject())
        probe.telemetry.attach(paymentId: "p1")
        probe.telemetry.attach(paymentId: "p2")
        probe.telemetry.cardFormReady(owner: NSObject())
        probe.telemetry.detach(paymentId: "p2")
        probe.telemetry.error(GopaySDKError(.validationInvalidInput, message: "x"), paymentId: nil)
        probe.telemetry.sessionClosed(paymentId: "p1")
        probe.telemetry.walletAvailability(caller: "isWalletAvailable", available: true, startedAt: Telemetry.now())

        // Without a client id, the first ready and the last probe have nothing to belong to.
        let events = await probe.settledEvents(3)
        #expect(events.count == 3)
        #expect(events.compactMap { $0["payment_session_id"] as? String } == ["p2", "p1", "p1"])
        #expect(events.compactMap { ($0["function_name"] ?? $0["navigation_type"]) as? String } == [
            "PAYMENT_CARD.ready", "VALIDATION_007", "leave",
        ])
    }

    @Test func reportsAnOverlongParamsObjectByItsSize() {
        let params = Telemetry.describeParams(["a": .string(String(repeating: "x", count: 500))])
        #expect(params?.hasPrefix(#"{"a":"#) == true)
        var many: [String: Telemetry.Param] = [:]
        for index in 0..<20 { many["k\(index)"] = .string(String(repeating: "x", count: 400)) }
        #expect(Telemetry.describeParams(many)?.hasPrefix(#"{"truncated":"#) == true)
    }
}

// MARK: - Apple Pay flow

/// A token carrying the given payment data.
private final class TelemetryStubToken: PKPaymentToken {
    private let data: Data
    init(paymentData: Data) {
        self.data = paymentData
        super.init()
    }
    override var paymentData: Data { data }
}

private final class TelemetryStubPayment: PKPayment {
    private let stubToken: PKPaymentToken
    init(paymentData: Data) {
        self.stubToken = TelemetryStubToken(paymentData: paymentData)
        super.init()
    }
    override var token: PKPaymentToken { stubToken }
}

@MainActor
struct ApplePayTelemetryTests {

    @Test func reportsASheetClosedWithoutAnAuthorizationAsTheCancel() async throws {
        let probe = TelemetryProbe()
        let coordinator = GopayApplePayCoordinator(
            appInfo: try applePayAppInfo(),
            telemetry: ApplePayTelemetry(telemetry: probe.telemetry, paymentId: "p1"),
            charge: { _, _ in },
            completion: { _ in }
        )

        coordinator.sheetDidClose()

        let event = try #require(await probe.events(1).first)
        #expect(event["function_name"] as? String == "APPLE_PAY.cancel")
        #expect(event["params"] as? String == #"{"status":"info"}"#)
        #expect(event["payment_session_id"] as? String == "p1")
    }

    @Test func reportsAnUnusableTokenAsAFailedAuthorizationAndTellsTheSheet() async throws {
        let probe = TelemetryProbe()
        let info = try applePayAppInfo(networks: ["visa"])
        let coordinator = GopayApplePayCoordinator(
            appInfo: info,
            telemetry: ApplePayTelemetry(telemetry: probe.telemetry, paymentId: "p1"),
            charge: { _, _ in Issue.record("an unusable token must not be charged") },
            completion: { _ in }
        )

        coordinator.paymentAuthorizationController(
            PKPaymentAuthorizationController(paymentRequest: GopayApplePayCoordinator.makePaymentRequest(from: info)),
            didAuthorizePayment: TelemetryStubPayment(paymentData: Data()),
            handler: { _ in }
        )
        coordinator.sheetDidClose()

        let events = await probe.settledEvents(2)
        #expect(events.compactMap { $0["function_name"] as? String } == ["APPLE_PAY.paymentAuthorized", "APPLE_PAY.completePayment"])
        #expect(events[0]["return_value"] as? String == "PAYMENT_003")
        #expect(events[1]["params"] as? String == #"{"result":"failure","status":"success"}"#)
        #expect(!events.contains { $0["event_type"] as? String == "interaction" }, "no usable token, no submit")
    }

    @Test func reportsAChargedAuthorizationFromSubmitToTheSheetsResult() async throws {
        let probe = TelemetryProbe()
        let info = try applePayAppInfo(networks: ["visa"])
        let coordinator = GopayApplePayCoordinator(
            appInfo: info,
            telemetry: ApplePayTelemetry(telemetry: probe.telemetry, paymentId: "p1"),
            charge: { _, done in done(.failure(GopaySDKError(.networkServerError, message: "HTTP 503", httpStatus: 503))) },
            completion: { _ in }
        )
        let token = Data("""
        {"version":"EC_v1","data":"d","signature":"s",
         "header":{"ephemeralPublicKey":"epk","publicKeyHash":"pkh","transactionId":"tx"}}
        """.utf8)

        coordinator.paymentAuthorizationController(
            PKPaymentAuthorizationController(paymentRequest: GopayApplePayCoordinator.makePaymentRequest(from: info)),
            didAuthorizePayment: TelemetryStubPayment(paymentData: token),
            handler: { _ in }
        )

        // The authorization succeeded with the token; the charge made from it is the checkout.
        let events = await probe.events(5)
        #expect(events[0]["element_id"] as? String == "applepay-button")
        #expect(events.dropFirst().compactMap { $0["function_name"] as? String } == [
            "APPLE_PAY.paymentAuthorized", "APPLE_PAY.checkout", "APPLE_PAY.checkout", "APPLE_PAY.completePayment",
        ])
        #expect(events[1]["params"] as? String == #"{"status":"success"}"#)
        #expect(events[2]["params"] as? String == #"{"status":"start"}"#)
        #expect(events[3]["params"] as? String == #"{"status":"failure"}"#)
        #expect(events[3]["return_value"] as? String == "NETWORK_003")
        #expect(events[3]["duration"] is Int, "timed from the charge being sent")
        #expect(events[4]["params"] as? String == #"{"result":"failure","status":"success"}"#)
    }

    @Test func reportsASheetPassKitWouldNotShowAsAFailedBegin() async throws {
        let probe = TelemetryProbe()
        var results: [Result<ChargePaymentResponse, Error>] = []
        let coordinator = GopayApplePayCoordinator(
            appInfo: try applePayAppInfo(),
            telemetry: ApplePayTelemetry(telemetry: probe.telemetry, paymentId: "p1"),
            charge: { _, _ in Issue.record("nothing should be charged") },
            completion: { results.append($0) }
        )

        coordinator.sheetWasNotPresented()

        let event = try #require(await probe.events(1).first)
        #expect(event["function_name"] as? String == "APPLE_PAY.begin")
        #expect(event["params"] as? String == #"{"status":"failure"}"#)
        #expect(event["return_value"] as? String == "PAYMENT_004")
        for _ in 0..<100 where results.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard case .failure(let error as GopaySDKError) = results.first else {
            Issue.record("expected the call to end with PAYMENT_004")
            return
        }
        #expect(error.code == .paymentMethodUnavailable)
    }
}

// MARK: - Through the gateway

extension SessionNetworkTests {

    private static let telemetryBrowserData = BrowserData(
        language: "cs-CZ", timezone: -60, screenWidth: 1170, screenHeight: 2532, colorDepth: 24,
        userAgent: "Mozilla/5.0 (iPhone)", javascriptEnabled: true
    )

    private func sdk(telemetry: Telemetry) -> GopaySDK {
        GopaySDK(
            config: GopaySDKConfig(environment: .development(baseURL: stubBaseURL), clientId: "client", shareableKey: "shareable"),
            networkClient: stubbedClient(),
            telemetry: telemetry
        )
    }

    @Test func reportsEveryGatewayRequestOfAPaymentAndItsLifecycle() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let probe = TelemetryProbe(clientId: "client")
        let sdk = sdk(telemetry: probe.telemetry)

        let session = try await sdk.startPaymentSession(paymentId: "3273103424", paymentSecret: "s3cret")
        _ = try await session.charge(
            .encryptedCard("JWE-PAYLOAD", browserData: Self.telemetryBrowserData, challengePreference: .auto)
        )
        await session.close()

        let events = await probe.settledEvents(5)
        #expect(events.count == 5)
        let token = events[0], navigate = events[1], browserData = events[2], charge = events[3], leave = events[4]

        #expect(token["target"] as? String == "/oauth2/token")
        #expect(token["http_method"] as? String == "POST")
        #expect(token["status_code"] as? Int == 200)
        #expect(token["payment_session_id"] as? String == "3273103424")
        #expect(token["res_body"] == nil, "a token pair is never reported")
        let form = try #require((token["req_body"] as? String).flatMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String] })
        #expect(form == ["grant_type": "payment_credentials", "scope": "payment:charge payment:read"])

        #expect(navigate["navigation_type"] as? String == "navigate")
        #expect(navigate["flow"] as? String == "attach")

        #expect(browserData["target"] as? String == "/cards/browser-data")
        #expect(browserData["payment_session_id"] as? String == "3273103424")

        #expect(charge["target"] as? String == "/payments/{id}/charge")
        #expect(charge["action"] as? String == "charge")
        #expect(charge["status_code"] as? Int == 200)
        let sent = try #require(charge["req_body"] as? String)
        #expect(!sent.contains("JWE-PAYLOAD"))
        #expect(!sent.contains("192.0.2.42"))
        #expect(!(charge["target"] as? String ?? "").contains("3273103424"))

        #expect(leave["navigation_type"] as? String == "leave")
        #expect(leave["payment_session_id"] as? String == "3273103424")
    }

    @Test func reportsAGatewayHttpErrorOnlyAsItsApiCall() async throws {
        StubURLProtocol.reset { req in
            (req.url?.path ?? "").hasSuffix("oauth2/token") ? tokenResponse() : (503, json(["message": "down"]))
        }
        let probe = TelemetryProbe(clientId: "client")
        // Held for the whole test: a session reports through the SDK that made it, while it lives.
        let sdk = sdk(telemetry: probe.telemetry)
        let session = try await sdk.startPaymentSession(paymentId: "1", paymentSecret: "s")

        await #expect(throws: GopaySDKError.self) { _ = try await session.getChargeState() }

        let events = await probe.settledEvents(3)
        #expect(events.count == 3)
        #expect(events[2]["target"] as? String == "/payments/{id}/charge")
        #expect(events[2]["status_code"] as? Int == 503)
        #expect(!events.contains { $0["event_type"] as? String == "js_event" })
    }

    @Test func reportsARequestWithoutAResponseAsNullStatusAndItsTransportError() async throws {
        let isOffline = Flag()
        StubURLProtocol.reset(transportError: .notConnectedToInternet) { req in
            if isOffline.value { return (StubURLProtocol.transportFailure, Data()) }
            return (req.url?.path ?? "").hasSuffix("oauth2/token") ? tokenResponse() : (404, Data())
        }
        let probe = TelemetryProbe(clientId: "client")
        let sdk = sdk(telemetry: probe.telemetry)
        let session = try await sdk.startPaymentSession(paymentId: "1", paymentSecret: "s")
        isOffline.value = true

        await #expect(throws: GopaySDKError.self) { _ = try await session.getStatus() }

        let events = await probe.settledEvents(4)
        let call = try #require(events.first { $0["target"] as? String == "/payments/{id}" })
        #expect(call["status_code"] is NSNull)
        #expect(call["action"] as? String == "payments")
        let error = try #require(events.first { $0["event_type"] as? String == "js_event" })
        #expect(error["function_name"] as? String == "NETWORK_004")
        #expect(error["payment_session_id"] as? String == "1")
        #expect(error["return_value"] as? String == "The request got no HTTP response: io")
    }

    @Test func reportsAnErrorBeforeAnySessionWithoutAPaymentSessionId() async throws {
        let probe = TelemetryProbe(clientId: "client")
        let sdk = sdk(telemetry: probe.telemetry)

        await #expect(throws: GopaySDKError.self) { _ = try await sdk.startPaymentSession(paymentId: " ", paymentSecret: "s") }

        let event = try #require(await probe.events(1).first)
        #expect(event["function_name"] as? String == "VALIDATION_007")
        #expect(event["payment_session_id"] == nil)
        #expect(event["client_id"] as? String == "client")
    }

    /// The telemetry is queued, so a payment never waits on an ingest that does not answer.
    @Test func neverHoldsAPaymentForAnUnreachableIngest() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let probe = TelemetryProbe(clientId: "client", failing: true)
        let session = try await sdk(telemetry: probe.telemetry).startPaymentSession(paymentId: "1", paymentSecret: "s")

        let response = try await session.charge(
            .encryptedCard("jwe", browserData: Self.telemetryBrowserData, challengePreference: .auto)
        )

        #expect(response.id == "ch_1")
    }

    // MARK: Card form unmount (reads the process-wide charge count, so serialized with the charges)

    @Test func reportsAnUnmountTimedFromItsReadyWithWhetherAChargeWasRunning() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        probe.telemetry.cardFormReady(owner: owner)
        probe.telemetry.cardFormUnmounted(owner: owner)
        Telemetry.chargesInFlight.start()
        probe.telemetry.cardFormUnmounted(owner: owner)
        Telemetry.chargesInFlight.finish()

        let events = await probe.events(3)
        let idle = events[1], aborted = events[2]
        #expect(idle["function_name"] as? String == "PAYMENT_CARD.unmount")
        #expect(idle["return_value"] as? String == "idle")
        #expect(idle["params"] as? String == #"{"charge_in_flight":false}"#)
        #expect(idle["duration"] is Int)
        #expect(aborted["return_value"] as? String == "charge-aborted")
        #expect(aborted["params"] as? String == #"{"charge_in_flight":true}"#)
        #expect(aborted["duration"] is NSNull, "a form that never became ready has nothing to time from")
    }

    // MARK: Paths, retries, sessions

    @Test func reportsThePathBelowTheGatewaysBasePath() async throws {
        StubURLProtocol.reset { _ in (200, json(["id": "1"])) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = DefaultNetworkClient(
            baseURL: "https://gw.sandbox.gopay.com/gp-gw/api/4.0/", configuration: configuration
        )
        let probe = TelemetryProbe()
        var request = URLRequest(url: try #require(client.makeURL(path: "payments/3273103424/charge")))
        request.httpMethod = "GET"

        _ = try await client.send(request, telemetry: probe.telemetry, paymentId: "3273103424")

        let event = try #require(await probe.events(1).first)
        #expect(event["target"] as? String == "/payments/{id}/charge")
        #expect(StubURLProtocol.paths == ["/gp-gw/api/4.0/payments/3273103424/charge"])
    }

    @Test func reportsBothRequestsOfARetryAfterA401() async throws {
        let reads = Counter()
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            return reads.increment() == 1 ? (401, Data()) : (200, json(["id": 1, "state": "CREATED"]))
        }
        let probe = TelemetryProbe(clientId: "client")
        let sdk = sdk(telemetry: probe.telemetry)
        let session = try await sdk.startPaymentSession(paymentId: "1", paymentSecret: "s")

        _ = try? await session.getStatus()

        let events = await probe.settledEvents(5)
        let calls = events.filter { $0["event_type"] as? String == "api_call" }
        #expect(calls.compactMap { $0["target"] as? String } == ["/oauth2/token", "/payments/{id}", "/oauth2/token", "/payments/{id}"])
        #expect(calls.compactMap { $0["status_code"] as? Int } == [200, 401, 200, 200])
    }

    @Test func reportsADuplicateStartAsItsErrorWithoutALeave() async throws {
        StubURLProtocol.reset { _ in tokenResponse() }
        let probe = TelemetryProbe(clientId: "client")
        let sdk = sdk(telemetry: probe.telemetry)
        let first = try await sdk.startPaymentSession(paymentId: "dup", paymentSecret: "s")

        await #expect(throws: GopaySDKError.self) { _ = try await sdk.startPaymentSession(paymentId: "dup", paymentSecret: "s") }
        await first.close()

        let events = await probe.settledEvents(5)
        #expect(events.compactMap { ($0["navigation_type"] ?? $0["function_name"] ?? $0["action"]) as? String } == [
            "token", "navigate", "token", "AUTH_012", "leave",
        ])
        #expect(events.allSatisfy { $0["payment_session_id"] as? String == "dup" })
    }

    /// A token exchange that gets no response is the SDK's own error, so it goes as a js_event
    /// as well as the api_call, and both name the payment the start was for.
    @Test func reportsATokenRequestWithoutAResponseWithItsPaymentId() async throws {
        StubURLProtocol.reset(transportError: .notConnectedToInternet) { _ in (StubURLProtocol.transportFailure, Data()) }
        let probe = TelemetryProbe(clientId: "client")
        let sdk = sdk(telemetry: probe.telemetry)

        await #expect(throws: GopaySDKError.self) { _ = try await sdk.startPaymentSession(paymentId: "p7", paymentSecret: "s") }

        let events = await probe.settledEvents(2)
        #expect(events.count == 2)
        #expect(events[0]["target"] as? String == "/oauth2/token")
        #expect(events[0]["status_code"] is NSNull)
        #expect(events[1]["function_name"] as? String == "NETWORK_004")
        #expect(events.allSatisfy { $0["payment_session_id"] as? String == "p7" })
    }

    /// A session nobody closed leaves the attribution once it is gone.
    @Test func dropsASessionReleasedWithoutCloseFromTheAttribution() async throws {
        StubURLProtocol.reset { _ in tokenResponse() }
        let probe = TelemetryProbe(clientId: nil)
        probe.telemetry.attach(paymentId: "p8")
        var session: PaymentSession? = try await PaymentSession.create(
            paymentId: "p8", paymentSecret: "s", scope: "payment:charge",
            authApi: AuthAPI(client: stubbedClient()),
            publicApi: PublicAPI(client: stubbedClient(), clientId: nil, shareableKey: nil),
            client: stubbedClient(),
            callbacks: SessionCallbacks(onClose: { _ in }, telemetry: probe.telemetry)
        )
        weak var released = session
        probe.telemetry.cardFormReady(owner: NSObject())
        session = nil
        #expect(released == nil)
        probe.telemetry.cardFormReady(owner: NSObject())

        let events = await probe.settledEvents(1)
        #expect(events.count == 1, "the second ready has nothing left to belong to")
        #expect(events.first?["payment_session_id"] as? String == "p8")
    }

    /// A start that fails is still about its payment (the contract's section 4).
    @Test func reportsAFailedStartWithItsPaymentId() async throws {
        StubURLProtocol.reset { _ in (401, json(["message": "nope"])) }
        let probe = TelemetryProbe(clientId: "client")
        let sdk = sdk(telemetry: probe.telemetry)

        await #expect(throws: GopaySDKError.self) { _ = try await sdk.startPaymentSession(paymentId: "p9", paymentSecret: "s") }
        sdk.report(GopaySDKError(.validationInvalidInput, message: "later, outside any session"))

        let events = await probe.settledEvents(2)
        #expect(events.count == 2, "AUTH_010 is the token call's own answer, not a js_event")
        #expect(events[0]["payment_session_id"] as? String == "p9")
        #expect(events[0]["status_code"] as? Int == 401)
        #expect(events[1]["payment_session_id"] == nil, "the failed start is not attributed to later")
    }

    // MARK: Submit and the registered form

    @Test func timesASubmitFromTheReadyOfTheFormRegisteredUnderItsId() async throws {
        let key = try TestEncryptionKey()
        StubURLProtocol.reset { req in
            (req.url?.path.hasSuffix("cards/public-key") ?? false) ? (200, key.publicJWKJSON) : (404, Data())
        }
        let probe = TelemetryProbe(clientId: "c")
        let sdk = sdk(telemetry: probe.telemetry)
        let card = GopayCardFormData(cardNumber: "4444333322221111", expirationMonth: "12", expirationYear: "30", cvv: "123")
        let shown = CardFormOwner()
        let other = CardFormOwner()
        probe.telemetry.cardFormReady(owner: other)
        sdk.registerCardFormReset({}, formId: "f1", owner: shown)
        sdk.updateCardFormData(card, formId: "f1")

        _ = try await sdk.submitCardForm(formId: "f1")
        probe.telemetry.cardFormReady(owner: shown)
        sdk.updateCardFormData(card, formId: "f1")
        _ = try await sdk.submitCardForm(formId: "f1")

        let submits = await probe.settledEvents(5).filter { $0["event_type"] as? String == "interaction" }
        #expect(submits.count == 2)
        #expect(submits[0]["duration"] is NSNull, "the registered form never became ready; another one did")
        #expect(submits[1]["duration"] is Int)
    }
}

/// Lines a test collects from any thread.
final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock(); lines.append(line); lock.unlock()
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }
}

// MARK: - The public initialize

/// In the locale suite because ``GopaySDK/initialize(with:)`` writes the SDK-wide default locale
/// those tests read, and only a suite of its own is serialized.
extension GopayLocalesTests {

    @Test func initializeSendsInitAndHandsOneInstanceToEveryApi() async throws {
        let first = TelemetryProbe(clientId: "c")
        let second = TelemetryProbe(clientId: "c")
        let probes = [first, second]
        let made = Counter()
        let sdk = GopaySDK()
        sdk.makeTelemetry = { _ in probes[made.increment() - 1].telemetry }
        // A host that does not resolve: every request ends without a response, and still reports.
        let config = GopaySDKConfig(
            environment: .development(baseURL: "https://telemetry-test.invalid/"), clientId: "c", shareableKey: "k"
        )

        sdk.initialize(with: config)
        _ = try? await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        _ = try? await sdk.encryptCardData(
            GopayCardData(cardPan: "4444333322221111", expMonth: "12", expYear: "30", cvv: "123")
        )
        sdk.initialize(with: config)

        let events = await first.settledEvents(3)
        #expect(events.first?["navigation_type"] as? String == "init")
        let calls = events.filter { $0["event_type"] as? String == "api_call" }
        #expect(calls.compactMap { $0["target"] as? String } == ["/oauth2/token", "/cards/public-key"])
        #expect(calls.allSatisfy { $0["status_code"] is NSNull })
        #expect(Set(events.compactMap { $0["sdk_instance_id"] as? String }) == [first.telemetry.instanceId])

        let again = try #require(await second.events(1).first)
        #expect(again["navigation_type"] as? String == "init")
        #expect(again["sdk_instance_id"] as? String == second.telemetry.instanceId)
        #expect(first.telemetry.instanceId != second.telemetry.instanceId)
    }
}
