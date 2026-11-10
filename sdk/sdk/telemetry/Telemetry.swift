import Foundation

/// The SDK's operational data: what it did, how long it took and how it ended, sent to GoPay's
/// ingest one event per request. The mobile counterpart of the browser SDK's telemetry, with the
/// same event shapes, the same budgets and the same redaction, so one query reads every producer.
///
/// Always on wherever there is an ingest to send to: sandbox and production. A `.development`
/// gateway has none, and neither does an SDK that was never initialized, so ``disabled`` sends
/// nothing. Nothing here is configurable by the integrator, and the debug flag only adds one log
/// line per event that is sent.
///
/// Fire and forget, and never in the way of a payment. Every emitter is synchronous, takes a lock
/// only for as long as it appends to a queue, and returns; building the event, redacting it and
/// handing it to `URLSession` happen later, in ``TelemetryTransport``. Nothing awaits the upload,
/// nothing retries it, and of the response only the status is read, to count an event that did
/// not arrive (see ``ProcessCounters``); every failure is otherwise dropped silently.
///
/// Mirrors the Android `GwLoggerTelemetry`.
final class Telemetry: @unchecked Sendable {

    /// Per payment session, and split, so a flood of one kind cannot silence another: a slow 3DS
    /// polled for minutes spends the `apiCall` budget, never the `lifecycle` one that holds the
    /// session's leave, nor the `error` one. Past its limit a kind is dropped silently.
    ///
    /// The browser SDK counts per SDK instance, which lives as long as the page. On a phone the
    /// instance lives as long as the app, for days, so the budgets start over with every payment
    /// session instead (see ``sessionStarted(paymentId:)``); otherwise a few payments' polling
    /// would silence the SDK for the rest of the process.
    enum Budget: Hashable, Sendable {
        /// Requests to the gateway.
        case apiCall
        /// Markers bounded by design: init, the session's start and leave, the 3DS leave, the
        /// card form's ready, submit and unmount, the wallet submit.
        case lifecycle
        /// Wallet steps and availability answers, which repeat with the user, and the card form's
        /// summary, one per visit.
        case step
        /// SDK errors.
        case error
        /// The card form's steps: started, completed, the pay button, and the errors of a submit,
        /// which typing must not be able to silence.
        case cardForm
        /// The card form's field errors raised while typing, which repeat with a customer who keeps
        /// getting the card wrong and must not spend the steps that say whether they got there.
        case fieldErrors

        var limit: Int {
            switch self {
            case .apiCall: return 200
            case .lifecycle: return 75
            case .step: return 150
            case .error: return 50
            case .cardForm: return 60
            case .fieldErrors: return 30
            }
        }
    }

    /// The outcome of a wallet step, the browser SDK's `start` / `success` / `failure` / `info`.
    enum StepStatus: String, Sendable {
        case start, success, failure, info
    }

    /// The Apple Pay steps, by the names gw-ui gives them, reported as `APPLE_PAY.<step>`.
    enum WalletStep: String, Sendable {
        /// The sheet was asked for.
        case begin
        /// The sheet handed back a payment token, or one the SDK cannot use.
        case paymentAuthorized
        /// The charge made from the token was sent, and how it ended.
        case checkout
        /// The sheet was told the charge's result. PassKit only; Google Pay has no such step.
        case completePayment
        /// The sheet closed without an authorization.
        case cancel
    }

    /// The card form's steps, by the names the browser SDK gives them, and the budget each spends.
    enum CardFormStep: Sendable {
        case started, completed, submitRequest, interaction
        case fieldErrors(CardFormProgress.Trigger)

        var name: String {
            switch self {
            case .started: return "started"
            case .completed: return "completed"
            case .submitRequest: return "submit-request"
            case .interaction: return "interaction"
            case .fieldErrors: return "field-errors"
            }
        }

        /// The errors of a submit count with the steps: they are the moment the customer tried to
        /// pay, and typing must not be able to silence it. The summary sits with the wallet steps,
        /// one per visit.
        var budget: Budget {
            switch self {
            case .started, .completed, .submitRequest, .fieldErrors(.submit): return .cardForm
            case .fieldErrors: return .fieldErrors
            case .interaction: return .step
            }
        }
    }

    /// One value in a `params` object.
    enum Param: Sendable {
        case string(String)
        case int(Int)
        case bool(Bool)
    }

    /// The `integration` this SDK reports as.
    static let integration = "ios-sdk"

    /// How long one upload may take before it is given up.
    static let requestTimeout: TimeInterval = 10

    /// The schema's cap on `origin`.
    static let maxOriginLength = 2048

    /// The only reason the SDK can give for Apple Pay being unavailable: the device says no.
    static let applePayUnavailable = "unsupported-device"

    /// Charges sent and not yet answered, across the process: what a card form leaving the screen
    /// may have cut short. Any charge counts, not only one made from that form's JWE, since the
    /// SDK cannot tell which card a charge carries. The Android `Telemetry.chargesInFlight`.
    static let chargesInFlight = InFlightCounter()

    /// One per process, the mobile counterpart of the browser's visit: every event this process
    /// sends carries it, across SDK instances and payments.
    static let processTransactionId = newId()

    /// Sends nothing. What an SDK that was never initialized, or a test that does not care about
    /// telemetry, uses.
    static let disabled = Telemetry(endpoint: nil, clientId: nil)

    /// Where the events go, `nil` for ``disabled``.
    let endpoint: URL?
    /// The numbering and the delivery count this instance shares, ``ProcessCounters/shared``
    /// outside tests.
    let counters: ProcessCounters

    private let clientId: String?
    private let origin: String
    /// The SDK's initialization, which the card form's `ready` is timed from.
    private let createdAt = Telemetry.now()
    private let transport: TelemetryTransport?
    private let queue = PendingEvents()

    /// Guards the state below. Never held across a suspension point.
    private let lock = NSLock()
    /// The payments of the sessions started and not yet closed, oldest first. An event that
    /// belongs to no payment of its own, a card form's or a probe's, is attributed to the last
    /// one, as the browser SDK attributes everything to the payment attached to it.
    private var attached: [String] = []
    /// Each card form on screen, from its ready to its unmount, keyed by the form's owner token.
    private var cardForms: [ObjectIdentifier: CardFormVisit] = [:]
    /// The last answer each availability probe reported, so a probe called from a view body does
    /// not report the same answer on every render.
    private var probeAnswers: [String: Bool] = [:]

    /// - Parameters:
    ///   - endpoint: The ingest's `/events` URL; `nil` sends nothing.
    ///   - clientId: The merchant's `client_id`, the attribution key of events with no payment.
    ///   - debugLogging: Logs one line per event sent, without its content.
    ///   - debugSink: Where that line goes; tests collect it instead of printing it.
    ///   - origin: The host app, by its bundle identifier.
    ///   - configuration: The upload session's configuration; tests swap in a stub protocol.
    ///   - counters: The process's numbering and delivery count; tests pass their own.
    ///   - onResponse: Called with the status and body of each upload's response. Tests only.
    init(
        endpoint: URL?,
        clientId: String?,
        debugLogging: Bool = false,
        debugSink: @escaping @Sendable (String) -> Void = { print($0) },
        origin: String = Bundle.main.bundleIdentifier ?? "",
        configuration: URLSessionConfiguration = Telemetry.sessionConfiguration(),
        counters: ProcessCounters = .shared,
        onResponse: (@Sendable (Int?, Data?) -> Void)? = nil
    ) {
        self.endpoint = endpoint
        self.counters = counters
        self.clientId = Self.nonEmpty(clientId)
        self.origin = TelemetryRedaction.capped(origin, at: Self.maxOriginLength)
        self.transport = endpoint.map {
            TelemetryTransport(
                endpoint: $0,
                session: URLSession(configuration: configuration),
                counters: counters,
                debugSink: debugLogging ? debugSink : nil,
                onResponse: onResponse
            )
        }
    }

    /// The telemetry a configuration asks for: its environment's ingest, its `client_id`.
    convenience init(config: GopayConfig) {
        self.init(
            endpoint: config.environment.telemetryURL,
            clientId: config.clientId,
            debugLogging: config.debugLoggingEnabled
        )
    }

    /// Ephemeral, with no cache, no cookies and no waiting for connectivity: an event that cannot
    /// go now is not worth keeping.
    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    // MARK: - Requests

    /// One request the SDK sent to the gateway, as the choke point read it: the browser SDK's
    /// `ApiCallRecord`. The bodies are raw here; the redaction runs on the transport.
    struct ApiCallRecord: Sendable {
        /// A body and the `Content-Type` it was sent or received with.
        struct Body: Sendable {
            let data: Data
            let contentType: String?
        }

        let method: String
        /// The path below the API's base path, query included; reported as a template.
        let path: String
        /// `nil` when no response came.
        let statusCode: Int?
        /// A ``Telemetry/now()`` reading taken when the request went out.
        let startedAt: UInt64
        let requestBody: Body?
        let responseBody: Body?
    }

    /// One request the SDK sent to the gateway, whichever way it ended. The bodies go out
    /// redacted, see ``TelemetryRedaction``.
    func apiCall(_ record: ApiCallRecord, paymentId: String?) {
        post(.apiCall, paymentId: paymentId, duration: Self.ms(since: record.startedAt)) {
            let target = TelemetryRedaction.endpointTemplate(record.path)
            return .apiCall(
                action: TelemetryRedaction.action(ofTemplate: target),
                httpMethod: record.method,
                target: target,
                statusCode: record.statusCode,
                requestBody: TelemetryRedaction.serializeBody(record.requestBody?.data, contentType: record.requestBody?.contentType),
                responseBody: TelemetryRedaction.serializeBody(record.responseBody?.data, contentType: record.responseBody?.contentType)
            )
        }
    }

    // MARK: - Lifecycle

    /// ``GopaySDK/initialize(with:)``.
    func initialized() {
        post(.lifecycle, paymentId: nil, duration: nil) { .navigation(type: "init", target: nil) }
    }

    /// A session for `paymentId` is being started: events without a payment of their own belong
    /// to it from here on, its token exchange included.
    func attach(paymentId: String) {
        lock.lock()
        attached.append(paymentId)
        lock.unlock()
    }

    /// The session for `paymentId` failed to start, lost the race for its payment, or closed.
    func detach(paymentId: String) {
        lock.lock()
        if let index = attached.lastIndex(of: paymentId) {
            attached.remove(at: index)
        }
        lock.unlock()
    }

    /// A payment session started: its credentials were accepted and it was registered. Every
    /// budget starts over with it, this event being the first one it spends.
    func sessionStarted(paymentId: String) {
        post(.lifecycle, paymentId: paymentId, duration: nil, flow: "attach", resetsBudgets: true) {
            .navigation(type: "navigate", target: nil)
        }
    }

    /// A payment session closed. Once per session; ``PaymentSession/close()`` guards that.
    func sessionClosed(paymentId: String) {
        post(.lifecycle, paymentId: paymentId, duration: nil) { .navigation(type: "leave", target: nil) }
        detach(paymentId: paymentId)
    }

    /// The 3DS verification screen is about to load `redirectURL`: the leave that is part of a
    /// payment, with where it went, by origin and path only.
    func verificationOpened(redirectURL: URL, paymentId: String) {
        post(.lifecycle, paymentId: paymentId, duration: nil, flow: "3ds-redirect") {
            .navigation(type: "leave", target: TelemetryRedaction.safeTarget(redirectURL))
        }
    }

    /// The card form the iOS SDK offers encrypts and hands the JWE back; it never charges. That is
    /// the browser SDK's encrypt-only flow.
    static let cardFormFlow = "return-payload"

    /// A ``PaymentCardForm`` appeared, timed from the SDK's initialization. Its first visit starts
    /// here, untouched.
    func cardFormReady(owner: AnyObject) {
        let now = Self.now()
        lock.lock()
        cardForms[ObjectIdentifier(owner)] = CardFormVisit(readyAt: now)
        lock.unlock()
        post(.lifecycle, paymentId: nil, duration: Self.ms(since: createdAt, until: now), flow: Self.cardFormFlow) {
            .jsEvent(functionName: "PAYMENT_CARD.ready", errorCode: nil, params: nil, returnValue: nil)
        }
    }

    /// ``GopaySDK/submitCardForm(formId:)`` made a JWE from the form `owner` registered. Timed
    /// from the form's ready; carries nothing about what was typed. The JWE ends the visit: its
    /// summary goes now, with the card as it was, before the SDK empties the form.
    func cardFormSubmitted(owner: AnyObject?) {
        let now = Self.now()
        var readyAt: UInt64?
        var summary: CardFormProgress.Report?
        if let owner = owner {
            lock.lock()
            if let visit = cardForms[ObjectIdentifier(owner)] {
                readyAt = visit.readyAt
                summary = visit.end(.submit)
            }
            lock.unlock()
        }
        let duration = readyAt.map { Self.ms(since: $0, until: now) }
        post(.lifecycle, paymentId: nil, duration: duration, paymentMethod: "card", flow: Self.cardFormFlow) {
            .interaction(elementId: "card-form")
        }
        if let summary = summary {
            postCardFormStep(.interaction, summary, duration: duration)
        }
    }

    /// A ``PaymentCardForm`` disappeared, timed from its ready, with whether a charge was still
    /// running in the process when it went (see ``chargesInFlight``), and then the summary of the
    /// visit still open, if any: a form whose last visit ended with a JWE has none.
    func cardFormUnmounted(owner: AnyObject) {
        let now = Self.now()
        lock.lock()
        let visit = cardForms.removeValue(forKey: ObjectIdentifier(owner))
        let summary = visit?.end(nil)
        lock.unlock()
        let duration = visit.map { Self.ms(since: $0.readyAt, until: now) }
        let chargeInFlight = Self.chargesInFlight.isRunning
        post(.lifecycle, paymentId: nil, duration: duration, flow: Self.cardFormFlow) {
            .jsEvent(
                functionName: "PAYMENT_CARD.unmount",
                errorCode: nil,
                params: Self.describeParams(["charge_in_flight": .bool(chargeInFlight)]),
                returnValue: chargeInFlight ? "charge-aborted" : "idle"
            )
        }
        if let summary = summary {
            postCardFormStep(.interaction, summary, duration: duration)
        }
    }

    /// The user authorized in the Apple Pay sheet. No duration, as in the browser SDK.
    func walletSubmitted(paymentId: String) {
        post(.lifecycle, paymentId: paymentId, duration: nil, paymentMethod: "applepay") {
            .interaction(elementId: "applepay-button")
        }
    }

    // MARK: - Card form steps

    /// The customer changed a field of the form `owner`; `states` are the three fields after it.
    /// Typing into a form whose visit ended with a JWE starts a new visit.
    func cardFormInput(owner: AnyObject, states: CardFormProgress.States) {
        let now = Self.now()
        lock.lock()
        var steps: [(CardFormStep, CardFormProgress.Report)] = []
        var duration: Int?
        if let visit = openVisit(of: owner, restarting: true) {
            let since = Self.ms(since: visit.readyAt, until: now)
            duration = since
            // Typing after a failed submit is a new attempt; the visit no longer ends with it.
            visit.ended = .unmount
            if let report = visit.progress.progress(states, sinceReady: since) {
                steps.append((.started, report))
            }
            if let report = visit.progress.validity(states.isValid, sinceReady: since) {
                steps.append((.completed, report))
            }
            if let report = visit.progress.fieldErrors(states.errors(judged: visit.judged), trigger: .input) {
                steps.append((.fieldErrors(.input), report))
            }
        }
        lock.unlock()
        steps.forEach { postCardFormStep($0.0, $0.1, duration: duration) }
    }

    /// The customer left `field`. Its errors stand from here on when they had edited it, so a
    /// field left half done is an error and a field typed through to the next one is not.
    ///
    /// Taken one frame later: a form leaving the screen resigns its field in the same frame it
    /// disappears, and that is not the customer leaving a field. By then the form's visit is gone
    /// with its unmount, and the blur with it. The states are the ones last reported; leaving a
    /// field changes none.
    ///
    /// - Parameters:
    ///   - inputRefused: The form refuses input because the screen is being captured, and took the
    ///     focus away itself; the customer did not leave the field, so nothing is reported.
    ///   - isOnActiveScreen: Asked when the blur is taken: whether the field is still in a window,
    ///     that window key, the app active, and its screen not being dismissed or popped. When not,
    ///     its screen or the app went away and took the focus with it, and nothing is reported.
    ///     The Android form drops such a blur by its window focus; a sheet on iOS shares its
    ///     window, so its dismissal is read from the view controllers instead.
    func cardFormFieldLeft(
        owner: AnyObject,
        field: CardFormProgress.Field,
        edited: Bool,
        inputRefused: Bool = false,
        isOnActiveScreen: @escaping () -> Bool = { true }
    ) {
        guard !inputRefused else { return }
        DispatchQueue.main.async { [weak self, weak owner] in
            guard let self = self, let owner = owner, isOnActiveScreen() else { return }
            let now = Self.now()
            self.lock.lock()
            var report: CardFormProgress.Report?
            var duration: Int?
            if let visit = self.openVisit(of: owner, restarting: false) {
                duration = Self.ms(since: visit.readyAt, until: now)
                if edited {
                    visit.judged.insert(field)
                }
                report = visit.progress.fieldErrors(visit.progress.states.errors(judged: visit.judged), trigger: .blur)
            }
            self.lock.unlock()
            if let report = report {
                self.postCardFormStep(.fieldErrors(.blur), report, duration: duration)
            }
        }
    }

    /// ``GopaySDK/submitCardForm(formId:)`` was asked for the form `owner` registered, before the
    /// card is judged: `submit-request` with the validity the form had, then the errors of the
    /// submit, every field's from now on, whether or not the form shows them. A submit into a form
    /// whose visit ended with a JWE starts a new visit.
    func cardFormSubmitRequested(owner: AnyObject?) {
        guard let owner = owner else { return }
        let now = Self.now()
        lock.lock()
        var steps: [(CardFormStep, CardFormProgress.Report)] = []
        var duration: Int?
        if let visit = openVisit(of: owner, restarting: true) {
            duration = Self.ms(since: visit.readyAt, until: now)
            steps.append((.submitRequest, visit.progress.submitRequest()))
            visit.judged = Set(CardFormProgress.Field.allCases)
            let errors = visit.progress.states.errors(judged: visit.judged)
            if let report = visit.progress.fieldErrors(errors, trigger: .submit) {
                steps.append((.fieldErrors(.submit), report))
            }
        }
        lock.unlock()
        steps.forEach { postCardFormStep($0.0, $0.1, duration: duration) }
    }

    /// The submit of the form `owner` registered failed to encrypt the card. The form keeps the
    /// card, so this is how its visit ends unless the customer types again.
    func cardFormEncryptFailed(owner: AnyObject?) {
        guard let owner = owner else { return }
        lock.lock()
        openVisit(of: owner, restarting: false)?.ended = .encryptError
        lock.unlock()
    }

    /// The SDK emptied the fields of the form `owner`. After a JWE the visit is already over and
    /// the next one starts with the next input; on the host's clear mid-visit the form is back to
    /// untouched, with nothing standing, and nothing is reported.
    func cardFormCleared(owner: AnyObject) {
        lock.lock()
        if let visit = openVisit(of: owner, restarting: false) {
            visit.progress.cleared()
            visit.judged = []
        }
        lock.unlock()
    }

    /// The visit of the form `owner` that is still open, under ``lock``. A visit that ended with a
    /// JWE is none, unless `restarting`, which opens the next one on the same form.
    private func openVisit(of owner: AnyObject, restarting: Bool) -> CardFormVisit? {
        guard let visit = cardForms[ObjectIdentifier(owner)] else { return nil }
        if visit.isOver {
            guard restarting else { return nil }
            visit.restart()
        }
        return visit
    }

    /// One step of the card form as `PAYMENT_CARD.<step>`, timed from the form's ready, or nothing
    /// when its params do not pass ``CardFormProgress/vetted(_:message:)``.
    private func postCardFormStep(_ step: CardFormStep, _ report: CardFormProgress.Report, duration: Int?) {
        guard let params = CardFormProgress.vetted(report.params, message: report.message) else { return }
        let message = report.message
        post(step.budget, paymentId: nil, duration: duration, flow: Self.cardFormFlow) {
            .jsEvent(
                functionName: "PAYMENT_CARD.\(step.name)",
                errorCode: nil,
                params: Self.describeParams(params),
                returnValue: message
            )
        }
    }

    /// One card form on screen from its ready to its unmount, and its current visit: what the
    /// customer did between the ready, or the JWE before, and how that visit ended. Guarded by the
    /// telemetry's lock.
    final class CardFormVisit {
        let readyAt: UInt64
        private(set) var progress = CardFormVisit.primed()
        /// The fields whose errors stand: left after being edited, or all of them after a submit,
        /// until the form is emptied.
        var judged: Set<CardFormProgress.Field> = []
        /// How the visit ends if the form leaves now.
        var ended: CardFormProgress.End = .unmount
        /// The visit ended with a JWE; the form stays on screen, emptied by the SDK, until the
        /// customer types into it or submits again.
        private(set) var isOver = false

        init(readyAt: UInt64) {
            self.readyAt = readyAt
        }

        /// Ends the visit, `.submit` for a JWE or as ``ended`` says, and hands back its summary;
        /// `nil` when it already ended.
        func end(_ how: CardFormProgress.End?) -> CardFormProgress.Report? {
            guard !isOver else { return nil }
            isOver = true
            return progress.summary(how ?? ended)
        }

        /// The next visit on the same form, from an emptied form.
        func restart() {
            progress = Self.primed()
            judged = []
            ended = .unmount
            isOver = false
        }

        /// A tracker that has seen the form untouched, so a visit nobody types into still ends
        /// with its states: "never started", every field `empty`.
        private static func primed() -> CardFormProgress {
            let progress = CardFormProgress()
            _ = progress.progress(.untouched, sinceReady: nil)
            _ = progress.validity(false, sinceReady: nil)
            return progress
        }
    }

    // MARK: - Wallet steps

    /// `APPLE_PAY.<step>` with its outcome in `params.status` and its detail, or the status when
    /// there is none, in `return_value`. Timed from `startedAt`, `null` without one.
    func walletStep(
        _ step: WalletStep,
        status: StepStatus,
        paymentId: String,
        detail: String? = nil,
        startedAt: UInt64? = nil,
        params: [String: Param] = [:]
    ) {
        let duration = startedAt.map { Self.ms(since: $0) }
        post(.step, paymentId: paymentId, duration: duration) {
            var fields = params
            fields["status"] = .string(status.rawValue)
            return .jsEvent(
                functionName: "APPLE_PAY.\(step.rawValue)",
                errorCode: nil,
                params: Self.describeParams(fields),
                returnValue: TelemetryRedaction.safeErrorMessage(detail ?? status.rawValue)
            )
        }
    }

    /// The answer an Apple Pay availability check reached, either way, as `APPLE_PAY.readyToPay`
    /// with the asking function in `params.caller`.
    ///
    /// - Parameter onlyWhenChanged: Reports only an answer that differs from the last one this
    ///   caller reported. For ``GopaySDK/canUseApplePay()`` alone, which a host may call from a
    ///   SwiftUI view body on every render; every other caller reports each answer, as the
    ///   browser SDK and Android do.
    func walletAvailability(
        caller: String,
        available: Bool,
        startedAt: UInt64,
        paymentId: String? = nil,
        onlyWhenChanged: Bool = false
    ) {
        if onlyWhenChanged {
            lock.lock()
            let previous = probeAnswers.updateValue(available, forKey: caller)
            lock.unlock()
            if previous == available { return }
        }
        post(.step, paymentId: paymentId, duration: Self.ms(since: startedAt)) {
            .jsEvent(
                functionName: "APPLE_PAY.readyToPay",
                errorCode: nil,
                params: Self.describeParams(["caller": .string(caller), "available": .bool(available)]),
                returnValue: available ? "available" : Self.applePayUnavailable
            )
        }
    }

    // MARK: - Errors

    /// An SDK error, once per error, as its code with the SDK's own message. An error that is a
    /// gateway's HTTP answer is left out: its request already went as an `api_call` with the
    /// status, and a second event would count every failed request twice.
    func error(_ error: GopaySDKError, paymentId: String?) {
        guard !Self.isGatewayResponse(error) else { return }
        let code = error.code.rawValue
        let status = error.httpStatus
        let message = Self.sdkAuthoredMessage(of: error)
        post(.error, paymentId: paymentId, duration: nil) {
            .jsEvent(
                functionName: code,
                errorCode: code,
                params: Self.describeParams(status.map { ["status": .int($0)] } ?? [:]),
                returnValue: TelemetryRedaction.safeErrorMessage(message)
            )
        }
    }

    /// Whether the error is the SDK's reading of a gateway response with an error status, the
    /// only codes built from one. A status on any other code, the 3DS page's, is not the gateway's.
    static func isGatewayResponse(_ error: GopaySDKError) -> Bool {
        guard error.httpStatus != nil else { return false }
        switch error.code {
        case .networkClientError, .networkServerError, .authPaymentTokenExpired, .authPaymentCredentialsInvalid,
             .paymentNotFound, .paymentChargeAlreadyExists:
            return true
        default:
            return false
        }
    }

    /// The message without what someone else wrote into it: the gateway's error message, a
    /// charge's `fail_reason` and a system error's description, the last replaced by its type.
    /// What the SDK wrote around them stays.
    static func sdkAuthoredMessage(of error: GopaySDKError) -> String {
        var text = error.message
        let gatewaySuffix = error.gatewayError.messageSuffix
        if !gatewaySuffix.isEmpty {
            text = text.replacingOccurrences(of: gatewaySuffix, with: "")
        }
        if let failReason = error.chargeState?.failReason, !failReason.isEmpty {
            text = text.replacingOccurrences(of: ": \(failReason)", with: "")
        }
        if let underlying = error.underlying, !(underlying is GopaySDKError) {
            let foreign = underlying.localizedDescription
            if !foreign.isEmpty {
                text = text.replacingOccurrences(of: foreign, with: failureLabel(underlying))
            }
        }
        return text
    }

    /// What a failure is, never by its message: an SDK error by its code, anything else by the
    /// vocabulary both SDKs share, `timeout`, `dns`, `io` or `error`.
    static func failureLabel(_ error: Error) -> String {
        if let sdkError = error as? GopaySDKError { return sdkError.code.rawValue }
        guard let urlError = error as? URLError else { return "error" }
        switch urlError.code {
        case .timedOut: return "timeout"
        case .cannotFindHost, .dnsLookupFailed: return "dns"
        default: return "io"
        }
    }

    // MARK: - Sending

    /// Queues one event. The envelope is fixed here, at the moment it happened; the payload is
    /// built later on the transport, where the redaction runs.
    ///
    /// - Parameter paymentId: The event's own payment; without one, the last session started and
    ///   not closed, as on Android.
    private func post(
        _ budget: Budget,
        paymentId: String?,
        duration: Int?,
        paymentMethod: String? = nil,
        flow: String? = nil,
        resetsBudgets: Bool = false,
        payload: @escaping @Sendable () -> TelemetryEvent.Payload
    ) {
        guard let transport = transport else { return }
        let paymentId = Self.nonEmpty(paymentId) ?? latestPaymentId()
        // The ingest needs one of the two to attribute an event and drops it without either.
        guard clientId != nil || paymentId != nil else { return }
        let clientId = self.clientId
        let origin = self.origin
        let traceId = Self.newId()
        let clientTime = Self.wallClockMs()
        queue.append(PendingEvent(budget: budget, resetsBudgets: resetsBudgets) {
            TelemetryEvent(
                clientId: clientId,
                paymentSessionId: paymentId,
                sdkVersion: GopaySDK.version,
                integration: Self.integration,
                paymentMethod: paymentMethod,
                flow: flow,
                traceId: traceId,
                transactionId: Self.processTransactionId,
                origin: origin,
                duration: duration,
                clientTime: clientTime,
                payload: payload()
            )
        })
        let queue = self.queue
        Task { await transport.drain(queue) }
    }

    private func latestPaymentId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return attached.last
    }

    /// A `params` object as the schema carries it: JSON text with absent values left out and
    /// strings scrubbed, or `{"truncated":<length>}` when it would not fit the 4096 the schema
    /// allows. `nil` when nothing is left.
    static func describeParams(_ fields: [String: Param]) -> String? {
        guard !fields.isEmpty else { return nil }
        var object: [String: Any] = [:]
        for (key, value) in fields {
            switch value {
            case .string(let text): object[key] = TelemetryRedaction.safeErrorMessage(text)
            case .int(let number): object[key] = number
            case .bool(let flag): object[key] = flag
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json.unicodeScalars.count <= maxParamsLength ? json : "{\"truncated\":\(json.unicodeScalars.count)}"
    }

    /// The schema's cap on `params`.
    static let maxParamsLength = 4096

    // MARK: - Clock and ids

    /// Monotonic nanoseconds, unaffected by the wall clock being changed mid-flow.
    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    /// The wall clock in whole epoch milliseconds, for `client_time` and nothing else.
    static func wallClockMs() -> Int {
        Int((Date().timeIntervalSince1970 * 1000).rounded())
    }

    /// Whole milliseconds between two ``now()`` readings.
    static func ms(since start: UInt64, until end: UInt64 = now()) -> Int {
        guard end > start else { return 0 }
        return Int((Double(end - start) / 1_000_000).rounded())
    }

    /// A random UUID, from the system's cryptographic source.
    static func newId() -> String {
        UUID().uuidString.lowercased()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Queue

    /// One queued event: its budget, whether it starts the budgets over, and how to build it.
    struct PendingEvent: Sendable {
        let budget: Budget
        let resetsBudgets: Bool
        let build: @Sendable () -> TelemetryEvent
    }

    /// The events emitted and not yet handed to the transport, in the order they happened. A
    /// plain lock rather than the actor's mailbox, because tasks started one after another are
    /// not guaranteed to reach the actor in that order; whichever drain runs first takes them
    /// all, in order.
    final class PendingEvents: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [PendingEvent] = []

        func append(_ event: PendingEvent) {
            lock.lock()
            events.append(event)
            lock.unlock()
        }

        func takeAll() -> [PendingEvent] {
            lock.lock()
            defer { lock.unlock() }
            let taken = events
            events = []
            return taken
        }
    }

    /// What every SDK instance in the process shares with ``processTransactionId``: the numbering
    /// of the events sent, and the count of those that did not arrive. A re-initialized SDK goes
    /// on with the same series rather than starting a second one from 1, so a gap in `seq` within
    /// one `transaction_id` is an event lost, and `unsent` says whether it was lost before the
    /// ingest or after. The Android `Telemetry` keeps the same two beside its transaction id.
    final class ProcessCounters: @unchecked Sendable {
        /// The process's own; tests make their own so they do not read each other's numbers.
        static let shared = ProcessCounters()

        private let lock = NSLock()
        private var lastSequence = 0
        private var unsentCount = 0

        /// Numbers one event and spends the number only when the event can go: `send` gets the
        /// next number and returns what it made with it, or `nil` when the event cannot be sent,
        /// which leaves the number to the next one. Held under the lock throughout, so two SDK
        /// instances sending at once never get the same number.
        func numbered<T>(_ send: (Int) -> T?) -> T? {
            lock.lock()
            defer { lock.unlock() }
            guard let sent = send(lastSequence + 1) else { return nil }
            lastSequence += 1
            return sent
        }

        /// An event handed to `URLSession` did not arrive: no response, or one outside 2xx. A 204
        /// for a payload the ingest dropped arrived, and is the ingest's to count.
        func countUnsent() {
            lock.lock()
            unsentCount += 1
            lock.unlock()
        }

        /// The events not delivered so far, `nil` while there are none: the ingest is to see the
        /// key missing rather than a 0. Never reset, because the event that carries it can be lost
        /// too, and a later one still holds the total.
        var unsent: Int? {
            lock.lock()
            defer { lock.unlock() }
            return unsentCount > 0 ? unsentCount : nil
        }
    }

    /// A count of things running at once, readable from any thread.
    final class InFlightCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var isRunning: Bool {
            lock.lock()
            defer { lock.unlock() }
            return count > 0
        }

        func start() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        func finish() {
            lock.lock()
            count -= 1
            lock.unlock()
        }
    }
}

/// Builds, numbers and uploads the queued events, one request each.
actor TelemetryTransport {

    /// The ingest's cap on a request body.
    static let maxRequestBytes = 16 * 1024

    private let endpoint: URL
    private let session: URLSession
    /// Numbers the events and counts the ones that did not arrive, for the whole process. A
    /// number is spent only on an event that was actually handed to `URLSession`, so a gap in the
    /// sequence means an event lost on the way.
    private let counters: Telemetry.ProcessCounters
    /// Where the one-line debug log goes; `nil` while debug logging is off.
    private let debugSink: (@Sendable (String) -> Void)?
    private let onResponse: (@Sendable (Int?, Data?) -> Void)?
    private var spent: [Telemetry.Budget: Int] = [:]

    init(
        endpoint: URL,
        session: URLSession,
        counters: Telemetry.ProcessCounters,
        debugSink: (@Sendable (String) -> Void)?,
        onResponse: (@Sendable (Int?, Data?) -> Void)?
    ) {
        self.endpoint = endpoint
        self.session = session
        self.counters = counters
        self.debugSink = debugSink
        self.onResponse = onResponse
    }

    deinit {
        // Lets the uploads already handed over finish, then releases the session, which would
        // otherwise outlive a re-initialized SDK for the rest of the process.
        session.finishTasksAndInvalidate()
    }

    func drain(_ queue: Telemetry.PendingEvents) {
        for event in queue.takeAll() {
            deliver(event)
        }
    }

    private func deliver(_ pending: Telemetry.PendingEvent) {
        if pending.resetsBudgets {
            spent = [:]
        }
        let used = spent[pending.budget, default: 0]
        guard used < pending.budget.limit else { return }
        var event = pending.build()
        event.unsent = counters.unsent
        guard let body = counters.numbered({ number -> Data? in
            event.seq = number
            return Self.fittingBody(of: event)
        }) else { return }

        var request = URLRequest(url: endpoint, timeoutInterval: Telemetry.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(DefaultNetworkClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        spent[pending.budget] = used + 1
        debugSink?("[GopaySDK] telemetry: \(event.payload.eventType) \(event.payload.name)")
        let onResponse = self.onResponse
        let counters = self.counters
        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            if error != nil || !(200..<300).contains(status ?? 0) {
                counters.countUnsent()
            }
            onResponse?(status, data)
        }.resume()
    }

    /// The request body, without the request and response bodies when it would not fit the
    /// ingest's limit with them, or `nil` when it does not fit at all.
    static func fittingBody(of event: TelemetryEvent) -> Data? {
        if let body = event.requestBody(), body.count <= maxRequestBytes {
            return body
        }
        if let body = event.withoutBodies()?.requestBody(), body.count <= maxRequestBytes {
            return body
        }
        return nil
    }
}
