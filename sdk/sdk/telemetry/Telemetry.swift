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
/// nothing retries it, the response is not read, and every failure is dropped silently.
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
        /// Wallet steps and availability answers, which repeat with the user.
        case step
        /// SDK errors.
        case error

        var limit: Int {
            switch self {
            case .apiCall: return 200
            case .lifecycle: return 75
            case .step: return 150
            case .error: return 50
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
    /// One per SDK instance, i.e. per ``GopaySDK/initialize(with:)``; ties an init to the payments
    /// made through it.
    let instanceId = Telemetry.newId()

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
    /// When each card form on screen became ready, keyed by the form's owner token.
    private var readyAt: [ObjectIdentifier: UInt64] = [:]
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
    ///   - onResponse: Called with the status and body of each upload's response. Tests only.
    init(
        endpoint: URL?,
        clientId: String?,
        debugLogging: Bool = false,
        debugSink: @escaping @Sendable (String) -> Void = { print($0) },
        origin: String = Bundle.main.bundleIdentifier ?? "",
        configuration: URLSessionConfiguration = Telemetry.sessionConfiguration(),
        onResponse: (@Sendable (Int?, Data?) -> Void)? = nil
    ) {
        self.endpoint = endpoint
        self.clientId = Self.nonEmpty(clientId)
        self.origin = TelemetryRedaction.capped(origin, at: Self.maxOriginLength)
        self.transport = endpoint.map {
            TelemetryTransport(
                endpoint: $0,
                session: URLSession(configuration: configuration),
                debugSink: debugLogging ? debugSink : nil,
                onResponse: onResponse
            )
        }
    }

    /// The telemetry a configuration asks for: its environment's ingest, its `client_id`.
    convenience init(config: GopaySDKConfig) {
        self.init(
            endpoint: config.environment.telemetryURL,
            clientId: config.clientId,
            debugLogging: config.enableDebugLogging
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

    /// A ``GopayCardForm`` appeared, timed from the SDK's initialization.
    func cardFormReady(owner: AnyObject) {
        let now = Self.now()
        lock.lock()
        readyAt[ObjectIdentifier(owner)] = now
        lock.unlock()
        post(.lifecycle, paymentId: nil, duration: Self.ms(since: createdAt, until: now), flow: Self.cardFormFlow) {
            .jsEvent(functionName: "PAYMENT_CARD.ready", errorCode: nil, params: nil, returnValue: nil)
        }
    }

    /// ``GopaySDK/submitCardForm(formId:)`` made a JWE from the form `owner` registered. Timed
    /// from the form's ready; carries nothing about what was typed.
    func cardFormSubmitted(owner: AnyObject?) {
        let since = owner.flatMap { owner -> UInt64? in
            lock.lock()
            defer { lock.unlock() }
            return readyAt[ObjectIdentifier(owner)]
        }
        post(
            .lifecycle, paymentId: nil, duration: since.map { Self.ms(since: $0) },
            paymentMethod: "card", flow: Self.cardFormFlow
        ) {
            .interaction(elementId: "card-form")
        }
    }

    /// A ``GopayCardForm`` disappeared, timed from its ready, with whether a charge was still
    /// running in the process when it went (see ``chargesInFlight``).
    func cardFormUnmounted(owner: AnyObject) {
        lock.lock()
        let since = readyAt.removeValue(forKey: ObjectIdentifier(owner))
        lock.unlock()
        let chargeInFlight = Self.chargesInFlight.isRunning
        post(.lifecycle, paymentId: nil, duration: since.map { Self.ms(since: $0) }, flow: Self.cardFormFlow) {
            .jsEvent(
                functionName: "PAYMENT_CARD.unmount",
                errorCode: nil,
                params: Self.describeParams(["charge_in_flight": .bool(chargeInFlight)]),
                returnValue: chargeInFlight ? "charge-aborted" : "idle"
            )
        }
    }

    /// The user authorized in the Apple Pay sheet. No duration, as in the browser SDK.
    func walletSubmitted(paymentId: String) {
        post(.lifecycle, paymentId: paymentId, duration: nil, paymentMethod: "applepay") {
            .interaction(elementId: "applepay-button")
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
        case .networkClientError, .networkServerError, .authPaymentTokenExpired, .authPaymentCredentialsInvalid:
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
        let instanceId = self.instanceId
        let origin = self.origin
        let traceId = Self.newId()
        queue.append(PendingEvent(budget: budget, resetsBudgets: resetsBudgets) {
            TelemetryEvent(
                clientId: clientId,
                paymentSessionId: paymentId,
                sdkInstanceId: instanceId,
                sdkVersion: GopaySDK.version,
                integration: Self.integration,
                paymentMethod: paymentMethod,
                flow: flow,
                traceId: traceId,
                transactionId: Self.processTransactionId,
                origin: origin,
                duration: duration,
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
    /// Where the one-line debug log goes; `nil` while debug logging is off.
    private let debugSink: (@Sendable (String) -> Void)?
    private let onResponse: (@Sendable (Int?, Data?) -> Void)?
    private var spent: [Telemetry.Budget: Int] = [:]
    /// The number the last event sent carried. A number is spent only on an event that was
    /// actually handed to `URLSession`, so a gap in the sequence means an event lost on the way.
    private var lastSequence = 0

    init(
        endpoint: URL,
        session: URLSession,
        debugSink: (@Sendable (String) -> Void)?,
        onResponse: (@Sendable (Int?, Data?) -> Void)?
    ) {
        self.endpoint = endpoint
        self.session = session
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
        event.seq = lastSequence + 1
        guard let body = Self.fittingBody(of: event) else { return }

        var request = URLRequest(url: endpoint, timeoutInterval: Telemetry.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(DefaultNetworkClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        lastSequence = event.seq
        spent[pending.budget] = used + 1
        debugSink?("[GopaySDK] telemetry: \(event.payload.eventType) \(event.payload.name)")
        let onResponse = self.onResponse
        session.dataTask(with: request) { data, response, _ in
            onResponse?((response as? HTTPURLResponse)?.statusCode, data)
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
