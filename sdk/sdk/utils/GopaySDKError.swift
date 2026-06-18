import Foundation

/// Structured error type for the per-payment session SDK surface.
///
/// Carries a stable string ``Code`` (mirrors the Android `GopayErrorCodes` catalog so the two
/// SDKs report the same codes), a human-readable message, and — for failures that originated from
/// an HTTP response — the offending status code. Conforms to `LocalizedError` so
/// `error.localizedDescription` reads `"[AUTH_010] payment_credentials rejected: HTTP 401"`.
public struct GopaySDKError: LocalizedError {

    /// Stable error codes, matching the Android SDK's `GopayErrorCodes` so both platforms agree.
    public enum Code: String {
        // Authentication (AUTH_XXX)
        /// Payment-scoped JWT expired and could not be re-acquired from the cached payment credentials.
        case authPaymentTokenExpired = "AUTH_009"
        /// `payment_id` / `payment_secret` pair was rejected by `/oauth2/token`.
        case authPaymentCredentialsInvalid = "AUTH_010"
        /// `clientId` / `shareableKey` missing from the config but required by the requested operation.
        case authShareableKeyMissing = "AUTH_011"
        /// A `PaymentSession` for the given `payment_id` already exists — close it before starting another.
        case authPaymentSessionAlreadyExists = "AUTH_012"
        /// Operation invoked on a `PaymentSession` that has been closed.
        case authPaymentSessionClosed = "AUTH_013"

        // Network (NETWORK_XXX)
        /// HTTP client error (4xx).
        case networkClientError = "NETWORK_002"
        /// HTTP server error (5xx).
        case networkServerError = "NETWORK_003"

        // Configuration (CONFIG_XXX)
        /// SDK has not been initialized.
        case sdkNotInitialized = "CONFIG_001"
        /// Missing required configuration parameter.
        case configMissingParameter = "CONFIG_003"
        /// Invalid API base URL.
        case invalidBaseURL = "CONFIG_006"

        // Payment (PAYMENT_XXX)
        /// A 3DS verification is already in progress; only one can run at a time.
        case paymentVerificationInProgress = "PAYMENT_008"
        /// An Apple Pay sheet is already in progress; only one can run at a time.
        case paymentApplePayInProgress = "PAYMENT_009"

        // Validation (VALIDATION_XXX)
        /// Invalid input data provided.
        case validationInvalidInput = "VALIDATION_007"

        // Internal (INTERNAL_XXX)
        /// Unexpected internal error.
        case unexpected = "INTERNAL_001"
        /// Serialization/deserialization error.
        case decoding = "INTERNAL_003"
    }

    /// The stable error code.
    public let code: Code
    /// Human-readable description of what went wrong.
    public let message: String
    /// HTTP status code when this error originated from an HTTP response, otherwise `nil`.
    public let httpStatus: Int?
    /// The underlying error, when this wraps another failure.
    public let underlying: Error?

    public init(_ code: Code, message: String, httpStatus: Int? = nil, underlying: Error? = nil) {
        self.code = code
        self.message = message
        self.httpStatus = httpStatus
        self.underlying = underlying
    }

    public var errorDescription: String? { "[\(code.rawValue)] \(message)" }
}
