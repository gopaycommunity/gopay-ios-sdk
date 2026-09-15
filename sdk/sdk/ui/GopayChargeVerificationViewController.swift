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

    /// The error for a WebKit load failure, or `nil` when it must not be reported at all.
    static func failure(forLoadError error: Error) -> GopaySDKError? {
        let nsError = error as NSError
        // A load stopped through the URL loading system, e.g. a navigation replaced by the next
        // one in a redirect chain. Never the first outcome, so reporting it would only overwrite
        // the real one.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return nil }
        return GopaySDKError(
            .paymentVerificationUnreachable,
            message: "The 3DS verification page could not be loaded",
            underlying: error
        )
    }
}

/// Internal view controller that presents a WKWebView for 3DS / PSD2 / bank
/// verification. The navigation delegate intercepts the SDK's return URL to
/// detect when verification is complete, then dismisses itself.
final class GopayChargeVerificationViewController: UIViewController {

    private let redirectURL: URL
    private let returnURLString: String
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
    ///   - returnURLString: The return URL the SDK sent to the API. Navigation
    ///     to this URL signals that verification is complete.
    ///   - onResult: Called exactly once with the verification outcome.
    init(
        redirectURL: URL,
        returnURLString: String,
        onResult: @escaping (GopayChargeVerificationResult) -> Void
    ) {
        self.redirectURL = redirectURL
        self.returnURLString = returnURLString
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
           url.absoluteString.hasPrefix(returnURLString) {
            decisionHandler(.cancel)
            report(.completed)
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
        guard let failure = GopayVerificationFailureMapper.failure(forLoadError: error) else { return }
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
