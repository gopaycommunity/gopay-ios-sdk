//
//  ErrorCallbackTests.swift
//  sdkTests
//
//  Pins the `errorCallback` rule (GPMOB-160): every GopaySDKError a public call throws reaches the
//  callback once, PAYMENT_007, PAYMENT_011 and a cancellation stay out, and nothing that is not a
//  GopaySDKError goes in. The Android SDK applies the same rule.
//

import Testing
import Foundation
@testable import sdk

/// Collects what the callback got, from whatever thread the failing call ended on.
final class ReportedErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Error] = []

    func append(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        stored.append(error)
    }

    var all: [Error] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    var codes: [GopaySDKError.Code] { all.compactMap { ($0 as? GopaySDKError)?.code } }
}

/// Which public call to make and how to tell its one request apart; the wrappers of a single
/// request are all alike, so one test runs over this table.
struct OneRequestCall: CustomTestStringConvertible, Sendable {
    let name: String
    let pathSuffix: String
    let call: @Sendable (PaymentSession) async throws -> Void

    var testDescription: String { name }
}

let oneRequestCalls: [OneRequestCall] = [
    OneRequestCall(name: "getStatus", pathSuffix: "payments/p1") { _ = try await $0.getStatus() },
    OneRequestCall(name: "getChargeState", pathSuffix: "/charge") { _ = try await $0.getChargeState() },
    OneRequestCall(name: "getQrPaymentInfo", pathSuffix: "qr-payment/info") { _ = try await $0.getQrPaymentInfo() },
    OneRequestCall(name: "getApplePayInfo", pathSuffix: "apple-pay/app-info") { _ = try await $0.getApplePayInfo() },
    OneRequestCall(name: "completeBrowserData", pathSuffix: "cards/browser-data") {
        _ = try await $0.completeBrowserData(BrowserData(language: "cs", timezone: -60, screenWidth: 1, screenHeight: 1, colorDepth: 24, userAgent: "ua"))
    },
]

// Part of the serialized `SessionNetworkTests`: every SDK here is built over the shared stub.
extension SessionNetworkTests {

    /// An SDK whose callback collects into `reported`, over the shared stub.
    func reportingSDK(_ reported: ReportedErrors, clientId: String? = "c", shareableKey: String? = "k") -> GopaySDK {
        GopaySDK(
            config: GopaySDKConfig(
                environment: .development(baseURL: stubBaseURL),
                clientId: clientId, shareableKey: shareableKey,
                errorCallback: { reported.append($0) }
            ),
            networkClient: stubbedClient()
        )
    }

    /// The gateway as these tests need it: a token, browser data, the charge endpoints, the Apple
    /// Pay info and the payment status, each with the status the test picks. The public key
    /// always fails with a 500, so an encryption ends on the key fetch; anything else is a 404.
    private func gateway(
        chargeState: String = "PROCESSING",
        chargeStatus: Int = 200,
        applePayStatus: Int = 200,
        browserDataStatus: Int = 200,
        tokenStatus: Int = 200,
        statusStatus: Int = 200,
        qrStatus: Int = 200,
        redirectUrl: String? = nil,
        delay: TimeInterval = 0
    ) {
        StubURLProtocol.reset(delay: delay) { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") {
                return tokenStatus == 200 ? tokenResponse() : (tokenStatus, json(["error": "unauthorized"]))
            }
            if path.hasSuffix("cards/browser-data") {
                return (browserDataStatus, json(["ip": "192.0.2.42", "user_agent": "ua", "accept_header": "a"]))
            }
            if path.hasSuffix("/charge") {
                var body: [String: Any] = ["id": "ch_1", "state": chargeState, "fail_reason": "declined"]
                if let redirectUrl = redirectUrl {
                    body["action"] = ["action_type": "EMV3DS", "redirect_url": redirectUrl]
                }
                return (chargeStatus, json(body))
            }
            if path.hasSuffix("apple-pay/app-info") { return (applePayStatus, json(applePayAppInfoJSON())) }
            if path.hasSuffix("qr-payment/info") { return (qrStatus, json(["amount": 100])) }
            if path.hasSuffix("payments/p1") { return (statusStatus, json(["id": "p1", "state": "CREATED", "amount": 100, "currency": "CZK"])) }
            if path.hasSuffix("cards/public-key") { return (500, Data()) }
            return (404, Data())
        }
    }

    private var browserData: BrowserData {
        BrowserData(
            language: "cs", timezone: -60, screenWidth: 1, screenHeight: 1, colorDepth: 24,
            userAgent: "ua", javascriptEnabled: true
        )
    }

    // MARK: The rule itself

    @Test func aPaymentTimeoutIsNotReported() {
        let reported = ReportedErrors()
        reportingSDK(reported).report(GopaySDKError(.paymentTimeout, message: "undecided"))
        #expect(reported.all.isEmpty)
    }

    @Test func aPaymentCancelledIsNotReported() {
        let reported = ReportedErrors()
        reportingSDK(reported).report(GopaySDKError(.paymentCancelled, message: "closed"))
        #expect(reported.all.isEmpty)
    }

    @Test func aCancellationIsNotReported() {
        let reported = ReportedErrors()
        reportingSDK(reported).report(CancellationError())
        #expect(reported.all.isEmpty)
    }

    /// The callback is typed `Error` for compatibility, but only a `GopaySDKError` ever arrives.
    @Test func anErrorOfAnotherTypeIsNotReported() {
        let reported = ReportedErrors()
        reportingSDK(reported).report(NSError(domain: "host", code: 1))
        #expect(reported.all.isEmpty)
    }

    @Test func everyOtherCodeIsReportedAsItIs() {
        let reported = ReportedErrors()
        reportingSDK(reported).report(GopaySDKError(.paymentDeclined, message: "declined"))
        #expect(reported.codes == [.paymentDeclined])
    }

    @Test func noConfigMeansNoCallback() {
        // Nothing to call and nothing to crash on.
        GopaySDK().report(GopaySDKError(.sdkNotInitialized, message: "not initialized"))
    }

    // MARK: Once per thrown error, across the SDK and its sessions

    @Test func rejectedCredentialsAreReportedOnceFromStartPaymentSession() async {
        gateway(tokenStatus: 401)
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)

        await #expect(throws: GopaySDKError.self) {
            try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        }

        #expect(reported.codes == [.authPaymentCredentialsInvalid])
    }

    @Test func emptyCredentialsAreReportedOnce() async {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)

        await #expect(throws: GopaySDKError.self) {
            try await sdk.startPaymentSession(paymentId: "", paymentSecret: "s")
        }

        #expect(reported.codes == [.validationInvalidInput])
    }

    @Test func aDuplicateSessionIsReportedOnce() async throws {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let first = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await first.close() } }

        await #expect(throws: GopaySDKError.self) {
            try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        }

        #expect(reported.codes == [.authPaymentSessionAlreadyExists])
    }

    /// Each wrapper of a single request reports that request's failure, once.
    @Test(arguments: oneRequestCalls)
    func aFailedSingleRequestIsReportedOnce(_ testCase: OneRequestCall) async throws {
        gateway(chargeStatus: 500, applePayStatus: 500, browserDataStatus: 500, statusStatus: 500, qrStatus: 500)
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        await #expect(throws: GopaySDKError.self) { try await testCase.call(session) }

        #expect(reported.codes == [.networkServerError])
        #expect(StubURLProtocol.requestCount(forPathSuffix: testCase.pathSuffix) == 1)
    }

    @Test func aFailedChargeIsReportedOnceBySession() async throws {
        gateway(chargeStatus: 500)
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        await #expect(throws: GopaySDKError.self) {
            try await session.charge(.cardToken("t", browserData: browserData))
        }

        #expect(reported.codes == [.networkServerError])
    }

    /// The charge wraps the browser data failure into its own error: that one is reported, and
    /// the inner failure is not reported a second time on its way through.
    @Test func aBrowserDataFailureInsideAChargeIsReportedOnce() async throws {
        gateway(browserDataStatus: 503)
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }
        let incomplete = BrowserData(language: "cs", timezone: -60, screenWidth: 1, screenHeight: 1, colorDepth: 24, userAgent: "ua")

        await #expect(throws: GopaySDKError.self) {
            try await session.charge(.cardToken("t", browserData: incomplete))
        }

        #expect(reported.codes == [.networkServerError])
        #expect((reported.all.first as? GopaySDKError)?.message.contains("browser data") == true)
    }

    @Test func aCallOnAClosedSessionIsReportedOnce() async throws {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        await session.close()

        await #expect(throws: GopaySDKError.self) {
            try await session.charge(.cardToken("t", browserData: browserData))
        }

        #expect(reported.codes == [.authPaymentSessionClosed])
    }

    /// A charge cancelled while its browser data is on its way is not sent and reports nothing.
    @Test func aChargeCancelledBeforeItIsSentSendsNothing() async throws {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }
        gateway(delay: 0.3)
        let incomplete = BrowserData(language: "cs", timezone: -60, screenWidth: 1, screenHeight: 1, colorDepth: 24, userAgent: "ua")

        let charge = Task { try await session.charge(.cardToken("t", browserData: incomplete)) }
        try await Task.sleep(nanoseconds: 100_000_000)
        charge.cancel()

        await #expect(throws: CancellationError.self) { try await charge.value }
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/charge") == 0)
        #expect(reported.all.isEmpty)
    }

    /// Any public call, not only the polling: a `getStatus` cancelled while its read is in
    /// flight ends with the cancellation even when the read then fails, and reports nothing.
    @Test func aSingleRequestCancelledWhileFailingIsACancellationAndNotReported() async throws {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }
        gateway(statusStatus: 500, delay: 0.3)

        let read = Task { try await session.getStatus() }
        try await Task.sleep(nanoseconds: 100_000_000)
        read.cancel()

        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(reported.all.isEmpty)
    }

    /// The failed Apple Pay info read ends the Apple Pay call; the call reports it, the read
    /// inside it does not.
    @Test func aFailedApplePayInfoReadIsReportedOnceByTheApplePayCharge() async throws {
        gateway(applePayStatus: 403)
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        await #expect(throws: GopaySDKError.self) {
            try await session.chargeWithApplePay(browserData: browserData)
        }

        #expect(reported.codes == [.networkClientError])
    }

    // MARK: The token refresh

    /// A refresh the gateway refuses inside a call is that call's failure: reported once, by it.
    @Test func aRefusedRefreshInsideACallIsReportedOnceByTheCall() async throws {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }
        // Every charge read is a 401 and the refresh is turned down.
        gateway(chargeStatus: 401, tokenStatus: 401)

        await #expect(throws: GopaySDKError.self) { _ = try await session.getChargeState() }

        #expect(reported.codes == [.authPaymentCredentialsInvalid])
        #expect(StubURLProtocol.requestCount(forPathSuffix: "oauth2/token") == 1)
    }

    /// `reauthenticate()` is public, so a host that calls it directly gets its failure reported
    /// like that of every other public call.
    @Test func aDirectReauthenticateOnAClosedSessionIsReportedOnce() async throws {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        await session.close()

        await #expect(throws: GopaySDKError.self) { _ = try await session.reauthenticate() }

        #expect(reported.codes == [.authPaymentSessionClosed])
    }

    // MARK: The polling

    @Test func aDeclinedChargeIsReportedOnceByAwaitChargeState() async throws {
        gateway(chargeState: "FAILED")
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        await #expect(throws: GopaySDKError.self) {
            try await session.awaitChargeState(AwaitChargeOptions(interval: 0.01, initialTimeout: 1))
        }

        #expect(reported.codes == [.paymentDeclined])
    }

    @Test func aChargeTimeoutIsNotReportedByAwaitChargeState() async throws {
        gateway(chargeState: "PROCESSING")
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        do {
            _ = try await session.awaitChargeState(AwaitChargeOptions(interval: 0.01, initialTimeout: 0.05))
            Issue.record("expected a timeout")
        } catch let error as GopaySDKError {
            #expect(error.code == .paymentTimeout)
        }

        #expect(reported.all.isEmpty)
    }

    @Test func aFailedReadInsideAwaitChargeStateIsReportedOnce() async throws {
        gateway(chargeStatus: 404)
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        await #expect(throws: GopaySDKError.self) {
            try await session.awaitChargeState(AwaitChargeOptions(interval: 0.01, initialTimeout: 1))
        }

        #expect(reported.codes == [.networkClientError])
    }

    @Test func aPollCancelledDuringTheWaitIsNotReported() async throws {
        gateway(chargeState: "PROCESSING")
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        let poll = Task { try await session.awaitChargeState(AwaitChargeOptions(interval: 0.05, initialTimeout: 10)) }
        try await Task.sleep(nanoseconds: 100_000_000)
        poll.cancel()

        await #expect(throws: CancellationError.self) { try await poll.value }
        #expect(reported.all.isEmpty)
    }

    /// URLSession finishes a read the task was cancelled during; a read that then fails must not
    /// turn the cancellation into a network error, reported or not.
    @Test func aPollCancelledDuringAFailingReadIsACancellationAndNotReported() async throws {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }
        gateway(chargeStatus: 500, delay: 0.3)

        let poll = Task { try await session.awaitChargeState(AwaitChargeOptions(interval: 0.05, initialTimeout: 10)) }
        try await Task.sleep(nanoseconds: 100_000_000)
        poll.cancel()

        await #expect(throws: CancellationError.self) { try await poll.value }
        #expect(reported.all.isEmpty)
    }

    // MARK: The 3DS challenge

    /// A redirect the WebView could never load is refused before anything is shown: one code,
    /// reported once by the public call.
    @Test func anUnloadableRedirectIsReportedOnceByHandle3dsVerification() async throws {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        await #expect(throws: GopaySDKError.self) {
            try await session.handle3dsVerification(redirectURL: URL(string: "ftp://acs.example/challenge")!)
        }

        #expect(reported.codes == [.paymentVerificationUnreachable])
    }

    /// The same redirect reached through the automatic challenge of `awaitChargeState` is that
    /// call's failure: still one code, reported once, not by the challenge and again by the poll.
    @Test func anUnloadableRedirectInsideAwaitChargeStateIsReportedOnce() async throws {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }
        gateway(chargeState: "ACTION_REQUIRED", redirectUrl: "ftp://acs.example/challenge")

        await #expect(throws: GopaySDKError.self) {
            try await session.awaitChargeState(AwaitChargeOptions(interval: 0.01, initialTimeout: 1))
        }

        #expect(reported.codes == [.paymentVerificationUnreachable])
    }

    // MARK: Card encryption

    @Test func aFailedKeyFetchIsReportedOnceFromEncryptCardData() async {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let card = GopayCardData(cardPan: "4444333322221111", expMonth: "12", expYear: "30", cvv: "123")

        await #expect(throws: GopaySDKError.self) { try await sdk.encryptCardData(card) }

        #expect(reported.codes == [.networkServerError])
    }

    /// `submitCardForm` ends with the encryption; its failure is reported by the submit alone.
    @Test func aFailedKeyFetchIsReportedOnceFromSubmitCardForm() async {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        sdk.updateCardFormData(
            GopayCardFormData(cardNumber: "4444333322221111", expirationMonth: "12", expirationYear: "30", cvv: "123"),
            formId: "f1"
        )

        await #expect(throws: GopaySDKError.self) { try await sdk.submitCardForm(formId: "f1") }

        #expect(reported.codes == [.networkServerError])
    }

    @Test func anInvalidCardIsReportedOnce() async {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)

        await #expect(throws: GopaySDKError.self) {
            try await sdk.encryptCardData(GopayCardData(cardPan: "1", expMonth: "12", expYear: "30", cvv: "123"))
        }
        await #expect(throws: GopaySDKError.self) { try await sdk.submitCardForm(formId: "none") }

        #expect(reported.codes == [.validationInvalidInput, .validationInvalidInput])
    }

    @Test func aMissingShareableKeyIsReportedOnce() async {
        gateway()
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported, shareableKey: nil)
        let card = GopayCardData(cardPan: "4444333322221111", expMonth: "12", expYear: "30", cvv: "123")

        await #expect(throws: GopaySDKError.self) { try await sdk.encryptCardData(card) }

        #expect(reported.codes == [.authShareableKeyMissing])
    }
}
