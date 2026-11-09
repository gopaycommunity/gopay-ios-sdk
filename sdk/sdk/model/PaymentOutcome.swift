import Foundation

/// How a payment stands, as ``PaymentSession/getPaymentOutcome()`` reads it from one
/// `GET /payments/{payment_id}`. The Android SDK returns the same `PaymentOutcome`, with the same
/// four outcomes.
///
/// It is the app's answer for the screen, without waiting: when the app comes back to the
/// foreground during a payment, or after a charge call ended with a network error. The
/// notification GoPay sends your backend stays the authoritative signal.
public struct PaymentOutcome: Sendable {

    /// The payment's outcome, decided by the payment's state first and by its charge only while
    /// the payment is still open.
    public enum Outcome: String, Sendable {
        /// The payment is `paid`, `authorized`, `refunded` or `partiallyRefunded`, or it is still
        /// open and its charge `succeeded`. A refunded payment stays `paid` whatever its charge says.
        case paid = "PAID"
        /// The charge `failed`. The payment is over; a retry means a new payment.
        case declined = "DECLINED"
        /// Nothing was charged. On a payment that is `created` or `paymentMethodChosen` no charge
        /// exists yet; on one that is `canceled` or `timeouted` the payment is over, with any
        /// charge it had released.
        case notCharged = "NOT_CHARGED"
        /// The payment is still open and its charge is `requested`, `processing`,
        /// `actionRequired` or in a state this SDK does not know: wait for it with
        /// ``PaymentSession/awaitChargeState(_:)``. Without a charge, the payment is in a state
        /// this SDK does not know: read it again later, or ask your backend.
        case undecided = "UNDECIDED"
    }

    /// The outcome.
    public let outcome: Outcome
    /// The whole answer of `GET /payments/{payment_id}`, as ``PaymentSession/getStatus()``
    /// returns it.
    public let payment: PaymentDetails
    /// The charge in ``payment``, `nil` when the payment has none. It carries only its `id` and
    /// `state`; read ``PaymentSession/getChargeState()`` for its `failReason`.
    public var charge: ChargePaymentResponse? { payment.charge }

    init(payment: PaymentDetails) {
        self.outcome = Self.outcome(of: payment)
        self.payment = payment
    }

    /// The rules in order: a settled payment is paid, a closed one declined or not charged, and an
    /// open one goes by its charge, or without one is not charged unless its state is unknown.
    /// The Android SDK applies the same rules.
    static func outcome(of payment: PaymentDetails) -> Outcome {
        let charge = payment.charge?.state
        switch payment.state {
        case .paid, .authorized, .refunded, .partiallyRefunded:
            return .paid
        case .canceled, .timeouted:
            return charge == .failed ? .declined : .notCharged
        case .created, .paymentMethodChosen, .unknown:
            guard let charge = charge else {
                return payment.state == .unknown ? .undecided : .notCharged
            }
            switch charge {
            case .succeeded:
                return .paid
            case .failed:
                return .declined
            case .requested, .processing, .actionRequired, .unknown:
                return .undecided
            }
        }
    }
}
