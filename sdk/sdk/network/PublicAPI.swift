import Foundation

/// Public-resource endpoints authenticated with the `shareable_key` HTTP Basic scheme
/// (`client_id:shareable_key`). Mirrors the Android `PublicApi` + `ShareableKeyInterceptor`.
///
/// Requires both `clientId` and `shareableKey` from ``GopaySDKConfig``; if either is missing every
/// call throws ``GopaySDKError/Code/authShareableKeyMissing``.
struct PublicAPI {
    private let client: AsyncHTTPClient
    private let clientId: String?
    private let shareableKey: String?

    init(client: AsyncHTTPClient, clientId: String?, shareableKey: String?) {
        self.client = client
        self.clientId = clientId
        self.shareableKey = shareableKey
    }

    /// `GET /cards/public-key` — fetches the merchant's RSA encryption JWK.
    func getPublicKey() async throws -> GopayJWK {
        let authHeader = try shareableKeyAuthHeader()
        guard let url = client.makeURL(path: "cards/public-key") else {
            throw GopaySDKError(.invalidBaseURL, message: "Invalid URL for cards/public-key")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let result = try await client.send(request)
        return try decodeOrThrow(GopayJWK.self, from: result, action: "fetch public key")
    }

    private func shareableKeyAuthHeader() throws -> String {
        guard let clientId = clientId, !clientId.isEmpty,
              let shareableKey = shareableKey, !shareableKey.isEmpty else {
            throw GopaySDKError(
                .authShareableKeyMissing,
                message: "clientId and shareableKey must be set on GopaySDKConfig to use public endpoints"
            )
        }
        return gopayBasicAuthHeader(user: clientId, secret: shareableKey)
    }
}
