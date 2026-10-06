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

    /// Everything the controller cancels from a policy decision comes back as WebKitErrorDomain
    /// 102. The hand-off to a banking app deliberately reports nothing, so without this it would
    /// be reported as a dead challenge instead.
    @Test func loadError_policyCancelledNavigationIsSuppressed() {
        let interrupted = NSError(domain: "WebKitErrorDomain", code: 102)
        #expect(GopayVerificationFailureMapper.failure(
            forLoadError: interrupted, unsupportedSchemeIsExpected: true
        ) == nil)
    }

    /// A load stopped through the URL loading system, e.g. a navigation replaced by the next one
    /// in a redirect chain. Never the first outcome, so reporting it would overwrite the real one.
    @Test func loadError_cancelledNavigationIsSuppressed() {
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        #expect(GopayVerificationFailureMapper.failure(
            forLoadError: cancelled, unsupportedSchemeIsExpected: false
        ) == nil)
    }

    /// The suppression is keyed on the domain too: code 102 elsewhere is a real failure.
    @Test func loadError_sameCodeInAnotherDomainIsStillReported() throws {
        let other = NSError(domain: NSURLErrorDomain, code: 102)
        let failure = try #require(GopayVerificationFailureMapper.failure(
            forLoadError: other, unsupportedSchemeIsExpected: true
        ))
        #expect(failure.code == .paymentVerificationUnreachable)
    }

    /// A scheme nobody can open, once a hand-off has been attempted, is a hand-off that did not
    /// happen rather than a dead challenge.
    @Test func loadError_unsupportedSchemeAfterAHandOffIsSuppressed() {
        let unsupported = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL)
        #expect(GopayVerificationFailureMapper.failure(
            forLoadError: unsupported, unsupportedSchemeIsExpected: true
        ) == nil)
    }

    /// Before any hand-off there is only one URL the WebView was given, so the same error means
    /// the redirect URL itself is unloadable. Suppressing it here is what would leave the caller
    /// waiting forever.
    @Test func loadError_unsupportedSchemeOnTheFirstLoadIsUnreachable() throws {
        let unsupported = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL)
        let failure = try #require(GopayVerificationFailureMapper.failure(
            forLoadError: unsupported, unsupportedSchemeIsExpected: false
        ))
        #expect(failure.code == .paymentVerificationUnreachable)
    }

    @Test func loadError_deadHostIsUnreachable() throws {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        let failure = try #require(GopayVerificationFailureMapper.failure(
            forLoadError: offline, unsupportedSchemeIsExpected: false
        ))

        #expect(failure.code == .paymentVerificationUnreachable)
        #expect(failure.httpStatus == nil)
        #expect((failure.underlying as NSError?)?.code == NSURLErrorCannotFindHost)
    }
}

struct ChargeVerificationNavigationPolicyTests {

    private func handsOff(_ string: String, isMainFrameNavigation: Bool = true) -> Bool {
        GopayVerificationNavigationPolicy.handsOffToAnotherApp(
            URL(string: string)!,
            isMainFrameNavigation: isMainFrameNavigation
        )
    }

    /// The challenge itself stays in the WebView.
    @Test func aWebURLStaysInTheWebView() {
        #expect(handsOff("https://3ds.example/step") == false)
        #expect(handsOff("http://3ds.example/step") == false)
        #expect(handsOff("about:blank") == false)
        #expect(handsOff("data:text/html,<p>hi</p>") == false)
    }

    /// The schemes European ACS actually push the main frame into.
    @Test func aBankingSchemeGoesToTheSystem() {
        #expect(handsOff("bankid://auth?token=x"))
        #expect(handsOff("intent://pay#Intent;scheme=csob;end"))
        #expect(handsOff("tel:+420800111222"))
    }

    /// A scheme is a scheme however the ACS spells it.
    @Test func theSchemeIsMatchedWithoutCase() {
        #expect(handsOff("HTTPS://3ds.example/step") == false)
        #expect(handsOff("BankID://auth"))
    }

    /// An iframe inside the ACS page must not be able to throw the user out of the app.
    @Test func aSubframeNavigationIsNotHandedOff() {
        #expect(handsOff("bankid://auth", isMainFrameNavigation: false) == false)
    }

    // MARK: - Redirect URL on the way in

    private func redirectFailure(_ string: String) -> GopaySDKError? {
        GopayVerificationNavigationPolicy.loadFailure(forRedirect: URL(string: string)!)
    }

    @Test func aWebRedirectIsAccepted() {
        #expect(redirectFailure("https://3ds.example/step") == nil)
        #expect(redirectFailure("http://localhost:8080/step") == nil)
        #expect(redirectFailure("HTTPS://3ds.example/step") == nil)
    }

    /// The hole the hand-off suppression would otherwise open: this URL never reaches a navigation
    /// decision, so without the check on the way in its load failure is swallowed and the caller
    /// waits for an outcome that cannot come.
    @Test func aNonWebRedirectIsRejectedBeforeAnythingIsPresented() throws {
        let failure = try #require(redirectFailure("bankid://auth?token=x"))
        #expect(failure.code == .paymentVerificationUnreachable)
    }

    @Test func aRedirectWithNoSchemeIsRejected() throws {
        let failure = try #require(redirectFailure("3ds.example/step"))
        #expect(failure.code == .paymentVerificationUnreachable)
    }

    /// A scheme the WebView could technically load is still not a 3DS redirect.
    @Test func aNonHttpWebSchemeIsRejectedAsARedirect() {
        #expect(redirectFailure("about:blank") != nil)
        #expect(redirectFailure("file:///etc/passwd") != nil)
        #expect(redirectFailure("javascript:alert(1)") != nil)
    }

    // MARK: - Return URL

    private func completes(_ string: String, returnURL: String?) -> Bool {
        let prefix = GopayVerificationNavigationPolicy.completionPrefix(
            forReturnURL: returnURL.flatMap(URL.init(string:))
        )
        return GopayVerificationNavigationPolicy.completesVerification(
            URL(string: string)!,
            completionPrefix: prefix
        )
    }

    /// The merchant's own return URL ends the verification, whatever the gateway appends to it.
    @Test func theReturnURLFromTheChargeEndsTheVerification() {
        #expect(completes("https://shop.example/return", returnURL: "https://shop.example/return"))
        #expect(completes("https://shop.example/return?id=51&state=done", returnURL: "https://shop.example/return"))
        #expect(completes("https://3ds.example/step", returnURL: "https://shop.example/return") == false)
    }

    /// Without a return URL the SDK falls back to its own constant.
    @Test func withoutAReturnURLTheConstantEndsTheVerification() {
        #expect(completes(GopaySDK.chargeReturnURL, returnURL: nil))
        #expect(completes(GopaySDK.chargeReturnURL + "?id=51", returnURL: nil))
        #expect(completes("https://3ds.example/step", returnURL: nil) == false)
    }

    /// The merchant's address wins: the constant is a fallback, not a second way out.
    @Test func withAReturnURLTheConstantNoLongerEndsTheVerification() {
        #expect(completes(GopaySDK.chargeReturnURL, returnURL: "https://shop.example/return") == false)
    }

    /// An address that cannot be the ACS coming back falls back to the constant. As a prefix,
    /// `https://` alone would match the challenge's first navigation.
    @Test func anUnusableReturnURLFallsBackToTheConstant() {
        let unusable = [
            "", "   ", "gopaysdk://charge-return", "https://", "shop.example/return",
            "https://:443", "https://user@/r", "https://@/r"
        ]
        for address in unusable {
            #expect(prefix(address) == GopaySDK.chargeReturnURL, "\(address) should fall back")
        }
        #expect(completes("https://3ds.example/step", returnURL: "https://") == false)
    }

    private func prefix(_ returnURL: String) -> String {
        GopayVerificationNavigationPolicy.completionPrefix(forReturnURL: URL(string: returnURL))
    }

    /// WebKit reports a navigation with its scheme and host in lowercase, so the return URL is
    /// matched in that form whatever case the merchant created the payment with.
    @Test func theReturnURLIsMatchedWithoutCaseInSchemeAndHost() {
        #expect(prefix("HTTPS://Shop.Example/return") == "https://shop.example/return")
        #expect(completes("https://shop.example/return?id=1", returnURL: "HTTPS://Shop.Example/return"))
    }

    /// The rest of the canonical form: path and query keep their case, a default port and
    /// trailing whitespace go, an empty path becomes `/`. Same results as the Android SDK.
    @Test func theReturnURLIsMatchedInItsCanonicalForm() {
        #expect(prefix("https://Shop.Example/Return?Id=A") == "https://shop.example/Return?Id=A")
        #expect(prefix("https://shop.example/r ") == "https://shop.example/r")
        #expect(prefix("https://Shop.Example:443/r") == "https://shop.example/r")
        #expect(prefix("http://shop.example:80/r") == "http://shop.example/r")
        #expect(prefix("https://shop.example:8443/r") == "https://shop.example:8443/r")
        #expect(prefix("https://Shop.Example") == "https://shop.example/")
        #expect(prefix("https://user@Shop.Example/r") == "https://user@shop.example/r")
    }

    /// An internationalised host is matched in the punycode form WebKit navigates with. iOS 13 to
    /// 16 cannot parse such an address at all, which leaves the caller with no URL to pass.
    @Test func anInternationalisedHostIsMatchedAsPunycode() {
        #expect(prefix("https://obchod.čz/r") == "https://obchod.xn--z-cia/r")
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
            returnURL: nil,
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

    /// The merchant's return URL from the charge ends the challenge in the controller itself, and
    /// the SDK constant no longer does.
    @Test func theControllerEndsTheChallengeOnTheMerchantsReturnURL() {
        var results: [GopayChargeVerificationResult] = []
        let controller = GopayChargeVerificationViewController(
            redirectURL: URL(string: "https://3ds.example/step")!,
            returnURL: URL(string: "https://shop.example/return"),
            onResult: { results.append($0) }
        )
        controller.viewDidAppear(false)

        let constant = decide(controller, GopaySDK.chargeReturnURL)
        #expect(constant == .allow)
        #expect(results.isEmpty)

        let merchant = decide(controller, "https://shop.example/return?id=51")
        #expect(merchant == .cancel)
        #expect(results.count == 1)
        guard case .completed = results.first else {
            Issue.record("expected the verification to complete, got \(String(describing: results.first))")
            return
        }
    }

    /// Runs the navigation decision for a main-frame navigation to `url`.
    private func decide(
        _ controller: GopayChargeVerificationViewController,
        _ url: String
    ) -> WKNavigationActionPolicy? {
        var policy: WKNavigationActionPolicy?
        controller.webView(
            stubWebView,
            decidePolicyFor: StubNavigationAction(url: URL(string: url)!),
            decisionHandler: { policy = $0 }
        )
        return policy
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

/// A main-frame navigation to a given URL. WebKit offers no way to build one, so the properties
/// the navigation decision reads are overridden.
private final class StubNavigationAction: WKNavigationAction {
    private let stubRequest: URLRequest

    init(url: URL) {
        stubRequest = URLRequest(url: url)
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var targetFrame: WKFrameInfo? { StubMainFrame.shared }
}

private final class StubMainFrame: WKFrameInfo {
    /// Never released: a `WKFrameInfo` built outside WebKit traps in its own `dealloc`.
    static let shared = StubMainFrame()

    override var isMainFrame: Bool { true }
}
