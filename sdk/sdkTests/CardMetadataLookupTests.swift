//
//  CardMetadataLookupTests.swift
//  sdkTests
//
//  `POST /cards/bin-lookup` behind `submitCardFormWithMetadata` (GPMOB-202): what goes out, how
//  strictly the answer is read, and that nothing that goes wrong is more than "no metadata". The
//  eight digits are card data, so no warning carries them and the operational data never gets the
//  request. The Android SDK tests the same cases.
//

import Testing
import Foundation
@testable import sdk

struct CardMetadataLookupTests {

    /// The sandbox test card and its first eight digits.
    private static let pan = "4444444444444448"
    private static let bin = "44444444"

    private static let full = #"{"scheme":"VISA","corporate":false,"brand":"GOLD","service_type":"DEBIT","#
        + #""issuer":"Example Bank, a.s.","issuer_country":"CZE"}"#

    private let warnings = Locked<[String]>([])

    /// The lookup over the SDK's own `PublicAPI`, the transport scripted. Its limit never passes
    /// unless a test gives it a clock.
    private func lookup(
        over gateway: ScriptedGateway,
        clientId: String? = "client-1",
        shareableKey: String? = "key-1",
        telemetry: Telemetry = .disabled,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in try await untilCancelled() }
    ) -> CardMetadataLookup {
        let warnings = self.warnings
        return CardMetadataLookup(
            publicAPI: PublicAPI(client: gateway, clientId: clientId, shareableKey: shareableKey, telemetry: telemetry),
            sleep: sleep,
            warn: { warnings.value.append($0) }
        )
    }

    private func lookUp(_ status: Int, _ body: String) async throws -> CardMetadata? {
        try await lookup(over: ScriptedGateway { _ in (status, body) }).lookUp(cardNumber: Self.pan)
    }

    /// `found` is nothing, and the one warning names `reason` and no card digits.
    private func expectNoMetadata(
        _ reason: String, _ found: CardMetadata?, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(found == nil, sourceLocation: sourceLocation)
        #expect(warnings.value == [CardMetadataLookup.warning(reason)], sourceLocation: sourceLocation)
        #expect(
            warnings.value.allSatisfy { !$0.contains(Self.bin) },
            "the warning carries no card digits", sourceLocation: sourceLocation
        )
        warnings.value = []
    }

    // MARK: The request

    @Test func theLookupPostsTheFirstEightDigitsWithTheShareableKey() async throws {
        let gateway = ScriptedGateway { _ in (200, Self.full) }

        _ = try await lookup(over: gateway).lookUp(cardNumber: Self.pan)

        let request = try #require(gateway.requests.first)
        #expect(gateway.requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/cards/bin-lookup")
        #expect(request.url?.query == nil)
        let basic = Data("client-1:key-1".utf8).base64EncodedString()
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(basic)")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")
        #expect(request.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"bin":"44444444"}"#)
        #expect(warnings.value.isEmpty)
    }

    @Test func aNumberShorterThanEightDigitsOrWithAnythingButDigitsIsNotLookedUp() async throws {
        let gateway = ScriptedGateway { _ in (200, Self.full) }
        let lookup = lookup(over: gateway)

        #expect(try await lookup.lookUp(cardNumber: "4444444") == nil)
        #expect(try await lookup.lookUp(cardNumber: "4444 4444 4444 4448") == nil)
        #expect(try await lookup.lookUp(cardNumber: "") == nil)
        // Digits of another script are digits to `Character.isNumber`, not to the gateway.
        #expect(try await lookup.lookUp(cardNumber: "٤٤٤٤٤٤٤٤٤٤٤٤٤٤٤٨") == nil)
        #expect(gateway.requests.isEmpty, "must not be sent")
        #expect(warnings.value.isEmpty)
    }

    // MARK: The answer

    @Test func aFullAnswerIsReadFieldByField() async throws {
        #expect(try await lookUp(200, Self.full) == CardMetadata(
            scheme: .visa,
            corporate: false,
            brand: "GOLD",
            serviceType: .debit,
            issuer: "Example Bank, a.s.",
            issuerCountry: "CZE"
        ))
        #expect(warnings.value.isEmpty)
    }

    @Test func aMinimalAnswerHasTheTwoRequiredFieldsAndNothingElse() async throws {
        #expect(
            try await lookUp(200, #"{"scheme":"MASTERCARD","corporate":true}"#)
                == CardMetadata(scheme: .mastercard, corporate: true)
        )
        #expect(
            try await lookUp(200, #"{"scheme":"MASTERCARD","corporate":true,"service_type":"CREDIT","brand":null}"#)
                == CardMetadata(scheme: .mastercard, corporate: true, serviceType: .credit)
        )
    }

    @Test func anHttpErrorIsNoMetadata() async throws {
        expectNoMetadata(
            "HTTP 404", try await lookUp(404, #"{"code":404,"error":"NOT_FOUND","message":"Resource not found"}"#)
        )
        expectNoMetadata("HTTP 500", try await lookUp(500, ""))
        expectNoMetadata("HTTP 401", try await lookUp(401, #"{"error":"unauthorized"}"#))
    }

    /// The transport's failure reaches the lookup as the SDK's error, and the warning names its
    /// code; the message, which is the system's, stays out.
    @Test func aRequestThatGotNoResponseIsNoMetadata() async throws {
        let gateway = ScriptedGateway { _ in
            throw GopaySDKError.transport(URLError(.notConnectedToInternet))
        }

        expectNoMetadata("NETWORK_004", try await lookup(over: gateway).lookUp(cardNumber: Self.pan))
    }

    /// A failure that is not the SDK's is named by its type alone.
    @Test func aForeignFailureIsNoMetadataAndItsMessageIsNotPrinted() async throws {
        struct Unreachable: Error, CustomStringConvertible {
            let description = "unreachable 44444444"
        }
        let gateway = ScriptedGateway { _ in throw Unreachable() }

        expectNoMetadata("Unreachable", try await lookup(over: gateway).lookUp(cardNumber: Self.pan))
    }

    @Test func missingCredentialsAreNoMetadataTheEncryptionReportsThem() async throws {
        let gateway = ScriptedGateway { _ in (200, Self.full) }

        let found = try await lookup(over: gateway, shareableKey: nil).lookUp(cardNumber: Self.pan)

        expectNoMetadata("AUTH_011", found)
        #expect(gateway.requests.isEmpty)
    }

    @Test func anAnswerThatCannotBeReadIsNoMetadata() async throws {
        for body in ["", "<html>captive portal</html>", #"{"scheme":"#, "[]", "null", #""VISA""#, "12"] {
            expectNoMetadata("the answer could not be read", try await lookUp(200, body))
        }
    }

    @Test func anAnswerWithoutAKnownSchemeOrABooleanCorporateIsNoMetadata() async throws {
        let bodies = [
            #"{"scheme":"AMEX","corporate":false}"#,
            #"{"scheme":"visa","corporate":false}"#,
            #"{"scheme":1,"corporate":false}"#,
            #"{"scheme":null,"corporate":false}"#,
            #"{"corporate":false,"brand":"GOLD"}"#,
            #"{"scheme":"VISA"}"#,
            #"{"scheme":"VISA","corporate":"false"}"#,
            #"{"scheme":"VISA","corporate":0}"#,
            #"{"scheme":"VISA","corporate":1}"#,
            #"{"scheme":"VISA","corporate":null}"#,
        ]
        for body in bodies {
            expectNoMetadata("the answer could not be read", try await lookUp(200, body))
        }
    }

    @Test func anOptionalFieldOutsideItsDocumentedShapeIsLeftOutTheRestStays() async throws {
        let base = CardMetadata(scheme: .visa, corporate: false)
        func read(_ fields: String) async throws -> CardMetadata? {
            try await lookUp(200, #"{"scheme":"VISA","corporate":false,"# + fields + "}")
        }
        let long = String(repeating: "x", count: 200)

        #expect(try await read(#""brand":123"#) == base, "a number")
        #expect(try await read(#""brand":"""#) == base, "empty")
        #expect(try await read(#""service_type":"PREPAID""#) == base, "a value the SDK does not know")
        #expect(try await read(#""service_type":"debit""#) == base, "lower case")
        #expect(try await read(#""issuer":"\#(long)x""#) == base, "201 characters")
        #expect(
            try await read(#""issuer":"\#(long)""#) == CardMetadata(scheme: .visa, corporate: false, issuer: long),
            "200 characters"
        )
        #expect(try await read(#""issuer":{"name":"Bank"}"#) == base, "an object")
        #expect(try await read(#""issuer_country":"cze""#) == base, "lower case")
        #expect(try await read(#""issuer_country":"CZ""#) == base, "alpha-2")
        #expect(try await read(#""issuer_country":"CZEX""#) == base, "four letters")
        // One bad field takes only itself.
        #expect(
            try await read(#""brand":"GOLD","service_type":"PREPAID","issuer":7,"issuer_country":"CZE""#)
                == CardMetadata(scheme: .visa, corporate: false, brand: "GOLD", issuerCountry: "CZE")
        )
        #expect(warnings.value.isEmpty)
    }

    @Test func noOtherFieldOfTheAnswerIsPassedOn() async throws {
        let found = try await lookUp(
            200, #"{"scheme":"VISA","corporate":false,"bin":"44444444","card_token":"tok_1","extra":{"a":1}}"#
        )

        #expect(found == CardMetadata(scheme: .visa, corporate: false))
        #expect(!String(describing: found).contains(Self.bin))
        #expect(!String(reflecting: found).contains(Self.bin))
    }

    // MARK: The limit and the cancellation

    /// The limit is on the whole lookup: the clock is asked for three seconds once, when the
    /// lookup starts, and when it gets there the request is dropped, not left to finish.
    @Test func anAnswerThatTakesLongerThanThreeSecondsIsNoMetadata() async throws {
        let gateway = ScriptedGateway { _ in try await untilCancelled() }
        let asked = Locked<[TimeInterval]>([])
        let clock = AsyncGate()
        let lookup = lookup(over: gateway, sleep: { seconds in
            asked.value.append(seconds)
            try await clock.wait()
        })

        let looking = Task { try await lookup.lookUp(cardNumber: Self.pan) }
        try #require(await settle(until: gateway.requests.count == 1 && clock.hasWaiter))
        #expect(warnings.value.isEmpty, "nothing is decided before the limit")
        clock.open()

        expectNoMetadata("no answer in 3000 ms", try await looking.value)
        #expect(asked.value == [3])
        #expect(gateway.droppedPaths == ["/api/cards/bin-lookup"])
    }

    /// An answer in time calls the limit off: its clock is cancelled, not waited for.
    @Test func anAnswerInTimeEndsTheLimit() async throws {
        let answer = AsyncGate()
        let gateway = ScriptedGateway { _ in
            try await answer.wait()
            return (200, Self.full)
        }
        let clockCancelled = Flag()
        let clock = AsyncGate()
        let lookup = lookup(over: gateway, sleep: { _ in
            do {
                try await clock.wait()
            } catch {
                clockCancelled.value = true
                throw error
            }
        })

        let looking = Task { try await lookup.lookUp(cardNumber: Self.pan) }
        try #require(await settle(until: answer.hasWaiter && clock.hasWaiter))
        answer.open()

        #expect(try await looking.value?.brand == "GOLD")
        #expect(clockCancelled.value)
        #expect(warnings.value.isEmpty)
    }

    @Test func aCancelledLookupEndsWithTheCancellationAndSaysNothing() async throws {
        let gateway = ScriptedGateway { _ in try await untilCancelled() }
        let lookup = lookup(over: gateway)

        let looking = Task { try await lookup.lookUp(cardNumber: Self.pan) }
        try #require(await settle(until: gateway.requests.count == 1))
        looking.cancel()

        await #expect(throws: CancellationError.self) { try await looking.value }
        #expect(gateway.droppedPaths == ["/api/cards/bin-lookup"])
        #expect(warnings.value.isEmpty)
    }

    /// A cancellation the network layer throws on its own, with nobody cancelling the lookup, is
    /// a lookup that failed: no metadata at once, named by its type, not a wait for the limit.
    /// The limit's clock here never gets there, so a lookup that waited for it would not return;
    /// the time limit turns that into a failure instead of a run that hangs.
    @Test(.timeLimit(.minutes(1))) func aCancellationNobodyAskedForIsNoMetadataAtOnce() async throws {
        let gateway = ScriptedGateway { _ in throw CancellationError() }

        expectNoMetadata("CancellationError", try await lookup(over: gateway).lookUp(cardNumber: Self.pan))
    }

    // MARK: Privacy

    /// A lookup its own limit ended is reported as one call without an answer, so a slow gateway
    /// shows in the operational data; the request and its digits are still not in it.
    @Test func aLookupTheLimitEndedIsReportedWithoutAStatusOrBodies() async throws {
        let probe = TelemetryProbe()
        let gateway = ScriptedGateway { _ in try await untilCancelled() }
        let clock = AsyncGate()
        let lookup = lookup(over: gateway, telemetry: probe.telemetry, sleep: { _ in try await clock.wait() })

        let looking = Task { try await lookup.lookUp(cardNumber: Self.pan) }
        try #require(await settle(until: gateway.requests.count == 1 && clock.hasWaiter))
        clock.open()
        expectNoMetadata("no answer in 3000 ms", try await looking.value)

        let events = await probe.settledEvents(1)
        try #require(events.count == 1)
        let event = events[0]
        #expect(event["event_type"] as? String == "api_call")
        #expect(event["target"] as? String == "/cards/bin-lookup")
        #expect(event["action"] as? String == "bin-lookup")
        #expect(event["http_method"] as? String == "POST")
        #expect(event["status_code"] is NSNull)
        #expect(event["duration"] is Int)
        #expect(event["req_body"] == nil && event["res_body"] == nil)
        #expect(probe.uploads.allSatisfy { !String(decoding: $0.body, as: UTF8.self).contains(Self.bin) })
    }

    /// A lookup that ended because its caller was cancelled was given up on, not timed out: it
    /// is not reported at all.
    @Test func aLookupItsCallerCancelledIsNotReported() async throws {
        let probe = TelemetryProbe()
        let gateway = ScriptedGateway { _ in try await untilCancelled() }
        let lookup = lookup(over: gateway, telemetry: probe.telemetry)

        let looking = Task { try await lookup.lookUp(cardNumber: Self.pan) }
        try #require(await settle(until: gateway.requests.count == 1))
        looking.cancel()
        await #expect(throws: CancellationError.self) { try await looking.value }

        #expect(await probe.settledEvents(0).isEmpty)
    }

    /// An error answer is reported by its status alone. The gateway may repeat the digits it was
    /// asked about, in a message or under a key the redaction does not know, and eight digits
    /// are too few for the scrub of card numbers to catch.
    @Test func anErrorAnswerIsReportedWithoutItsBody() async throws {
        let probe = TelemetryProbe()
        let echo = #"{"code":404,"message":"No card details found for the BIN 44444444","card_bin":"44444444"}"#
        let answers = Locked<[(Int, String)]>([(404, echo), (400, echo), (500, echo)])
        let gateway = ScriptedGateway { _ in answers.value.removeFirst() }
        let lookup = lookup(over: gateway, telemetry: probe.telemetry)

        for status in [404, 400, 500] {
            expectNoMetadata("HTTP \(status)", try await lookup.lookUp(cardNumber: Self.pan))
        }

        let events = await probe.settledEvents(3)
        try #require(events.count == 3)
        #expect(events.map { $0["status_code"] as? Int } == [404, 400, 500])
        for event in events {
            #expect(event["target"] as? String == "/cards/bin-lookup")
            #expect(event["req_body"] == nil && event["res_body"] == nil)
        }
        #expect(probe.uploads.allSatisfy { !String(decoding: $0.body, as: UTF8.self).contains(Self.bin) })
    }

    /// The request is the start of a card number, so the operational data gets the call without
    /// it, whichever way the call ends. The answer of a lookup that found the card is no secret.
    @Test func theOperationalDataGetsTheLookupWithoutItsRequest() async throws {
        let probe = TelemetryProbe()
        let answers = Locked<[(Int, String)?]>([
            (200, #"{"scheme":"VISA","corporate":false,"issuer_country":"CZE"}"#),
            (404, #"{"code":404,"error":"NOT_FOUND"}"#),
            nil,
        ])
        let gateway = ScriptedGateway { _ in
            guard let answer = answers.value.removeFirst() else {
                throw GopaySDKError.transport(URLError(.timedOut))
            }
            return answer
        }
        let lookup = lookup(over: gateway, telemetry: probe.telemetry)

        for _ in 0..<3 {
            _ = try await lookup.lookUp(cardNumber: Self.pan)
        }

        let events = await probe.settledEvents(3)
        try #require(events.count == 3)
        for event in events {
            #expect(event["event_type"] as? String == "api_call")
            #expect(event["target"] as? String == "/cards/bin-lookup")
            #expect(event["action"] as? String == "bin-lookup")
            #expect(event["http_method"] as? String == "POST")
            #expect(event["req_body"] == nil)
        }
        let (found, unknown, lost) = (events[0], events[1], events[2])
        #expect(found["res_body"] as? String == #"{"corporate":false,"issuer_country":"CZE","scheme":"VISA"}"#)
        #expect(found["status_code"] as? Int == 200)
        #expect(unknown["status_code"] as? Int == 404)
        #expect(unknown["res_body"] == nil)
        #expect(lost["status_code"] is NSNull)
        #expect(probe.uploads.allSatisfy { !String(decoding: $0.body, as: UTF8.self).contains(Self.bin) })
    }

    /// Every other request still reports its body: the exception is the lookup's alone.
    @Test func aRequestBodyIsStillReportedWhereNothingKeepsItBack() async throws {
        let probe = TelemetryProbe()
        let gateway = ScriptedGateway { _ in (200, "{}") }
        var request = URLRequest(url: try #require(gateway.makeURL(path: "payments/1/charge")))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"state":"x"}"#.utf8)

        _ = try await gateway.send(request, telemetry: probe.telemetry, paymentId: "1")

        let event = try #require(await probe.events(1).first)
        #expect(event["req_body"] as? String == #"{"state":"x"}"#)
    }
}
