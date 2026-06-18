import Foundation
import PassKit

public extension PaymentSession {

    /// Managed Apple Pay flow: fetches the Apple Pay config for this payment, presents the Apple Pay
    /// sheet, maps the resulting token, and submits the charge in one call.
    ///
    /// Suspends while the sheet is visible. Returns the ``ChargePaymentResponse`` on success —
    /// inspect `action?.redirectUrl` and call
    /// ``handle3dsVerification(redirectURL:presenting:)`` if 3DS is required, then
    /// ``getChargeState()`` for the final result.
    ///
    /// Only one Apple Pay sheet can be presented per process; a concurrent attempt throws
    /// ``GopaySDKError/Code/paymentApplePayInProgress``. User dismissal is reported as
    /// `CancellationError`.
    ///
    /// - Parameters:
    ///   - browserData: Optional 3DS browser data. The spec requires it on every card charge; when
    ///     `nil` the SDK derives it from the device via ``BrowserData/deviceDefault()``.
    ///   - challengePreference: 3DS challenge preference forwarded to the gateway.
    func chargeWithApplePay(
        browserData: BrowserData? = nil,
        challengePreference: ChallengePreference? = nil
    ) async throws -> ChargePaymentResponse {
        let appInfo = try await getApplePayInfo()

        let resolvedBrowserData: BrowserData
        if let browserData = browserData {
            resolvedBrowserData = browserData
        } else {
            resolvedBrowserData = await BrowserData.deviceDefault()
        }

        return try await presentApplePay(
            appInfo: appInfo,
            browserData: resolvedBrowserData,
            challengePreference: challengePreference
        )
    }

    private func presentApplePay(
        appInfo: GopayApplePayAppInfoResponse,
        browserData: BrowserData,
        challengePreference: ChallengePreference?
    ) async throws -> ChargePaymentResponse {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ChargePaymentResponse, Error>) in
            Task { @MainActor in
                if SheetGuards.applePayInProgress {
                    continuation.resume(throwing: GopaySDKError(
                        .paymentApplePayInProgress,
                        message: "An Apple Pay payment is already in progress"
                    ))
                    return
                }
                SheetGuards.applePayInProgress = true

                let coordinator = GopayApplePayCoordinator(
                    appInfo: appInfo,
                    charge: { fields, done in
                        Task {
                            do {
                                let response = try await self.charge(
                                    .applePay(
                                        data: fields.data,
                                        signature: fields.signature,
                                        version: fields.version,
                                        header: fields.header,
                                        browserData: browserData,
                                        challengePreference: challengePreference
                                    )
                                )
                                done(.success(response))
                            } catch {
                                done(.failure(error))
                            }
                        }
                    },
                    completion: { result in
                        SheetGuards.applePayInProgress = false
                        continuation.resume(with: result)
                    }
                )
                coordinator.start()
            }
        }
    }
}
