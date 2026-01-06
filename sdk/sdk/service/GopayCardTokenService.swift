import Foundation

/// Card scheme enumeration.
public enum CardScheme: String, Decodable {
    case visa = "VISA"
    case mastercard = "MASTERCARD"
}

/// Card data structure for encryption.
public struct GopayCardData: Encodable {
    /// Card PAN (Primary Account Number).
    public let card_pan: String
    /// Expiration month (MM format).
    public let exp_month: String
    /// Expiration year (YY format).
    public let exp_year: String
    /// Card CVV.
    public let cvv: String
    
    public init(card_pan: String, exp_month: String, exp_year: String, cvv: String) {
        self.card_pan = card_pan
        self.exp_month = exp_month
        self.exp_year = exp_year
        self.cvv = cvv
    }
}

/// Request body for creating a card token.
struct GopayCreateCardTokenRequest: Encodable {
    /// The JWE string containing the encrypted card data.
    let payload: String
    /// Whether to save the card for permanent usage.
    let permanent: Bool
}

/// Response from creating a card token.
public struct GopayCreateCardTokenResponse: Decodable {
    /// Masked funding PAN of the card.
    public let masked_pan: String
    /// Expiration month (MM format).
    public let expiration_month: String
    /// Expiration year (YY format).
    public let expiration_year: String
    /// Card scheme.
    public let scheme: CardScheme
}

public class GopayCardTokenService {
    private let networkClient: NetworkClientProtocol
    private let keychainStorage: KeychainStorageProtocol
    private let encryptionService: GopayEncryptionService
    private let endpoint: String = "cards/tokens"
    
    public init(networkClient: NetworkClientProtocol, keychainStorage: KeychainStorageProtocol, encryptionService: GopayEncryptionService) {
        self.networkClient = networkClient
        self.keychainStorage = keychainStorage
        self.encryptionService = encryptionService
    }
    
    /// Creates a card token by encrypting card data and sending it to the API.
    /// - Parameters:
    ///   - cardData: The card data to encrypt and tokenize.
    ///   - permanent: Whether to save the card for permanent usage.
    ///   - completion: Completion handler with result containing the card token response or an error.
    public func createCardToken(cardData: GopayCardData, permanent: Bool, completion: @escaping (Result<GopayCreateCardTokenResponse, Error>) -> Void) {
        // Validate access token exists and is not expired
        guard let accessToken = keychainStorage.getAccessToken() else {
            completion(.failure(GopaySDKErrors.cardTokenServiceError(GopaySDKErrors.noAccessToken)))
            return
        }
        
        if let isExpired = JwtUtils.isExpired(jwt: accessToken), isExpired == true {
            completion(.failure(GopaySDKErrors.cardTokenServiceError(GopaySDKErrors.accessTokenExpired)))
            return
        }
        
        // Get public key
        encryptionService.getPublicKey { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let jwk):
                // Encrypt card data using JWE
                let jweResult = JweUtils.createJWE(cardData: cardData, jwk: jwk)
                
                switch jweResult {
                case .success(let jweString):
                    // Build POST request
                    self.sendCreateCardTokenRequest(jweString: jweString, permanent: permanent, accessToken: accessToken, completion: completion)
                    
                case .failure(let error):
                    completion(.failure(error))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func sendCreateCardTokenRequest(jweString: String, permanent: Bool, accessToken: String, completion: @escaping (Result<GopayCreateCardTokenResponse, Error>) -> Void) {
        guard let url = networkClient.makeURL(path: endpoint) else {
            completion(.failure(GopaySDKErrors.cardTokenServiceError(GopaySDKErrors.invalidCardTokenURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let requestBody = GopayCreateCardTokenRequest(payload: jweString, permanent: permanent)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.failure(GopaySDKErrors.cardTokenServiceError(GopaySDKErrors.encodingErrorMessage)))
            return
        }
        
        networkClient.sendRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(GopayCreateCardTokenResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

