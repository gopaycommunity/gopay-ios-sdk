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
