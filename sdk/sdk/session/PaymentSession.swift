import Foundation

/// A live, per-payment authentication context.
///
/// Created via ``GopaySDK/startPaymentSession(paymentId:paymentSecret:scope:)`` with the
/// `payment_id` / `payment_secret` pair the merchant backend issued when it created the payment.
/// Holds the secret in memory (never persisted) and exchanges it at `POST /oauth2/token` with
/// `grant_type=payment_credentials` for a payment-scoped JWT. The JWT is attached to every request
/// on this session's ``PaymentAPI``; on a 401 the session re-authenticates exactly once using the
/// cached secret.
///
/// Sessions are concurrency-safe (an `actor`) and independent — two sessions for two payments never
/// share credentials or tokens. Always ``close()`` a session when the flow terminates so the
/// in-memory secret is wiped. Construction goes through the eager ``create(paymentId:paymentSecret:scope:authApi:client:onClose:)``
/// factory so bad credentials surface at the start of the flow rather than on the first API call.
public actor PaymentSession {

    /// The payment this session is scoped to. Immutable, so it's readable without `await`.
    public nonisolated let paymentId: String

    private let scope: String
    private let authApi: AuthAPI
    private let onClose: @Sendable (PaymentSession) async -> Void

    /// In-memory only; `nil` once ``close()`` wipes it — the canonical "closed" signal.
    private var paymentSecret: String?
    private var token: String?
    /// Unix seconds. `0` means "unknown" (no `exp` claim); checked alongside ``token``.
    private var tokenExpiresAt: TimeInterval = 0
    /// In-flight re-auth, used to single-flight concurrent callers (actors are reentrant, so a bare
    /// flag would let several callers each fire a token request).
    private var authTask: Task<String, Error>?

    /// Set once by ``attach(client:)`` immediately after construction.
    private var api: PaymentAPI!

    init(
        paymentId: String,
        scope: String,
        authApi: AuthAPI,
        onClose: @escaping @Sendable (PaymentSession) async -> Void
    ) {
        self.paymentId = paymentId
        self.scope = scope
        self.authApi = authApi
        self.onClose = onClose
        self.api = nil
    }

    private func attach(client: AsyncHTTPClient) {
        self.api = PaymentAPI(client: client, tokenProvider: self)
    }

    // MARK: - Endpoints

    /// `GET /payments/{payment_id}`
    public func getStatus() async throws -> PaymentDetails {
        try await api.getPaymentStatus(paymentId: paymentId)
    }

    /// `POST /payments/{payment_id}/charge`
    public func charge(_ request: ChargePaymentRequest) async throws -> ChargePaymentResponse {
        try await api.charge(paymentId: paymentId, request: request)
    }

    /// `GET /payments/{payment_id}/charge`
    public func getChargeState() async throws -> ChargePaymentResponse {
        try await api.getChargeState(paymentId: paymentId)
    }

    /// `GET /payments/{payment_id}/qr-payment/info`
    public func getQrPaymentInfo(format: QrCodeFormat? = nil) async throws -> QrPaymentDetails {
        try await api.getQrPaymentInfo(paymentId: paymentId, format: format)
    }

    /// `GET /payments/{payment_id}/apple-pay/app-info` — the BE-configured Apple Pay request for
    /// this payment, used to build the native sheet.
    public func getApplePayInfo() async throws -> GopayApplePayAppInfoResponse {
        try await api.getApplePayAppInfo(paymentId: paymentId)
    }

    // MARK: - Lifecycle

    /// Wipes the in-memory `payment_secret` and JWT and unregisters this session from the SDK
    /// registry. Idempotent — once the secret is nil, ``reauthenticate()`` throws
    /// ``GopaySDKError/Code/authPaymentSessionClosed``.
    public func close() async {
        guard paymentSecret != nil else { return }
        paymentSecret = nil
        token = nil
        tokenExpiresAt = 0
        authTask?.cancel()
        authTask = nil
        await onClose(self)
    }

    // MARK: - Eager auth

    private func startEagerAuth(secret: String) async throws {
        paymentSecret = secret
        _ = try await reauthenticate()
    }

    private func performAuth() async throws -> String {
        guard let secret = paymentSecret else {
            throw GopaySDKError(
                .authPaymentSessionClosed,
                message: "PaymentSession for \(paymentId) is closed"
            )
        }
        let response: AccessTokenResponse
        do {
            response = try await authApi.token(
                basicAuth: gopayBasicAuthHeader(user: paymentId, secret: secret),
                grantType: Self.grantTypePaymentCredentials,
                scope: scope
            )
        } catch let error as GopaySDKError where error.code == .networkClientError {
            // A 4xx from /oauth2/token means the payment_id / payment_secret pair was rejected.
            throw GopaySDKError(
                .authPaymentCredentialsInvalid,
                message: "payment_credentials rejected: HTTP \(error.httpStatus.map(String.init) ?? "?")",
                httpStatus: error.httpStatus,
                underlying: error
            )
        } catch let error as GopaySDKError {
            throw error
        } catch {
            throw GopaySDKError(
                .authPaymentCredentialsInvalid,
                message: "Failed to acquire payment-scoped token: \(error.localizedDescription)",
                underlying: error
            )
        }
        token = response.accessToken
        tokenExpiresAt = JwtUtils.expirationSeconds(jwt: response.accessToken)
        return response.accessToken
    }

    // MARK: - Factory

    /// Builds a session and authenticates eagerly. Throws if the credentials are rejected.
    static func create(
        paymentId: String,
        paymentSecret: String,
        scope: String,
        authApi: AuthAPI,
        client: AsyncHTTPClient,
        onClose: @escaping @Sendable (PaymentSession) async -> Void
    ) async throws -> PaymentSession {
        let session = PaymentSession(paymentId: paymentId, scope: scope, authApi: authApi, onClose: onClose)
        await session.attach(client: client)
        try await session.startEagerAuth(secret: paymentSecret)
        return session
    }

    /// Minimal scope sufficient to read a payment and charge it. Override by passing a different
    /// `scope` to ``GopaySDK/startPaymentSession(paymentId:paymentSecret:scope:)``.
    public static let defaultScope = "payment:charge payment:read"

    // Custom GoPay grant type for the payment-credentials flow (Payments.yaml,
    // components.schemas.Payment-Credentials-Request).
    private static let grantTypePaymentCredentials = "payment_credentials"
}

extension PaymentSession: SessionTokenProviding {
    /// Returns the cached JWT if it's still valid, otherwise `nil`. Lets ``PaymentAPI`` avoid
    /// re-parsing the JWT on every request — expiry is captured once at re-auth time.
    public func currentToken() -> String? {
        guard let token = token else { return nil }
        if tokenExpiresAt != 0, Date().timeIntervalSince1970 >= tokenExpiresAt { return nil }
        return token
    }

    public func invalidateToken() {
        token = nil
        tokenExpiresAt = 0
    }

    public func reauthenticate() async throws -> String {
        if let token = currentToken() { return token }
        if let authTask = authTask { return try await authTask.value }

        let task = Task { try await self.performAuth() }
        authTask = task
        defer { authTask = nil }
        return try await task.value
    }
}
