import Foundation

public struct GopayAuthResponse: Decodable, Encodable {
    public let accessToken: String
    public let tokenType: String
    public let refreshToken: String?
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case scope
    }
}

public class GopayAuthService {
    private let networkClient: NetworkClientProtocol
    private let endpoint: String = "oauth2/token"

    public init(networkClient: NetworkClientProtocol) {
        self.networkClient = networkClient
    }

    /// Authenticates using client credentials grant.
    /// - Parameters:
    ///   - clientId: The client ID.
    ///   - clientSecret: The client secret.
    ///   - scope: The requested scopes (space-separated).
    ///   - completion: Completion handler with result.
    public func authenticate(clientId: String, clientSecret: String, scope: String, completion: @escaping (Result<GopayAuthResponse, Error>) -> Void) {
        guard let url = networkClient.makeURL(path: endpoint) else {
            completion(.failure(GopaySDKErrors.invalidURLError()))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Basic Auth header
        let credentials = "\(clientId):\(clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            completion(.failure(GopaySDKErrors.encodingError()))
            return
        }
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        // Body
        let bodyString = "grant_type=client_credentials&scope=\(scope)"
        request.httpBody = bodyString.data(using: .utf8)

        networkClient.sendRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(GopayAuthResponse.self, from: data)
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
