import Foundation

/// Builds an `Authorization: Basic …` header value from a user/secret pair, using the
/// standard-alphabet base64 encoding required by HTTP Basic auth (RFC 7617).
func gopayBasicAuthHeader(user: String, secret: String) -> String {
    let encoded = Data("\(user):\(secret)".utf8).base64EncodedString()
    return "Basic \(encoded)"
}

/// Encodes a `[String: String]` body as `application/x-www-form-urlencoded` data.
func formURLEncodedBody(_ params: [String: String]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let pairs = params.map { key, value -> String in
        let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(k)=\(v)"
    }
    return Data(pairs.joined(separator: "&").utf8)
}

/// Validates an HTTP result and decodes its body, or throws a ``GopaySDKError`` describing the
/// failure. The iOS counterpart of the Android `Response<T>.unwrap(action)` helper.
///
/// - Non-2xx → ``GopaySDKError/Code/networkClientError`` (4xx) or
///   ``GopaySDKError/Code/networkServerError`` (5xx), carrying the HTTP status.
/// - Decoding failure → ``GopaySDKError/Code/decoding``.
func decodeOrThrow<T: Decodable>(
    _ type: T.Type,
    from result: (Data, HTTPURLResponse),
    action: String
) throws -> T {
    let (data, http) = result
    try throwIfNotSuccessful(http, action: action)
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        throw GopaySDKError(
            .decoding,
            message: "Failed to decode response while trying to \(action): \(error.localizedDescription)",
            underlying: error
        )
    }
}

/// Validates an HTTP result without decoding a body, throwing on non-2xx.
func throwIfNotSuccessful(_ http: HTTPURLResponse, action: String) throws {
    guard (200..<300).contains(http.statusCode) else {
        let code: GopaySDKError.Code = http.statusCode >= 500 ? .networkServerError : .networkClientError
        throw GopaySDKError(
            code,
            message: "Failed to \(action): HTTP \(http.statusCode)",
            httpStatus: http.statusCode
        )
    }
}
