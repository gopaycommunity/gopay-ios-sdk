import Foundation
import UIKit

public extension BrowserData {
    /// Standard `Accept` header sent by a modern mobile WebView. There's no device API to read
    /// this back at charge time (the ACS challenge WebView doesn't exist yet), so this mirrors
    /// the conventional value every mainstream mobile browser/3DS SDK reports.
    private static let defaultAcceptHeader =
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"

    /// Best-effort ``BrowserData`` derived from the current device.
    ///
    /// The spec requires `browser_data` on every card charge, but an Apple Pay payment doesn't
    /// naturally surface it — the device's locale, screen, and timezone are reasonable defaults.
    /// `colorDepth` has no real device API on iOS; 24 is the universal value every mobile browser
    /// reports regardless of hardware. `javascriptEnabled` reflects that the SDK's own 3DS
    /// challenge (``GopayChargeVerificationViewController``) renders in a `WKWebView` with a
    /// default configuration, which runs JavaScript. Reads `UIScreen`, so it is `@MainActor`.
    @MainActor
    static func deviceDefault() -> BrowserData {
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
            userAgent: nil,
            acceptHeader: defaultAcceptHeader,
            javascriptEnabled: true
        )
    }
}
