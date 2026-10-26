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
/// in-memory secret is wiped. Construction goes through the eager ``create(paymentId:paymentSecret:scope:authApi:publicApi:client:callbacks:)``
/// factory so bad credentials surface at the start of the flow rather than on the first API call.
public actor PaymentSession {

    /// The payment this session is scoped to. Immutable, so it's readable without `await`.
    public nonisolated let paymentId: String

    private let scope: String
    private let authApi: AuthAPI
    /// Shareable-key endpoints; ``charge(_:)`` completes the browser data through it.
    private let publicApi: PublicAPI
    private let onClose: @Sendable (PaymentSession) async -> Void
    /// Where every error a public call of this session throws goes, once, with the session's
    /// payment: the owning ``GopaySDK/report(_:paymentId:)``, which applies the `errorCallback` rule.
    private let report: @Sendable (Error, String) -> Void
    /// The operational data of the SDK that made the session.
    nonisolated let telemetry: Telemetry

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

    /// Where a charge without browser data gets the device's. ``BrowserData/deviceDefault()``
    /// unless a test replaces it with ``useDeviceBrowserData(_:)``, so the tests of the charges
    /// do not have to start a WKWebView for the User-Agent.
    private var deviceBrowserData: @Sendable () async -> BrowserData = { await BrowserData.deviceDefault() }

    /// Replaces the device's browser data for the tests.
    func useDeviceBrowserData(_ provider: @escaping @Sendable () async -> BrowserData) {
        deviceBrowserData = provider
    }

    /// The caller's browser data, or the device's when there is none. The one place the
    /// convenience charges, the wallet included, resolve it, so they cannot drift apart.
    func resolveBrowserData(_ browserData: BrowserData?) async -> BrowserData {
        if let browserData = browserData {
            return browserData
        }
        return await deviceBrowserData()
    }

    /// The clock, the sleep and the 3DS step ``awaitChargeState(_:)`` runs on. The live ones
    /// unless a test replaces them with ``useAwaitChargeHooks(_:)``.
    private(set) var awaitChargeHooks = AwaitChargeHooks.live

    /// Replaces the hooks for the tests, which run the polling on virtual time and stand in for
    /// the verification screen. Takes effect for the next ``awaitChargeState(_:)`` call; one
    /// already running keeps the hooks it started with.
    func useAwaitChargeHooks(_ hooks: AwaitChargeHooks) {
        awaitChargeHooks = hooks
    }

    init(
        paymentId: String,
        scope: String,
        authApi: AuthAPI,
        publicApi: PublicAPI,
        callbacks: SessionCallbacks
    ) {
        self.paymentId = paymentId
        self.scope = scope
        self.authApi = authApi
        self.publicApi = publicApi
        self.onClose = callbacks.onClose
        self.report = callbacks.report
        self.telemetry = callbacks.telemetry
        self.api = nil
    }

    /// A session dropped without ``close()`` still leaves the telemetry's attribution, or every
    /// later event without a payment of its own would go on naming this one. A closed session, or
    /// one whose start failed, has already left it.
    deinit {
        if paymentSecret != nil {
            telemetry.detach(paymentId: paymentId)
        }
    }

    private func attach(client: AsyncHTTPClient) {
        self.api = PaymentAPI(client: client, tokenProvider: self, telemetry: telemetry)
    }

    // MARK: - Error reporting

    /// Runs one public call and reports what it throws, once, before rethrowing it.
    ///
    /// Every public method of the session, the token provider's ``reauthenticate()`` included,
    /// is one `reported` block around an unreported implementation, and the implementations
    /// call each other, never the public methods: a charge that fails while
    /// ``chargeWithWallet(browserData:challengePreference:)`` runs it is reported by that call
    /// alone, a read that fails inside ``awaitChargeState(_:)`` by that one, and a token refresh
    /// the gateway refuses inside any call by that call. The rule itself, which errors are
    /// passed on, is ``GopaySDK/report(_:paymentId:)``'s.
    func reported<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            // URLSession does not notice the task being cancelled, so a request in flight
            // finishes, or fails, on its own. A task cancelled meanwhile ends with the
            // cancellation, not with the request's error, and reports nothing.
            try Task.checkCancellation()
            report(error, paymentId)
            throw error
        }
    }

    // MARK: - Endpoints

    /// `GET /payments/{payment_id}`
    public func getStatus() async throws -> PaymentDetails {
        try await reported { try await api.getPaymentStatus(paymentId: paymentId) }
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
        try await reported { try await sendCharge(request) }
    }

    /// ``charge(_:)`` without the reporting, for the calls that run a charge as one of their
    /// steps.
    func sendCharge(_ request: ChargePaymentRequest) async throws -> ChargePaymentResponse {
        // Checked before the browser data step, which runs under the shareable key rather than
        // the session's token: a closed session would otherwise still ask the gateway once, and
        // without a shareable key report that key as missing instead of the closure.
        guard paymentSecret != nil else { throw closedError() }
        // A task cancelled before the charge even started fetches nothing and sends nothing.
        try Task.checkCancellation()
        let instrument = request.paymentInstrument
        let completed = ChargePaymentRequest(
            paymentInstrument: PaymentChargeInstrument(
                input: instrument.input,
                browserData: try await fillBrowserData(instrument.browserData),
                challengePreference: instrument.challengePreference,
                paymentInstrument: instrument.paymentInstrument
            )
        )
        // The browser data step is an await the cancellation may have passed through: a charge
        // the caller no longer wants must not reach the gateway.
        try Task.checkCancellation()
        // Counted for the card form's unmount, which reports whether it cut a charge short.
        Telemetry.chargesInFlight.start()
        defer { Telemetry.chargesInFlight.finish() }
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
    ///   the transport codes `NETWORK_001`, `NETWORK_004`, `NETWORK_005` or `NETWORK_007` when no
    ///   response came, ``GopaySDKError/Code/authShareableKeyMissing`` when the config has no
    ///   shareable key, or any other code the fetch produced) and the original error as
    ///   `underlying`.
    public func completeBrowserData(_ browserData: BrowserData) async throws -> BrowserData {
        try await reported { try await fillBrowserData(browserData) }
    }

    /// ``completeBrowserData(_:)`` without the reporting, the step every charge runs first.
    private func fillBrowserData(_ browserData: BrowserData) async throws -> BrowserData {
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
            return try await publicApi.getBrowserData(userAgent: userAgent, paymentId: paymentId)
        } catch let error as GopaySDKError {
            // Charging without the address would fail on the gateway anyway, and reporting that as
            // the charge's own 400 would hide where it went wrong.
            throw GopaySDKError(
                error.code,
                message: "Failed to charge payment: browser data could not be fetched (\(error.message))",
                httpStatus: error.httpStatus,
                // The failure itself, e.g. the URLError, not the SDK error already wrapping it.
                underlying: error.underlying ?? error,
                gatewayError: error.gatewayError
            )
        }
    }

    /// `GET /payments/{payment_id}/charge`
    public func getChargeState() async throws -> ChargePaymentResponse {
        try await reported { try await readChargeState() }
    }

    /// ``getChargeState()`` without the reporting, the read ``awaitChargeState(_:)`` repeats.
    func readChargeState() async throws -> ChargePaymentResponse {
        try await api.getChargeState(paymentId: paymentId)
    }

    /// `GET /payments/{payment_id}/qr-payment/info`
    public func getQrPaymentInfo(format: QrCodeFormat? = nil) async throws -> QrPaymentDetails {
        try await reported { try await api.getQrPaymentInfo(paymentId: paymentId, format: format) }
    }

    /// `GET /payments/{payment_id}/apple-pay/app-info` — the BE-configured Apple Pay request for
    /// this payment, used to build the native sheet.
    public func getApplePayInfo() async throws -> GopayApplePayAppInfoResponse {
        try await reported { try await fetchApplePayInfo() }
    }

    /// ``getApplePayInfo()`` without the reporting, the first step of the Apple Pay charge.
    func fetchApplePayInfo() async throws -> GopayApplePayAppInfoResponse {
        try await api.getApplePayAppInfo(paymentId: paymentId)
    }

    // MARK: - Lifecycle

    /// Wipes the in-memory `payment_secret` and JWT and unregisters this session from the SDK
    /// registry. Idempotent — once the secret is nil, ``reauthenticate()`` throws
    /// ``GopaySDKError/Code/authPaymentSessionClosed``.
    public func close() async {
        await close(reportsLeave: true)
    }

    /// ``close()``, and whether the telemetry hears of it as the session's leave. A session that
    /// lost the race for its payment never started as far as the telemetry knows, so its close
    /// only drops it from the attribution.
    func close(reportsLeave: Bool) async {
        guard paymentSecret != nil else { return }
        paymentSecret = nil
        token = nil
        tokenExpiresAt = 0
        authTask?.cancel()
        authTask = nil
        if reportsLeave {
            telemetry.sessionClosed(paymentId: paymentId)
        } else {
            telemetry.detach(paymentId: paymentId)
        }
        await onClose(self)
    }

    // MARK: - Eager auth

    private func startEagerAuth(secret: String) async throws {
        paymentSecret = secret
        do {
            _ = try await authenticate()
        } catch {
            // The session is never handed out, and the SDK has already taken it off the
            // telemetry's attribution: wiping the secret keeps `deinit` from doing that twice.
            paymentSecret = nil
            throw error
        }
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
                scope: scope,
                paymentId: paymentId
            )
        } catch let error as GopaySDKError {
            // Only the gateway turning the pair down means the payment_id / payment_secret pair
            // is wrong. Any other 4xx, a 5xx and a transport failure keep their own codes, so a
            // device that is merely offline is not told to fetch new credentials.
            guard let status = error.httpStatus, Self.credentialsRejectedStatuses.contains(status) else {
                throw error
            }
            throw GopaySDKError(
                .authPaymentCredentialsInvalid,
                message: "payment_credentials rejected: HTTP \(status)" + error.gatewayError.messageSuffix,
                httpStatus: status,
                underlying: error,
                gatewayError: error.gatewayError
            )
        }
        token = response.accessToken
        tokenExpiresAt = JwtUtils.expirationSeconds(jwt: response.accessToken)
        return response.accessToken
    }

    // MARK: - Factory

    /// Builds a session and authenticates eagerly. Throws if the credentials are rejected; that
    /// error is the caller's to report, since ``GopaySDK/startPaymentSession(paymentId:paymentSecret:scope:)``
    /// is the public call it fails.
    ///
    /// - Parameter callbacks: What the session calls back into the SDK that made it.
    static func create(
        paymentId: String,
        paymentSecret: String,
        scope: String,
        authApi: AuthAPI,
        publicApi: PublicAPI,
        client: AsyncHTTPClient,
        callbacks: SessionCallbacks
    ) async throws -> PaymentSession {
        let session = PaymentSession(
            paymentId: paymentId, scope: scope, authApi: authApi, publicApi: publicApi,
            callbacks: callbacks
        )
        await session.attach(client: client)
        try await session.startEagerAuth(secret: paymentSecret)
        return session
    }

    /// The scope to read a payment and charge it, and the widest the gateway grants for payment
    /// credentials: `payment:read` and `payment:charge` are the only two. Pass a narrower one to
    /// ``GopaySDK/startPaymentSession(paymentId:paymentSecret:scope:)`` to only read the payment.
    public static let defaultScope = "payment:charge payment:read"

    // Custom GoPay grant type for the payment-credentials flow (Payments.yaml,
    // components.schemas.Payment-Credentials-Request).
    private static let grantTypePaymentCredentials = "payment_credentials"
    /// The `/oauth2/token` answers that mean the payment_id / payment_secret pair is wrong, and so
    /// ``GopaySDKError/Code/authPaymentCredentialsInvalid``. A `payment_secret` past its seven
    /// days is refused with a 403.
    private static let credentialsRejectedStatuses: Set<Int> = [400, 401, 403]
}

/// What a ``PaymentSession`` calls back into the SDK that made it.
struct SessionCallbacks: Sendable {
    /// Called once the session is closed, so the SDK can drop it from its registry.
    let onClose: @Sendable (PaymentSession) async -> Void
    /// Where the session's public calls report what they throw, with the session's payment.
    let report: @Sendable (Error, String) -> Void
    /// Where the session's operational data goes.
    let telemetry: Telemetry

    init(
        onClose: @escaping @Sendable (PaymentSession) async -> Void,
        report: @escaping @Sendable (Error, String) -> Void = { _, _ in
            // Tests that build a session outside the SDK have no errorCallback to report to.
        },
        telemetry: Telemetry = .disabled
    ) {
        self.onClose = onClose
        self.report = report
        self.telemetry = telemetry
    }
}

/// The token provider ``PaymentAPI`` reads. Public only because an earlier protocol needed it, and
/// listed for removal in 3.0. ``PaymentAPI`` and the eager authentication use the unreported
/// ``authenticate()``, so a refresh that fails inside a call is reported by that call; the public
/// ``reauthenticate()`` is reported like every other public call, for a host that calls it
/// directly.
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
        try await reported { try await authenticate() }
    }

    /// ``reauthenticate()`` without the reporting: the single-flighted token refresh every
    /// request on this session falls back to.
    func authenticate() async throws -> String {
        if let token = currentToken() { return token }
        if let authTask = authTask { return try await authTask.value }

        let task = Task { try await self.performAuth() }
        authTask = task
        defer { authTask = nil }
        return try await task.value
    }
}
