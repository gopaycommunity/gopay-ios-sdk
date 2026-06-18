import Foundation

/// Thread-safe registry of live ``PaymentSession`` instances keyed by `payment_id`. Supports
/// concurrent payments. The iOS counterpart of the Android `ConcurrentHashMap<String, PaymentSession>`.
actor SessionRegistry {
    private var sessions: [String: PaymentSession] = [:]

    /// Registers a session, or throws ``GopaySDKError/Code/authPaymentSessionAlreadyExists`` if one
    /// for the same `payment_id` already exists. Mirrors `ConcurrentHashMap.putIfAbsent`.
    func register(_ session: PaymentSession) throws {
        let id = session.paymentId
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
}
