import Foundation

/// The OAuth2 token endpoint.
///
/// Used on mobile with payment-scoped credentials: basic auth `payment_id:payment_secret`,
/// `grant_type=payment_credentials`, returning a JWT scoped to that single payment. No bearer
/// token is attached here — credentials are supplied per call. Mirrors the Android `AuthApi`.
struct AuthAPI {
    private let client: AsyncHTTPClient

    init(client: AsyncHTTPClient) {
        self.client = client
    }

    /// Exchanges credentials for an access token.
    ///
    /// - Parameters:
    ///   - basicAuth: A full `Basic base64(payment_id:payment_secret)` header value.
    ///   - grantType: Custom GoPay value `payment_credentials` (Payments.yaml,
    ///     `Payment-Credentials-Request`).
    ///   - scope: Optional space-separated scope list.
    func token(basicAuth: String, grantType: String, scope: String?) async throws -> AccessTokenResponse {
        guard let url = client.makeURL(path: "oauth2/token") else {
            throw GopaySDKError(.invalidBaseURL, message: "Invalid URL for oauth2/token")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(basicAuth, forHTTPHeaderField: "Authorization")

        var params = ["grant_type": grantType]
        if let scope = scope { params["scope"] = scope }
        request.httpBody = formURLEncodedBody(params)

        let result = try await client.send(request)
        return try decodeOrThrow(AccessTokenResponse.self, from: result, action: "acquire payment-scoped token")
    }
}
