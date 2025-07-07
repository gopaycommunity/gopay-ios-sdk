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
        case .development: return ""
        case .sandbox: return ""
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
    /// The timeout for requests in milliseconds.
    public let requestTimeoutMs: Int?
    
    /// Creates a new configuration for the Gopay SDK.
    /// - Parameters:
    ///   - environment: The environment to use.
    ///   - enableDebugLogging: Enable debug logging (default: `false`).
    ///   - errorCallback: Callback for error handling (default: `nil`).
    ///   - requestTimeoutMs: Request timeout in milliseconds (default: `30000`).
    public init(
        environment: GopayEnvironment,
        enableDebugLogging: Bool = false,
        errorCallback: ((Error) -> Void)? = nil,
        requestTimeoutMs: Int? = 30000
    ) {
        self.environment = environment
        self.enableDebugLogging = enableDebugLogging
        self.errorCallback = errorCallback
        self.requestTimeoutMs = requestTimeoutMs
    }
}

/// The main class for the Gopay SDK.
///
/// Use the shared instance to interact with the SDK.
public class GopaySDK {
    /// The shared instance of the SDK.
    public static let shared = GopaySDK()
    
    /// The current configuration for the SDK.
    public private(set) var config: GopaySDKConfig?
    
    /// Initializes the SDK with the given configuration.
    /// - Parameter config: The configuration to use.
    public func initialize(with config: GopaySDKConfig) {
        self.config = config
    }
    
    /// Handles an error using the configured error callback and debug logging.
    /// - Parameter error: The error to handle.
    func handleError(_ error: Error) {
        config?.errorCallback?(error)
        if config?.enableDebugLogging == true {
            print("[GopaySDK] Error: \(error)")
        }
    }
    
    /// Private initializer to enforce singleton usage.
    private init() {}
}
