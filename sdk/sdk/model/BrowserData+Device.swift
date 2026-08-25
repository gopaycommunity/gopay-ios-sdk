import Foundation
import UIKit

public extension BrowserData {
    /// Standard `Accept` header sent by a modern mobile WebView. There's no device API to read
    /// this back at charge time (the ACS challenge WebView doesn't exist yet), so this mirrors
    /// the conventional value every mainstream mobile browser/3DS SDK reports.
    private static let defaultAcceptHeader =
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"

    /// Synthesized fallback User-Agent, used only if the real WebView lookup in
    /// ``GopayUserAgent`` fails. Reproduces the form a plain `WKWebView` reports (the
    /// `Mobile/15E148` token without Safari's trailing `Version/… Safari/…`; the WebKit build
    /// token is fixed across iOS releases), so even the fallback is plausible to an issuer.
    @MainActor
    static func syntheticUserAgent() -> String {
        let device = UIDevice.current
        let isPad = device.userInterfaceIdiom == .pad
        let platform = isPad ? "iPad" : "iPhone"
        // UA convention: "CPU iPhone OS 18_2" on iPhone, "CPU OS 18_2" on iPad.
        let cpu = isPad ? "OS" : "iPhone OS"
        let osVersion = device.systemVersion.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (\(platform); CPU \(cpu) \(osVersion) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    }

    /// Best-effort ``BrowserData`` derived from the current device.
    ///
    /// The spec requires `browser_data` on every card charge, but an Apple Pay payment doesn't
    /// naturally surface it — the device's locale, screen, and timezone are reasonable defaults.
    /// `colorDepth` has no real device API on iOS; 24 is the universal value every mobile browser
    /// reports regardless of hardware. `javascriptEnabled` reflects that the SDK's own 3DS
    /// challenge (``GopayChargeVerificationViewController``) renders in a `WKWebView` with a
    /// default configuration, which runs JavaScript. `userAgent` is the real UA that WebView
    /// reports — see ``GopayUserAgent``, which requires a JS round-trip and so makes this async.
    ///
    /// Every field can be overridden by constructing ``BrowserData`` directly if you collected
    /// more accurate values elsewhere.
    @MainActor
    static func deviceDefault() async -> BrowserData {
        let bounds = UIScreen.main.nativeBounds
        let language = Locale.preferredLanguages.first ?? Locale.current.identifier
        // JavaScript convention: minutes west of UTC (CET = -60).
        let timezoneOffsetMinutes = -TimeZone.current.secondsFromGMT() / 60
        return BrowserData(
            language: language,
            timezone: timezoneOffsetMinutes,
            screenWidth: Int(bounds.width),
            screenHeight: Int(bounds.height),
            colorDepth: 24,
            userAgent: await GopayUserAgent.resolve(),
            acceptHeader: defaultAcceptHeader,
            javascriptEnabled: true
        )
    }
}
