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
/// in-memory secret is wiped. Construction goes through the eager ``create(paymentId:paymentSecret:scope:authApi:publicApi:client:onClose:)``
/// factory so bad credentials surface at the start of the flow rather than on the first API call.
public actor PaymentSession {

    /// The payment this session is scoped to. Immutable, so it's readable without `await`.
    public nonisolated let paymentId: String

    private let scope: String
    private let authApi: AuthAPI
    /// Shareable-key endpoints; ``charge(_:)`` completes the browser data through it.
    private let publicApi: PublicAPI
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
        publicApi: PublicAPI,
        onClose: @escaping @Sendable (PaymentSession) async -> Void
    ) {
        self.paymentId = paymentId
        self.scope = scope
        self.authApi = authApi
        self.publicApi = publicApi
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

    /// `POST /payments/{payment_id}/charge`.
    ///
    /// The gateway rejects a charge whose `browser_data` lacks `ip`, and the device cannot know
    /// its own public address, so the request's ``BrowserData`` first goes through
    /// ``completeBrowserData(_:)``. Every charge on this session ends here, the wrappers included,
    /// so a caller who builds the request by hand gets the same treatment. When the gateway cannot
    /// be asked for the data, the charge is not sent and the failure surfaces as a charge error
    /// with the underlying one as its cause.
    public func charge(_ request: ChargePaymentRequest) async throws -> ChargePaymentResponse {
        // Checked before the browser data step, which runs under the shareable key rather than
        // the session's token: a closed session would otherwise still ask the gateway once, and
        // without a shareable key report that key as missing instead of the closure.
        guard paymentSecret != nil else { throw closedError() }
        let instrument = request.paymentInstrument
        let completed = ChargePaymentRequest(
            paymentInstrument: PaymentChargeInstrument(
                input: instrument.input,
                browserData: try await completeBrowserData(instrument.browserData),
                challengePreference: instrument.challengePreference,
                paymentInstrument: instrument.paymentInstrument
            ),
            returnUrl: request.returnUrl
        )
        return try await api.charge(paymentId: paymentId, request: completed)
    }

    /// Fills in the ``BrowserData`` fields only the gateway can supply: `ip`, and `accept_header`
    /// from the same request, which is what the issuer expects. Fetches them from
    /// `GET /cards/browser-data` with the SDK's shareable key and returns a copy with every `nil`
    /// among the two set; `javascript_enabled` becomes `true` when `nil`, because the SDK's
    /// challenge WebView runs JavaScript.
    ///
    /// The request goes out with `User-Agent` set to ``BrowserData/userAgent``, so the gateway
    /// sees the challenge WebView's User-Agent rather than the SDK's HTTP client; `user_agent`
    /// itself is never taken from the answer. A `browserData` built without one gets the
    /// challenge WebView's User-Agent before the fetch, the value ``BrowserData/deviceDefault()``
    /// reads, and a warning is logged: the SDK's own HTTP User-Agent in `user_agent` would fail
    /// the issuer's comparison against the challenge. A
    /// value the caller set is never replaced, and when `browserData` already carries `ip` and
    /// `acceptHeader` the gateway is not asked at all.
    ///
    /// ``charge(_:)`` calls this itself; call it directly when you want to see or log the values
    /// before they go out, and pass the result to the charge unchanged.
    ///
    /// - Throws: ``GopaySDKError`` when the fetch fails, with the underlying error's code
    ///   (``GopaySDKError/Code/networkClientError`` for an HTTP 4xx,
    ///   ``GopaySDKError/Code/networkServerError`` for a 5xx,
    ///   ``GopaySDKError/Code/networkIOError`` for a transport failure,
    ///   ``GopaySDKError/Code/authShareableKeyMissing`` when the config has no shareable key,
    ///   or any other code the fetch produced) and the original error as `underlying`. A
    ///   transport failure is mapped to `networkIOError` in this step only; the charge request
    ///   itself still surfaces one as the bare `URLError`, as it always has.
    public func completeBrowserData(_ browserData: BrowserData) async throws -> BrowserData {
        var data = browserData
        if data.userAgent == nil {
            // Filled in before the fetch is decided, whether or not one runs: sent as the
            // fetch's User-Agent and kept in user_agent, so the gateway's echo is not relied on
            // for the value the issuer compares with the challenge WebView. Android does the same.
            data = data.withUserAgent(await GopayUserAgent.resolve())
            GopaySDK.shared.logWarning(
                "browser_data has no user_agent, filling in the challenge WebView's User-Agent"
            )
        }
        if data.hasGatewayFields {
            return data.filled(from: nil)
        }
        return data.filled(from: try await fetchBrowserData(userAgent: data.userAgent))
    }

    private func fetchBrowserData(userAgent: String?) async throws -> BrowserDataDetected {
        do {
            return try await publicApi.getBrowserData(userAgent: userAgent)
        } catch let error as GopaySDKError {
            // Charging without the address would fail on the gateway anyway, and reporting that as
            // the charge's own 400 would hide where it went wrong.
            throw GopaySDKError(
                error.code,
                message: "Failed to charge payment: browser data could not be fetched (\(error.message))",
                httpStatus: error.httpStatus,
                underlying: error
            )
        } catch {
            throw GopaySDKError(
                .networkIOError,
                message: "Failed to charge payment: browser data could not be fetched (\(error.localizedDescription))",
                underlying: error
            )
        }
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

    private func closedError() -> GopaySDKError {
        GopaySDKError(.authPaymentSessionClosed, message: "PaymentSession for \(paymentId) is closed")
    }

    private func performAuth() async throws -> String {
        guard let secret = paymentSecret else { throw closedError() }
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
        publicApi: PublicAPI,
        client: AsyncHTTPClient,
        onClose: @escaping @Sendable (PaymentSession) async -> Void
    ) async throws -> PaymentSession {
        let session = PaymentSession(
            paymentId: paymentId, scope: scope, authApi: authApi, publicApi: publicApi, onClose: onClose
        )
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
