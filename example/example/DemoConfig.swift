//
//  DemoConfig.swift
//  example
//
//  Which gateway environment the demo currently talks to, and the merchant credentials that go
//  with it. Selectable from `RootView`; the app always starts on `.development` — the choice is
//  not persisted across launches.
//

import Foundation
import GopaySDK

enum DemoEnvironment: String, CaseIterable, Identifiable {
    case development
    case sandbox
    case production

    var id: String { rawValue }

    var title: String {
        switch self {
        case .development: "Development"
        case .sandbox: "Sandbox"
        case .production: "Production"
        }
    }

    /// The `GopayEnvironment` case this maps to. Sandbox and production reuse the SDK's own
    /// built-in hosts (``GopayEnvironment/sandbox``, ``GopayEnvironment/production``) rather than
    /// duplicating a URL here, so the demo can never drift from what the SDK itself resolves.
    var gopayEnvironment: GopayEnvironment {
        switch self {
        case .development: .development(baseURL: DemoConfig.developmentBaseURL)
        case .sandbox: .sandbox
        case .production: .production
        }
    }

    /// Merchant credentials for this environment. Sandbox and production ship as empty
    /// placeholders — fill them in before selecting those environments. An empty `clientId` /
    /// `shareableKey` / `clientSecret` fails clearly at the gateway rather than silently mixing
    /// environments.
    var credentials: DemoCredentials {
        switch self {
        case .development: DemoConfig.developmentCredentials
        case .sandbox, .production: .placeholder
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

    static let placeholder = DemoCredentials(clientId: "", shareableKey: "", clientSecret: "", goid: "")
}

/// Holds the demo's currently-selected environment and builds the SDK config for it. This is the
/// single path both `exampleApp` (at launch) and the environment picker (at runtime) go through,
/// so a switch can never leave the SDK and the picker disagreeing about what's active.
@Observable
final class DemoConfig {
    static let shared = DemoConfig()

    /// Dev gateway URL — the only per-environment value that's actually app-editable. Replace with
    /// your own merchant's development host.
    static let developmentBaseURL = "https://gw.alpha8.dev.gopay.com/gp-gw/api/4.0/"

    static let developmentCredentials = DemoCredentials(
        clientId: "your_client_id",
        // Public shareable key — safe to ship in the app.
        shareableKey: "your_sharable_key",
        // Merchant secret — **never ship this in a real app.** Used here only by the in-app
        // `MerchantBackendSimulator` to stand in for your server while demoing.
        clientSecret: "your_client_secret",
        goid: "8761908826"
    )

    private(set) var environment: DemoEnvironment = .development

    private init() {
        // Empty — enforces the singleton via `shared`; there is no per-instance state to initialize.
    }

    var credentials: DemoCredentials { environment.credentials }

    /// Closes any live payment session — otherwise it would keep talking to the old gateway, since
    /// each `PaymentSession` captures its own API client at creation — then re-initializes the SDK
    /// against the new environment and updates the published selection. Only reachable from
    /// `RootView`, which never holds a session itself.
    @MainActor
    func select(_ newEnvironment: DemoEnvironment) {
        guard newEnvironment != environment else { return }
        Task {
            await GopaySDK.shared.closeAllPaymentSessions()
            GopaySDK.shared.initialize(with: Self.buildConfig(for: newEnvironment))
            environment = newEnvironment
        }
    }

    /// Builds the SDK config for `environment`, reproducing every setting from app launch exactly
    /// (custom locale, debug logging, …) so a runtime switch behaves identically to a cold start.
    static func buildConfig(for environment: DemoEnvironment) -> GopaySDKConfig {
        // Register a custom locale (code "xx") the form can select alongside the built-ins, and
        // leave `locale = nil` so the default follows the device language (falling back to cs).
        var customLocale = GopayLocales.en
        customLocale.panLabel = "Yer card number"
        customLocale.expLabel = "Doom date"
        customLocale.cvvLabel = "Secret code"

        let credentials = environment.credentials
        return GopaySDKConfig(
            environment: environment.gopayEnvironment,
            clientId: credentials.clientId,
            shareableKey: credentials.shareableKey,
            enableDebugLogging: true,
            customLocales: ["xx": customLocale]
        )
    }
}
