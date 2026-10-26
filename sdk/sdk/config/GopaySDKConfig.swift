import Foundation

/// The environment to use for the SDK.
///
/// - Note: Each case represents a different backend environment.
public enum GopayEnvironment: Equatable {
    /// The development environment with a custom base URL.
    case development(baseURL: String)
    /// The sandbox environment.
    case sandbox
    /// The production environment. Charges made through it are real.
    case production

    private static let sandboxBaseURL = "https://gw.sandbox.gopay.com/gp-gw/api/4.0/"
    private static let productionBaseURL = "https://gate.gopay.com/gp-gw/api/4.0/"
    private static let sandboxTelemetryURL = URL(string: "https://lx.sandbox.gopay.com/events")
    private static let productionTelemetryURL = URL(string: "https://lx.gopay.com/events")

    /// The base URL for the selected environment. Public so host apps can display or route
    /// around it (e.g. a demo backend simulator deriving its own base URL from the live SDK
    /// config, so the two can never disagree about which gateway is active).
    public var baseURL: String {
        switch self {
        case .development(let url): return url
        case .sandbox: return Self.sandboxBaseURL
        case .production: return Self.productionBaseURL
        }
    }

    /// The operational-data ingest that belongs to this gateway, or `nil` for a development
    /// gateway, which has none. Not derived from ``baseURL``: a gateway URL pointed at a mock
    /// server must not move the telemetry with it.
    var telemetryURL: URL? {
        switch self {
        case .development: return nil
        case .sandbox: return Self.sandboxTelemetryURL
        case .production: return Self.productionTelemetryURL
        }
    }
}

/// Configuration for the Gopay SDK.
///
/// Use this struct to configure the SDK before initialization.
public struct GopaySDKConfig {
    /// The environment to use for the SDK.
    public let environment: GopayEnvironment

    /// Merchant `client_id`. Required together with ``shareableKey`` to call the public-resource
    /// endpoints (`GET /cards/public-key`, `GET /cards/browser-data`) authenticated with
    /// `shareable_key` basic auth. Safe to embed in the mobile app — it is paired with the
    /// shareable key, never with the merchant secret.
    public let clientId: String?

    /// Merchant `shareable_key`. Required together with ``clientId`` for public-resource
    /// endpoints: encrypting a card, and every ``PaymentSession/charge(_:)`` whose ``BrowserData``
    /// does not already carry both `ip` and `acceptHeader`, since the charge then fetches them
    /// from `GET /cards/browser-data` first. That includes ``PaymentSession/chargeWithApplePay(browserData:challengePreference:)``
    /// with the device default. Without the key such a call throws
    /// ``GopaySDKError/Code/authShareableKeyMissing``. The key cannot authorize a charge by itself.
    public let shareableKey: String?

    /// Whether to enable debug logging.
    ///
    /// With it on, the SDK also logs one line for each operational-data event it sends to GoPay,
    /// the event's type and name without its content. It does not change what is sent; see
    /// "Operational data" in the README.
    ///
    /// - Note: One message ignores this flag and the ``errorCallback``: ``GopaySDK/initialize(with:)``
    ///   always prints when the selected environment resolves to no base URL. That is a
    ///   misconfiguration nothing downstream can recover from, and staying silent about it would
    ///   surface later as a `CONFIG_006` on an unrelated-looking call.
    public let enableDebugLogging: Bool

    /// Called with every ``GopaySDKError`` a public call of the SDK or of one of its
    /// ``PaymentSession``s throws, once per error, for central logging and monitoring. Two codes
    /// stay out, because they are outcomes of a payment window rather than failures:
    /// ``GopaySDKError/Code/paymentTimeout`` and ``GopaySDKError/Code/paymentCancelled``. So does a
    /// `CancellationError` from a task the host cancelled, and so does any error that is not a
    /// `GopaySDKError`. The rule is the same on Android. The callback runs on whatever thread the
    /// failing call ends on, and it is not a substitute for catching the error at the call.
    public let errorCallback: ((Error) -> Void)?

    /// Preferred locale code (ISO 639-1, e.g. `"cs"`, `"de"`) for the payment card form labels.
    /// When `nil` (default) the SDK uses the device language, falling back to Czech. A
    /// ``GopayCardForm`` `locale` parameter overrides this per form.
    public let locale: String?

    /// Custom locale translations to register with the SDK, keyed by locale code. These are
    /// available to the payment card form alongside the built-in locales and take priority over a
    /// built-in of the same code. See ``GopayLocaleStrings``.
    public let customLocales: [String: GopayLocaleStrings]

    /// Creates a new configuration for the Gopay SDK.
    /// - Parameters:
    ///   - environment: The environment to use.
    ///   - clientId: Merchant `client_id` for public-resource endpoints (default: `nil`).
    ///   - shareableKey: Merchant `shareable_key` for public-resource endpoints (default: `nil`).
    ///   - enableDebugLogging: Enable debug logging (default: `false`).
    ///   - errorCallback: Callback for error handling (default: `nil`).
    ///   - locale: Preferred form locale code; `nil` follows the device language (default: `nil`).
    ///   - customLocales: Custom locale translations to register (default: empty).
    public init(
        environment: GopayEnvironment,
        clientId: String? = nil,
        shareableKey: String? = nil,
        enableDebugLogging: Bool = false,
        errorCallback: ((Error) -> Void)? = nil,
        locale: String? = nil,
        customLocales: [String: GopayLocaleStrings] = [:]
    ) {
        self.environment = environment
        self.clientId = clientId
        self.shareableKey = shareableKey
        self.enableDebugLogging = enableDebugLogging
        self.errorCallback = errorCallback
        self.locale = locale
        self.customLocales = customLocales
    }
}
