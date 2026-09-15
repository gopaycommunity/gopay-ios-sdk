//
//  ChargeVerificationTests.swift
//  sdkTests
//
//  Pins the decisions the 3DS verification flow makes: which HTTP statuses count as an
//  unreachable challenge, which load failures must not be reported at all, and the rule that
//  only the first outcome reaches the caller.
//

import Testing
import Foundation
import WebKit
@testable import sdk

struct ChargeVerificationFailureMapperTests {

    // MARK: - Status boundary

    @Test func status_belowFourHundredIsNotAFailure() {
        #expect(GopayVerificationFailureMapper.failure(forStatus: 200) == nil)
        #expect(GopayVerificationFailureMapper.failure(forStatus: 302) == nil)
        #expect(GopayVerificationFailureMapper.failure(forStatus: 399) == nil)
    }

    @Test func status_fourHundredAndAboveIsUnreachable() throws {
        for status in [400, 404, 499, 500, 503] {
            let failure = try #require(
                GopayVerificationFailureMapper.failure(forStatus: status),
                "HTTP \(status) should be reported"
            )
            #expect(failure.code == .paymentVerificationUnreachable)
            #expect(failure.httpStatus == status)
        }
    }

    /// The dead redirect the gateway hands out for part of the charges.
    @Test func status_deadRedirectCarriesItsStatus() throws {
        let failure = try #require(GopayVerificationFailureMapper.failure(forStatus: 404))
        #expect(failure.errorDescription?.contains("PAYMENT_010") == true)
        #expect(failure.errorDescription?.contains("404") == true)
    }

    // MARK: - Load errors

    /// A load stopped through the URL loading system, e.g. a navigation replaced by the next one
    /// in a redirect chain. Never the first outcome, so reporting it would overwrite the real one.
    @Test func loadError_cancelledNavigationIsSuppressed() {
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        #expect(GopayVerificationFailureMapper.failure(forLoadError: cancelled) == nil)
    }


    @Test func loadError_deadHostIsUnreachable() throws {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        let failure = try #require(GopayVerificationFailureMapper.failure(forLoadError: offline))

        #expect(failure.code == .paymentVerificationUnreachable)
        #expect(failure.httpStatus == nil)
        #expect((failure.underlying as NSError?)?.code == NSURLErrorCannotFindHost)
    }
}

@MainActor
struct ChargeVerificationReportingTests {

    /// The delegate callbacks ignore their WebView argument; this only satisfies the signature.
    private var stubWebView: WKWebView { WKWebView() }

    private func makeController(
        onResult: @escaping (GopayChargeVerificationResult) -> Void
    ) -> GopayChargeVerificationViewController {
        GopayChargeVerificationViewController(
            redirectURL: URL(string: "https://3ds.example/step")!,
            returnURLString: "https://gopay.com/sdk/charge-return",
            onResult: onResult
        )
    }

    /// An outcome that beats the presentation animation has to wait: dismissing mid-transition
    /// does nothing and its completion never fires, which used to strand the modal for good.
    @Test func resultBeforePresentationFinishesIsHeldUntilItDoes() {
        var results: [GopayChargeVerificationResult] = []
        let controller = makeController { results.append($0) }

        controller.report(.cancelled)
        #expect(results.isEmpty)

        controller.viewDidAppear(false)
        #expect(results.count == 1)
    }

    /// The continuation behind `onResult` would trap on a second resume.
    @Test func onlyTheFirstOutcomeIsForwarded() {
        var results: [GopayChargeVerificationResult] = []
        let controller = makeController { results.append($0) }
        controller.viewDidAppear(false)

        controller.report(.completed)
        controller.report(.cancelled)
        controller.report(.failed(GopaySDKError(.paymentVerificationUnreachable, message: "late")))

        #expect(results.count == 1)
        if case .completed = results[0] {} else {
            Issue.record("expected the first outcome to win, got \(results[0])")
        }
    }

    /// The line the whole feature is drawn on: before the challenge starts rendering a dead page
    /// is a `PAYMENT_010` the host can act on, afterwards the user may already have answered and
    /// the same failure is a cancellation the host settles by reading the charge state.
    @Test func aFailureBeforeTheFirstCommitIsReportedAsUnreachable() {
        var results: [GopayChargeVerificationResult] = []
        let controller = makeController { results.append($0) }
        controller.viewDidAppear(false)

        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        controller.webView(stubWebView, didFailProvisionalNavigation: nil, withError: offline)

        #expect(results.count == 1)
        if case .failed(let error) = results.first {
            #expect(error.code == .paymentVerificationUnreachable)
        } else {
            Issue.record("expected a failure, got \(String(describing: results.first))")
        }
    }

    @Test func aFailureAfterTheFirstCommitIsReportedAsACancellation() {
        var results: [GopayChargeVerificationResult] = []
        let controller = makeController { results.append($0) }
        controller.viewDidAppear(false)

        controller.webView(stubWebView, didCommit: nil)
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        controller.webView(stubWebView, didFailProvisionalNavigation: nil, withError: offline)

        #expect(results.count == 1)
        if case .cancelled = results.first {} else {
            Issue.record("expected a cancellation, got \(String(describing: results.first))")
        }
    }

    /// A buffered outcome still blocks the ones behind it, so the flush cannot double-report.
    @Test func aBufferedOutcomeStillBlocksLaterOnes() {
        var results: [GopayChargeVerificationResult] = []
        let controller = makeController { results.append($0) }

        controller.report(.failed(GopaySDKError(.paymentVerificationUnreachable, message: "dead")))
        controller.report(.cancelled)
        controller.viewDidAppear(false)

        #expect(results.count == 1)
        if case .failed(let error) = results[0] {
            #expect(error.message == "dead")
        } else {
            Issue.record("expected the buffered failure, got \(results[0])")
        }
    }
}
