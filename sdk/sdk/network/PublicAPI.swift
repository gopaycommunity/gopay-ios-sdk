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
        let request = try jsonGET(path: "cards/public-key")
        let result = try await client.send(request)
        return try decodeOrThrow(GopayJWK.self, from: result, action: "fetch public key")
    }

    /// `GET /cards/browser-data`: the address, User-Agent and Accept headers of this very request,
    /// as the gateway saw them. The deployed gateway answers the shareable-key scheme only; a
    /// payment or merchant token gets "Token domain not permitted", so it lives here next to the
    /// public key rather than on ``PaymentAPI``.
    ///
    /// `userAgent` goes out as the request's `User-Agent` and comes back as `user_agent`. It has
    /// to be the User-Agent the 3DS challenge WebView will send, because the issuer compares the
    /// value in the AReq with the browser it then sees; the SDK's own HTTP User-Agent would fail
    /// that comparison. `nil` leaves the header to ``DefaultNetworkClient``.
    func getBrowserData(userAgent: String?) async throws -> BrowserDataDetected {
        var request = try jsonGET(path: "cards/browser-data")
        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        let result = try await client.send(request)
        return try decodeOrThrow(BrowserDataDetected.self, from: result, action: "fetch browser data")
    }

    private func jsonGET(path: String) throws -> URLRequest {
        let authHeader = try shareableKeyAuthHeader()
        guard let url = client.makeURL(path: path) else {
            throw GopaySDKError(.invalidBaseURL, message: "Invalid URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        return request
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
