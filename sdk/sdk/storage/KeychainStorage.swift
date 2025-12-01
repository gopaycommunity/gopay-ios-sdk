import Foundation
import Security

/// Protocol for keychain storage operations.
///
/// Allows for dependency injection and testing by providing a mockable interface
/// for token storage and retrieval.
public protocol KeychainStorageProtocol {
    func storeAccessToken(_ token: String) -> Bool
    func storeRefreshToken(_ token: String) -> Bool
    func getAccessToken() -> String?
    func getRefreshToken() -> String?
    func clearTokens()
}

class KeychainStorage: KeychainStorageProtocol {
    static let shared: KeychainStorageProtocol = KeychainStorage()
    private init() {}
    
    private let accessTokenKey = "com.gopay.sdk.accessToken"
    private let refreshTokenKey = "com.gopay.sdk.refreshToken"
    
    // MARK: - Public Methods
    
    func storeAccessToken(_ token: String) -> Bool {
        return store(token: token, forKey: accessTokenKey)
    }
    
    func storeRefreshToken(_ token: String) -> Bool {
        return store(token: token, forKey: refreshTokenKey)
    }
    
    func getAccessToken() -> String? {
        return retrieveToken(forKey: accessTokenKey)
    }
    
    func getRefreshToken() -> String? {
        return retrieveToken(forKey: refreshTokenKey)
    }
    
    func clearTokens() {
        deleteToken(forKey: accessTokenKey)
        deleteToken(forKey: refreshTokenKey)
    }
    
    // MARK: - Private Methods
    
    private func store(token: String, forKey key: String) -> Bool {
        if let data = token.data(using: .utf8) {
            // Delete any existing item
            deleteToken(forKey: key)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecValueData as String: data
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            return status == errSecSuccess
        }
        return false
    }
    
    private func retrieveToken(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data, let token = String(data: data, encoding: .utf8) {
            return token
        }
        return nil
    }
    
    private func deleteToken(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
} 