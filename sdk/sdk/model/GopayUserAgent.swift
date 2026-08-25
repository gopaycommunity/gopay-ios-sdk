import Foundation
@preconcurrency import WebKit

/// Resolves the real User-Agent string a `WKWebView` reports on this device.
///
/// EMV 3DS browser-channel authentication carries `browserUserAgent` in the AReq, and the gateway
/// forwards `browser_data.user_agent` to the issuer. Reading the value from an actual `WKWebView`
/// (rather than synthesizing one) guarantees it matches, byte for byte, what
/// ``GopayChargeVerificationViewController``'s own WebView sends when the challenge renders.
///
/// The lookup requires a live `WKWebView` and a JavaScript round-trip, so it's async. The result is
/// cached for the process lifetime — the UA cannot change between charges — and concurrent callers
/// share one in-flight lookup rather than each spinning up a WebView.
@MainActor
enum GopayUserAgent {
    private static var cached: String?
    private static var inFlight: Task<String, Never>?

    /// Returns the device's real WebView User-Agent, resolving it on first use. Falls back to a
    /// synthesized string (never `nil`) if the WebView lookup fails for any reason.
    static func resolve() async -> String {
        if let cached { return cached }
        if let inFlight { return await inFlight.value }

        let task = Task<String, Never> {
            let value = await Self.fetchFromWebView() ?? BrowserData.syntheticUserAgent()
            cached = value
            inFlight = nil
            return value
        }
        inFlight = task
        return await task.value
    }

    /// Kicks off resolution without waiting for it, so the first charge doesn't pay the
    /// WebView-construction latency. Safe to call multiple times; safe to call before or without
    /// ever calling ``resolve()``.
    static func prewarm() {
        guard cached == nil, inFlight == nil else { return }
        Task { _ = await resolve() }
    }

    private static func fetchFromWebView() async -> String? {
        // Configuration mirrors GopayChargeVerificationViewController's WebView exactly, so the
        // UA we report is the UA that WebView will actually send.
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        // This WebView never loads a URL — it exists solely to read navigator.userAgent — so any
        // navigation attempt (e.g. triggered by injected script) is denied outright.
        let navigationDelegate = DenyAllNavigationDelegate()
        webView.navigationDelegate = navigationDelegate

        return await withCheckedContinuation { continuation in
            var didResume = false
            // Capture `webView` and `navigationDelegate` explicitly — nothing else references
            // them after this call, and ARC would otherwise be free to deallocate them (the
            // delegate is held weakly by WKWebView) before the async JS callback fires.
            webView.evaluateJavaScript("navigator.userAgent") { [webView, navigationDelegate] result, _ in
                _ = webView
                _ = navigationDelegate
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: result as? String)
            }
        }
    }
}

private final class DenyAllNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.cancel)
    }
}
