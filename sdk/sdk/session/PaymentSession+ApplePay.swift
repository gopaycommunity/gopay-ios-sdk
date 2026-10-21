import Foundation
import PassKit

public extension PaymentSession {

    /// Managed Apple Pay flow: fetches the Apple Pay config for this payment, presents the Apple Pay
    /// sheet, maps the resulting token, and submits the charge in one call.
    ///
    /// Suspends while the sheet is visible. Returns the ``ChargePaymentResponse`` on success —
    /// inspect `action?.redirectUrl` and call
    /// ``handle3dsVerification(redirectURL:returnURL:presenting:)`` if 3DS is required, then
    /// ``getChargeState()`` for the final result.
    ///
    /// Only one Apple Pay sheet can be presented per process; a concurrent attempt throws
    /// ``GopaySDKError/Code/paymentApplePayInProgress``. A sheet closed without paying throws
    /// ``GopaySDKError/Code/paymentCancelled``. A sheet that closes while its charge is still
    /// running, which PassKit does after a time limit, does not end the call: it waits for the
    /// charge and returns its result or its error. When Apple Pay
    /// cannot be used, because the device cannot pay with it, the payment allows no card network
    /// it supports or the sheet cannot be shown, it throws
    /// ``GopaySDKError/Code/paymentMethodUnavailable``; a payment token the SDK cannot read, or an
    /// empty one as the iOS Simulator returns, is ``GopaySDKError/Code/paymentProcessingFailed``.
    /// A failed charge keeps its own code.
    ///
    /// A task cancelled before the sheet is shown throws `CancellationError` and shows nothing.
    /// Cancelling it later does not close the sheet: the call waits until the sheet closes, then
    /// returns the charge if it succeeded and otherwise throws `CancellationError`, so neither
    /// ``GopaySDKError/Code/paymentCancelled`` nor the charge's error is thrown or reported. The
    /// Android SDK differs here, its call ends at once.
    ///
    /// - Parameters:
    ///   - browserData: Optional 3DS browser data. The spec requires it on every card charge; when
    ///     `nil` the SDK derives it from the device via ``BrowserData/deviceDefault()``.
    ///   - challengePreference: 3DS challenge preference forwarded to the gateway.
    func chargeWithApplePay(
        browserData: BrowserData? = nil,
        challengePreference: ChallengePreference? = nil
    ) async throws -> ChargePaymentResponse {
        try await reported {
            try await runApplePay(browserData: browserData, challengePreference: challengePreference)
        }
    }

    /// The Apple Pay flow without the reporting: its own steps are unreported calls, so the one
    /// error it ends with is reported once, by the public call.
    private func runApplePay(
        browserData: BrowserData?,
        challengePreference: ChallengePreference?
    ) async throws -> ChargePaymentResponse {
        let appInfo = try await fetchApplePayInfo()

        let resolvedBrowserData: BrowserData
        if let browserData = browserData {
            resolvedBrowserData = browserData
        } else {
            resolvedBrowserData = await BrowserData.deviceDefault()
        }

        // A task already cancelled gets no sheet. Once the sheet is up it stays until it closes,
        // and the call ends with what the sheet ended with.
        try Task.checkCancellation()
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
                self.startApplePayFlow(
                    appInfo: appInfo,
                    browserData: browserData,
                    challengePreference: challengePreference,
                    continuation: continuation
                )
            }
        }
    }

    /// Builds and starts the Apple Pay coordinator on the main actor, resolving `continuation` with
    /// the final outcome. Split out of ``presentApplePay`` to keep closure nesting shallow.
    @MainActor
    private func startApplePayFlow(
        appInfo: GopayApplePayAppInfoResponse,
        browserData: BrowserData,
        challengePreference: ChallengePreference?,
        continuation: CheckedContinuation<ChargePaymentResponse, Error>
    ) {
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
                self.submitApplePayCharge(
                    fields: fields,
                    browserData: browserData,
                    challengePreference: challengePreference,
                    done: done
                )
            },
            completion: { result in
                SheetGuards.applePayInProgress = false
                continuation.resume(with: result)
            }
        )
        coordinator.start()
    }

    /// Submits the charge built from the Apple Pay token fields and relays the result to `done`.
    nonisolated private func submitApplePayCharge(
        fields: GopayApplePayCoordinator.TokenFields,
        browserData: BrowserData,
        challengePreference: ChallengePreference?,
        done: @escaping (Result<ChargePaymentResponse, Error>) -> Void
    ) {
        Task {
            do {
                let response = try await self.sendCharge(
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
    }
}
