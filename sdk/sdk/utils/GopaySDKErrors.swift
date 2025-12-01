import Foundation

/// Centralized error definitions for the Gopay SDK.
///
/// Provides consistent error domains, codes, and messages across the SDK.
public enum GopaySDKErrors {
    // MARK: - Error Domains
    
    /// Error domain for SDK-level errors.
    public static let sdkDomain = "GopaySDK"
    
    /// Error domain for encryption service errors.
    public static let encryptionServiceDomain = "GopayEncryptionService"
    
    /// Error domain for authentication service errors.
    public static let authServiceDomain = "GopayAuthService"
    
    /// Error domain for network-related errors.
    public static let networkDomain = "GopayNetwork"
    
    /// Error domain for invalid URL errors.
    public static let invalidURLDomain = "GopayInvalidURL"
    
    /// Error domain for encoding errors.
    public static let encodingDomain = "GopayEncoding"
    
    // MARK: - Error Codes
    
    /// Generic error code.
    public static let genericErrorCode = -1
    
    /// Error code for invalid URL.
    public static let invalidURLErrorCode = -2
    
    /// Error code for encoding failures.
    public static let encodingErrorCode = -3
    
    /// Error code for network failures.
    public static let networkErrorCode = -4
    
    // MARK: - Error Messages
    
    /// No access token found. Please authenticate first.
    public static let noAccessToken = "No access token found. Please authenticate first."
    
    /// Access token is expired. Please authenticate again.
    public static let accessTokenExpired = "Access token is expired. Please authenticate again."
    
    /// Access token is expired (short version).
    public static let accessTokenExpiredShort = "Access token is expired."
    
    /// SDK not initialized or authService unavailable.
    public static let sdkNotInitializedAuthService = "SDK not initialized or authService unavailable."
    
    /// SDK not initialized or encryptionService unavailable.
    public static let sdkNotInitializedEncryptionService = "SDK not initialized or encryptionService unavailable."
    
    /// Invalid URL for public key endpoint.
    public static let invalidPublicKeyURL = "Invalid URL for public key endpoint."
    
    /// Invalid URL.
    public static let invalidURL = "Invalid URL."
    
    /// Encoding error message.
    public static let encodingErrorMessage = "Encoding error."
    
    /// Unknown error message.
    public static let unknownErrorMessage = "Unknown error."
    
    // MARK: - Error Creation Helpers
    
    /// Creates an SDK error with the given message.
    /// - Parameter message: The error message.
    /// - Returns: An NSError with the SDK domain and generic error code.
    public static func sdkError(_ message: String) -> NSError {
        return NSError(
            domain: sdkDomain,
            code: genericErrorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    /// Creates an encryption service error with the given message.
    /// - Parameter message: The error message.
    /// - Returns: An NSError with the encryption service domain and generic error code.
    public static func encryptionServiceError(_ message: String) -> NSError {
        return NSError(
            domain: encryptionServiceDomain,
            code: genericErrorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    /// Creates an authentication service error with the given message.
    /// - Parameter message: The error message.
    /// - Returns: An NSError with the auth service domain and generic error code.
    public static func authServiceError(_ message: String) -> NSError {
        return NSError(
            domain: authServiceDomain,
            code: genericErrorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    /// Creates a network error with the given message.
    /// - Parameter message: The error message.
    /// - Returns: An NSError with the network domain and network error code.
    public static func networkError(_ message: String) -> NSError {
        return NSError(
            domain: networkDomain,
            code: networkErrorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    /// Creates an unknown error.
    /// - Returns: An NSError with the network domain and network error code.
    public static func unknownError() -> NSError {
        return NSError(
            domain: networkDomain,
            code: networkErrorCode,
            userInfo: [NSLocalizedDescriptionKey: unknownErrorMessage]
        )
    }
    
    /// Creates an invalid URL error.
    /// - Returns: An NSError with the invalid URL domain and invalid URL error code.
    public static func invalidURLError() -> NSError {
        return NSError(
            domain: invalidURLDomain,
            code: invalidURLErrorCode,
            userInfo: [NSLocalizedDescriptionKey: invalidURL]
        )
    }
    
    /// Creates an encoding error.
    /// - Returns: An NSError with the encoding domain and encoding error code.
    public static func encodingError() -> NSError {
        return NSError(
            domain: encodingDomain,
            code: encodingErrorCode,
            userInfo: [NSLocalizedDescriptionKey: encodingErrorMessage]
        )
    }
}

