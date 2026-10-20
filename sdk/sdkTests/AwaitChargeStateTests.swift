//
//  AwaitChargeStateTests.swift
//  sdkTests
//
//  Pins `awaitChargeState`: the polling cadence, the two codes it owns (PAYMENT_006 for a charge
//  that ended FAILED, PAYMENT_007 for one that stayed REQUESTED / PROCESSING / UNKNOWN for the
//  whole initial timeout), the 3DS step in both modes and what cancellation stops. The clock, the
//  sleep and the verification are replaced through `AwaitChargeHooks`, so no test waits for real
//  and none presents a screen. The Android SDK pins the same behaviour with `runTest`.
//

import Testing
import Foundation
import UIKit
@testable import sdk

/// Virtual time: a sleep advances the clock at once and is remembered, so a test can check both
/// the cadence and where the timeout landed. The stub advances it too, to stand in for a slow
/// answer.
private final class VirtualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    private var slept: [TimeInterval] = []

    var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return time }
    var sleeps: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return slept }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); time += seconds; lock.unlock()
    }

    func sleep(_ seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        lock.lock()
        slept.append(seconds)
        time += seconds
        lock.unlock()
        await Task.yield()
    }
}

/// What the callbacks and the verification stand-in saw, readable from any thread.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStates: [ChargeState] = []
    private var storedRedirects: [String] = []
    private var storedVerifications: [(redirect: String, returnURL: URL?, presenting: UIViewController?)] = []

    var states: [ChargeState] { lock.lock(); defer { lock.unlock() }; return storedStates }
    var redirects: [String] { lock.lock(); defer { lock.unlock() }; return storedRedirects }
    var verifications: [(redirect: String, returnURL: URL?, presenting: UIViewController?)] {
        lock.lock(); defer { lock.unlock() }; return storedVerifications
    }

    func state(_ charge: ChargePaymentResponse) { lock.lock(); storedStates.append(charge.state); lock.unlock() }
    func redirect(_ url: String) { lock.lock(); storedRedirects.append(url); lock.unlock() }
    func verification(_ redirect: String, _ returnURL: URL?, _ presenting: UIViewController?) {
        lock.lock(); storedVerifications.append((redirect, returnURL, presenting)); lock.unlock()
    }
}

/// A charge as `GET /payments/{id}/charge` answers it. A `redirect` of `nil` leaves the action
/// without `redirect_url`; an empty string sends it empty.
private func charge(_ state: String, redirect: String? = nil, failReason: String? = nil) -> [String: Any] {
    var body: [String: Any] = ["id": "ch_1", "state": state]
    if state == "ACTION_REQUIRED" {
        var action: [String: Any] = ["action_type": "EMV3DS", "state": "CHALLENGE_REQUIRED"]
        if let redirect = redirect { action["redirect_url"] = redirect }
        body["action"] = action
    } else if let redirect = redirect {
        body["action"] = ["action_type": "EMV3DS", "state": "CHALLENGE_REQUIRED", "redirect_url": redirect]
    }
    if let failReason = failReason { body["fail_reason"] = failReason }
    return body
}

private let chargePath = "/payments/p1/charge"

/// Answers the token and then the charge reads in order, each with its HTTP status; the last
/// answer repeats. `beforeAnswer` runs on the stub's thread before each charge answer, where a
/// test moves the virtual clock to stand in for the gateway's latency.
private func serveCharges(
    _ answers: [(status: Int, body: [String: Any])],
    beforeAnswer: (@Sendable () -> Void)? = nil
) {
    let counter = Counter()
    StubURLProtocol.reset { req in
        let path = req.url?.path ?? ""
        if path.hasSuffix("oauth2/token") { return tokenResponse() }
        guard path.hasSuffix(chargePath) else { return (404, Data()) }
        beforeAnswer?()
        let answer = answers[min(counter.increment(), answers.count) - 1]
        return (answer.status, json(answer.body))
    }
}

private func serveCharges(_ bodies: [[String: Any]], beforeAnswer: (@Sendable () -> Void)? = nil) {
    serveCharges(bodies.map { (200, $0) }, beforeAnswer: beforeAnswer)
}

private func chargeReads() -> Int { StubURLProtocol.requestCount(forPathSuffix: chargePath) }

/// Polls `condition` for up to two seconds, for the tests that race a real task.
private func waitUntil(_ condition: @escaping () -> Bool) async throws {
    for _ in 0..<100 where !condition() {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(condition())
}

// Extends `SessionNetworkTests` for its `makeSession()` and for the serialized suite: every test
// here shares the one `StubURLProtocol`, so two cannot run at once.
extension SessionNetworkTests {

    private func makePollingSession(
        clock: VirtualClock,
        recorder: Recorder,
        verify: ((String) async throws -> Void)? = nil
    ) async throws -> PaymentSession {
        let session = try await makeSession()
        await session.useAwaitChargeHooks(AwaitChargeHooks(
            now: { clock.now },
            sleep: { try await clock.sleep($0) },
            verify: { _, redirect, returnURL, presenting in
                recorder.verification(redirect, returnURL, presenting)
                try await verify?(redirect)
            }
        ))
        return session
    }

    private func options(
        _ recorder: Recorder,
        interval: TimeInterval = 1,
        initialTimeout: TimeInterval = 30,
        threeDSMode: ThreeDSMode = .automatic,
        returnURL: URL? = nil,
        presenting: UIViewController? = nil
    ) -> AwaitChargeOptions {
        AwaitChargeOptions(
            interval: interval,
            initialTimeout: initialTimeout,
            threeDSMode: threeDSMode,
            returnURL: returnURL,
            presenting: presenting,
            onStateChange: { recorder.state($0) },
            onActionRequired: { recorder.redirect($0) }
        )
    }

    /// The `GopaySDKError` the call ends with, `nil` when it returns; any other error fails the
    /// test here rather than as a missing value further down.
    private func failure(_ body: () async throws -> ChargePaymentResponse) async -> GopaySDKError? {
        do {
            _ = try await body()
            return nil
        } catch let error as GopaySDKError {
            return error
        } catch {
            Issue.record("expected a GopaySDKError, got \(error)")
            return nil
        }
    }

    // MARK: Results

    @Test func aChargeAlreadySucceededReturnsAtOnce() async throws {
        serveCharges([charge("SUCCEEDED")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let result = try await session.awaitChargeState(options(recorder))

        #expect(result.state == .succeeded)
        #expect(chargeReads() == 1)
        #expect(clock.sleeps.isEmpty)
        #expect(recorder.states == [.succeeded])
    }

    @Test func aProcessingChargeIsReadAgainAfterTheInterval() async throws {
        serveCharges([charge("REQUESTED"), charge("PROCESSING"), charge("SUCCEEDED")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let result = try await session.awaitChargeState(options(recorder))

        #expect(result.state == .succeeded)
        #expect(chargeReads() == 3)
        #expect(clock.sleeps == [1, 1])
        #expect(recorder.states == [.requested, .processing, .succeeded])
    }

    @Test func theIntervalIsTheCallersOwn() async throws {
        serveCharges([charge("PROCESSING"), charge("PROCESSING"), charge("SUCCEEDED")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        _ = try await session.awaitChargeState(options(recorder, interval: 2.5))

        #expect(clock.sleeps == [2.5, 2.5])
    }

    /// The interval is counted from the answer, not from the request: a slow gateway does not
    /// shorten the pause after it.
    @Test func theIntervalStartsWhenTheAnswerArrives() async throws {
        let clock = VirtualClock(), recorder = Recorder()
        serveCharges([charge("PROCESSING"), charge("SUCCEEDED")]) { clock.advance(0.5) }
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        _ = try await session.awaitChargeState(options(recorder))

        #expect(clock.sleeps == [1])
        #expect(clock.now == 2)
    }

    /// The last state goes to the callback too, before the error, so the app can show it.
    @Test func aFailedChargeIsPaymentDeclinedWithTheCharge() async throws {
        serveCharges([charge("PROCESSING"), charge("FAILED", failReason: "Insufficient funds")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let error = try #require(await failure { try await session.awaitChargeState(options(recorder)) })

        #expect(error.code == .paymentDeclined)
        #expect(error.chargeState?.state == .failed)
        #expect(error.chargeState?.failReason == "Insufficient funds")
        #expect(error.message.contains("Insufficient funds"))
        #expect(recorder.states == [.processing, .failed])
        #expect(chargeReads() == 2)
    }

    // MARK: Timeout

    /// The read on the deadline decides: 31 reads for 30 seconds at one a second, and the clock
    /// stands at the timeout, not an interval past it. The error carries that last read.
    @Test func aChargeStuckInProcessingTimesOutOnTheDeadline() async throws {
        serveCharges([charge("PROCESSING")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let error = try #require(await failure { try await session.awaitChargeState(options(recorder)) })

        #expect(error.code == .paymentTimeout)
        #expect(error.chargeState?.state == .processing)
        #expect(chargeReads() == 31)
        #expect(clock.now == 30)
        #expect(recorder.states.count == 31)
    }

    /// A charge that moves on the deadline read is handled as that state, not as a timeout.
    @Test func aChargeThatMovesOnTheDeadlineReadIsThatState() async throws {
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        serveCharges(Array(repeating: charge("PROCESSING"), count: 30) + [charge("SUCCEEDED")])
        let result = try await session.awaitChargeState(options(recorder))
        #expect(result.state == .succeeded)
        #expect(chargeReads() == 31)
        #expect(clock.now == 30)

        serveCharges(Array(repeating: charge("PROCESSING"), count: 30) + [charge("FAILED", failReason: "declined")])
        let error = try #require(await failure { try await session.awaitChargeState(options(recorder)) })
        #expect(error.code == .paymentDeclined)
        #expect(chargeReads() == 31)
    }

    /// An answer that arrives after the deadline is never cut off: one that moved is handled as
    /// that state, one still undecided is the timeout, without another read.
    @Test func anAnswerAfterTheDeadlineIsNeverCutOff() async throws {
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        serveCharges([charge("SUCCEEDED")]) { clock.advance(40) }
        let result = try await session.awaitChargeState(options(recorder))
        #expect(result.state == .succeeded)
        #expect(chargeReads() == 1)

        serveCharges([charge("PROCESSING")]) { clock.advance(40) }
        let error = try #require(await failure { try await session.awaitChargeState(options(recorder)) })
        #expect(error.code == .paymentTimeout)
        #expect(chargeReads() == 1)
        #expect(clock.sleeps.isEmpty)
    }

    /// The last wait is cut to what is left of the timeout rather than running a full interval.
    @Test func theLastWaitBeforeTheTimeoutIsShortened() async throws {
        serveCharges([charge("REQUESTED")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let error = try #require(await failure {
            try await session.awaitChargeState(options(recorder, interval: 7, initialTimeout: 30))
        })

        #expect(error.code == .paymentTimeout)
        #expect(clock.sleeps == [7, 7, 7, 7, 2])
        #expect(chargeReads() == 6)
    }

    /// A state this SDK does not know is waited out like processing, and times out like it.
    @Test func anUnknownStateIsWaitedOutAndTimesOut() async throws {
        serveCharges([charge("SETTLING")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let error = try #require(await failure {
            try await session.awaitChargeState(options(recorder, initialTimeout: 3))
        })

        #expect(error.code == .paymentTimeout)
        #expect(error.chargeState?.state == .unknown)
        #expect(recorder.states.first == .unknown)
        #expect(chargeReads() == 4)
    }

    // MARK: 3DS

    /// In manual mode the first address lifts the timeout for good: the charge may stay in
    /// processing for as long as the user needs.
    @Test func inManualModeAnActionRequiredLiftsTheTimeoutForGood() async throws {
        var answers = [charge("ACTION_REQUIRED", redirect: "https://acs.example/a")]
        answers += Array(repeating: charge("PROCESSING"), count: 40)
        answers.append(charge("SUCCEEDED"))
        serveCharges(answers)
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let result = try await session.awaitChargeState(options(recorder, threeDSMode: .manual))

        #expect(result.state == .succeeded)
        #expect(clock.now == 41)
        #expect(chargeReads() == 42)
    }

    /// An `ACTION_REQUIRED` without an address, missing or empty, is no challenge: nothing is
    /// reported or opened, and the timeout stays armed, in either mode.
    @Test func anActionRequiredWithoutAnAddressIsWaitedOutAndTimesOut() async throws {
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        for mode in [ThreeDSMode.automatic, .manual] {
            serveCharges([charge("ACTION_REQUIRED"), charge("ACTION_REQUIRED", redirect: ""), charge("PROCESSING")])
            let error = try #require(await failure {
                try await session.awaitChargeState(options(recorder, initialTimeout: 3, threeDSMode: mode))
            })
            #expect(error.code == .paymentTimeout)
            #expect(chargeReads() == 4)
        }
        #expect(recorder.redirects.isEmpty)
        #expect(recorder.verifications.isEmpty)
    }

    /// The challenge runs once per address with the options' return URL and presenter, and the
    /// polling carries on after it; the same address reported again is not opened again.
    @Test func anAutomaticChallengeRunsOncePerAddressAndPollingContinues() async throws {
        serveCharges([
            charge("ACTION_REQUIRED", redirect: "https://acs.example/a"),
            charge("ACTION_REQUIRED", redirect: "https://acs.example/a"),
            charge("PROCESSING"),
            charge("SUCCEEDED"),
        ])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)
        let returnURL = URL(string: "https://shop.example/return")!
        let presenter = await MainActor.run { UIViewController() }

        let result = try await session.awaitChargeState(
            options(recorder, returnURL: returnURL, presenting: presenter)
        )

        #expect(result.state == .succeeded)
        #expect(recorder.redirects == ["https://acs.example/a"])
        #expect(recorder.verifications.count == 1)
        #expect(recorder.verifications.first?.redirect == "https://acs.example/a")
        #expect(recorder.verifications.first?.returnURL == returnURL)
        #expect(recorder.verifications.first?.presenting === presenter)
        #expect(chargeReads() == 4)
        #expect(clock.sleeps == [1, 1, 1])
    }

    /// After the challenge the gateway gets the initial timeout again: a charge it never decides
    /// ends in PAYMENT_007 instead of being polled forever.
    @Test func afterAnAutomaticChallengeTheTimeoutStartsAgain() async throws {
        serveCharges([charge("ACTION_REQUIRED", redirect: "https://acs.example/a"), charge("PROCESSING")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder) { _ in clock.advance(120) }

        let error = try #require(await failure {
            try await session.awaitChargeState(options(recorder, initialTimeout: 5))
        })

        #expect(error.code == .paymentTimeout)
        #expect(error.chargeState?.state == .processing)
        #expect(recorder.verifications.count == 1)
        // The challenge took two minutes; the five seconds are counted from its return.
        #expect(clock.now == 125)
        #expect(chargeReads() == 6)
    }

    /// The same address echoed after the challenge is not a new challenge: it neither opens the
    /// screen again nor lifts the fresh timeout, so the charge ends in PAYMENT_007 on it.
    @Test func theSameAddressAfterTheChallengeKeepsTheFreshTimeout() async throws {
        serveCharges([
            charge("ACTION_REQUIRED", redirect: "https://acs.example/a"),
            charge("ACTION_REQUIRED", redirect: "https://acs.example/a"),
        ])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let error = try #require(await failure {
            try await session.awaitChargeState(options(recorder, initialTimeout: 5))
        })

        #expect(error.code == .paymentTimeout)
        #expect(error.chargeState?.state == .actionRequired)
        #expect(recorder.verifications.count == 1)
        #expect(recorder.redirects == ["https://acs.example/a"])
        #expect(clock.now == 5)
        #expect(chargeReads() == 6)
    }

    /// A new address after the challenge is a new challenge, which lifts the timeout again.
    @Test func aNewAddressAfterTheChallengeIsVerifiedAgain() async throws {
        var answers = [charge("ACTION_REQUIRED", redirect: "https://acs.example/a"), charge("PROCESSING")]
        answers.append(charge("ACTION_REQUIRED", redirect: "https://acs.example/b"))
        answers += Array(repeating: charge("PROCESSING"), count: 4)
        answers.append(charge("SUCCEEDED"))
        serveCharges(answers)
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let result = try await session.awaitChargeState(options(recorder, initialTimeout: 5))

        #expect(result.state == .succeeded)
        #expect(recorder.verifications.map(\.redirect) == ["https://acs.example/a", "https://acs.example/b"])
        // The second challenge restarted the five seconds at t = 2; the result lands on t = 7.
        #expect(chargeReads() == 8)
        #expect(clock.now == 7)
    }

    /// The verification's own error, PAYMENT_011 for a closed screen as here, PAYMENT_010 for an
    /// unreachable challenge or PAYMENT_008 for a busy one, ends the call unchanged, and nothing
    /// is read after it.
    @Test func aFailedChallengeEndsTheCallWithItsOwnError() async throws {
        serveCharges([charge("ACTION_REQUIRED", redirect: "https://acs.example/a"), charge("SUCCEEDED")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder) { _ in
            throw GopaySDKError(.paymentCancelled, message: "closed")
        }

        let error = try #require(await failure { try await session.awaitChargeState(options(recorder)) })

        #expect(error.code == .paymentCancelled)
        #expect(error.message == "closed")
        #expect(chargeReads() == 1)
        #expect(recorder.states == [.actionRequired])
    }

    /// A redirect that is not a web address is PAYMENT_010 with the manual call's own wording,
    /// whether the string fails to become a URL or, as here on iOS 17 and later where it is
    /// percent-encoded into one, the URL has no scheme the WebView could load.
    @Test func aRedirectThatIsNotAnAddressIsUnreachable() async throws {
        serveCharges([charge("ACTION_REQUIRED", redirect: "not a url"), charge("SUCCEEDED")])
        let session = try await makeSession()
        let clock = VirtualClock()
        await session.useAwaitChargeHooks(AwaitChargeHooks(
            now: { clock.now }, sleep: { try await clock.sleep($0) }, verify: AwaitChargeHooks.live.verify
        ))

        let error = try #require(await failure { try await session.awaitChargeState() })

        #expect(error.code == .paymentVerificationUnreachable)
        #expect(error.message.hasPrefix(GopayVerificationNavigationPolicy.unloadableRedirectMessage))
        #expect(chargeReads() == 1)
    }

    /// In manual mode each new address is reported once and the challenge is left to the app.
    @Test func manualModeReportsEachAddressOnceAndNeverOpensIt() async throws {
        serveCharges([
            charge("ACTION_REQUIRED", redirect: "https://acs.example/a"),
            charge("ACTION_REQUIRED", redirect: "https://acs.example/a"),
            charge("ACTION_REQUIRED", redirect: "https://acs.example/b"),
            charge("ACTION_REQUIRED"),
            charge("SUCCEEDED"),
        ])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let result = try await session.awaitChargeState(options(recorder, threeDSMode: .manual))

        #expect(result.state == .succeeded)
        #expect(recorder.redirects == ["https://acs.example/a", "https://acs.example/b"])
        #expect(recorder.verifications.isEmpty)
        #expect(chargeReads() == 5)
    }

    /// An infinite interval, which a bridge can hand over, is a wait without end rather than a
    /// trap in the conversion to nanoseconds.
    @Test func anInfiniteIntervalIsWaitedOutNotTrappedOn() async throws {
        serveCharges([charge("ACTION_REQUIRED", redirect: "https://acs.example/a"), charge("SUCCEEDED")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let result = try await session.awaitChargeState(
            options(recorder, interval: .infinity, threeDSMode: .manual)
        )

        #expect(result.state == .succeeded)
        #expect(clock.sleeps == [.infinity])
        #expect(AwaitChargeHooks.nanoseconds(for: .infinity) > UInt64.max - 1_000_000_000)
        #expect(AwaitChargeHooks.nanoseconds(for: 1e30) == AwaitChargeHooks.nanoseconds(for: .infinity))
        #expect(AwaitChargeHooks.nanoseconds(for: 1.5) == 1_500_000_000)
        #expect(AwaitChargeHooks.nanoseconds(for: -1) == 0)
        #expect(AwaitChargeHooks.nanoseconds(for: .nan) == 0)
    }

    // MARK: Failures and cancellation

    /// The read's own code, here a 5xx, ends the call; the status with it.
    @Test func aFailedReadEndsTheCallWithItsOwnCode() async throws {
        serveCharges([(200, charge("PROCESSING")), (503, ["error": "SERVICE_UNAVAILABLE"])])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let error = try #require(await failure { try await session.awaitChargeState(options(recorder)) })

        #expect(error.code == .networkServerError)
        #expect(error.httpStatus == 503)
        #expect(chargeReads() == 2)
        #expect(recorder.states == [.processing])
    }

    @Test func aClosedSessionIsReported() async throws {
        serveCharges([charge("SUCCEEDED")])
        let session = try await makeSession()
        await session.close()

        let error = try #require(await failure { try await session.awaitChargeState() })

        #expect(error.code == .authPaymentSessionClosed)
        #expect(chargeReads() == 0)
    }

    @Test func anIntervalOrTimeoutThatIsNotPositiveIsRejected() async throws {
        serveCharges([charge("SUCCEEDED")])
        let session = try await makeSession()

        let zeroInterval = try #require(await failure {
            try await session.awaitChargeState(AwaitChargeOptions(interval: 0))
        })
        let negativeTimeout = try #require(await failure {
            try await session.awaitChargeState(AwaitChargeOptions(initialTimeout: -1))
        })

        #expect(zeroInterval.code == .validationInvalidInput)
        #expect(negativeTimeout.code == .validationInvalidInput)
        #expect(chargeReads() == 0)
    }

    /// Cancelling the awaiting task during the wait between two reads is a `CancellationError`
    /// and no read goes out after it.
    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringTheWaitStopsThePolling() async throws {
        serveCharges([charge("PROCESSING")])
        let recorder = Recorder()
        let session = try await makeSession()
        await session.useAwaitChargeHooks(AwaitChargeHooks(
            now: { 0 },
            // A wait that only cancellation ends.
            sleep: { _ in try await Task.sleep(nanoseconds: 60_000_000_000) },
            verify: { _, _, _, _ in }
        ))

        let task = Task { try await session.awaitChargeState(options(recorder)) }
        // Past the read and into the wait: the callback has seen the state.
        try await waitUntil { !recorder.states.isEmpty }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(chargeReads() == 1)
    }

    /// Cancelling while a read is in flight ends the call with `CancellationError` once the read
    /// is back: the answer is neither reported nor acted on, even when it would have been the
    /// result.
    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringTheReadReportsNothing() async throws {
        serveCharges([charge("SUCCEEDED")])
        // The stub answers only after a second, so the cancel lands while the read is in flight.
        StubURLProtocol.reset(delay: 1) { req in
            (req.url?.path ?? "").hasSuffix("oauth2/token") ? tokenResponse() : (200, json(charge("SUCCEEDED")))
        }
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder)

        let task = Task { try await session.awaitChargeState(options(recorder)) }
        try await waitUntil { chargeReads() == 1 }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(recorder.states.isEmpty)
        #expect(chargeReads() == 1)
    }

    /// Cancelling while the challenge is up ends the challenge, which is the manual call's own
    /// rule, and the polling with it.
    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringTheChallengeStopsThePolling() async throws {
        serveCharges([charge("ACTION_REQUIRED", redirect: "https://acs.example/a"), charge("SUCCEEDED")])
        let clock = VirtualClock(), recorder = Recorder()
        let session = try await makePollingSession(clock: clock, recorder: recorder) { _ in
            // The screen stays up until the awaiting task is cancelled, as the real one does.
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }

        let task = Task { try await session.awaitChargeState(options(recorder)) }
        try await waitUntil { !recorder.verifications.isEmpty }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(chargeReads() == 1)
        #expect(recorder.verifications.count == 1)
    }
}
