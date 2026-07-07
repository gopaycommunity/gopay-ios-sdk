import Foundation

/// The environment to use for the SDK.
///
/// - Note: Each case represents a different backend environment.
public enum GopayEnvironment: Equatable {
    /// The development environment with a custom base URL.
    case development(baseURL: String)
    /// The sandbox environment.
    case sandbox
    /// The production environment.
    case production

    private static let sandboxBaseURL = "https://gw.sandbox.gopay.com/gp-gw/api/4.0/"

    /// The base URL for the selected environment.
    var baseURL: String {
        switch self {
        case .development(let url): return url
        case .sandbox: return Self.sandboxBaseURL
        case .production: return ""
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
    /// endpoints (`GET /cards/public-key`) authenticated with `shareable_key` basic auth. Safe to
    /// embed in the mobile app — it is paired with the shareable key, never with the merchant
    /// secret.
    public let clientId: String?

    /// Merchant `shareable_key`. Required together with ``clientId`` for public-resource
    /// endpoints. Optional if the SDK is only used to charge existing payments through a
    /// ``PaymentSession``.
    public let shareableKey: String?

    /// Whether to enable debug logging.
    public let enableDebugLogging: Bool

    /// The callback to use for errors.
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
