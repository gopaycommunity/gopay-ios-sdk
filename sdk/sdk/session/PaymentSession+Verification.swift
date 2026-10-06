import Foundation
import UIKit

public extension PaymentSession {

    /// Presents a managed WebView to complete a 3DS challenge and suspends until the user finishes
    /// or cancels. Call this whenever ``charge(_:)`` or ``getChargeState()`` returns a response with
    /// a non-`nil` `action?.redirectUrl`. After it returns, call ``getChargeState()`` to read the
    /// final charge result.
    ///
    /// Only one verification can run per process at a time; a concurrent attempt throws
    /// ``GopaySDKError/Code/paymentVerificationInProgress``. User dismissal surfaces as
    /// `CancellationError`.
    ///
    /// A verification page that cannot be loaded at all throws a ``GopaySDKError`` with
    /// ``GopaySDKError/Code/paymentVerificationUnreachable`` rather than letting the payment lapse
    /// without a reason. When the page answered with an error status, `httpStatus` carries it. The
    /// gateway announces a 3DS action for part of the charges and then never produces the data
    /// behind the link, which is the case this reports. The Android SDK reports the same code.
    /// A screen the system refuses to present, which is what an immediate retry runs into while
    /// the previous one is still animating away, is reported the same way and can be retried, and
    /// so is a `redirectURL` that is not an `http(s)` address — that one throws before anything is
    /// presented at all.
    ///
    /// This applies only while the challenge has not started rendering. Once it has, the user may
    /// already have answered it, so a later failure surfaces as `CancellationError` like a
    /// dismissal does, and the payment is settled by reading ``getChargeState()``.
    ///
    /// The verification ends when the challenge navigates to `returnURL`, the address the payment
    /// was created with (`callback.return_url`), which the charge response repeats as
    /// ``ChargePaymentResponse/returnUrl``. Pass it from the same response as `redirectURL`.
    /// Without it the SDK waits for ``GopaySDK/chargeReturnURL`` instead, and then the payment
    /// has to be created with that address, otherwise the window never closes and the user can
    /// only cancel.
    ///
    /// - Parameters:
    ///   - redirectURL: The `action.redirect_url` returned by the charge.
    ///   - returnURL: The `return_url` returned by the charge. When `nil`, blank, not `http(s)` or
    ///     without a host, ``GopaySDK/chargeReturnURL`` is used. Scheme and host are matched
    ///     without case. The return URL should carry no fragment (`#…`): what the gateway appends
    ///     lands in front of it, and the address no longer matches. On iOS 13 to 16 an address
    ///     with non-ASCII characters cannot be parsed, so the SDK waits for the constant instead.
    ///   - presenting: The view controller to present from. When `nil`, the SDK finds the topmost
    ///     view controller automatically.
    func handle3dsVerification(
        redirectURL: URL,
        returnURL: URL? = nil,
        presenting: UIViewController? = nil
    ) async throws {
        // Rejected before anything is registered or presented. A redirect URL the WebView cannot
        // load never reaches the navigation decision — that only sees where the page navigates
        // next — so the hand-off suppression downstream would swallow its load failure and the
        // caller would wait for an outcome that cannot come, with the in-progress guard held.
        if let unloadable = GopayVerificationNavigationPolicy.loadFailure(forRedirect: redirectURL) {
            throw unloadable
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                self.startVerificationFlow(
                    redirectURL: redirectURL,
                    returnURL: returnURL,
                    presenting: presenting,
                    continuation: continuation
                )
            }
        }
    }

    /// Presents the verification WebView on the main actor and resolves `continuation` with the
    /// outcome. Split out of ``handle3dsVerification(redirectURL:returnURL:presenting:)`` to keep
    /// closure nesting shallow.
    @MainActor
    private func startVerificationFlow(
        redirectURL: URL,
        returnURL: URL?,
        presenting: UIViewController?,
        continuation: CheckedContinuation<Void, Error>
    ) {
        if SheetGuards.verificationInProgress {
            continuation.resume(throwing: GopaySDKError(
                .paymentVerificationInProgress,
                message: "A payment verification is already in progress"
            ))
            return
        }
        guard let presenter = presenting ?? gopayTopViewController() else {
            continuation.resume(throwing: GopaySDKError(
                .unexpected,
                message: "Could not find a view controller to present verification"
            ))
            return
        }
        SheetGuards.verificationInProgress = true

        // The controller's own "first outcome wins" rule, extended over the presentation: a
        // presentation UIKit refuses is settled here, and a controller that somehow reports
        // afterwards must not resume the continuation a second time.
        var hasSettled = false
        func claimTheOutcome() -> Bool {
            guard !hasSettled else { return false }
            hasSettled = true
            return true
        }

        let verificationVC = GopayChargeVerificationViewController(
            redirectURL: redirectURL,
            returnURL: returnURL
        ) { result in
            guard claimTheOutcome() else { return }
            // The guard drops and the caller resumes before the dismissal, and never inside its
            // completion: a dismiss that cannot run — the presentation is still animating, the
            // presenter is gone — would otherwise swallow the return to the caller and leave
            // every later verification failing on ``GopaySDKError/Code/paymentVerificationInProgress``.
            SheetGuards.verificationInProgress = false
            presenter.dismiss(animated: true)
            switch result {
            case .completed:
                continuation.resume(returning: ())
            case .cancelled:
                continuation.resume(throwing: CancellationError())
            case .failed(let error):
                continuation.resume(throwing: error)
            }
        }
        presenter.present(verificationVC, animated: true)
        // UIKit refuses to present while the presenter is still animating something else away and
        // says so only in the console: nothing reaches the screen, no delegate callback ever
        // comes, and the caller would stay suspended with the in-progress guard held for the rest
        // of the process. An immediate retry after a failure is exactly that window, and the new
        // ``GopaySDKError/Code/paymentVerificationUnreachable`` invites one. `present` wires the
        // presentation up synchronously, so a nil presenter here means it was refused.
        if verificationVC.presentingViewController == nil, claimTheOutcome() {
            SheetGuards.verificationInProgress = false
            let error = GopaySDKError(
                .paymentVerificationUnreachable,
                message: "The 3DS verification screen could not be presented, the presenter is busy"
            )
            continuation.resume(throwing: error)
        }
    }
}
