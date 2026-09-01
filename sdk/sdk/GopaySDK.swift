import Foundation
import PassKit

/// Main entry point for the GoPay SDK.
///
/// Usage:
/// 1. `GopaySDK.shared.initialize(with: GopaySDKConfig(environment:, clientId:, shareableKey:))`
///    once on app start.
/// 2. The merchant backend creates a payment and returns `payment_id` + `payment_secret` to the
///    device.
/// 3. `try await GopaySDK.shared.startPaymentSession(paymentId:, paymentSecret:)` — returns a
///    ``PaymentSession`` scoped to that single payment.
/// 4. All charge / status / Apple Pay / 3DS operations run through `session.*`. Multiple sessions
///    can run concurrently — they're keyed by `payment_id` and never share credentials.
/// 5. `await session.close()` when done; the `payment_secret` and JWT are wiped from memory.
///
/// Card collection: ``encryptCardData(_:)`` (or ``submitCardForm(formId:)`` with a
/// `GopayCardForm`) returns a JWE that the host app forwards to its backend; the merchant backend
/// calls `POST /cards/tokens`. The mobile SDK never touches that endpoint.
public class GopaySDK {

    /// The current version of the SDK.
    ///
    /// A compiled-in constant rather than an Info.plist lookup: under Swift Package Manager the
    /// SDK links statically into the host app, so `Bundle(for:)` resolves to the *app* bundle and
    /// would report the integrating app's `MARKETING_VERSION` instead of the SDK's.
    ///
    /// - Note: Rewritten automatically on release by `scripts/set-version.sh`. Don't edit by hand.
    public static let version = "1.5.0"

    /// The shared instance of the SDK.
    public static let shared = GopaySDK()

    /// Return URL the SDK uses for charge verification flows. The 3DS WebView intercepts it and
    /// never actually loads it; ``PaymentSession/handle3dsVerification(redirectURL:presenting:)``
    /// uses it internally to detect completion. (It is not sent on the charge request — the
    /// deployed gateway rejects a request-level `return_url`.)
    public static let chargeReturnURL = "https://gopay.com/sdk/charge-return"

    /// The current configuration for the SDK.
    public private(set) var config: GopaySDKConfig?

    /// Async HTTP client used by the per-payment session API layer.
    private var asyncClient: AsyncHTTPClient?
    /// Unauthenticated token endpoint used to acquire payment-scoped JWTs.
    private var authAPI: AuthAPI?
    /// In-memory cache of the merchant's encryption JWK.
    private var publicKeyCache: PublicKeyCache?
    /// Registry of live payment sessions keyed by `payment_id`. Supports concurrent payments.
    private let sessionRegistry = SessionRegistry()

    /// Internal storage for card form data keyed by form ID (never exposed to the user).
    /// Entries are removed after a successful ``submitCardForm(formId:)``, when the form
    /// disappears, or via ``clearCardFormData(formId:)`` — SAD must not outlive its use
    /// (PCI DSS 4.0.1, req. 3.3.1). `private(set)` so tests can verify the cleanup.
    internal private(set) var internalCardFormData: [String: GopayCardFormData] = [:]
    /// Tracks the most recently active form ID.
    internal private(set) var mostRecentFormId: String?
    /// Guards the two properties above: keystrokes write from the main thread while
    /// ``submitCardForm(formId:)`` reads and clears from whatever executor resumes it.
    private let cardFormDataLock = NSLock()

    /// Initializes the SDK with the given configuration. Call once before any other operation.
    /// - Parameter config: The configuration to use.
    public func initialize(with config: GopaySDKConfig) {
        self.config = config
        GopayLocales.registerAll(config.customLocales)
        GopayLocales.setDefaultLocale(config.locale)
        // Said once here, unconditionally, because the first symptom otherwise is a CONFIG_006 on
        // an unrelated-looking call. Only `.development(baseURL:)` can be empty — `.sandbox` and
        // `.production` carry their own hosts.
        if config.environment.baseURL.isEmpty {
            print("[GopaySDK] The selected environment has no base URL, so every request will fail with CONFIG_006. Pass an absolute https:// URL to .development(baseURL:).")
        }
        let client = DefaultNetworkClient(baseURL: config.environment.baseURL)
        self.asyncClient = client
        self.authAPI = AuthAPI(client: client)
        self.publicKeyCache = PublicKeyCache(
            publicAPI: PublicAPI(client: client, clientId: config.clientId, shareableKey: config.shareableKey)
        )
        // Resolve the real WebView User-Agent now, off the critical path, so the first charge's
        // browser_data doesn't pay the WKWebView construction + JS round-trip latency.
        Task { @MainActor in GopayUserAgent.prewarm() }
    }

    /// Resolves the ``GopayLocaleStrings`` the payment card form uses for its labels.
    ///
    /// Resolution order: `preferred` (if given and known) -> the SDK-wide `GopaySDKConfig.locale`
    /// -> the device language -> Czech. Handy for reading the localized error / pay strings from
    /// host code (e.g. to display inline validation messages).
    public func currentLocaleStrings(preferred: String? = nil) -> GopayLocaleStrings {
        GopayLocales.resolve(preferred)
    }

    /// Internal/test initializer for dependency injection.
    internal init(config: GopaySDKConfig? = nil, networkClient: AsyncHTTPClient? = nil) {
        self.config = config
        let environment = config?.environment ?? GopayEnvironment.sandbox
        let client = networkClient ?? DefaultNetworkClient(baseURL: environment.baseURL)
        self.asyncClient = client
        self.authAPI = AuthAPI(client: client)
        self.publicKeyCache = PublicKeyCache(
            publicAPI: PublicAPI(client: client, clientId: config?.clientId, shareableKey: config?.shareableKey)
        )
    }

    // MARK: - Payment sessions

    /// Starts a payment-scoped session.
    ///
    /// Performs the `POST /oauth2/token` call with `grant_type=payment_credentials` and basic auth
    /// `paymentId:paymentSecret` eagerly, so bad credentials surface at the start of the flow
    /// rather than on the first API call. The resulting JWT is held in memory only — neither the
    /// secret nor the token is persisted.
    ///
    /// Each `paymentId` may have at most one live session at a time; ``PaymentSession/close()`` it
    /// before starting another for the same payment, or reuse an existing one via
    /// ``getPaymentSession(_:)``.
    ///
    /// - Parameters:
    ///   - paymentId: The payment identifier issued by the merchant backend.
    ///   - paymentSecret: The matching `payment_secret`.
    ///   - scope: OAuth scopes to request. Defaults to ``PaymentSession/defaultScope``
    ///     (`payment:charge payment:read`). Override only when a wider scope is needed.
    public func startPaymentSession(
        paymentId: String,
        paymentSecret: String,
        scope: String = PaymentSession.defaultScope
    ) async throws -> PaymentSession {
        guard !paymentId.isEmpty else {
            throw GopaySDKError(.validationInvalidInput, message: "paymentId must not be empty")
        }
        guard !paymentSecret.isEmpty else {
            throw GopaySDKError(.validationInvalidInput, message: "paymentSecret must not be empty")
        }
        guard let authAPI = authAPI, let client = asyncClient else {
            throw GopaySDKError(
                .sdkNotInitialized,
                message: "GopaySDK has not been initialized. Call initialize(with:) first."
            )
        }

        let registry = sessionRegistry
        let session = try await PaymentSession.create(
            paymentId: paymentId,
            paymentSecret: paymentSecret,
            scope: scope,
            authApi: authAPI,
            client: client,
            onClose: { session in await registry.remove(session) }
        )
        do {
            try await registry.register(session)
        } catch {
            // Lost a race for this paymentId — wipe the just-created session and surface the error.
            await session.close()
            handleError(error)
            throw error
        }
        return session
    }

    /// Looks up an in-progress ``PaymentSession`` by `payment_id`. Returns `nil` if none is
    /// registered (never started, or already closed).
    public func getPaymentSession(_ paymentId: String) async -> PaymentSession? {
        await sessionRegistry.get(paymentId)
    }

    /// Closes and unregisters every live ``PaymentSession``, wiping in-memory secrets and tokens.
    /// Intended for global teardown (e.g. the user signs out of the host app).
    public func closeAllPaymentSessions() async {
        for session in await sessionRegistry.all() {
            await session.close()
        }
    }

    // MARK: - Card encryption

    /// Fetches the merchant's encryption JWK from `GET /cards/public-key` using the `shareable_key`
    /// basic-auth scheme. Requires `clientId` and `shareableKey` on ``GopaySDKConfig``. The key is
    /// cached in memory only.
    /// - Parameter forceRefresh: Bypass the in-memory cache and fetch fresh.
    public func getPublicEncryptionKey(forceRefresh: Bool = false) async throws -> GopayJWK {
        guard let publicKeyCache = publicKeyCache else {
            throw GopaySDKError(
                .sdkNotInitialized,
                message: "GopaySDK has not been initialized. Call initialize(with:) first."
            )
        }
        do {
            return try await publicKeyCache.get(forceRefresh: forceRefresh)
        } catch {
            handleError(error)
            throw error
        }
    }

    /// Encrypts card data into a JWE for server-side tokenization.
    ///
    /// The mobile SDK never calls `POST /cards/tokens` itself (that endpoint requires merchant
    /// credentials). Instead, the host app forwards the returned JWE to its backend, which submits
    /// it on the device's behalf. The public key is fetched via ``getPublicEncryptionKey(forceRefresh:)``
    /// and cached in memory; card data is never persisted.
    ///
    /// - Returns: A JWE compact serialization (RFC 7516) ready to send to the merchant backend.
    /// - Throws: ``GopaySDKError`` if `cardData` fails validation, the public key fetch fails, or
    ///   encryption fails.
    public func encryptCardData(_ cardData: GopayCardData) async throws -> String {
        try validateCardData(cardData)
        let jwk = try await getPublicEncryptionKey()
        guard let clientId = config?.clientId, !clientId.isEmpty else {
            let error = GopaySDKError(.authShareableKeyMissing, message: "clientId must be set on GopaySDKConfig to encrypt card data")
            handleError(error)
            throw error
        }
        switch JweUtils.createJWE(cardData: cardData, clientId: clientId, jwk: jwk) {
        case .success(let jwe):
            return jwe
        case .failure(let error):
            handleError(error)
            throw error
        }
    }

    /// Encrypts the card data currently held by a ``GopayCardForm`` into a JWE for server-side
    /// tokenization. The sensitive PAN/CVV never leave the SDK — only the JWE is returned.
    ///
    /// On success the form's card data is removed from memory, so a second call for the same
    /// form throws ``GopaySDKError`` with `GopaySDKErrors.noCardFormData` until the form
    /// re-syncs (it does so on appear and on any edit). Forward the returned JWE promptly and
    /// use it for a single charge: the gateway accepts each JWE only once and its payload
    /// expires 10 minutes after creation, so a retry needs the user to confirm the card again.
    ///
    /// - Parameter formId: The form to read. When `nil`, uses the most recently active form.
    public func submitCardForm(formId: String? = nil) async throws -> String {
        cardFormDataLock.lock()
        let resolvedId = formId ?? mostRecentFormId ?? internalCardFormData.keys.first
        let stored = resolvedId.flatMap { internalCardFormData[$0] }
        cardFormDataLock.unlock()
        guard let id = resolvedId, let data = stored else {
            let error = GopaySDKError(.validationInvalidInput, message: GopaySDKErrors.noCardFormData)
            handleError(error)
            throw error
        }
        guard data.isValid else {
            let error = GopaySDKError(.validationInvalidInput, message: GopaySDKErrors.invalidCardFormData)
            handleError(error)
            throw error
        }
        let cardData = GopayCardData(
            cardPan: data.cardNumber,
            expMonth: data.expirationMonth,
            expYear: data.expirationYear,
            cvv: data.cvv
        )
        let jwe = try await encryptCardData(cardData)
        // Only clear after encryption succeeded — on failure (e.g. key fetch offline) the user
        // shouldn't have to retype the card; authorization hasn't happened yet.
        clearCardFormData(formId: id)
        return jwe
    }

    /// Removes card data held for a ``GopayCardForm`` from memory.
    ///
    /// ``submitCardForm(formId:)`` calls this automatically after returning a JWE, and
    /// ``GopayCardForm`` calls it when the form disappears. Call it yourself when the user
    /// abandons checkout while the form stays on screen, so the PAN/CVV don't linger in
    /// memory longer than needed (PCI DSS 4.0.1, req. 3.3.1).
    ///
    /// - Parameter formId: The form to clear. When `nil`, clears every stored form.
    public func clearCardFormData(formId: String? = nil) {
        cardFormDataLock.lock()
        defer { cardFormDataLock.unlock() }
        if let id = formId {
            internalCardFormData.removeValue(forKey: id)
            if mostRecentFormId == id {
                mostRecentFormId = nil
            }
        } else {
            internalCardFormData.removeAll()
            mostRecentFormId = nil
        }
    }

    private func validateCardData(_ cardData: GopayCardData) throws {
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw GopaySDKError(.validationInvalidInput, message: message) }
        }
        func matches(_ value: String, _ pattern: String) -> Bool {
            value.range(of: pattern, options: .regularExpression) != nil
        }
        try require(!cardData.cardPan.isEmpty, "Card PAN cannot be empty")
        try require((13...19).contains(cardData.cardPan.count), "Card PAN must be 13-19 digits")
        try require(cardData.cardPan.allSatisfy { $0.isNumber }, "Card PAN must contain only digits")
        try require(matches(cardData.expMonth, "^(0[1-9]|1[0-2])$"), "Expiration month must be 01-12")
        try require(matches(cardData.expYear, "^[0-9]{2,4}$"), "Expiration year must be 2-4 digits")
        try require(matches(cardData.cvv, "^[0-9]{3,4}$"), "CVV must be 3-4 digits")
    }

    // MARK: - Apple Pay availability

    /// Default card networks a caller can use to build an Apple Pay request before a payment-scoped
    /// config is available. The authoritative list for a given payment always comes from the BE
    /// (`/apple-pay/app-info`); this constant only exists as a convenient default before a
    /// payment has been created.
    public static let defaultApplePayNetworks: [PKPaymentNetwork] = {
        var networks: [PKPaymentNetwork] = [.visa, .masterCard, .amex]
        if #available(iOS 12.0, *) {
            networks.append(contentsOf: [.maestro, .electron, .vPay])
        }
        return networks
    }()

    /// Indicates whether this device can present an Apple Pay sheet. Checks device capability only;
    /// does NOT require a card to already be in the Wallet — the sheet will guide the user to add
    /// one if needed. Safe to call synchronously (e.g. from a SwiftUI view body).
    public static func canUseApplePay() -> Bool {
        return PKPaymentAuthorizationController.canMakePayments()
    }

    // MARK: - Internals

    /// Internal method to update card form data (called automatically by ``GopayCardForm``).
    internal func updateCardFormData(_ data: GopayCardFormData, formId: String) {
        cardFormDataLock.lock()
        defer { cardFormDataLock.unlock() }
        self.internalCardFormData[formId] = data
        self.mostRecentFormId = formId
    }

    /// Routes an error through the configured error callback and debug logging.
    func handleError(_ error: Error) {
        config?.errorCallback?(error)
        if config?.enableDebugLogging == true {
            print("[GopaySDK] Error: \(error)")
        }
    }
}
