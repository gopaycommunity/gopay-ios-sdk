import Foundation
import UIKit

public extension BrowserData {
    /// Best-effort ``BrowserData`` derived from the current device.
    ///
    /// The spec requires `browser_data` on every card charge, but an Apple Pay payment doesn't
    /// naturally surface it — the device's locale, screen, and timezone are reasonable defaults.
    /// Reads `UIScreen`, so it is `@MainActor`.
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
            acceptHeader: nil,
            javascriptEnabled: false
        )
    }
}
