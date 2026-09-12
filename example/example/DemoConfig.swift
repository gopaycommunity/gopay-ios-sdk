//
//  DemoConfig.swift
//  example
//
//  Which gateway the demo talks to, and the merchant credentials that go with it. Both come from
//  `Config/Demo.xcconfig` (see `Config/Local.xcconfig.example`) through the app's Info.plist.
//

import Foundation
import GopaySDK

enum DemoEnvironment: String {
    case development
    case sandbox
    case production

    /// The `GopayEnvironment` case this maps to. Sandbox and production reuse the SDK's own
    /// built-in hosts (``GopayEnvironment/sandbox``, ``GopayEnvironment/production``) rather than
    /// duplicating a URL here.
    var gopayEnvironment: GopayEnvironment {
        switch self {
        case .development: .development(baseURL: DemoConfig.baseURL)
        case .sandbox: .sandbox
        case .production: .production
        }
    }
}

/// Merchant credentials used by both the SDK config (`clientId`/`shareableKey`) and the simulated
/// merchant backend (`clientSecret`/`goid`, for the `client_credentials` grant that only ever runs
/// on your real server).
struct DemoCredentials {
    let clientId: String
    let shareableKey: String
    let clientSecret: String
    let goid: String
}

/// Holds the environment the demo runs against and builds the SDK config for it. The environment
/// is decided once, by `GOPAY_DEMO_BASE_URL`, and never changes while the app runs: point the
/// demo somewhere else by editing `Local.xcconfig` and launching again.
final class DemoConfig {
    static let shared = DemoConfig()

    /// Gateway from `GOPAY_DEMO_BASE_URL`. Empty means the SDK's own sandbox host.
    static let baseURL = normalizedBaseURL(infoValue("GOPAY_DEMO_BASE_URL"))

    /// Trims the configured value, appends the trailing `/` the SDK concatenates paths onto, and
    /// refuses anything that is neither empty nor an `http(s)` URL. Android rejects the same
    /// values while building; here the value is only visible at runtime, so this is where it fails.
    static func normalizedBaseURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let scheme = trimmed.lowercased()
        guard scheme.hasPrefix("http://") || scheme.hasPrefix("https://") else {
            preconditionFailure("GOPAY_DEMO_BASE_URL must be empty or an http(s) URL, got '\(trimmed)'")
        }

        return trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
    }

    static let credentials = DemoCredentials(
        clientId: infoValue("GOPAY_DEMO_CLIENT_ID"),
        shareableKey: infoValue("GOPAY_DEMO_SHAREABLE_KEY"),
        clientSecret: infoValue("GOPAY_DEMO_CLIENT_SECRET"),
        goid: infoValue("GOPAY_DEMO_GOID")
    )

    /// Which environment a normalized `GOPAY_DEMO_BASE_URL` names: empty means the SDK's own
    /// sandbox, a URL equal to one of the SDK's built-in hosts names that environment (so the
    /// badge reads SANDBOX or PRODUCTION, not DEVELOPMENT), and anything else is a custom gateway.
    static func environment(for baseURL: String) -> DemoEnvironment {
        switch baseURL {
        case "", GopayEnvironment.sandbox.baseURL: .sandbox
        case GopayEnvironment.production.baseURL: .production
        default: .development
        }
    }

    let environment: DemoEnvironment = DemoConfig.environment(for: DemoConfig.baseURL)

    private init() {
        // Empty — enforces the singleton via `shared`; there is no per-instance state to initialize.
    }

    /// Builds the SDK config for `environment`: the custom locale, debug logging and the rest of
    /// what the app registers at launch.
    static func buildConfig(for environment: DemoEnvironment) -> GopaySDKConfig {
        // Register a custom locale (code "xx") the form can select alongside the built-ins, and
        // leave `locale = nil` so the default follows the device language (falling back to cs).
        var customLocale = GopayLocales.en
        customLocale.panLabel = "Yer card number"
        customLocale.expLabel = "Doom date"
        customLocale.cvvLabel = "Secret code"

        return GopaySDKConfig(
            environment: environment.gopayEnvironment,
            clientId: credentials.clientId,
            shareableKey: credentials.shareableKey,
            enableDebugLogging: true,
            customLocales: ["xx": customLocale]
        )
    }

    private static func infoValue(_ key: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
