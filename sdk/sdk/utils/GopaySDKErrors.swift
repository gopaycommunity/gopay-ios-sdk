import Foundation

/// The message texts of the errors the SDK builds in more than one place. Internal since 3.0: the
/// SDK throws ``GopaySDKError`` with a code, and a host compares the code, never a message.
enum GopaySDKErrors {
    /// Card form data is invalid.
    static let invalidCardFormData = "Card form data is invalid. Please check all fields."

    /// No card form data available. Please use PaymentCardForm to enter card data.
    static let noCardFormData = "No card form data available. Please use PaymentCardForm to enter card data."

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

    /// JWE AES-GCM not available.
    static let jweAESGCMNotAvailable = "AES-GCM encryption requires iOS 13.0 or later."

    /// JWE nonce creation failed.
    static let jweNonceCreationFailed = "Failed to create nonce."

    /// JWE invalid key size.
    static let jweInvalidKeySize = "Invalid key size for AES-256-GCM (must be 32 bytes)."

    /// JWE invalid IV size.
    static let jweInvalidIVSize = "Invalid IV size for AES-GCM (must be 12 bytes)."
}
