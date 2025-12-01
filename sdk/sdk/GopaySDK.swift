import Foundation
import SwiftUI

/// The environment to use for the SDK.
///
/// - Note: Each case represents a different backend environment.
public enum GopayEnvironment {
    /// The development environment.
    case development
    /// The sandbox environment.
    case sandbox
    /// The production environment.
    case production
    
    /// The base URL for the selected environment.
    var baseURL: String {
        switch self {
        case .development: return "https://gw.alpha8.dev.gopay.com/gp-gw/api/4.0/"
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
    /// The shared instance of the SDK.
    public static let shared = GopaySDK()
    
    /// The keychain storage to use for the SDK.
    private var keychainStorage: KeychainStorageProtocol = KeychainStorage.shared

    /// The current configuration for the SDK.
    public private(set) var config: GopaySDKConfig?
    /// The authentication service.
    public private(set) var authService: GopayAuthService?
    
    /// Initializes the SDK with the given configuration.
    /// - Parameter config: The configuration to use.
    public func initialize(with config: GopaySDKConfig) {
        self.config = config
        let client = DefaultNetworkClient(baseURL: config.environment.baseURL)
        self.authService = GopayAuthService(networkClient: client)
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
            completion(.failure(NSError(domain: "GopaySDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "SDK not initialized or authService unavailable."])))
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
            throw NSError(domain: "GopaySDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "Access token is expired."])
        }

        self.keychainStorage.storeAccessToken(response.access_token)
        if let refresh = response.refresh_token {
            self.keychainStorage.storeRefreshToken(refresh)
        }
    }
    
    /// Internal/test initializer for dependency injection
    internal init(
        config: GopaySDKConfig? = nil,
        networkClient: NetworkClientProtocol? = nil,
        keychainStorage: KeychainStorageProtocol = KeychainStorage.shared
    ) {
        self.config = config
        let environment = config?.environment ?? GopayEnvironment.development
        let networkClient = networkClient ?? DefaultNetworkClient(baseURL: environment.baseURL)
        self.authService = GopayAuthService(networkClient: networkClient)
        self.keychainStorage = keychainStorage
    }
}
