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

/// Reads an HTTP `Date` header in the IMF-fixdate form (RFC 9110, section 5.6.7), for example
/// `Wed, 30 Sep 2026 17:34:17 GMT`. Returns `nil` for a missing value or any other form, the
/// obsolete RFC 850 and asctime ones and offsets other than `GMT` included; the gateway sends
/// IMF-fixdate, and a value it did not send is not worth guessing at. Mirrors the Android
/// `HttpDate.parseSeconds`, which accepts and refuses the same inputs.
///
/// `DateFormatter` alone is too forgiving even when not lenient: it takes a two-digit year as the
/// year 26, a single-digit hour, any letter case and a missing zone. So the shape is checked by
/// the pattern first, the formatter only reads the numbers, and the day of the week has to match
/// the date it names. The digits are spelled `[0-9]` because `\d` in `NSRegularExpression` also
/// matches non-ASCII digits, which Java's `\d` on Android does not.
func parseHTTPDate(_ value: String?) -> Date? {
    guard let value = value,
          value.range(of: imfFixdatePattern, options: .regularExpression) != nil,
          let date = imfFixdateFormatter.date(from: value)
    else { return nil }
    let weekday = imfFixdateCalendar.component(.weekday, from: date)
    guard imfFixdateFormatter.shortWeekdaySymbols[weekday - 1] == value.prefix(3) else { return nil }
    return date
}

private let imfFixdatePattern = #"^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$"#

private let imfFixdateCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "GMT")!
    return calendar
}()

/// `DateFormatter` is thread-safe since iOS 7, so one instance serves every request.
private let imfFixdateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    formatter.isLenient = false
    return formatter
}()

/// Validates an HTTP result and decodes its body, or throws a ``GopaySDKError`` describing the
/// failure. The iOS counterpart of the Android `Response<T>.unwrap(action)` helper.
///
/// - Non-2xx → ``GopaySDKError/Code/networkClientError`` (4xx) or
///   ``GopaySDKError/Code/networkServerError`` (5xx), carrying the HTTP status and the gateway's
///   error body.
/// - Decoding failure → ``GopaySDKError/Code/decoding``.
func decodeOrThrow<T: Decodable>(
    _ type: T.Type,
    from result: (Data, HTTPURLResponse),
    action: String
) throws -> T {
    let (data, http) = result
    try throwIfNotSuccessful(http, body: data, action: action)
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

/// Validates an HTTP result without decoding a body, throwing on non-2xx. The gateway's error
/// body, when `body` holds one, goes into ``GopaySDKError/gatewayError`` and its `message` into
/// the error's own message, so "HTTP 403" says why.
func throwIfNotSuccessful(_ http: HTTPURLResponse, body: Data, action: String) throws {
    guard (200..<300).contains(http.statusCode) else {
        let code: GopaySDKError.Code = http.statusCode >= 500 ? .networkServerError : .networkClientError
        let gatewayError = GopayGatewayError.parse(body)
        throw GopaySDKError(
            code,
            message: "Failed to \(action): HTTP \(http.statusCode)" + gatewayError.messageSuffix,
            httpStatus: http.statusCode,
            gatewayError: gatewayError
        )
    }
}

extension Optional where Wrapped == GopayGatewayError {
    /// `": <message>"` from the gateway, or nothing when it sent none or only white space.
    var messageSuffix: String {
        guard let message = self?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else { return "" }
        return ": \(message)"
    }
}

extension AsyncHTTPClient {
    /// Sends `request` and reports it to `telemetry` as one `api_call`, whichever way it ends:
    /// with its status, or without one when no response came. The one place every gateway request
    /// passes through, so the method, the path, the status, the time and the bodies are read from
    /// the request itself and never drift from what was sent.
    ///
    /// The report is queued, not awaited, so it adds nothing to the request's own time.
    ///
    /// - Parameters:
    ///   - paymentId: The payment the request belongs to, `nil` for the merchant-level ones.
    ///   - reportsResponseBody: `false` for the token exchange, whose answer is a token pair the
    ///     redaction would reduce to nothing anyway, and for the public key.
    func send(
        _ request: URLRequest,
        telemetry: Telemetry,
        paymentId: String?,
        reportsResponseBody: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let startedAt = Telemetry.now()
        let path = telemetryPath(of: request)
        func report(_ result: (Data, HTTPURLResponse)?) {
            telemetry.apiCall(
                method: request.httpMethod ?? "GET",
                path: path,
                statusCode: result?.1.statusCode,
                startedAt: startedAt,
                requestBody: request.httpBody,
                requestContentType: request.value(forHTTPHeaderField: "Content-Type"),
                responseBody: reportsResponseBody ? result?.0 : nil,
                responseContentType: result?.1.value(forHTTPHeaderField: "Content-Type"),
                paymentId: paymentId
            )
        }
        do {
            let result = try await send(request)
            report(result)
            return result
        } catch {
            report(nil)
            throw error
        }
    }

    /// The request's path below the API's base path, so the report reads `/payments/…` whatever
    /// gateway the SDK talks to.
    private func telemetryPath(of request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        guard let basePath = URL(string: baseURL)?.path, basePath.count > 1 else { return path }
        let prefix = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
