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
    public static let version = "2.3.0"

    /// The shared instance of the SDK.
    public static let shared = GopaySDK()

    /// Fallback return URL for the 3DS verification.
    ///
    /// ``PaymentSession/handle3dsVerification(redirectURL:returnURL:presenting:)`` watches for the
    /// `returnURL` it is given, the address your backend created the payment with
    /// (`callback.return_url`). Only without a usable one does it wait for this address instead,
    /// and then the payment has to be created with it as `callback.return_url`. The 3DS WebView
    /// intercepts it and never actually loads it.
    public static let chargeReturnURL = "https://gopay.com/sdk/charge-return"

    /// The current configuration for the SDK.
    ///
    /// Written by ``initialize(with:)`` on whatever thread the host calls it from and read by
    /// ``report(_:)`` on whatever executor a failing call ends on, so both go through
    /// ``configLock``.
    public private(set) var config: GopaySDKConfig? {
        get {
            configLock.lock()
            defer { configLock.unlock() }
            return storedConfig
        }
        set {
            configLock.lock()
            defer { configLock.unlock() }
            storedConfig = newValue
        }
    }
    private var storedConfig: GopaySDKConfig?
    private let configLock = NSLock()

    /// Async HTTP client used by the per-payment session API layer.
    private var asyncClient: AsyncHTTPClient?
    /// Unauthenticated token endpoint used to acquire payment-scoped JWTs.
    private var authAPI: AuthAPI?
    /// Shareable-key endpoints: the public key, and the browser data every charge completes itself with.
    private var publicAPI: PublicAPI?
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

    /// What the SDK can tell a live ``GopayCardForm``, and which form it is.
    struct CardFormHandlers {
        /// The form that registered, held weakly: the one object the form keeps for its whole
        /// life, so a second form under the same ID, as a navigation transition or a `key()`
        /// churn produces, does not let the first form's departure drop the second form's
        /// handlers and card. The Android `CardFormStore` keeps the same owner token.
        weak var owner: AnyObject?
        /// Wipes the fields the form still shows. Clearing ``GopaySDK/internalCardFormData``
        /// only drops the SDK's own copy; the digits the user typed stay on screen until the form
        /// itself is told to let go of them.
        let reset: () -> Void
        /// Tells a form in the `.onSubmit` validation mode that a submit was attempted, so it
        /// shows its errors. Called by ``GopaySDK/submitCardForm(formId:)`` before the card is
        /// validated, whatever the outcome, which is what the Android form does too.
        let submitAttempted: () -> Void
    }

    /// The handlers of every form on screen, keyed by form ID. Registered while a form is on
    /// screen and guarded by ``cardFormDataLock`` alongside the data they belong to.
    private var cardFormHandlers: [String: CardFormHandlers] = [:]

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
        let publicAPI = PublicAPI(client: client, clientId: config.clientId, shareableKey: config.shareableKey)
        self.publicAPI = publicAPI
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
        let publicAPI = PublicAPI(client: client, clientId: config?.clientId, shareableKey: config?.shareableKey)
        self.publicAPI = publicAPI
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
    ///     (`payment:charge payment:read`), which are the only two the gateway grants for payment
    ///     credentials, so there is no wider one. A scope it does not accept throws
    ///     ``GopaySDKError/Code/authPaymentCredentialsInvalid``.
    /// - Throws: ``GopaySDKError`` with ``GopaySDKError/Code/sdkNotInitialized`` before
    ///   ``initialize(with:)``, ``GopaySDKError/Code/validationInvalidInput`` for an empty
    ///   `paymentId` or `paymentSecret`, ``GopaySDKError/Code/authPaymentCredentialsInvalid``
    ///   when the gateway turns the pair down, ``GopaySDKError/Code/authPaymentSessionAlreadyExists``
    ///   for a payment that already has a session, or the token request's own error.
    public func startPaymentSession(
        paymentId: String,
        paymentSecret: String,
        scope: String = PaymentSession.defaultScope
    ) async throws -> PaymentSession {
        try await reported {
            try await openPaymentSession(paymentId: paymentId, paymentSecret: paymentSecret, scope: scope)
        }
    }

    private func openPaymentSession(
        paymentId: String,
        paymentSecret: String,
        scope: String
    ) async throws -> PaymentSession {
        // Checked first, as the Android `getInstance()` is: without a config there is no gateway
        // to talk to, whatever the credentials look like.
        guard config != nil, let authAPI = authAPI, let publicAPI = publicAPI, let client = asyncClient else {
            throw notInitializedError()
        }
        // Blank, not only empty, as the Android `isBlank` check: a value of white space would
        // otherwise go to the gateway and come back as AUTH_010, a wrong-credentials answer for
        // what is a missing value.
        guard !paymentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GopaySDKError(.validationInvalidInput, message: "paymentId must not be empty")
        }
        guard !paymentSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GopaySDKError(.validationInvalidInput, message: "paymentSecret must not be empty")
        }

        let registry = sessionRegistry
        let session = try await PaymentSession.create(
            paymentId: paymentId,
            paymentSecret: paymentSecret,
            scope: scope,
            authApi: authAPI,
            publicApi: publicAPI,
            client: client,
            callbacks: SessionCallbacks(
                onClose: { session in await registry.remove(session) },
                // The session outlives nothing of the SDK that made it: `shared` lives for the
                // process, and a test instance that is gone has no callback left to call.
                report: { [weak self] error in self?.report(error) }
            )
        )
        do {
            try await registry.register(session)
        } catch {
            // Lost a race for this paymentId — wipe the just-created session and surface the error.
            await session.close()
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

    /// Logged when the public-key response gives no usable clock. Word for word the Android
    /// `CardEncryption.MISSING_DATE_WARNING`.
    static let missingDateWarning =
        "GET /cards/public-key came back without a usable Date header, using the device clock for the JWE iat"

    /// One `GET /cards/public-key`, using the `shareable_key` basic-auth scheme: the merchant's
    /// encryption key and the gateway's clock from the same response. Never cached; the key is
    /// fetched only when a card is being encrypted.
    private func fetchPublicKey() async throws -> ServedPublicKey {
        guard let publicAPI = publicAPI else { throw notInitializedError() }
        return try await publicAPI.getPublicKey()
    }

    /// Encrypts card data into a JWE for server-side tokenization.
    ///
    /// The mobile SDK never calls `POST /cards/tokens` itself (that endpoint requires merchant
    /// credentials). Instead, the host app forwards the returned JWE to its backend, which submits
    /// it on the device's behalf. Card data is never persisted.
    ///
    /// Every call fetches the public key from `GET /cards/public-key` afresh, and the payload's
    /// `iat` / `exp` follow the gateway's clock from that response's `Date` header rather than the
    /// device's, so a device with a wrong clock still produces a JWE the gateway accepts. When the
    /// header is missing or unreadable the device clock is used instead, with a warning in the
    /// debug log while `GopaySDKConfig.enableDebugLogging` is on.
    ///
    /// A task cancelled while the key is on its way gets `CancellationError`, which is not reported
    /// through `errorCallback`, and no JWE is built.
    ///
    /// - Returns: A JWE compact serialization (RFC 7516) ready to send to the merchant backend.
    /// - Throws: ``GopaySDKError`` with ``GopaySDKError/Code/sdkNotInitialized`` before
    ///   ``initialize(with:)``, ``GopaySDKError/Code/validationInvalidInput`` when `cardData`
    ///   fails validation, the public key fetch's own code when that fails, or
    ///   ``GopaySDKError/Code/unexpected`` when the encryption itself fails, with the step that
    ///   failed in the message and the system's error as `underlying`.
    public func encryptCardData(_ cardData: GopayCardData) async throws -> String {
        try await reported { try await encrypt(cardData) }
    }

    /// ``encryptCardData(_:)`` without the reporting, the step ``submitCardForm(formId:)`` ends
    /// with.
    private func encrypt(_ cardData: GopayCardData) async throws -> String {
        guard config != nil else { throw notInitializedError() }
        try validateCardData(cardData)
        let served = try await fetchPublicKey()
        // URLSession's completion API does not notice the task being cancelled, so the fetch
        // finishes anyway. Stopping here keeps a cancelled submitCardForm from wiping the form.
        try Task.checkCancellation()
        guard let clientId = config?.clientId, !clientId.isEmpty else {
            throw GopaySDKError(.authShareableKeyMissing, message: "clientId must be set on GopaySDKConfig to encrypt card data")
        }
        let issuedAt: Date
        if let serverTime = served.serverTime {
            issuedAt = serverTime
        } else {
            issuedAt = Date()
            logWarning(Self.missingDateWarning)
        }
        return try JweUtils.createJWE(cardData: cardData, clientId: clientId, jwk: served.jwk, issuedAt: issuedAt).get()
    }

    /// Encrypts the card data currently held by a ``GopayCardForm`` into a JWE for server-side
    /// tokenization. The sensitive PAN/CVV never leave the SDK — only the JWE is returned.
    ///
    /// On success the form returns to its pristine state: the SDK's copy of the card is dropped
    /// **and the visible fields are emptied**, so the user sees an empty card form and your own UI
    /// should move on rather than wait for further input. A failed encryption leaves everything as
    /// the user typed it, since nothing has been authorized yet.
    ///
    /// A second call for the same form therefore fails with `GopaySDKErrors.noCardFormData`
    /// until a new card is typed: an emptied form, whether it has re-synced its empty fields or
    /// not, is a form without a card, as on Android. A card that is typed but invalid is
    /// `GopaySDKErrors.invalidCardFormData`.
    ///
    /// Like ``encryptCardData(_:)``, every call fetches the public key afresh and dates the
    /// payload by the gateway's clock. A task cancelled while the key is on its way gets
    /// `CancellationError`, not reported through `errorCallback`, and the card stays in the form.
    ///
    /// Forward the returned JWE promptly and use it for a single charge: the gateway accepts each
    /// JWE only once and its payload expires 10 minutes after creation, so a retry needs the user
    /// to confirm the card again.
    ///
    /// - Parameter formId: The form to read. When `nil`, uses the most recently active form.
    /// - Throws: ``GopaySDKError`` with ``GopaySDKError/Code/sdkNotInitialized`` before
    ///   ``initialize(with:)``, ``GopaySDKError/Code/validationInvalidInput`` when no card is
    ///   held or the held one is invalid, and otherwise what ``encryptCardData(_:)`` throws.
    public func submitCardForm(formId: String? = nil) async throws -> String {
        try await reported { try await submitStoredCard(formId: formId) }
    }

    private func submitStoredCard(formId: String?) async throws -> String {
        guard config != nil else { throw notInitializedError() }
        let (resolvedId, stored) = storedCardForm(formId: formId)
        // The submit is what the `.onSubmit` validation mode waits for, so the form is told
        // first, before the card is judged: an empty or invalid card then shows its errors, as
        // the Android form shows them on `submitCardForm`.
        if let id = resolvedId {
            notifyCardFormSubmitAttempted(formId: id)
        }
        // A form whose fields are all empty holds no card, the same answer as no form at all:
        // hosts key their "enter the card again" path on this message, and the Android SDK
        // answers an empty form with it too.
        guard let id = resolvedId, let data = stored, !data.isEmpty else {
            throw GopaySDKError(.validationInvalidInput, message: GopaySDKErrors.noCardFormData)
        }
        guard data.isValid else {
            throw GopaySDKError(.validationInvalidInput, message: GopaySDKErrors.invalidCardFormData)
        }
        let cardData = GopayCardData(
            cardPan: data.cardNumber,
            expMonth: data.expirationMonth,
            expYear: data.expirationYear,
            cvv: data.cvv
        )
        let jwe = try await encrypt(cardData)
        // Only clear after encryption succeeded — on failure (e.g. key fetch offline) the user
        // shouldn't have to retype the card; authorization hasn't happened yet. Clearing also
        // empties the fields the form still shows, so the card does not outlive the JWE made
        // from it (PCI DSS 4.0.1, req. 3.3.1). Mirrors the Android SDK, which resets the form on
        // a successful encryption and deliberately not on a failed one.
        clearCardFormData(formId: id)
        return jwe
    }

    /// The form a submit reads and the card it holds, looked up under ``cardFormDataLock``.
    /// Kept synchronous so the lock is never held across a suspension point.
    private func storedCardForm(formId: String?) -> (String?, GopayCardFormData?) {
        cardFormDataLock.lock()
        defer { cardFormDataLock.unlock() }
        let resolvedId = formId ?? mostRecentFormId ?? internalCardFormData.keys.first
        return (resolvedId, resolvedId.flatMap { internalCardFormData[$0] })
    }

    /// Registers the wipe a live ``GopayCardForm`` performs on its own fields, and what it does
    /// when a submit is attempted, on behalf of `owner`, the object the form keeps for its whole
    /// life. A later registration under the same form ID replaces an earlier one.
    internal func registerCardFormReset(
        _ reset: @escaping () -> Void,
        submitAttempted: @escaping () -> Void = {
            // A form without .onSubmit validation has no errors to reveal on a submit.
        },
        formId: String,
        owner: AnyObject
    ) {
        cardFormDataLock.lock()
        defer { cardFormDataLock.unlock() }
        cardFormHandlers[formId] = CardFormHandlers(owner: owner, reset: reset, submitAttempted: submitAttempted)
    }

    /// Runs the submit-attempted handler of a form, on the main thread, where it writes SwiftUI
    /// state. The handler is looked up there, not before the hop: a form that leaves the screen
    /// in between is not told, so its `attempted` binding is not switched on behind its back.
    /// Nothing happens for a form that is not on screen.
    internal func notifyCardFormSubmitAttempted(formId: String) {
        runOnMain { [self] in
            cardFormDataLock.lock()
            let attempted = cardFormHandlers[formId]?.submitAttempted
            cardFormDataLock.unlock()
            attempted?()
        }
    }

    /// Drops the handlers and the card of a form that is leaving the screen, and runs its wipe,
    /// when the form is still the one registered under its ID. A form that another one under the
    /// same ID has already replaced takes nothing with it: the second form's handlers and card
    /// stay, and the first one empties its own fields itself.
    ///
    /// The wipe runs because the form's `@State` outlives the view whenever the hierarchy is only
    /// detached rather than destroyed, an inactive tab being the common case: dropping the
    /// handler without firing it would leave the PAN and the CVV sitting in that state with
    /// nothing left able to reach them, ready for the next `onAppear` to sync them straight back
    /// into the SDK.
    internal func unregisterCardFormReset(formId: String, owner: AnyObject) {
        cardFormDataLock.lock()
        guard let handlers = cardFormHandlers[formId], handlers.owner === owner else {
            cardFormDataLock.unlock()
            return
        }
        cardFormHandlers.removeValue(forKey: formId)
        internalCardFormData.removeValue(forKey: formId)
        if mostRecentFormId == formId {
            mostRecentFormId = nil
        }
        cardFormDataLock.unlock()
        runOnMain { handlers.reset() }
    }

    /// Runs `work` on the main thread, synchronously when already there.
    ///
    /// The wipes write SwiftUI state. ``clearCardFormData(formId:)`` is public and documented as
    /// callable from anywhere, and ``submitCardForm(formId:)`` resumes on whatever executor the
    /// encryption left it on.
    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Removes card data held for a ``GopayCardForm`` from memory.
    ///
    /// ``submitCardForm(formId:)`` calls this automatically after returning a JWE. A
    /// ``GopayCardForm`` that leaves the screen drops its card without it, through its own
    /// unregistration, so this call is the host's: make it when the user abandons checkout while
    /// the form stays on screen, so the PAN/CVV don't linger in memory longer than needed
    /// (PCI DSS 4.0.1, req. 3.3.1).
    ///
    /// This empties the fields of every affected form that is currently on screen, not just the
    /// SDK's copy of them — otherwise clearing on the host's behalf would leave the card the user
    /// can still see, and the form's next appearance would sync it straight back in.
    ///
    /// - Parameter formId: The form to clear. When `nil`, clears every stored form.
    public func clearCardFormData(formId: String? = nil) {
        cardFormDataLock.lock()
        let resets: [() -> Void]
        if let id = formId {
            internalCardFormData.removeValue(forKey: id)
            if mostRecentFormId == id {
                mostRecentFormId = nil
            }
            resets = cardFormHandlers[id].map { [$0.reset] } ?? []
        } else {
            internalCardFormData.removeAll()
            mostRecentFormId = nil
            resets = cardFormHandlers.values.map(\.reset)
        }
        cardFormDataLock.unlock()
        // Run outside the lock: a wipe re-enters through the form's own bookkeeping.
        runOnMain { resets.forEach { $0() } }
    }

    /// `CONFIG_001`: thrown by every entry point that needs the gateway while ``config`` is `nil`.
    /// `shared` is built with API objects over the sandbox so the internals never see a `nil`,
    /// which is why the config itself, not those objects, is the test.
    private func notInitializedError() -> GopaySDKError {
        GopaySDKError(
            .sdkNotInitialized,
            message: "GopaySDK has not been initialized. Call initialize(with:) first."
        )
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

    /// Whether the platform wallet can be used on this device, under the name both SDKs share: on
    /// iOS the same answer as ``canUseApplePay()``, which it returns, and on Android
    /// `isWalletAvailable(activity, info)`, whose answer has to be asked of Play services, which
    /// is why the shared name is `async` on both. A payment's own card networks are not checked
    /// here; ``PaymentSession/chargeWithWallet(browserData:challengePreference:)`` throws
    /// ``GopaySDKError/Code/paymentMethodUnavailable`` when the payment allows none the sheet can
    /// offer.
    public static func isWalletAvailable() async -> Bool {
        canUseApplePay()
    }

    // MARK: - Internals

    /// Internal method to update card form data (called automatically by ``GopayCardForm``).
    internal func updateCardFormData(_ data: GopayCardFormData, formId: String) {
        cardFormDataLock.lock()
        defer { cardFormDataLock.unlock() }
        self.internalCardFormData[formId] = data
        self.mostRecentFormId = formId
    }

    /// Runs one public call and reports what it throws, once, before rethrowing it. The public
    /// entry points of this class are one `reported` block each around an unreported
    /// implementation, as the ``PaymentSession`` calls are, so an error crosses exactly one block
    /// on its way out.
    private func reported<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            // As in PaymentSession: a request in flight does not notice the task being cancelled,
            // so a task cancelled meanwhile ends with the cancellation and reports nothing.
            try Task.checkCancellation()
            report(error)
            throw error
        }
    }

    /// The `errorCallback` rule, in one place for the SDK and every session it made.
    ///
    /// Every ``GopaySDKError`` a public call throws reaches ``GopaySDKConfig/errorCallback``
    /// once, except ``GopaySDKError/Code/paymentTimeout`` and ``GopaySDKError/Code/paymentCancelled``,
    /// which are outcomes of a payment window rather than failures. Nothing else reaches it: not
    /// `CancellationError`, which is the host's own decision, and no error of another type. The
    /// Android SDK applies the same rule. The debug log, when on, gets the same errors, as their
    /// code and message; the charge a `PAYMENT_006` carries is not printed.
    func report(_ error: Error) {
        guard let sdkError = error as? GopaySDKError else { return }
        switch sdkError.code {
        case .paymentTimeout, .paymentCancelled:
            return
        default:
            break
        }
        // Read once: a re-initialization halfway through must not split the callback from its
        // own logging flag.
        guard let config = config else { return }
        config.errorCallback?(sdkError)
        if config.enableDebugLogging {
            print("[GopaySDK] Error: \(sdkError.errorDescription ?? sdkError.message)")
        }
    }

    /// Logs something the integrator should know about that is not an error, such as a response
    /// field the decoder had to substitute, a hand-off no app answered or a failure the SDK
    /// degraded to a cancellation. Printed with the same gate as ``report(_:)``: only while
    /// `GopaySDKConfig.enableDebugLogging` is on, and never through `errorCallback`.
    func logWarning(_ message: String) {
        if config?.enableDebugLogging == true {
            warnSink(message)
        }
    }

    /// Where ``logWarning(_:)`` writes. Replaced in tests to collect the warnings instead of
    /// printing them, like the Android `SdkLog.warnSink`.
    var warnSink: (String) -> Void = { message in
        print("[GopaySDK] Warning: \(message)")
    }
}
