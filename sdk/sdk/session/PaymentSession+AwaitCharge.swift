import Foundation
import UIKit

/// How ``PaymentSession/awaitChargeState(_:)`` handles a 3DS challenge the gateway asks for.
/// Mirrors the Android `ThreeDSMode`.
public enum ThreeDSMode {
    /// The SDK opens the challenge itself through
    /// ``PaymentSession/handle3dsVerification(redirectURL:returnURL:presenting:)``, with the
    /// `returnURL` and `presenting` from ``AwaitChargeOptions``, and keeps polling once it
    /// returns. The default.
    case automatic
    /// The SDK only reports the redirect URL through ``AwaitChargeOptions/onActionRequired`` and
    /// keeps polling; the app runs the challenge itself.
    case manual
}

/// Options for ``PaymentSession/awaitChargeState(_:)``. The defaults poll once a second, as the
/// GoPay guide recommends, give the gateway 30 seconds to decide and run a 3DS challenge
/// automatically. The Android `AwaitChargeOptions` has the matching options, in milliseconds.
public struct AwaitChargeOptions {
    /// How long after one answer the next `GET /payments/{id}/charge` goes out, in seconds.
    /// Defaults to 1 second, the cadence GoPay recommends.
    public var interval: TimeInterval
    /// How long the charge may stay undecided, in `requested`, `processing` or `unknown`, before
    /// the call gives up with ``GopaySDKError/Code/paymentTimeout``, in seconds. Defaults to 30
    /// seconds, counted from the call. Lifted the first time the charge reports `actionRequired`
    /// with a redirect URL: a 3DS challenge takes as long as the user needs. In
    /// ``ThreeDSMode/automatic`` the same timeout starts again once the challenge returns, so the
    /// gateway has 30 seconds to decide after it; in ``ThreeDSMode/manual`` it stays lifted.
    public var initialTimeout: TimeInterval
    /// Whether the SDK runs a 3DS challenge itself. Defaults to ``ThreeDSMode/automatic``.
    public var threeDSMode: ThreeDSMode
    /// The `callback.return_url` the payment was created with, for the automatic 3DS challenge;
    /// the same address ``PaymentSession/handle3dsVerification(redirectURL:returnURL:presenting:)``
    /// takes. Without a usable one the SDK waits for ``GopaySDK/chargeReturnURL`` instead.
    public var returnURL: URL?
    /// The view controller to present the automatic 3DS challenge from. When `nil`, the SDK
    /// finds the topmost view controller, as the manual call does.
    public var presenting: UIViewController?
    /// Called on the main actor with every charge state the call reads, the last one included,
    /// before the call returns or throws.
    public var onStateChange: (@MainActor (ChargePaymentResponse) -> Void)?
    /// Called on the main actor with each new `action.redirect_url` the charge reports, once per
    /// address, before the SDK opens it in ``ThreeDSMode/automatic``.
    public var onActionRequired: (@MainActor (String) -> Void)?

    public init(
        interval: TimeInterval = 1,
        initialTimeout: TimeInterval = 30,
        threeDSMode: ThreeDSMode = .automatic,
        returnURL: URL? = nil,
        presenting: UIViewController? = nil,
        onStateChange: (@MainActor (ChargePaymentResponse) -> Void)? = nil,
        onActionRequired: (@MainActor (String) -> Void)? = nil
    ) {
        self.interval = interval
        self.initialTimeout = initialTimeout
        self.threeDSMode = threeDSMode
        self.returnURL = returnURL
        self.presenting = presenting
        self.onStateChange = onStateChange
        self.onActionRequired = onActionRequired
    }
}

/// What ``PaymentSession/awaitChargeState(_:)`` waits on and runs between its reads. The live
/// set uses the system uptime, `Task.sleep` and the session's own 3DS verification; tests replace
/// it to run on virtual time and to stand in for the verification screen.
struct AwaitChargeHooks {
    /// Seconds on a monotonic clock, one a change of the wall clock does not move; only
    /// differences are read.
    var now: () -> TimeInterval
    /// Suspends for the given seconds and throws `CancellationError` when the task is cancelled.
    var sleep: (TimeInterval) async throws -> Void
    /// Runs the 3DS challenge for a redirect URL and returns once it is answered.
    var verify: (PaymentSession, _ redirectURL: String, _ returnURL: URL?, _ presenting: UIViewController?) async throws -> Void

    static let live = AwaitChargeHooks(
        now: { ProcessInfo.processInfo.systemUptime },
        sleep: { seconds in
            try await Task.sleep(nanoseconds: nanoseconds(for: seconds))
        },
        verify: { session, redirect, returnURL, presenting in
            // The same answer the manual call gives a redirect that is not a web address: the
            // manual call needs a URL to be asked at all, so the string that cannot become one
            // is settled here with the same code and reason.
            guard let url = URL(string: redirect) else {
                throw GopayVerificationNavigationPolicy.unloadableRedirect(reason: "not a URL")
            }
            try await session.handle3dsVerification(redirectURL: url, returnURL: returnURL, presenting: presenting)
        }
    )

    /// The sleep's argument as `Task.sleep` takes it. An interval that is huge or infinite, which
    /// a React Native bridge can hand over, is capped at what the type holds rather than trapping
    /// in the conversion; anything negative or not a number sleeps not at all.
    static func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        guard !seconds.isNaN, seconds > 0 else { return 0 }
        let longest = TimeInterval(UInt64.max / 1_000_000_000)
        return UInt64(min(seconds, longest) * 1_000_000_000)
    }
}

public extension PaymentSession {

    /// Polls `GET /payments/{payment_id}/charge` until the charge is decided, running a 3DS
    /// challenge on the way, and returns the charge once it is `succeeded`.
    ///
    /// Call it after any charge on this session: ``charge(_:)``, ``chargeWithApplePay(browserData:challengePreference:)``
    /// or a charge your backend made. It is the one call that replaces a polling loop of your
    /// own; the manual path, ``getChargeState()`` plus
    /// ``handle3dsVerification(redirectURL:returnURL:presenting:)``, stays as it is. The Android
    /// SDK has the same `awaitChargeState` with the matching options, defaults and codes.
    ///
    /// The first read goes out at once, every later one ``AwaitChargeOptions/interval`` after the
    /// previous answer, or after the 3DS challenge when one ran. Each state read goes to
    /// ``AwaitChargeOptions/onStateChange``, the last one included. Then:
    ///
    /// - `succeeded` returns the charge.
    /// - `failed` throws ``GopaySDKError/Code/paymentDeclined`` with the charge as
    ///   ``GopaySDKError/chargeState`` and its `failReason` in the message.
    /// - `requested`, `processing` and `unknown` are waited out. When they last past
    ///   ``AwaitChargeOptions/initialTimeout``, counted from the call, the read on the deadline
    ///   decides: a charge still undecided there throws ``GopaySDKError/Code/paymentTimeout``,
    ///   with that read as ``GopaySDKError/chargeState``. The charge is not over then; read
    ///   ``getChargeState()`` or wait for your backend's notification before offering a new
    ///   payment.
    /// - `actionRequired` with a `redirect_url` not seen before lifts the timeout, because a
    ///   challenge takes as long as the user needs, and goes to
    ///   ``AwaitChargeOptions/onActionRequired``. In ``ThreeDSMode/automatic`` the SDK then opens
    ///   ``handle3dsVerification(redirectURL:returnURL:presenting:)`` with the options' `returnURL`
    ///   and `presenting`, and once it returns polls on under a fresh `initialTimeout`, so a
    ///   gateway that never decides after the challenge still ends in `paymentTimeout`; in
    ///   ``ThreeDSMode/manual`` it polls on at once, without a timeout, and the challenge is yours
    ///   to run. The same address reported again is not opened again, and an `actionRequired`
    ///   without an address is waited out like `processing`.
    ///
    /// A failed read ends the call with that read's own error, unchanged: `NETWORK_*` for a
    /// transport or HTTP failure, ``GopaySDKError/Code/authPaymentSessionClosed`` for a closed
    /// session. A 3DS challenge that fails ends it the same way with the verification's error,
    /// ``GopaySDKError/Code/paymentCancelled`` for a closed screen among them, and as after the
    /// manual call the charge may still be through: read ``getChargeState()`` before offering the
    /// payment again. Cancelling the task that awaits the call stops the polling at once, closes a
    /// challenge that is up and throws `CancellationError`; no state is returned or reported after
    /// that, and no read goes out. Two concurrent calls on one session each poll on their own;
    /// only their 3DS challenges exclude each other, the second with
    /// ``GopaySDKError/Code/paymentVerificationInProgress``.
    ///
    /// - Parameter options: The cadence, the timeout, the 3DS mode and the callbacks. The
    ///   defaults poll once a second for 30 seconds and run the challenge automatically.
    /// - Returns: The charge in `succeeded`.
    /// - Throws: ``GopaySDKError`` with ``GopaySDKError/Code/validationInvalidInput`` when
    ///   `interval` or `initialTimeout` is not positive, with ``GopaySDKError/Code/paymentDeclined``
    ///   or ``GopaySDKError/Code/paymentTimeout`` as above, or the error of the read or the
    ///   verification that failed; `CancellationError` when the awaiting task is cancelled.
    func awaitChargeState(_ options: AwaitChargeOptions = .init()) async throws -> ChargePaymentResponse {
        guard options.interval > 0, options.initialTimeout > 0 else {
            throw GopaySDKError(
                .validationInvalidInput,
                message: "awaitChargeState needs a positive interval and initialTimeout"
            )
        }
        let hooks = awaitChargeHooks
        // `nil` while a challenge is on: it has no time limit.
        var deadline: TimeInterval? = hooks.now() + options.initialTimeout
        // Every address a challenge was reported for: a gateway that keeps echoing the same
        // action must not send the user through the same challenge twice.
        var reportedRedirects = Set<String>()

        while true {
            try Task.checkCancellation()
            let charge = try await getChargeState()
            // A read the cancellation did not cut short must not be reported or acted on.
            try Task.checkCancellation()
            if let onStateChange = options.onStateChange {
                await onStateChange(charge)
                try Task.checkCancellation()
            }

            switch charge.state {
            case .succeeded:
                return charge
            case .failed:
                throw GopaySDKError(
                    .paymentDeclined,
                    message: "Charge failed" + (charge.failReason.map { ": \($0)" } ?? ""),
                    chargeState: charge
                )
            case .actionRequired:
                // An address is an address only when there is one: an empty redirect_url is as
                // missing as none, and then there is nothing to report or open.
                if let redirect = charge.action?.redirectUrl, !redirect.isEmpty,
                   reportedRedirects.insert(redirect).inserted {
                    deadline = nil
                    if let onActionRequired = options.onActionRequired {
                        await onActionRequired(redirect)
                    }
                    if options.threeDSMode == .automatic {
                        try await hooks.verify(self, redirect, options.returnURL, options.presenting)
                        // The challenge is answered; the gateway gets the initial timeout again
                        // to decide, otherwise a charge it never decides would be polled forever.
                        deadline = hooks.now() + options.initialTimeout
                    }
                }
            case .requested, .processing, .unknown:
                // Not decided yet. A state this SDK does not know is waited out like processing.
                break
            }

            var wait = options.interval
            if let deadline = deadline {
                let remaining = deadline - hooks.now()
                if remaining <= 0 {
                    throw GopaySDKError(
                        .paymentTimeout,
                        message: "Charge did not leave \(charge.state.rawValue) within "
                            + "\(Self.formatSeconds(options.initialTimeout)) s; read getChargeState() "
                            + "or wait for the payment notification before offering a new payment",
                        chargeState: charge
                    )
                }
                // The read that decides the timeout lands on the deadline, not an interval past it.
                wait = min(wait, remaining)
            }
            try await hooks.sleep(wait)
        }
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        seconds == seconds.rounded() ? String(Int(seconds)) : String(seconds)
    }
}
