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
        /// `payment_id` / `payment_secret` pair was rejected by `/oauth2/token` with HTTP 400, 401
        /// or 403.
        case authPaymentCredentialsInvalid = "AUTH_010"
        /// `clientId` / `shareableKey` missing from the config but required by the requested operation.
        case authShareableKeyMissing = "AUTH_011"
        /// A `PaymentSession` for the given `payment_id` already exists — close it before starting another.
        case authPaymentSessionAlreadyExists = "AUTH_012"
        /// Operation invoked on a `PaymentSession` that has been closed.
        case authPaymentSessionClosed = "AUTH_013"

        // Network (NETWORK_XXX)
        /// The request timed out before the gateway answered.
        case networkTimeout = "NETWORK_001"
        /// HTTP client error (4xx).
        case networkClientError = "NETWORK_002"
        /// HTTP server error (5xx).
        case networkServerError = "NETWORK_003"
        /// No connection to the gateway: the device is offline, the host does not resolve, or the
        /// connection is refused.
        case networkNoConnection = "NETWORK_004"
        /// A certificate failed: the server's was not accepted, or the server asked for or refused
        /// a client certificate. Any other TLS failure, a connection reset mid-handshake included,
        /// is ``networkIOError``.
        case networkSSLError = "NETWORK_005"
        /// The request never got an HTTP response for any other reason, e.g. the connection
        /// dropped halfway.
        case networkIOError = "NETWORK_007"

        // Configuration (CONFIG_XXX)
        /// SDK has not been initialized.
        case sdkNotInitialized = "CONFIG_001"
        /// Missing required configuration parameter.
        case configMissingParameter = "CONFIG_003"
        /// Invalid API base URL.
        case invalidBaseURL = "CONFIG_006"

        // Payment (PAYMENT_XXX)
        /// A wallet payment failed: the wallet produced no usable payment token. A failed charge
        /// keeps the code of its own failure.
        case paymentProcessingFailed = "PAYMENT_003"
        /// The wallet cannot be used here: the device cannot pay with it, the payment allows no
        /// card network it supports, or its sheet could not be shown.
        case paymentMethodUnavailable = "PAYMENT_004"
        /// A 3DS verification is already in progress; only one can run at a time.
        case paymentVerificationInProgress = "PAYMENT_008"
        /// An Apple Pay sheet is already in progress; only one can run at a time.
        case paymentApplePayInProgress = "PAYMENT_009"
        /// The 3DS challenge never reached the user: the page could not be loaded, e.g. the
        /// redirect URL is dead or is not a web address, the verification screen could not be
        /// presented, or no app on the device took the hand-off the challenge asked for.
        case paymentVerificationUnreachable = "PAYMENT_010"
        /// The payment window closed before it finished: the Apple Pay sheet or the 3DS screen was
        /// closed, or the 3DS page failed after it had started rendering. Not a failed payment, and
        /// not necessarily one that did not happen: read ``PaymentSession/getChargeState()`` before
        /// offering it again. Cancelling the task that awaits the call is not this code; that stays
        /// `CancellationError`.
        case paymentCancelled = "PAYMENT_011"

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

extension GopaySDKError {

    /// The error a request that never got an HTTP response surfaces as. Mirrors the transport
    /// mapping of the Android SDK, so both report the same code for the same failure:
    ///
    /// - a timeout is ``Code/networkTimeout``;
    /// - no connection (offline, a host that does not resolve, a refused connection) is
    ///   ``Code/networkNoConnection``;
    /// - a certificate failure is ``Code/networkSSLError``;
    /// - anything else is ``Code/networkIOError``.
    ///
    /// The original error is kept as `underlying`.
    static func transport(_ error: Error) -> GopaySDKError {
        let code: Code
        switch (error as? URLError)?.code {
        case URLError.Code.timedOut?:
            code = .networkTimeout
        case URLError.Code.notConnectedToInternet?, URLError.Code.cannotFindHost?,
             URLError.Code.cannotConnectToHost?, URLError.Code.dnsLookupFailed?,
             URLError.Code.dataNotAllowed?, URLError.Code.internationalRoamingOff?,
             URLError.Code.callIsActive?:
            code = .networkNoConnection
        case URLError.Code.serverCertificateHasBadDate?, URLError.Code.serverCertificateUntrusted?,
             URLError.Code.serverCertificateHasUnknownRoot?, URLError.Code.serverCertificateNotYetValid?,
             URLError.Code.clientCertificateRejected?, URLError.Code.clientCertificateRequired?:
            // Only a certificate. `secureConnectionFailed` says the handshake failed for a reason
            // Apple does not name, a reset connection included, so it is NETWORK_007, as an
            // `SSLException` without a certificate cause is on Android.
            code = .networkSSLError
        default:
            code = .networkIOError
        }
        return GopaySDKError(
            code,
            message: "The request got no HTTP response: \(error.localizedDescription)",
            underlying: error
        )
    }
}
