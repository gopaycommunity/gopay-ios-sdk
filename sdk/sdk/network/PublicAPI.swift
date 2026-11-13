import Foundation

/// Public-resource endpoints authenticated with the `shareable_key` HTTP Basic scheme
/// (`client_id:shareable_key`). Mirrors the Android `PublicApi` + `ShareableKeyInterceptor`.
///
/// Requires both `clientId` and `shareableKey` from ``GopayConfig``; if either is missing every
/// call throws ``GopaySDKError/Code/authShareableKeyMissing``.
struct PublicAPI {
    private let client: AsyncHTTPClient
    private let clientId: String?
    private let shareableKey: String?
    private let telemetry: Telemetry

    init(client: AsyncHTTPClient, clientId: String?, shareableKey: String?, telemetry: Telemetry = .disabled) {
        self.client = client
        self.clientId = clientId
        self.shareableKey = shareableKey
        self.telemetry = telemetry
    }

    /// `GET /cards/public-key`: the merchant's RSA encryption JWK together with the gateway's
    /// clock, read from the response's `Date` header. The JWE built from the key takes its `iat`
    /// from that clock, so a device whose own clock is off still produces a payload the gateway
    /// accepts.
    ///
    /// The request skips `URLCache`: a stored response would bring back the old `Date` with it.
    /// Its answer is not reported: a public key is 2000 characters of nothing to read.
    func getPublicKey() async throws -> ServedPublicKey {
        var request = try jsonGET(path: "cards/public-key")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let result = try await client.send(request, telemetry: telemetry, paymentId: nil, reportsResponseBody: false)
        let jwk = try decodeOrThrow(GopayJWK.self, from: result, action: "fetch public key")
        let response = result.1
        let serverTime = parseHTTPDate(response.value(forHTTPHeaderField: "Date"))
        return ServedPublicKey(jwk: jwk, serverTime: serverTime)
    }

    /// `GET /cards/browser-data`: the address, User-Agent and Accept headers of this very request,
    /// as the gateway saw them. The deployed gateway answers the shareable-key scheme only; a
    /// payment or merchant token gets "Token domain not permitted", so it lives here next to the
    /// public key rather than on ``PaymentAPI``.
    ///
    /// `userAgent` goes out as the request's `User-Agent` and comes back as `user_agent`. It has
    /// to be the User-Agent the 3DS challenge WebView will send, because the issuer compares the
    /// value in the AReq with the browser it then sees; the SDK's own HTTP User-Agent would fail
    /// that comparison. `nil` leaves the header to ``DefaultNetworkClient``. `paymentId` is the
    /// charge's, for the telemetry.
    func getBrowserData(userAgent: String?, paymentId: String?) async throws -> BrowserDataDetected {
        var request = try jsonGET(path: "cards/browser-data")
        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        let result = try await client.send(request, telemetry: telemetry, paymentId: paymentId)
        return try decodeOrThrow(BrowserDataDetected.self, from: result, action: "fetch browser data")
    }

    /// `POST /cards/bin-lookup`: what the gateway knows about a card from the first digits of its
    /// number, with the body `{"bin": "<6 to 8 digits>"}`; a 404 when it knows nothing about the
    /// BIN. Both bodies are raw: ``CardMetadataLookup`` writes the BIN and reads the answer field
    /// by field rather than through a model, and judges the status itself.
    ///
    /// The BIN is card data, so the request body is never reported, and the answer only when its
    /// status is 2xx: an error answer may repeat the digits it was asked about. The request is
    /// dropped, not finished, when the task running it is cancelled, which is how the lookup's
    /// time limit ends it. A request dropped that way is not reported here;
    /// ``reportBinLookupWithoutAnswer(startedAt:)`` reports the one the limit ended.
    func lookUpBin(_ bin: String) async throws -> (Data, HTTPURLResponse) {
        var request = try jsonRequest("POST", path: Self.binLookupPath)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"bin\":\"\(bin)\"}".utf8)
        return try await client.send(
            request, telemetry: telemetry, paymentId: nil,
            reportsRequestBody: false, reportsErrorResponseBody: false, cancellable: true
        )
    }

    private static let binLookupPath = "cards/bin-lookup"

    /// Reports a BIN lookup its own time limit ended as one `api_call` without a status and
    /// without bodies, timed from `startedAt`, so a gateway that answers too slowly shows in the
    /// operational data. Not for a lookup that ended because the submit was cancelled or the
    /// encryption failed: that one is not reported at all. The Android SDK follows the same rule.
    ///
    /// - Parameter startedAt: A ``Telemetry/now()`` reading taken when the lookup started.
    func reportBinLookupWithoutAnswer(startedAt: UInt64) {
        telemetry.apiCall(
            Telemetry.ApiCallRecord(
                method: "POST", path: "/" + Self.binLookupPath, statusCode: nil, startedAt: startedAt,
                requestBody: nil, responseBody: nil
            ),
            paymentId: nil
        )
    }

    private func jsonGET(path: String) throws -> URLRequest {
        try jsonRequest("GET", path: path)
    }

    private func jsonRequest(_ method: String, path: String) throws -> URLRequest {
        let authHeader = try shareableKeyAuthHeader()
        guard let url = client.makeURL(path: path) else {
            throw GopaySDKError(.invalidBaseURL, message: "Invalid URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        return request
    }

    private func shareableKeyAuthHeader() throws -> String {
        guard let clientId = clientId, !clientId.isEmpty,
              let shareableKey = shareableKey, !shareableKey.isEmpty else {
            throw GopaySDKError(
                .authShareableKeyMissing,
                message: "clientId and shareableKey must be set on GopayConfig to use public endpoints"
            )
        }
        return gopayBasicAuthHeader(user: clientId, secret: shareableKey)
    }
}

/// The merchant's encryption key as `GET /cards/public-key` served it.
struct ServedPublicKey {
    let jwk: GopayJWK
    /// The gateway's clock from the response's `Date` header, or `nil` when the header was missing
    /// or not an IMF-fixdate.
    let serverTime: Date?
}
