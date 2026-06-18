import UIKit
@preconcurrency import WebKit

/// Outcome of the charge verification WebView flow.
enum GopayChargeVerificationResult {
    case completed
    case cancelled
}

/// Internal view controller that presents a WKWebView for 3DS / PSD2 / bank
/// verification. The navigation delegate intercepts the SDK's return URL to
/// detect when verification is complete, then dismisses itself.
final class GopayChargeVerificationViewController: UIViewController {

    private let redirectURL: URL
    private let returnURLString: String
    private let onResult: (GopayChargeVerificationResult) -> Void

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
        onResult(.cancelled)
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
            onResult(.completed)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        activityIndicator.stopAnimating()
    }

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        activityIndicator.startAnimating()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        activityIndicator.stopAnimating()
    }
}
