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
    
    /// The base URL for the selected environment.
    var baseURL: String {
        switch self {
        case .development(let url): return url
        case .sandbox: return "https://gw.sandbox.gopay.com/gp-gw/api/4.0/"
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
    /// The network client for making API requests.
    private var networkClient: NetworkClientProtocol?
    
    /// Initializes the SDK with the given configuration.
    /// - Parameter config: The configuration to use.
    public func initialize(with config: GopaySDKConfig) {
        self.config = config
        let client = DefaultNetworkClient(baseURL: config.environment.baseURL)
        self.networkClient = client
        self.authService = GopayAuthService(networkClient: client)
        self.encryptionService = GopayEncryptionService(networkClient: client, keychainStorage: keychainStorage)
    }
    
    /// Handles an error using the configured error callback and debug logging.
    /// - Parameter error: The error to handle.
    func handleError(_ error: Error) {
        config?.errorCallback?(error)
        if config?.enableDebugLogging == true {
            print("[GopaySDK] Error: \(error)")
        }
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
                self.keychainStorage.storeAccessToken(response.access_token)
                if let refresh = response.refresh_token {
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
        if JwtUtils.isExpired(jwt: response.access_token) == true {
            throw GopaySDKErrors.sdkError(GopaySDKErrors.accessTokenExpiredShort)
        }

        self.keychainStorage.storeAccessToken(response.access_token)
        if let refresh = response.refresh_token {
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
    
    /// Internal/test initializer for dependency injection
    internal init(
        config: GopaySDKConfig? = nil,
        networkClient: NetworkClientProtocol? = nil,
        keychainStorage: KeychainStorageProtocol = KeychainStorage.shared
    ) {
        self.config = config
        let environment = config?.environment ?? GopayEnvironment.sandbox
        let networkClient = networkClient ?? DefaultNetworkClient(baseURL: environment.baseURL)
        self.networkClient = networkClient
        self.authService = GopayAuthService(networkClient: networkClient)
        self.encryptionService = GopayEncryptionService(networkClient: networkClient, keychainStorage: keychainStorage)
        self.keychainStorage = keychainStorage
    }
}
