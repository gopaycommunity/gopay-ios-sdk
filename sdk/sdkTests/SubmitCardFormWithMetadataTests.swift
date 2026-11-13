//
//  SubmitCardFormWithMetadataTests.swift
//  sdkTests
//
//  `submitCardFormWithMetadata` (GPMOB-202): the submit of `submitCardForm` with the card's
//  metadata looked up beside the encryption. The lookup decides nothing, the result waits for
//  both, and a failed encryption or a cancellation ends the lookup too. No test waits on a clock:
//  the answers and the lookup's limit are held by gates. The Android SDK tests the same cases.
//

import Testing
import Foundation
@testable import sdk

struct SubmitCardFormWithMetadataTests {

    private static let form = "submit-with-metadata-test"
    private static let jwe = "header.key.iv.ciphertext.tag"
    private static let pan = "4444444444444448"
    private static let serverDate = "Wed, 30 Sep 2026 17:34:17 GMT"

    private static let valid = GopayCardFormData(
        cardNumber: pan, expirationMonth: "12", expirationYear: "30", cvv: "123"
    )
    private static let visa = CardMetadata(
        scheme: .visa, corporate: false, brand: "GOLD", serviceType: .debit, issuer: "Example Bank", issuerCountry: "CZE"
    )
    private static let visaAnswer = #"{"scheme":"VISA","corporate":false,"brand":"GOLD","service_type":"DEBIT","#
        + #""issuer":"Example Bank","issuer_country":"CZE"}"#

    // MARK: A form on screen

    /// An SDK of the test's own with one form registered, as a `PaymentCardForm` on screen is.
    private final class Checkout: @unchecked Sendable {
        let sdk: GopaySDK
        let owner = CardFormOwner()
        let resets = Locked(0)
        let attempts = Locked(0)
        let reported = ReportedErrors()
        let warnings = Locked<[String]>([])

        init(
            gateway: AsyncHTTPClient = ScriptedGateway { _ in (500, "") },
            clientId: String? = "client-1",
            shareableKey: String? = "key-1",
            telemetry: Telemetry = .disabled
        ) {
            let reported = self.reported
            sdk = GopaySDK(
                config: GopayConfig(
                    environment: .development(baseUrl: "https://gw.example/api/"),
                    clientId: clientId,
                    shareableKey: shareableKey,
                    debugLoggingEnabled: true,
                    errorCallback: { reported.append($0) }
                ),
                networkClient: gateway,
                telemetry: telemetry
            )
            let warnings = self.warnings
            sdk.warnSink = { warnings.value.append($0) }
            let (resets, attempts) = (self.resets, self.attempts)
            sdk.registerCardFormReset(
                { resets.value += 1 },
                submitAttempted: { attempts.value += 1 },
                formId: SubmitCardFormWithMetadataTests.form,
                owner: owner
            )
        }

        func type(_ data: GopayCardFormData) {
            sdk.updateCardFormData(data, formId: SubmitCardFormWithMetadataTests.form, owner: owner)
        }

        var holdsCard: Bool { sdk.internalCardFormData[SubmitCardFormWithMetadataTests.form] != nil }

        /// The SDK's copy is gone and the fields were emptied, once. The fields are emptied on the
        /// main thread, so that is waited for.
        func expectFormEmptied(sourceLocation: SourceLocation = #_sourceLocation) async {
            #expect(!holdsCard, "the SDK's copy is gone", sourceLocation: sourceLocation)
            await expectSettled(resets.value == 1, "the fields were emptied", sourceLocation: sourceLocation)
        }

        func expectCardKept(sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(holdsCard, "the card stays in the form", sourceLocation: sourceLocation)
            #expect(resets.value == 0, sourceLocation: sourceLocation)
        }

        /// The unreported body behind the public call, with a stand-in encryption and lookup.
        func submit(
            encrypt: @escaping @Sendable (GopayCardData) async throws -> String,
            lookUp: @escaping @Sendable (String) async throws -> CardMetadata?
        ) async throws -> EncryptedCardPayloadWithMetadata {
            try await sdk.submitStoredCardWithMetadata(
                formId: SubmitCardFormWithMetadataTests.form, encrypt: encrypt, lookUp: lookUp
            )
        }
    }

    // MARK: The result

    @Test func theSubmitReturnsTheJweWithTheMetadataAndEmptiesTheForm() async throws {
        let checkout = Checkout()
        checkout.type(Self.valid)
        let encrypted = Locked<GopayCardData?>(nil)
        let lookedUp = Locked<String?>(nil)

        let result = try await checkout.submit(
            encrypt: { encrypted.value = $0; return Self.jwe },
            lookUp: { lookedUp.value = $0; return Self.visa }
        )

        #expect(result == EncryptedCardPayloadWithMetadata(encryptedPayload: Self.jwe, cardMetadata: Self.visa))
        #expect(encrypted.value?.cardPan == Self.pan)
        #expect(encrypted.value?.expMonth == "12")
        #expect(encrypted.value?.cvv == "123")
        #expect(lookedUp.value == Self.pan, "the lookup is asked about the card of the form")
        await checkout.expectFormEmptied()
        await expectSettled(checkout.attempts.value == 1, "the form was told a submit ran")
        #expect(checkout.reported.all.isEmpty, "nothing to report")
    }

    @Test func aLookupThatFindsNothingReturnsTheJweWithoutMetadataAndEmptiesTheForm() async throws {
        let checkout = Checkout()
        checkout.type(Self.valid)

        let result = try await checkout.submit(encrypt: { _ in Self.jwe }, lookUp: { _ in nil })

        #expect(result.encryptedPayload == Self.jwe)
        #expect(result.cardMetadata == nil)
        await checkout.expectFormEmptied()
        #expect(checkout.reported.all.isEmpty)
    }

    @Test func aLookupThatThrowsIsNoMetadataNeverAFailedSubmit() async throws {
        struct LookupBroke: Error {}
        let checkout = Checkout()
        checkout.type(Self.valid)

        let result = try await checkout.submit(encrypt: { _ in Self.jwe }, lookUp: { _ in throw LookupBroke() })

        #expect(result == EncryptedCardPayloadWithMetadata(encryptedPayload: Self.jwe, cardMetadata: nil))
        await checkout.expectFormEmptied()
        #expect(checkout.reported.all.isEmpty)
    }

    /// A lookup cancelled by anyone but the caller is a lookup that failed: the submit's task is
    /// not cancelled, so the JWE is returned without metadata.
    @Test func aLookupCancelledByAnyoneButTheCallerIsNoMetadataNeverAFailedSubmit() async throws {
        let checkout = Checkout()
        checkout.type(Self.valid)

        let result = try await checkout.submit(encrypt: { _ in Self.jwe }, lookUp: { _ in throw CancellationError() })

        #expect(result == EncryptedCardPayloadWithMetadata(encryptedPayload: Self.jwe, cardMetadata: nil))
        await checkout.expectFormEmptied()
        #expect(checkout.reported.all.isEmpty)
    }

    // MARK: Side by side

    @Test func theLookupRunsBesideTheEncryptionAndTheResultWaitsForBoth() async throws {
        let checkout = Checkout()
        checkout.type(Self.valid)
        let key = AsyncGate()
        let answer = AsyncGate()
        let encrypted = Flag()
        let finished = Flag()

        let submit = Task {
            defer { finished.value = true }
            return try await checkout.submit(
                encrypt: { _ in
                    try await key.wait()
                    encrypted.value = true
                    return Self.jwe
                },
                lookUp: { _ in
                    try await answer.wait()
                    return Self.visa
                }
            )
        }

        try #require(await settle(until: key.hasWaiter), "the encryption started")
        try #require(await settle(until: answer.hasWaiter), "the lookup started while the key was still on its way")

        key.open()
        try #require(await settle(until: encrypted.value))
        #expect(!finished.value, "the JWE alone is not the result")
        checkout.expectCardKept()

        answer.open()
        #expect(try await submit.value == EncryptedCardPayloadWithMetadata(encryptedPayload: Self.jwe, cardMetadata: Self.visa))
        await checkout.expectFormEmptied()
    }

    @Test func aLookupThatAnswersFirstWaitsForTheEncryption() async throws {
        let checkout = Checkout()
        checkout.type(Self.valid)
        let key = AsyncGate()
        let lookedUp = Flag()
        let finished = Flag()

        let submit = Task {
            defer { finished.value = true }
            return try await checkout.submit(
                encrypt: { _ in
                    try await key.wait()
                    return Self.jwe
                },
                lookUp: { _ in
                    lookedUp.value = true
                    return Self.visa
                }
            )
        }
        try #require(await settle(until: key.hasWaiter && lookedUp.value))
        #expect(!finished.value)
        checkout.expectCardKept()

        key.open()

        #expect(try await submit.value == EncryptedCardPayloadWithMetadata(encryptedPayload: Self.jwe, cardMetadata: Self.visa))
    }

    /// The lookup's own limit, counted from the submit: the clock is asked while the key is still
    /// on its way, and when it gets there the JWE goes back without metadata.
    @Test func aLookupSlowerThanThreeSecondsReturnsTheJweWithoutMetadata() async throws {
        let gateway = ScriptedGateway { _ in try await untilCancelled() }
        let checkout = Checkout(gateway: gateway)
        checkout.type(Self.valid)
        let asked = Locked<[TimeInterval]>([])
        let clock = AsyncGate()
        let key = AsyncGate()
        let warnings = checkout.warnings
        let lookup = CardMetadataLookup(
            publicAPI: PublicAPI(client: gateway, clientId: "client-1", shareableKey: "key-1"),
            sleep: { seconds in
                asked.value.append(seconds)
                try await clock.wait()
            },
            warn: { warnings.value.append($0) }
        )

        let submit = Task {
            try await checkout.submit(
                encrypt: { _ in
                    try await key.wait()
                    return Self.jwe
                },
                lookUp: { try await lookup.lookUp(cardNumber: $0) }
            )
        }
        try #require(await settle(until: key.hasWaiter && clock.hasWaiter))
        #expect(asked.value == [3], "the limit runs from the submit, not from the JWE")
        clock.open()
        key.open()

        #expect(try await submit.value == EncryptedCardPayloadWithMetadata(encryptedPayload: Self.jwe, cardMetadata: nil))
        #expect(checkout.warnings.value == [CardMetadataLookup.warning("no answer in 3000 ms")])
        #expect(gateway.droppedPaths == ["/api/cards/bin-lookup"])
        await checkout.expectFormEmptied()
        #expect(checkout.reported.all.isEmpty, "a slow lookup is nobody's error")
    }

    // MARK: Failure and cancellation

    @Test func aFailedEncryptionCancelsTheLookupThrowsWhatItThrewAndKeepsTheCard() async throws {
        let checkout = Checkout()
        checkout.type(Self.valid)
        let key = AsyncGate()
        let lookingUp = Flag()
        let lookupCancelled = Flag()
        let failure = GopaySDKError(.networkIOError, message: "key fetch failed")

        let submit = Task {
            try await checkout.submit(
                encrypt: { _ in
                    try await key.wait()
                    throw failure
                },
                lookUp: { _ in
                    lookingUp.value = true
                    do {
                        try await untilCancelled()
                    } catch {
                        lookupCancelled.value = true
                        throw error
                    }
                }
            )
        }
        try #require(await settle(until: key.hasWaiter && lookingUp.value))
        key.open()

        await #expect {
            try await submit.value
        } throws: { error in
            // The encryption's own error, as submitCardForm throws it.
            let error = error as? GopaySDKError
            return error?.code == .networkIOError && error?.message == "key fetch failed"
        }
        #expect(lookupCancelled.value, "the lookup had ended before the error left")
        checkout.expectCardKept()
    }

    @Test func aCancelledSubmitEndsBothRethrowsAndKeepsTheCard() async throws {
        let checkout = Checkout()
        checkout.type(Self.valid)
        let encrypting = Flag()
        let lookingUp = Flag()
        let encryptionCancelled = Flag()
        let lookupCancelled = Flag()

        let submit = Task {
            try await checkout.submit(
                encrypt: { _ in
                    encrypting.value = true
                    do {
                        try await untilCancelled()
                    } catch {
                        encryptionCancelled.value = true
                        throw error
                    }
                },
                lookUp: { _ in
                    lookingUp.value = true
                    do {
                        try await untilCancelled()
                    } catch {
                        lookupCancelled.value = true
                        throw error
                    }
                }
            )
        }
        try #require(await settle(until: encrypting.value && lookingUp.value))

        submit.cancel()

        await #expect(throws: CancellationError.self) { try await submit.value }
        #expect(encryptionCancelled.value)
        #expect(lookupCancelled.value)
        checkout.expectCardKept()
        #expect(checkout.reported.all.isEmpty)
    }

    /// A submit cancelled once the JWE exists and the lookup is still out: no result, and the
    /// card stays, since nothing was handed over.
    @Test func aSubmitCancelledWhileOnlyTheLookupIsLeftKeepsTheCard() async throws {
        let checkout = Checkout()
        checkout.type(Self.valid)
        let lookingUp = Flag()

        let submit = Task {
            try await checkout.submit(
                encrypt: { _ in Self.jwe },
                lookUp: { _ in
                    lookingUp.value = true
                    try await untilCancelled()
                }
            )
        }
        try #require(await settle(until: lookingUp.value))
        submit.cancel()

        await #expect(throws: CancellationError.self) { try await submit.value }
        checkout.expectCardKept()
    }

    @Test func anEmptyInvalidOrUnsupportedCardIsRefusedBeforeAnythingIsEncryptedOrLookedUp() async throws {
        let checkout = Checkout()
        var shortCvv = Self.valid
        shortCvv.cvv = "12"
        // Discover: sixteen digits that pass the Luhn check, of a brand the form does not accept.
        var discover = Self.valid
        discover.cardNumber = "6011000000000004"
        let cases: [(GopayCardFormData, GopaySDKError.Code)] = [
            (GopayCardFormData(), .validationCardFormEmpty),
            (shortCvv, .validationInvalidInput),
            (discover, .validationInvalidInput),
        ]
        let touched = Flag()

        for (data, code) in cases {
            checkout.type(data)

            await #expect {
                try await checkout.submit(
                    encrypt: { _ in touched.value = true; return Self.jwe },
                    lookUp: { _ in touched.value = true; return nil }
                )
            } throws: { ($0 as? GopaySDKError)?.code == code }
        }

        #expect(!touched.value, "must not encrypt or look up")
        await expectSettled(checkout.attempts.value == 3, ".onSubmit shows its errors whether or not the submit passes")
        #expect(checkout.resets.value == 0)
        #expect(checkout.reported.all.isEmpty, "the core reports nothing; the public call does")
    }

    @Test func theResultPrintsItsMetadataButNeverTheJwe() {
        let result = EncryptedCardPayloadWithMetadata(encryptedPayload: Self.jwe, cardMetadata: Self.visa)
        var dumped = ""
        dump(result, to: &dumped)

        for printed in [String(describing: result), String(reflecting: result), "\(result)", dumped] {
            #expect(!printed.contains(Self.jwe), "\(printed)")
            #expect(printed.contains("GOLD"), "\(printed)")
        }
        #expect(
            String(describing: EncryptedCardPayloadWithMetadata(encryptedPayload: Self.jwe, cardMetadata: nil))
                == "EncryptedCardPayloadWithMetadata(encryptedPayload=***, cardMetadata=nil)"
        )
    }

    // MARK: The public call, against a gateway

    /// A gateway that serves `key` and answers the lookup with `lookup`.
    private func gateway(
        serving key: TestEncryptionKey,
        lookup: @escaping @Sendable () async throws -> (status: Int, body: String)
    ) -> ScriptedGateway {
        let jwk = String(decoding: key.publicJWKJSON, as: UTF8.self)
        return ScriptedGateway(headers: ["Date": Self.serverDate]) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("cards/public-key") { return (200, jwk) }
            if path.hasSuffix("cards/bin-lookup") { return try await lookup() }
            return (404, "")
        }
    }

    @Test func thePublicCallEncryptsTheCardAndLooksUpItsFirstEightDigits() async throws {
        let key = try TestEncryptionKey()
        let gateway = gateway(serving: key) { (200, Self.visaAnswer) }
        let checkout = Checkout(gateway: gateway)
        checkout.type(Self.valid)

        let result = try await checkout.sdk.submitCardFormWithMetadata(formId: Self.form)

        #expect(result.cardMetadata == Self.visa)
        let claims = try key.decryptClaims(result.encryptedPayload)
        #expect(String(describing: claims).contains(Self.pan), "the JWE holds the card of the form")
        let lookups = gateway.requests(to: "cards/bin-lookup")
        #expect(lookups.count == 1)
        #expect(lookups.first?.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"bin":"44444444"}"#)
        #expect(gateway.requests(to: "cards/public-key").count == 1)
        await checkout.expectFormEmptied()
        #expect(checkout.warnings.value.isEmpty)
        #expect(checkout.reported.all.isEmpty)
    }

    /// The sandbox of today: the gateway has no such endpoint, or does not know the BIN.
    @Test func aLookupTheGatewayAnswersWith404ReturnsTheJweAndWarnsOnce() async throws {
        let key = try TestEncryptionKey()
        let gateway = gateway(serving: key) { (404, #"{"code":404,"error":"NOT_FOUND","message":"Resource not found"}"#) }
        let checkout = Checkout(gateway: gateway)
        checkout.type(Self.valid)

        let result = try await checkout.sdk.submitCardFormWithMetadata()

        #expect(result.cardMetadata == nil)
        #expect(result.encryptedPayload.split(separator: ".").count == 5)
        #expect(checkout.warnings.value == [CardMetadataLookup.warning("HTTP 404")])
        #expect(checkout.reported.all.isEmpty, "nothing reaches errorCallback")
        await checkout.expectFormEmptied()
    }

    /// The key fetch runs to its answer and fails; the lookup, still out, is dropped with it.
    @Test func aKeyFetchThatFailsDropsTheLookupAndReportsTheEncryptionsErrorOnce() async throws {
        let lookingUp = Flag()
        let gateway = ScriptedGateway { request in
            if request.url?.path.hasSuffix("cards/bin-lookup") ?? false {
                lookingUp.value = true
                try await untilCancelled()
            }
            // Held until the lookup is out, so the failure finds it in flight.
            await settle(until: lookingUp.value)
            return (500, "")
        }
        let probe = TelemetryProbe(clientId: "client-1")
        let checkout = Checkout(gateway: gateway, telemetry: probe.telemetry)
        checkout.type(Self.valid)

        await #expect {
            try await checkout.sdk.submitCardFormWithMetadata(formId: Self.form)
        } throws: { ($0 as? GopaySDKError)?.code == .networkServerError }

        #expect(gateway.droppedPaths == ["/api/cards/bin-lookup"])
        // Given up on, not timed out: the operational data hears of the key fetch, not of the
        // lookup.
        let events = await probe.settledEvents(1)
        #expect(events.contains { $0["target"] as? String == "/cards/public-key" })
        #expect(!events.contains { $0["target"] as? String == "/cards/bin-lookup" })
        #expect(checkout.reported.codes == [.networkServerError])
        #expect(checkout.warnings.value.isEmpty, "a lookup the submit gave up on is not a lookup without metadata")
        checkout.expectCardKept()
    }

    /// The public call fails like `submitCardForm`, with the same codes, each reported once.
    @Test func thePublicCallFailsLikeSubmitCardFormEachErrorReportedOnce() async throws {
        // No shareable key: the lookup has nothing to ask with and only warns, and the key fetch
        // fails with AUTH_011, the error submitCardForm reports for the same form.
        let gateway = ScriptedGateway { _ in (200, "{}") }
        let checkout = Checkout(gateway: gateway, shareableKey: nil)

        func code(formId: String?) async -> GopaySDKError? {
            do {
                _ = try await checkout.sdk.submitCardFormWithMetadata(formId: formId)
                return nil
            } catch {
                return error as? GopaySDKError
            }
        }

        let none = await code(formId: "no-such-form")
        #expect(none?.code == .validationCardFormEmpty)
        #expect(none?.message == GopaySDKErrors.noCardFormData)

        var shortCvv = Self.valid
        shortCvv.cvv = "12"
        checkout.type(shortCvv)
        let invalid = await code(formId: Self.form)
        #expect(invalid?.code == .validationInvalidInput)
        #expect(invalid?.message == GopaySDKErrors.invalidCardFormData)

        checkout.type(Self.valid)
        let noKey = await code(formId: nil)
        #expect(noKey?.code == .authShareableKeyMissing)

        #expect(
            checkout.reported.codes == [.validationCardFormEmpty, .validationInvalidInput, .authShareableKeyMissing],
            "the failed lookup reports nothing, the rest once each"
        )
        // This depends on a race, so it is not pinned to one outcome: the encryption fails at
        // once and cancels the lookup, and the lookup's warning is there only when the lookup
        // got to say it first. Either is right; `CardMetadataLookupTests` pins the warning.
        #expect(checkout.warnings.value.allSatisfy { $0 == CardMetadataLookup.warning("AUTH_011") })
        #expect(checkout.warnings.value.count <= 1)
        #expect(gateway.requests.isEmpty)
        checkout.expectCardKept()
    }

    @Test func thePublicCallBeforeInitializeIsConfig001() async {
        let sdk = GopaySDK()

        await #expect {
            try await sdk.submitCardFormWithMetadata()
        } throws: { ($0 as? GopaySDKError)?.code == .sdkNotInitialized }
    }

    // MARK: Operational data

    /// The submit names its flow, `return-payload` or `payload-with-metadata`, the form's own
    /// steps keep `return-payload`, and the lookup adds nothing of the card.
    @Test func theSubmitNamesItsFlowAndTheLookupAddsNothingOfTheCard() async throws {
        let key = try TestEncryptionKey()
        let gateway = gateway(serving: key) { (200, Self.visaAnswer) }
        let probe = TelemetryProbe(clientId: "client-1")
        let checkout = Checkout(gateway: gateway, telemetry: probe.telemetry)
        probe.telemetry.cardFormReady(owner: checkout.owner)

        checkout.type(Self.valid)
        _ = try await checkout.sdk.submitCardForm(formId: Self.form)
        checkout.type(Self.valid)
        _ = try await checkout.sdk.submitCardFormWithMetadata(formId: Self.form)

        // Ready; then per submit the request step, the key fetch, the submit and its summary; and
        // the lookup of the second one.
        let events = await probe.settledEvents(10)
        let submits = events.filter { $0["event_type"] as? String == "interaction" }
        #expect(submits.map { $0["flow"] as? String } == ["return-payload", "payload-with-metadata"])
        for submit in submits {
            #expect(submit["element_id"] as? String == "card-form")
        }
        let steps = events.filter { ($0["function_name"] as? String)?.hasPrefix("PAYMENT_CARD.") ?? false }
        #expect(!steps.isEmpty)
        #expect(steps.allSatisfy { $0["flow"] as? String == "return-payload" })
        let lookups = events.filter { $0["target"] as? String == "/cards/bin-lookup" }
        #expect(lookups.count == 1)
        #expect(lookups.first?["req_body"] == nil)

        for upload in probe.uploads {
            let sent = String(decoding: upload.body, as: UTF8.self)
            for leak in ["44444444", Self.pan] {
                #expect(!sent.contains(leak), "\(leak) in \(sent)")
            }
        }
    }
}
