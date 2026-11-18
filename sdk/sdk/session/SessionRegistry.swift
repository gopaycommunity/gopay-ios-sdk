import Foundation

/// Thread-safe registry of live ``PaymentSession`` instances keyed by `payment_id`. Supports
/// concurrent payments. The iOS counterpart of the Android `ConcurrentHashMap<String, PaymentSession>`.
actor SessionRegistry {
    private var sessions: [String: PaymentSession] = [:]
    /// Set by ``retire()``: the SDK has moved to another connection and this registry takes no
    /// more sessions.
    private var retired = false

    /// Registers a session, or throws ``GopaySDKError/Code/authPaymentSessionAlreadyExists`` if one
    /// for the same `payment_id` already exists. Mirrors `ConcurrentHashMap.putIfAbsent`.
    ///
    /// A retired registry throws ``GopaySDKError/Code/authPaymentSessionClosed`` instead: the
    /// session was started over the connection a later ``GopaySDK/initialize(with:)`` replaced,
    /// which closes every session of it.
    func register(_ session: PaymentSession) throws {
        let id = session.paymentId
        guard !retired else { throw Self.replacedConnectionError(paymentId: id) }
        guard sessions[id] == nil else {
            throw GopaySDKError(
                .authPaymentSessionAlreadyExists,
                message: "A PaymentSession for \(id) already exists; close it before starting a new one."
            )
        }
        sessions[id] = session
    }

    /// Removes a session only if it is the currently-registered one for its `payment_id` — so a
    /// losing concurrent session closing itself never evicts the winner. Mirrors
    /// `ConcurrentHashMap.remove(key, value)`.
    func remove(_ session: PaymentSession) {
        let id = session.paymentId
        if let existing = sessions[id], existing === session {
            sessions[id] = nil
        }
    }

    func get(_ paymentId: String) -> PaymentSession? {
        sessions[paymentId]
    }

    func all() -> [PaymentSession] {
        Array(sessions.values)
    }

    /// `AUTH_013` for a session that finished starting over a connection a later
    /// ``GopaySDK/initialize(with:)`` replaced. Word for word the Android message.
    static func replacedConnectionError(paymentId: String) -> GopaySDKError {
        GopaySDKError(
            .authPaymentSessionClosed,
            message: "PaymentSession for \(paymentId) is closed: initialize switched to another connection while it started."
        )
    }

    /// Takes no more sessions from now on and returns the ones it holds, for the SDK to close.
    /// Called once the SDK has switched to another connection; a session that registers before
    /// this is in the returned list, one that registers after it is refused.
    func retire() -> [PaymentSession] {
        retired = true
        return Array(sessions.values)
    }
}
