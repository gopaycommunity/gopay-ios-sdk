import Foundation

/// The SDK's own error domains and message texts. Internal since 3.0: the SDK throws
/// ``GopaySDKError`` with a code, and a host compares the code, never a message.
enum GopaySDKErrors: Sendable {
    // MARK: - Error Domains
    
    /// Error domain for SDK-level errors.
    static let sdkDomain = "GopaySDK"
    
    /// Error domain for encryption service errors.
    static let encryptionServiceDomain = "GopayEncryptionService"
    
    /// Error domain for authentication service errors.
    static let authServiceDomain = "GopayAuthService"
    
    /// Error domain for network-related errors.
    static let networkDomain = "GopayNetwork"
    
    /// Error domain for invalid URL errors.
    static let invalidURLDomain = "GopayInvalidURL"
    
    /// Error domain for encoding errors.
    static let encodingDomain = "GopayEncoding"
    
    /// Error domain for card token service errors.
    static let cardTokenServiceDomain = "GopayCardTokenService"

    /// Error domain for payment service errors.
    static let paymentServiceDomain = "GopayPaymentService"
    
    /// Error domain for JWE encryption errors.
    static let jweDomain = "GopayJWE"
    
    // MARK: - Error Codes
    
    /// Generic error code.
    static let genericErrorCode = -1
    
    /// Error code for invalid URL.
    static let invalidURLErrorCode = -2
    
    /// Error code for encoding failures.
    static let encodingErrorCode = -3
    
    /// Error code for network failures.
    static let networkErrorCode = -4
    
    // MARK: - Error Messages
    
    /// No access token found. Please authenticate first.
    static let noAccessToken = "No access token found. Please authenticate first."
    
    /// Access token is expired. Please authenticate again.
    static let accessTokenExpired = "Access token is expired. Please authenticate again."
    
    /// Access token is expired (short version).
    static let accessTokenExpiredShort = "Access token is expired."
    
    /// SDK not initialized or authService unavailable.
    static let sdkNotInitializedAuthService = "SDK not initialized or authService unavailable."
    
    /// SDK not initialized or encryptionService unavailable.
    static let sdkNotInitializedEncryptionService = "SDK not initialized or encryptionService unavailable."
    
    /// Invalid URL for key endpoint.
    static let invalidPublicKeyURL = "Invalid URL for key endpoint."
    
    /// Invalid URL.
    static let invalidURL = "Invalid URL."
    
    /// Encoding error message.
    static let encodingErrorMessage = "Encoding error."
    
    /// Unknown error message.
    static let unknownErrorMessage = "Unknown error."
    
    /// SDK not initialized or cardTokenService unavailable.
    static let sdkNotInitializedCardTokenService = "SDK not initialized or cardTokenService unavailable."

    /// SDK not initialized or paymentService unavailable.
    static let sdkNotInitializedPaymentService = "SDK not initialized or paymentService unavailable."
    
    /// Card token creation failed.
    static let cardTokenCreationFailed = "Card token creation failed."
    
    /// Card form data is invalid.
    static let invalidCardFormData = "Card form data is invalid. Please check all fields."
    
    /// No card form data available. Please use PaymentCardForm to enter card data.
    static let noCardFormData = "No card form data available. Please use PaymentCardForm to enter card data."
    
    /// Invalid URL for card token endpoint.
    static let invalidCardTokenURL = "Invalid URL for card token endpoint."

    /// Invalid URL for payment endpoint.
    static let invalidPaymentURL = "Invalid URL for payment endpoint."

    /// Invalid URL for charge endpoint.
    static let invalidChargeURL = "Invalid URL for charge endpoint."

    /// Invalid URL for QR payment info endpoint.
    static let invalidQRPaymentInfoURL = "Invalid URL for QR payment info endpoint."

    /// Invalid URL for Apple Pay app-info endpoint.
    static let invalidApplePayAppInfoURL = "Invalid URL for Apple Pay app-info endpoint."


    /// Apple Pay is not configured for this merchant.
    static let applePayNotConfigured = "Apple Pay is not configured for this merchant."



    /// Apple Pay response from the backend is missing a payment request.
    static let applePayMissingRequest = "Apple Pay response is missing the payment request."

    /// Payment verification was cancelled by the user.
    static let chargeVerificationCancelled = "Payment verification was cancelled by the user."

    /// Payment verification failed.
    static let chargeVerificationFailed = "Payment verification failed."

    /// Could not find a view controller to present verification.
    static let noPresentingViewController = "Could not find a view controller to present verification."
    
    /// JWE encryption failed.
    static let jweEncryptionFailed = "JWE encryption failed."
    
    /// JWE key generation failed.
    static let jweKeyGenerationFailed = "Failed to generate encryption key."
    
    /// JWE IV generation failed.
    static let jweIVGenerationFailed = "Failed to generate initialization vector."
    
    /// JWE card data encoding failed.
    static let jweCardDataEncodingFailed = "Failed to encode card data."
    
    /// JWE header encoding failed.
    static let jweHeaderEncodingFailed = "Failed to encode JWE header."
    
    /// JWE key creation failed.
    static let jwePublicKeyCreationFailed = "Failed to create key from JWK."
    
    /// JWE CEK encryption failed.
    static let jweCEKEncryptionFailed = "Failed to encrypt content encryption key."
    
    /// JWE AES encryption failed.
    static let jweAESEncryptionFailed = "AES encryption failed."
    
    /// JWE AES-GCM not available.
    static let jweAESGCMNotAvailable = "AES-GCM encryption requires iOS 13.0 or later."
    
    /// JWE key creation failed.
    static let jweKeyCreationFailed = "Failed to create symmetric key."
    
    /// JWE nonce creation failed.
    static let jweNonceCreationFailed = "Failed to create nonce."
    
    /// JWE invalid key size.
    static let jweInvalidKeySize = "Invalid key size for AES-256-GCM (must be 32 bytes)."
    
    /// JWE invalid IV size.
    static let jweInvalidIVSize = "Invalid IV size for AES-GCM (must be 12 bytes)."
    
    // MARK: - Error Creation Helpers
    
    /// Creates an encryption service error with the given message.
    /// - Parameter message: The error message.
    /// - Returns: An NSError with the encryption service domain and generic error code.
    static func encryptionServiceError(_ message: String) -> NSError {
        return NSError(
            domain: encryptionServiceDomain,
            code: genericErrorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    /// Creates an authentication service error with the given message.
    /// - Parameter message: The error message.
    /// - Returns: An NSError with the auth service domain and generic error code.
    static func authServiceError(_ message: String) -> NSError {
        return NSError(
            domain: authServiceDomain,
            code: genericErrorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    /// Creates a network error with the given message.
    /// - Parameter message: The error message.
    /// - Returns: An NSError with the network domain and network error code.
    static func networkError(_ message: String) -> NSError {
        return NSError(
            domain: networkDomain,
            code: networkErrorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    /// Creates an unknown error.
    /// - Returns: An NSError with the network domain and network error code.
    static func unknownError() -> NSError {
        return NSError(
            domain: networkDomain,
            code: networkErrorCode,
            userInfo: [NSLocalizedDescriptionKey: unknownErrorMessage]
        )
    }
    
    /// Creates an invalid URL error.
    /// - Returns: An NSError with the invalid URL domain and invalid URL error code.
    static func invalidURLError() -> NSError {
        return NSError(
            domain: invalidURLDomain,
            code: invalidURLErrorCode,
            userInfo: [NSLocalizedDescriptionKey: invalidURL]
        )
    }
    
    /// Creates an encoding error.
    /// - Returns: An NSError with the encoding domain and encoding error code.
    static func encodingError() -> NSError {
        return NSError(
            domain: encodingDomain,
            code: encodingErrorCode,
            userInfo: [NSLocalizedDescriptionKey: encodingErrorMessage]
        )
    }
    
    /// Creates a card token service error with the given message.
    /// - Parameter message: The error message.
    /// - Returns: An NSError with the card token service domain and generic error code.
    static func cardTokenServiceError(_ message: String) -> NSError {
        return NSError(
            domain: cardTokenServiceDomain,
            code: genericErrorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    /// Creates a payment service error with the given message.
    /// - Parameter message: The error message.
    /// - Returns: An NSError with the payment service domain and generic error code.
    static func paymentServiceError(_ message: String) -> NSError {
        return NSError(
            domain: paymentServiceDomain,
            code: genericErrorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    /// Creates a JWE error with the given message.
    /// - Parameter message: The error message.
    /// - Returns: An NSError with the JWE domain and generic error code.
    static func jweError(_ message: String) -> NSError {
        return NSError(
            domain: jweDomain,
            code: genericErrorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

