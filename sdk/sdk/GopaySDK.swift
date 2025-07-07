import Foundation
import SwiftUI

/**
 * The environment to use for the SDK.
 * 
 * @param development The development environment.
 * @param sandbox The sandbox environment.
 * @param production The production environment.
 */
public enum GopayEnvironment {
    case development
    case sandbox
    case production
    
    var baseURL: String {
        switch self {
        case .development: return ""
        case .sandbox: return ""
        case .production: return ""
        }
    }
}

/**
 * Configuration class for the Gopay SDK.
 * Holds all environment-specific constants and settings. 
 * 
 * @param environment The environment to use for the SDK.
 * @param enableDebugLogging Whether to enable debug logging.
 * @param errorCallback The callback to use for errors.
 * @param requestTimeoutMs The timeout for requests in milliseconds.
 */
public struct GopaySDKConfig {
    public let environment: GopayEnvironment
    public let enableDebugLogging: Bool
    public let errorCallback: ((Error) -> Void)?
    public let requestTimeoutMs: Int?
    
    public init(environment: GopayEnvironment,
                enableDebugLogging: Bool = false,
                errorCallback: ((Error) -> Void)? = nil,
                requestTimeoutMs: Int? = 30000) {
        self.environment = environment
        self.enableDebugLogging = enableDebugLogging
        self.errorCallback = errorCallback
        self.requestTimeoutMs = requestTimeoutMs
    }
}

/**
 * The main class for the Gopay SDK.
 * 
 * @param shared The shared instance of the SDK.
 * @param config The configuration for the SDK.
 */
public class GopaySDK {
    public static let shared = GopaySDK()
    
    public private(set) var config: GopaySDKConfig?
    
    /**
     * Constructor intentially let empty. Will be used in later development phases
     */
    private init() {}
    
    public func initialize(with config: GopaySDKConfig) {
        self.config = config
    }
    
    func handleError(_ error: Error) {
        config?.errorCallback?(error)
        if config?.enableDebugLogging == true {
            print("[GopaySDK] Error: \(error)")
        }
    }
}
