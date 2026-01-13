import Foundation

/// JSON Web Key (JWK) structure for public encryption key.
///
/// Represents the public key used for encrypting card data.
/// Format follows RFC 7517: JSON Web Key (JWK).
public struct GopayJWK: Decodable, Encodable {
    /// Key type. Will always be "RSA".
    public let kty: String
    /// Key ID containing information about the key age.
    public let kid: String
    /// Key usage. Will always be "enc".
    public let use: String
    /// Algorithm to be used for encryption with the key.
    public let alg: String
    /// The RSA public key modulus part.
    public let n: String
    /// The RSA public key exponent part.
    public let e: String
}

public class GopayEncryptionService {
    private let networkClient: NetworkClientProtocol
    private let keychainStorage: KeychainStorageProtocol
    private let endpoint: String = "encryption/public-key"
    
    public init(networkClient: NetworkClientProtocol, keychainStorage: KeychainStorageProtocol) {
        self.networkClient = networkClient
        self.keychainStorage = keychainStorage
    }
    
    /// Retrieves the public encryption key to be used for encrypting card data.
    ///
    /// The key is structured as a JWK (JSON Web Key) described by RFC 7517.
    /// Before making the request, validates that the access token is not expired.
    ///
    /// - Parameter completion: Completion handler with result containing the JWK or an error.
    public func getPublicKey(completion: @escaping (Result<GopayJWK, Error>) -> Void) {
        // Get access token from storage
        guard let accessToken = keychainStorage.getAccessToken() else {
            completion(.failure(GopaySDKErrors.encryptionServiceError(GopaySDKErrors.noAccessToken)))
            return
        }
        
        // Validate token is not expired
        if let isExpired = JwtUtils.isExpired(jwt: accessToken), isExpired {
            completion(.failure(GopaySDKErrors.encryptionServiceError(GopaySDKErrors.accessTokenExpired)))
            return
        }
        
        // Build request
        guard let url = networkClient.makeURL(path: endpoint) else {
            completion(.failure(GopaySDKErrors.encryptionServiceError(GopaySDKErrors.invalidPublicKeyURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // Send request
        networkClient.sendRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    let jwk = try JSONDecoder().decode(GopayJWK.self, from: data)
                    completion(.success(jwk))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

