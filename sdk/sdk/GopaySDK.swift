import Foundation
import SwiftUI

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
    /// Whether to enable debug logging.
    public let enableDebugLogging: Bool
    /// The callback to use for errors.
    public let errorCallback: ((Error) -> Void)?
    
    /// Creates a new configuration for the Gopay SDK.
    /// - Parameters:
    ///   - environment: The environment to use.
    ///   - enableDebugLogging: Enable debug logging (default: `false`).
    ///   - errorCallback: Callback for error handling (default: `nil`).
    public init(
        environment: GopayEnvironment,
        enableDebugLogging: Bool = false,
        errorCallback: ((Error) -> Void)? = nil
    ) {
        self.environment = environment
        self.enableDebugLogging = enableDebugLogging
        self.errorCallback = errorCallback
    }
}

/// The main class for the Gopay SDK.
///
/// Use the shared instance to interact with the SDK.
public class GopaySDK {
    /// The current version of the SDK.
    /// This version is automatically read from the bundle's Info.plist,
    /// which is populated from the Xcode project's MARKETING_VERSION setting.
    public static var version: String {
        let bundle = Bundle(for: GopaySDK.self)
        return bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    /// The shared instance of the SDK.
    public static let shared = GopaySDK()
    
    /// The keychain storage to use for the SDK.
    private var keychainStorage: KeychainStorageProtocol = KeychainStorage.shared

    /// The current configuration for the SDK.
    public private(set) var config: GopaySDKConfig?
    /// The authentication service.
    public private(set) var authService: GopayAuthService?
    /// The encryption service.
    public private(set) var encryptionService: GopayEncryptionService?
    /// The card token service.
    public private(set) var cardTokenService: GopayCardTokenService?
    /// The network client for making API requests.
    private var networkClient: NetworkClientProtocol?
    
    /// Internal storage for card form data keyed by form ID (never exposed to the user).
    private var internalCardFormData: [String: GopayCardFormData] = [:]
    
    /// Tracks the most recently active form ID.
    private var mostRecentFormId: String?
    
    /// Initializes the SDK with the given configuration.
    /// - Parameter config: The configuration to use.
    public func initialize(with config: GopaySDKConfig) {
        self.config = config
        let client = DefaultNetworkClient(baseURL: config.environment.baseURL)
        self.networkClient = client
        self.authService = GopayAuthService(networkClient: client)
        let encryptionService = GopayEncryptionService(networkClient: client, keychainStorage: keychainStorage)
        self.encryptionService = encryptionService
        self.cardTokenService = GopayCardTokenService(networkClient: client, keychainStorage: keychainStorage, encryptionService: encryptionService)
    }
    
    /// Handles an error using the configured error callback and debug logging.
    /// - Parameter error: The error to handle.
    func handleError(_ error: Error) {
        config?.errorCallback?(error)
        if config?.enableDebugLogging == true {
            print("[GopaySDK] Error: \(error)")
        }
    }
    
    /// Internal method to update card form data (called automatically by GopayCardForm).
    /// - Parameters:
    ///   - data: The card form data to store internally.
    ///   - formId: The unique identifier for the form instance.
    internal func updateCardFormData(_ data: GopayCardFormData, formId: String) {
        self.internalCardFormData[formId] = data
        self.mostRecentFormId = formId
    }
    
    /// Authenticates using the configured auth service.
    /// - Parameters:
    ///   - clientId: The client ID.
    ///   - clientSecret: The client secret.
    ///   - scope: The requested scopes (space-separated).
    ///   - completion: Completion handler with result.
    public func authenticate(clientId: String, clientSecret: String, scope: String, completion: @escaping (Result<GopayAuthResponse, Error>) -> Void) {
        guard let authService = self.authService else {
            completion(.failure(GopaySDKErrors.sdkError(GopaySDKErrors.sdkNotInitializedAuthService)))
            return
        }
        authService.authenticate(clientId: clientId, clientSecret: clientSecret, scope: scope) { result in
            switch result {
            case .success(let response):
                self.keychainStorage.storeAccessToken(response.accessToken)
                if let refresh = response.refreshToken {
                    self.keychainStorage.storeRefreshToken(refresh)
                }
                completion(.success(response))
            case .failure(let error):
                self.handleError(error)
                completion(.failure(error))
            }
        }
    }
    
    /// Sets the authentication response to the storage.
    /// - Parameter response: The authentication response containing tokens.
    public func setAuthenticationResponse(with response: GopayAuthResponse) throws {
        if let isExpired = JwtUtils.isExpired(jwt: response.accessToken), isExpired {
            throw GopaySDKErrors.sdkError(GopaySDKErrors.accessTokenExpiredShort)
        }

        self.keychainStorage.storeAccessToken(response.accessToken)
        if let refresh = response.refreshToken {
            self.keychainStorage.storeRefreshToken(refresh)
        }
    }
    
    /// Retrieves the public encryption key to be used for encrypting card data.
    ///
    /// The key is structured as a JWK (JSON Web Key) described by RFC 7517.
    /// Before making the request, validates that the access token is not expired.
    ///
    /// - Parameter completion: Completion handler with result containing the JWK or an error.
    public func getPublicKey(completion: @escaping (Result<GopayJWK, Error>) -> Void) {
        guard let encryptionService = self.encryptionService else {
            let error = GopaySDKErrors.sdkError(GopaySDKErrors.sdkNotInitializedEncryptionService)
            handleError(error)
            completion(.failure(error))
            return
        }
        
        encryptionService.getPublicKey { result in
            switch result {
            case .success(let jwk):
                completion(.success(jwk))
            case .failure(let error):
                self.handleError(error)
                completion(.failure(error))
            }
        }
    }
    
    /// Creates a card token by encrypting card data and sending it to the API.
    ///
    /// This method encrypts the card data using JWE (JSON Web Encryption) with RSA-OAEP-256
    /// for key encryption and AES-256-GCM for content encryption, then sends it to the
    /// GoPay API to create a card token.
    ///
    /// - Parameters:
    ///   - cardPan: The card PAN (Primary Account Number).
    ///   - expMonth: The expiration month in MM format.
    ///   - expYear: The expiration year in YY format.
    ///   - cvv: The card CVV.
    ///   - permanent: Whether to save the card for permanent usage.
    ///   - completion: Completion handler with result containing the card token response or an error.
    public func createCardToken(cardPan: String, expMonth: String, expYear: String, cvv: String, permanent: Bool, completion: @escaping (Result<GopayCreateCardTokenResponse, Error>) -> Void) {
        guard let cardTokenService = self.cardTokenService else {
            let error = GopaySDKErrors.sdkError(GopaySDKErrors.sdkNotInitializedCardTokenService)
            handleError(error)
            completion(.failure(error))
            return
        }
        
        let cardData = GopayCardData(cardPan: cardPan, expMonth: expMonth, expYear: expYear, cvv: cvv)
        cardTokenService.createCardToken(cardData: cardData, permanent: permanent) { result in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                self.handleError(error)
                completion(.failure(error))
            }
        }
    }
    
    /// Submits card form data to create a card token.
    ///
    /// This method uses the card form data that was automatically stored internally by `GopayCardForm`.
    /// It validates the card form data and then creates a card token by encrypting the card data
    /// using JWE (JSON Web Encryption) with RSA-OAEP-256 for key encryption and AES-256-GCM for
    /// content encryption, then sends it to the GoPay API.
    ///
    /// The sensitive card data (PAN, CVV) remains internal to the SDK and is never exposed
    /// to the caller. Only the masked response is returned.
    ///
    /// - Note: The card form data must be provided via `GopayCardForm`, which automatically
    ///   syncs the data to the SDK. This method retrieves the data internally. If multiple forms
    ///   are present, it uses the most recently active form. To submit a specific form, use
    ///   `submitCardForm(formId:permanent:completion:)`.
    ///
    /// - Parameters:
    ///   - permanent: Whether to save the card for permanent usage.
    ///   - completion: Completion handler with result containing the card token response or an error.
    public func submitCardForm(permanent: Bool, completion: @escaping (Result<GopayCreateCardTokenResponse, Error>) -> Void) {
        // Use the most recently active form, or the first available form if none is tracked
        let formId = mostRecentFormId ?? internalCardFormData.keys.first
        
        guard let formId = formId,
              let data = internalCardFormData[formId] else {
            let error = GopaySDKErrors.sdkError(GopaySDKErrors.noCardFormData)
            handleError(error)
            completion(.failure(error))
            return
        }
        
        // Validate form data
        guard data.isValid else {
            let error = GopaySDKErrors.sdkError(GopaySDKErrors.invalidCardFormData)
            handleError(error)
            completion(.failure(error))
            return
        }
        
        // Extract card data internally (sensitive data stays within SDK)
        let cardPan = data.cardNumber
        let expMonth = data.expirationMonth
        let expYear = data.expirationYear
        let cvv = data.cvv
        
        // Call existing createCardToken method with extracted data
        createCardToken(cardPan: cardPan, expMonth: expMonth, expYear: expYear, cvv: cvv, permanent: permanent, completion: completion)
    }
    
    /// Submits card form data from a specific form to create a card token.
    ///
    /// This method allows you to submit data from a specific form when multiple forms are present.
    /// Use this when you need to submit a particular form's data rather than the most recently active one.
    ///
    /// - Parameters:
    ///   - formId: The unique identifier of the form to submit (obtained from `GopayCardForm.formId`).
    ///   - permanent: Whether to save the card for permanent usage.
    ///   - completion: Completion handler with result containing the card token response or an error.
    public func submitCardForm(formId: String, permanent: Bool, completion: @escaping (Result<GopayCreateCardTokenResponse, Error>) -> Void) {
        // Retrieve form data for the specified form ID
        guard let data = internalCardFormData[formId] else {
            let error = GopaySDKErrors.sdkError(GopaySDKErrors.noCardFormData)
            handleError(error)
            completion(.failure(error))
            return
        }
        
        // Validate form data
        guard data.isValid else {
            let error = GopaySDKErrors.sdkError(GopaySDKErrors.invalidCardFormData)
            handleError(error)
            completion(.failure(error))
            return
        }
        
        // Extract card data internally (sensitive data stays within SDK)
        let cardPan = data.cardNumber
        let expMonth = data.expirationMonth
        let expYear = data.expirationYear
        let cvv = data.cvv
        
        // Call existing createCardToken method with extracted data
        createCardToken(cardPan: cardPan, expMonth: expMonth, expYear: expYear, cvv: cvv, permanent: permanent, completion: completion)
    }
    
    /// Internal/test initializer for dependency injection
    internal init(
        config: GopaySDKConfig? = nil,
        networkClient: NetworkClientProtocol? = nil,
        keychainStorage: KeychainStorageProtocol = KeychainStorage.shared
    ) {
        self.config = config
        let environment = config?.environment ?? GopayEnvironment.sandbox
        let client = networkClient ?? DefaultNetworkClient(baseURL: environment.baseURL)
        self.networkClient = client
        self.authService = GopayAuthService(networkClient: client)
        let encryptionService = GopayEncryptionService(networkClient: client, keychainStorage: keychainStorage)
        self.encryptionService = encryptionService
        self.cardTokenService = GopayCardTokenService(networkClient: client, keychainStorage: keychainStorage, encryptionService: encryptionService)
        self.keychainStorage = keychainStorage
    }
}
