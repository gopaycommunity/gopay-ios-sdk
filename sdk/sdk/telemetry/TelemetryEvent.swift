import Foundation

/// One event as the operational-data ingest takes it, `{"event": {...}}` on the wire.
///
/// The ingest's schema has `additionalProperties: false` and drops a whole event for one key it
/// does not know, so the keys are spelled out here and nowhere else: the common envelope every
/// event carries, then the fields of its type. An absent value is left out rather than sent empty,
/// except `duration`, which is always present and `null` when there is nothing to time from, and
/// the `target` and `status_code` the schema requires on their types.
struct TelemetryEvent: Encodable, Sendable {

    /// The four event types of the schema and the fields that belong to each.
    enum Payload: Sendable {
        /// A request the SDK actually sent to the gateway. `statusCode` is `nil` when no response
        /// came at all.
        case apiCall(action: String, httpMethod: String, target: String, statusCode: Int?, requestBody: String?, responseBody: String?)
        /// `init`, `navigate` or `leave`. `target` is where a leave went, when it went somewhere.
        case navigation(type: String, target: String?)
        /// A submit the user made, nothing about its content.
        case interaction(elementId: String)
        /// Anything the SDK did that was not a request: a step, a probe, an error.
        case jsEvent(functionName: String, errorCode: String?, params: String?, returnValue: String?)

        var eventType: String {
            switch self {
            case .apiCall: return "api_call"
            case .navigation: return "navigation"
            case .interaction: return "interaction"
            case .jsEvent: return "js_event"
            }
        }

        /// What the debug log calls the event after its type.
        var name: String {
            switch self {
            case .apiCall(let action, _, _, _, _, _): return action
            case .navigation(let type, _): return type
            case .interaction(let elementId): return elementId
            case .jsEvent(let functionName, _, _, _): return functionName
            }
        }
    }

    var clientId: String?
    var paymentSessionId: String?
    var sdkInstanceId: String
    /// Set when the event is actually sent; see ``TelemetryTransport``.
    var seq = 0
    var sdkVersion: String
    var integration: String
    var paymentMethod: String?
    var flow: String?
    var traceId: String
    var transactionId: String
    var origin: String
    /// Whole milliseconds, or `nil` when there is nothing to time from.
    var duration: Int?
    var payload: Payload

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case clientId = "client_id"
        case paymentSessionId = "payment_session_id"
        case sdkInstanceId = "sdk_instance_id"
        case seq
        case sdkVersion = "sdk_version"
        case integration
        case paymentMethod = "payment_method"
        case flow
        case traceId = "trace_id"
        case transactionId = "transaction_id"
        case origin
        case duration
        case action
        case httpMethod = "http_method"
        case target
        case statusCode = "status_code"
        case requestBody = "req_body"
        case responseBody = "res_body"
        case navigationType = "navigation_type"
        case interactionType = "interaction_type"
        case elementId = "element_id"
        case functionName = "function_name"
        case errorCode = "error_code"
        case params
        case returnValue = "return_value"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(payload.eventType, forKey: .eventType)
        try c.encodeIfPresent(clientId, forKey: .clientId)
        try c.encodeIfPresent(paymentSessionId, forKey: .paymentSessionId)
        try c.encode(sdkInstanceId, forKey: .sdkInstanceId)
        try c.encode(seq, forKey: .seq)
        try c.encode(sdkVersion, forKey: .sdkVersion)
        try c.encode(integration, forKey: .integration)
        try c.encodeIfPresent(paymentMethod, forKey: .paymentMethod)
        try c.encodeIfPresent(flow, forKey: .flow)
        try c.encode(traceId, forKey: .traceId)
        try c.encode(transactionId, forKey: .transactionId)
        try c.encode(origin, forKey: .origin)
        try c.encodeOrNull(duration, forKey: .duration)
        switch payload {
        case let .apiCall(action, httpMethod, target, statusCode, requestBody, responseBody):
            try c.encode(action, forKey: .action)
            try c.encode(httpMethod, forKey: .httpMethod)
            try c.encode(target, forKey: .target)
            try c.encodeOrNull(statusCode, forKey: .statusCode)
            try c.encodeIfPresent(requestBody, forKey: .requestBody)
            try c.encodeIfPresent(responseBody, forKey: .responseBody)
        case let .navigation(type, target):
            try c.encode(type, forKey: .navigationType)
            try c.encodeOrNull(target, forKey: .target)
        case let .interaction(elementId):
            try c.encode("submit", forKey: .interactionType)
            try c.encode(elementId, forKey: .elementId)
        case let .jsEvent(functionName, errorCode, params, returnValue):
            try c.encode(functionName, forKey: .functionName)
            try c.encodeIfPresent(errorCode, forKey: .errorCode)
            try c.encodeIfPresent(params, forKey: .params)
            try c.encodeIfPresent(returnValue, forKey: .returnValue)
        }
    }

    /// The request body, `{"event": {...}}`.
    func requestBody() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(["event": self])
    }

    /// The same event without its request and response bodies, for the one that would not fit
    /// the ingest's size limit with them.
    func withoutBodies() -> TelemetryEvent? {
        guard case let .apiCall(action, method, target, status, request, response) = payload,
              request != nil || response != nil
        else { return nil }
        var copy = self
        copy.payload = .apiCall(action: action, httpMethod: method, target: target, statusCode: status, requestBody: nil, responseBody: nil)
        return copy
    }
}

private extension KeyedEncodingContainer {
    /// The value, or `null` under the same key: for the keys the schema requires present even
    /// when there is nothing to put in them.
    mutating func encodeOrNull<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value = value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
