import Foundation

/// Process-wide flags ensuring only one Apple Pay sheet and one 3DS verification run at a time.
///
/// Only ever read/written on the main thread (both presentation and the completion callbacks are
/// dispatched there), so plain stored properties are sufficient. The iOS counterpart of Android's
/// `GooglePayBridge` / `PaymentVerificationBridge` single-flight registers.
enum SheetGuards {
    static var applePayInProgress = false
    static var verificationInProgress = false
}
