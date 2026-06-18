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
    /// - Parameters:
    ///   - redirectURL: The `action.redirect_url` returned by the charge.
    ///   - presenting: The view controller to present from. When `nil`, the SDK finds the topmost
    ///     view controller automatically.
    func handle3dsVerification(redirectURL: URL, presenting: UIViewController? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                self.startVerificationFlow(
                    redirectURL: redirectURL,
                    presenting: presenting,
                    continuation: continuation
                )
            }
        }
    }

    /// Presents the verification WebView on the main actor and resolves `continuation` with the
    /// outcome. Split out of ``handle3dsVerification(redirectURL:presenting:)`` to keep closure
    /// nesting shallow.
    @MainActor
    private func startVerificationFlow(
        redirectURL: URL,
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

        let verificationVC = GopayChargeVerificationViewController(
            redirectURL: redirectURL,
            returnURLString: GopaySDK.chargeReturnURL
        ) { result in
            presenter.dismiss(animated: true) {
                SheetGuards.verificationInProgress = false
                switch result {
                case .completed:
                    continuation.resume(returning: ())
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                }
            }
        }
        presenter.present(verificationVC, animated: true)
    }
}
