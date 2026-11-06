import Foundation

/// Supplies the payment-scoped JWT to ``PaymentAPI`` and re-authenticates on demand.
///
/// Implemented by ``PaymentSession`` (an actor), so all members are accessed asynchronously. The
/// reference is held weakly by ``PaymentAPI`` to avoid a session ⇄ api retain cycle.
protocol SessionTokenProviding: AnyObject {
    /// The cached JWT if still valid, otherwise `nil`.
    func currentToken() async -> String?
    /// Drops the cached token so the next request re-authenticates.
    func invalidateToken() async
    /// Acquires a fresh token (single-flighted). Throws if credentials are rejected or the session
    /// is closed. Unreported: the call this runs inside reports the failure.
    func authenticate() async throws -> String
}

/// Per-session payment endpoints. Attaches the session's `Bearer` token to every request and, on a
/// 401, re-authenticates exactly once and retries; a second 401 surfaces as
/// ``GopaySDKError/Code/authPaymentTokenExpired``. The iOS counterpart of the Android
/// `PaymentApi` + `SessionAuthInterceptor`.
final class PaymentAPI {
    private let client: AsyncHTTPClient
    private weak var tokenProvider: SessionTokenProviding?
    private let telemetry: Telemetry

    init(client: AsyncHTTPClient, tokenProvider: SessionTokenProviding, telemetry: Telemetry = .disabled) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.telemetry = telemetry
    }

    /// `GET /payments/{payment_id}`
    func getPaymentStatus(paymentId: String) async throws -> PaymentDetails {
        try await run(action: "get payment status", paymentId: paymentId) {
            self.jsonGET(path: "payments/\(paymentId)")
        }
    }

    /// `POST /payments/{payment_id}/charge`
    func charge(paymentId: String, request: ChargePaymentRequest) async throws -> ChargePaymentResponse {
        let body = try JSONEncoder().encode(request)
        return try await run(action: "charge payment", paymentId: paymentId) {
            guard let url = self.client.makeURL(path: "payments/\(paymentId)/charge") else { return nil }
            var r = URLRequest(url: url)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            r.httpBody = body
            return r
        }
    }

    /// `GET /payments/{payment_id}/charge`
    func getChargeState(paymentId: String) async throws -> ChargePaymentResponse {
        try await run(action: "get charge state", paymentId: paymentId) {
            self.jsonGET(path: "payments/\(paymentId)/charge")
        }
    }

    /// `GET /payments/{payment_id}/apple-pay/app-info`
    func getApplePayAppInfo(paymentId: String) async throws -> GopayApplePayAppInfoResponse {
        try await run(action: "get Apple Pay info", paymentId: paymentId) {
            self.jsonGET(path: "payments/\(paymentId)/apple-pay/app-info")
        }
    }

    /// `GET /payments/{payment_id}/qr-payment/info`
    func getQrPaymentInfo(paymentId: String, format: QrCodeFormat?) async throws -> QrPaymentDetails {
        var path = "payments/\(paymentId)/qr-payment/info"
        if let format = format { path += "?format=\(format.rawValue)" }
        return try await run(action: "get QR payment info", paymentId: paymentId) {
            self.jsonGET(path: path)
        }
    }

    /// `POST /payments/{payment_id}/init-session`: tells the gateway which SDK, in which version,
    /// works with the payment, and in `Accept-Language` the device's languages, from which it sets
    /// the payment's language. Answered with a `204` and no body; nothing is read from it.
    ///
    /// Unlike every other call here it does not go through `run`: a 401 neither drops the
    /// session's token nor asks for a new one, since a call the payment never needed must not
    /// touch the session the payment runs on (the browser SDK's `recoverAuth = false`). Without a
    /// valid token in hand nothing is sent. The request gives up after
    /// ``initSessionTimeout``, as the telemetry does, and is dropped, not finished, when the task
    /// running it is cancelled.
    ///
    /// - Parameter languages: The device's languages, in its order, for `Accept-Language`
    ///   (``acceptLanguageHeader(_:fallback:)``).
    /// - Throws: The request's own failure: ``GopaySDKError`` for an HTTP error status or a
    ///   transport failure, `CancellationError` when cancelled. The caller swallows them.
    func initSession(paymentId: String, request: InitSessionRequest, languages: [String]) async throws {
        guard let token = await tokenProvider?.currentToken(),
              let url = client.makeURL(path: "payments/\(paymentId)/init-session")
        else { return }
        var r = URLRequest(url: url, timeoutInterval: Self.initSessionTimeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let acceptLanguage = acceptLanguageHeader(languages) {
            r.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        }
        r.httpBody = try JSONEncoder().encode(request)
        let (data, http) = try await client.send(
            authorized(r, token: token), telemetry: telemetry, paymentId: paymentId, cancellable: true
        )
        try throwIfNotSuccessful(http, body: data, action: "init session")
    }

    /// How long ``initSession(paymentId:request:languages:)`` waits: the telemetry's own timeout.
    /// `URLRequest.timeoutInterval` is an idle timeout, the longest wait for the next data, not
    /// the Android SDK's call timeout over the whole request; for a request this small the two
    /// end the same.
    static let initSessionTimeout = Telemetry.requestTimeout

    // MARK: - Internals

    private func jsonGET(path: String) -> URLRequest? {
        guard let url = client.makeURL(path: path) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    private func run<T: Decodable>(action: String, paymentId: String, build: () -> URLRequest?) async throws -> T {
        guard let provider = tokenProvider else {
            throw GopaySDKError(.authPaymentSessionClosed, message: "PaymentSession is closed")
        }
        guard let request = build() else {
            throw GopaySDKError(.invalidBaseURL, message: "Invalid URL while trying to \(action)")
        }

        var token = try await validToken(from: provider)
        var result = try await client.send(authorized(request, token: token), telemetry: telemetry, paymentId: paymentId)

        if result.1.statusCode == 401 {
            // Stale token — re-auth once and retry.
            await provider.invalidateToken()
            token = try await provider.authenticate()
            result = try await client.send(authorized(request, token: token), telemetry: telemetry, paymentId: paymentId)
            if result.1.statusCode == 401 {
                let gatewayError = GopayGatewayError.parse(result.0)
                throw GopaySDKError(
                    .authPaymentTokenExpired,
                    message: "Payment-scoped token still rejected after re-authentication" + gatewayError.messageSuffix,
                    httpStatus: 401,
                    gatewayError: gatewayError
                )
            }
        }

        return try decodeOrThrow(T.self, from: result, action: action)
    }

    private func validToken(from provider: SessionTokenProviding) async throws -> String {
        if let token = await provider.currentToken() {
            return token
        }
        return try await provider.authenticate()
    }

    private func authorized(_ request: URLRequest, token: String) -> URLRequest {
        var r = request
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }
}
