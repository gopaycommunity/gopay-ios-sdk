import UIKit
@preconcurrency import WebKit

/// Outcome of the charge verification WebView flow.
enum GopayChargeVerificationResult {
    case completed
    case cancelled
    /// The verification page could not be loaded at all, so the user never got a challenge to
    /// answer. Distinct from ``cancelled``, which is the user walking away from a live page.
    case failed(GopaySDKError)
}

/// Maps a failed verification load onto the error the host should see.
///
/// Pure, so the boundaries can be pinned by tests without driving a live WKWebView: the status
/// mapping and the suppressions are the only non-trivial decisions in the whole flow.
enum GopayVerificationFailureMapper {

    /// The error for a main-frame HTTP status, or `nil` when the response is fine to render.
    static func failure(forStatus status: Int) -> GopaySDKError? {
        guard status >= 400 else { return nil }
        return GopaySDKError(
            .paymentVerificationUnreachable,
            message: "The 3DS verification page could not be loaded: HTTP \(status)",
            httpStatus: status
        )
    }

    /// WebKit's own domain. Not exposed to Swift, so the string and the code are spelled out.
    private static let webKitErrorDomain = "WebKitErrorDomain"
    /// `WebKitErrorFrameLoadInterruptedByPolicyChange`: the navigation was cancelled by a policy
    /// decision, which is exactly what this controller does to intercept a navigation.
    private static let webKitFrameLoadInterrupted = 102

    /// The error for a WebKit load failure, or `nil` when it must not be reported at all.
    ///
    /// - Parameter unsupportedSchemeIsExpected: whether a scheme WKWebView cannot load is
    ///   explained by something that already happened — a hand-off this controller attempted, or a
    ///   challenge that has started rendering and can send the user anywhere it likes. On the
    ///   first load nothing explains it: the redirect URL itself is unloadable and reporting it is
    ///   the only thing standing between the caller and a wait that never ends.
    static func failure(forLoadError error: Error, unsupportedSchemeIsExpected: Bool) -> GopaySDKError? {
        let nsError = error as NSError
        // Everything this controller cancels from a policy decision — the return URL, a 4xx
        // response, a hand-off to a banking app — comes back here as WebKitErrorDomain 102, not as
        // NSURLErrorCancelled. Without this the hand-off, which deliberately reports nothing,
        // would be reported as a dead challenge instead.
        if nsError.domain == webKitErrorDomain, nsError.code == webKitFrameLoadInterrupted { return nil }
        // A load stopped through the URL loading system, e.g. a navigation replaced by the next
        // one in a redirect chain. Never the first outcome, so reporting it would only overwrite
        // the real one.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return nil }
        // A scheme nobody can open reaches here instead of the external hand-off. Killing the
        // verification over it would be the same regression as handling it in the failure path —
        // but only once a hand-off or the challenge itself can account for it. Suppressed
        // unconditionally it would swallow the very first load, so a redirect URL the WebView
        // cannot load would leave the caller waiting for an outcome that never comes.
        if unsupportedSchemeIsExpected,
           nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorUnsupportedURL { return nil }
        return GopaySDKError(
            .paymentVerificationUnreachable,
            message: "The 3DS verification page could not be loaded",
            underlying: error
        )
    }
}

/// Decides which navigations leave the verification WebView for another app.
///
/// Pure and kept out of the controller for the same reason as ``GopayVerificationFailureMapper``:
/// it is a decision the whole hand-off rests on, and driving a live WKWebView to reach it is not
/// a way to pin it.
enum GopayVerificationNavigationPolicy {

    /// Schemes a WKWebView can load itself. Everything else belongs to another app. The Android
    /// SDK keeps the same seven.
    static let webSchemes: Set<String> = [
        "http", "https", "about", "data", "blob", "file", "javascript"
    ]

    /// Whether this navigation has to be handed to another app.
    ///
    /// - Parameters:
    ///   - url: The URL the navigation is going to.
    ///   - isMainFrameNavigation: Whether the navigation concerns the main frame — either as its
    ///     target, or, for a new window, as the frame that asked for it. An iframe inside the ACS
    ///     page must not be able to throw the user out of the app on its own.
    static func handsOffToAnotherApp(_ url: URL, isMainFrameNavigation: Bool) -> Bool {
        guard isMainFrameNavigation, let scheme = url.scheme?.lowercased() else { return false }
        return !webSchemes.contains(scheme)
    }

    /// Schemes a 3DS redirect URL may arrive with. The gateway hands out `https`; `http` is here
    /// for a local test rig.
    static let redirectSchemes: Set<String> = ["http", "https"]

    /// The address whose arrival ends the verification.
    ///
    /// The ACS finishes by sending the browser to the `return_url` the payment was created with,
    /// which the charge response repeats. That is the merchant's own address, so it wins. Without
    /// a usable one the SDK falls back to ``GopaySDK/chargeReturnURL``, which only works when the
    /// payment was created with it. A blank address, one that is not `http(s)` and one without a
    /// host are not usable: as a prefix, `https://` would match the challenge's own first
    /// navigation and end the verification before the user saw it. The Android SDK applies the
    /// same conditions.
    ///
    /// The address is matched in a form close to the one WebKit reports a navigation in: scheme
    /// and host in lowercase, no default port, `/` for an empty path, no whitespace at the end.
    /// Path, query and fragment stay as they are, so what WebKit normalises there (`/../` in the
    /// path, `'` in the query) has to be written the same way in the return URL already. The return URL should carry no fragment (`#…`): what the
    /// gateway appends lands in front of it, and the address no longer matches.
    /// A host with non-ASCII characters is not recognised on iOS 13 to 16, where Foundation
    /// cannot parse such an address, and the SDK waits for the constant instead.
    static func completionPrefix(forReturnURL returnURL: URL?) -> String {
        guard let returnURL,
              var components = URLComponents(url: returnURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), redirectSchemes.contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty
        else { return GopaySDK.chargeReturnURL }
        components.scheme = scheme
        components.host = host
        if components.port == defaultPorts[scheme] { components.port = nil }
        if components.percentEncodedPath.isEmpty { components.percentEncodedPath = "/" }
        guard var canonical = components.string else { return GopaySDK.chargeReturnURL }
        // iOS 17 and later percent-encode trailing whitespace instead of refusing the string.
        while let tail = encodedWhitespace.first(where: { canonical.hasSuffix($0) }) {
            canonical.removeLast(tail.count)
        }
        return canonical
    }

    private static let defaultPorts = ["http": 80, "https": 443]
    private static let encodedWhitespace = ["%20", "%09", "%0A", "%0D"]

    /// Whether this navigation is the ACS coming back, i.e. the verification is over. Matched by
    /// prefix, so whatever the gateway appends to the address still counts.
    static func completesVerification(_ url: URL, completionPrefix: String) -> Bool {
        url.absoluteString.hasPrefix(completionPrefix)
    }

    /// The error for a redirect URL the verification WebView cannot load, or `nil` when it can.
    ///
    /// Checked on the way in, because nothing downstream would catch it: the navigation decision
    /// only sees URLs the page navigates to, never the one the WebView is told to load, so a
    /// `bankid://` or scheme-less redirect URL would reach no hand-off and no policy, only a load
    /// failure the hand-off suppression is there to swallow. The Android SDK validates the same
    /// thing at the same place and for the same reason.
    static func loadFailure(forRedirect url: URL) -> GopaySDKError? {
        guard let scheme = url.scheme?.lowercased(), redirectSchemes.contains(scheme) else {
            let named = url.scheme.map { "\($0):" } ?? "no scheme at all"
            return GopaySDKError(
                .paymentVerificationUnreachable,
                message: "The 3DS redirect URL is not a web address the verification WebView can load: \(named)"
            )
        }
        return nil
    }
}

/// Internal view controller that presents a WKWebView for 3DS / PSD2 / bank
/// verification. The navigation delegate intercepts the return URL to detect
/// when verification is complete, then dismisses itself.
final class GopayChargeVerificationViewController: UIViewController {

    private let redirectURL: URL
    /// Prefix of the address that ends the verification, from
    /// ``GopayVerificationNavigationPolicy/completionPrefix(forReturnURL:)``.
    private let completionPrefix: String
    private let onResult: (GopayChargeVerificationResult) -> Void

    /// `onResult` is contractually called once, but several delegate callbacks can race to report
    /// the same dead load (a cancelled response, then a provisional failure). Resuming the
    /// continuation behind it twice would trap, so the first outcome wins.
    private var hasReportedResult = false

    /// True once the presentation animation has finished and the controller is on screen.
    private var hasAppeared = false

    /// True once any navigation has committed, i.e. the challenge actually started rendering.
    ///
    /// Separates "the challenge never came up" from "something went wrong after it did". Once the
    /// user has answered, the ACS redirects towards the return URL and a transient error or a 4xx
    /// on an intermediate step is no reason to call the payment failed: it may well have gone
    /// through. Past this point a failure is reported as a cancellation so the host reads the
    /// charge state, which is what the documentation tells it to do.
    private var hasCommittedNavigation = false

    /// True once a navigation has been handed to another app.
    ///
    /// Together with ``hasCommittedNavigation`` it says whether an unsupported scheme reaching the
    /// failure path is accounted for. Before either, the only URL the WebView has been given is
    /// the redirect URL itself.
    private var hasAttemptedHandOff = false

    /// An outcome that arrived before the controller finished being presented.
    ///
    /// A dead host, a scheme WKWebView cannot open or an ATS-blocked `http://` fail in a few
    /// milliseconds, well inside the roughly 0.35 s presentation animation. Dismissing while that
    /// transition is still running does nothing and its completion never fires, which used to
    /// leave a white full screen modal with a Cancel button already silenced by
    /// ``hasReportedResult``, and the caller suspended forever. The outcome therefore waits here
    /// until ``viewDidAppear(_:)``.
    private var pendingResult: GopayChargeVerificationResult?

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator: UIActivityIndicatorView
        if #available(iOS 13.0, *) {
            indicator = UIActivityIndicatorView(style: .large)
        } else {
            indicator = UIActivityIndicatorView(style: .whiteLarge)
        }
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    // MARK: - Initialisation

    /// - Parameters:
    ///   - redirectURL: The URL to load in the WebView (from the charge action).
    ///   - returnURL: The `return_url` from the charge response. Navigation to it signals that
    ///     verification is complete. `nil` or an unusable one falls back to
    ///     ``GopaySDK/chargeReturnURL``.
    ///   - onResult: Called exactly once with the verification outcome.
    init(
        redirectURL: URL,
        returnURL: URL?,
        onResult: @escaping (GopayChargeVerificationResult) -> Void
    ) {
        self.redirectURL = redirectURL
        self.completionPrefix = GopayVerificationNavigationPolicy.completionPrefix(forReturnURL: returnURL)
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        setupNavigationBar()
        setupActivityIndicator()

        activityIndicator.startAnimating()
        webView.load(URLRequest(url: redirectURL))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        if let buffered = pendingResult {
            pendingResult = nil
            onResult(buffered)
        }
    }

    // MARK: - Layout

    private func setupNavigationBar() {
        let nav = UINavigationBar(frame: .zero)
        nav.translatesAutoresizingMaskIntoConstraints = false

        let item = UINavigationItem(title: "")
        item.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        nav.setItems([item], animated: false)

        view.addSubview(nav)
        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            nav.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nav.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: nav.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupActivityIndicator() {
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
        ])
    }

    // MARK: - External schemes

    /// Hands a non-web URL to the system, leaving the WebView where it is.
    ///
    /// European ACS routinely push the main frame into a banking app (`intent://`, `bankid://`,
    /// `csob://`, sometimes `tel:`). WKWebView cannot load those, so the navigation used to end up
    /// in the failure path and, since failures became an outcome, killed the verification outright
    /// while everything was in fact working. The user has to reach their bank, so the URL goes to
    /// the system.
    ///
    /// `open` is called without asking `canOpenURL` first, which is the whole reason this works:
    /// since iOS 9 `canOpenURL` answers `false` for any custom scheme the *host* app has not
    /// listed in its `LSApplicationQueriesSchemes`, and an SDK cannot declare that key on the
    /// host's behalf. `open` needs no such whitelist and reports back whether anything took the
    /// URL.
    private func openExternally(_ url: URL) {
        hasAttemptedHandOff = true
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            self?.handOffFailed(url)
        }
    }

    /// Nothing on the device answered the hand-off: the banking app is not installed, or the ACS
    /// sent a scheme this device knows nothing about.
    ///
    /// Only the scheme is logged. The URL itself belongs to the challenge and can carry a token.
    private func handOffFailed(_ url: URL) {
        let scheme = url.scheme ?? "a non-web scheme"
        GopaySDK.shared.logWarning(
            "The 3DS challenge asked to open \(scheme): and no app on this device took it"
        )
        // Reported as unreachable only while the challenge has not started rendering, the same
        // line the load failures are drawn on. Once the page is up it stays usable, and ending
        // the verification over a hand-off nobody answered would take away a challenge the user
        // can still complete by other means.
        guard !hasCommittedNavigation else { return }
        report(.failed(GopaySDKError(
            .paymentVerificationUnreachable,
            message: "The 3DS challenge could not be handed to another app: nothing on this device opens \(scheme):"
        )))
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        report(.cancelled)
    }

    /// Forwards the first outcome to the caller and ignores every later one.
    ///
    /// An outcome that beats the presentation animation is held in ``pendingResult`` and released
    /// by ``viewDidAppear(_:)``; dismissing mid-transition would otherwise strand the modal.
    ///
    /// Not private so tests can drive both rules without a live navigation.
    internal func report(_ result: GopayChargeVerificationResult) {
        guard !hasReportedResult else { return }
        hasReportedResult = true
        guard hasAppeared else {
            pendingResult = result
            return
        }
        onResult(result)
    }
}

// MARK: - WKNavigationDelegate

extension GopayChargeVerificationViewController: WKNavigationDelegate {

    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           GopayVerificationNavigationPolicy.completesVerification(url, completionPrefix: completionPrefix) {
            decisionHandler(.cancel)
            report(.completed)
            return
        }
        // A hand-off to a banking app is a step of the challenge, not a failure of it. A new
        // window has no target frame, so the frame that asked for it decides instead; either way
        // an iframe inside the ACS page cannot send the user off to another app.
        let isMainFrameNavigation = navigationAction.targetFrame?.isMainFrame
            ?? navigationAction.sourceFrame.isMainFrame
        if let url = navigationAction.request.url,
           GopayVerificationNavigationPolicy.handsOffToAnotherApp(url, isMainFrameNavigation: isMainFrameNavigation) {
            decisionHandler(.cancel)
            openExternally(url)
            return
        }
        decisionHandler(.allow)
    }

    /// Catches a redirect target the gateway announced but never produced. Part of the charges
    /// that report an action come back `404 NOT_FOUND, "Redirect data not found for payment"`,
    /// permanently. Without this the WebView would render that JSON body as the challenge and the
    /// host could only tell the payment apart from a user cancel by guessing.
    ///
    /// Only the main frame counts: a challenge page is free to lose a subresource.
    func webView(
        _: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame,
              let response = navigationResponse.response as? HTTPURLResponse,
              let failure = GopayVerificationFailureMapper.failure(forStatus: response.statusCode) else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        activityIndicator.stopAnimating()
        reportFailure(failure)
    }

    func webView(_: WKWebView, didCommit _: WKNavigation!) {
        hasCommittedNavigation = true
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        activityIndicator.stopAnimating()
    }

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        activityIndicator.startAnimating()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        reportLoadFailure(error)
    }

    /// A verification page that never commits — a dead host, no route, a refused connection —
    /// used to leave the spinner turning with nothing behind it.
    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        reportLoadFailure(error)
    }

    private func reportLoadFailure(_ error: Error) {
        guard let failure = GopayVerificationFailureMapper.failure(
            forLoadError: error,
            unsupportedSchemeIsExpected: hasAttemptedHandOff || hasCommittedNavigation
        ) else { return }
        reportFailure(failure)
    }

    /// Reports a load failure as hard only while the challenge has not started rendering.
    ///
    /// Afterwards the user may already have answered and the payment may already be through, so
    /// the outcome is a cancellation and the host settles it by reading the charge state. The
    /// degradation is logged rather than silent: to support, an HTTP 404 in the middle of a
    /// challenge would otherwise be indistinguishable from a tap on Cancel.
    private func reportFailure(_ error: GopaySDKError) {
        guard hasCommittedNavigation else {
            report(.failed(error))
            return
        }
        let status = error.httpStatus.map { " HTTP \($0)" } ?? ""
        GopaySDK.shared.logWarning(
            "3DS verification failed after the challenge started rendering, reporting it as a cancellation: "
                + "[\(error.code.rawValue)]\(status) \(error.message)"
        )
        report(.cancelled)
    }
}
