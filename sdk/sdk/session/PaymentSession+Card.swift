import Foundation

// The card charges as one call each, the shape the Android SDK has had since 2.0 and the one the
// shared API documents: the request is built here, the browser data is the device's when none is
// given, and the rest is the charge itself.
public extension PaymentSession {

    /// Charges the payment with a permanent card token, the one your backend got from
    /// `POST /cards/tokens`.
    ///
    /// Builds ``ChargePaymentRequest/cardToken(_:browserData:challengePreference:)`` and sends it
    /// as ``charge(_:)`` would, so the browser data is completed, and a failure reported, exactly
    /// as for a request built by hand. Read the result with ``awaitChargeState(_:)``.
    ///
    /// - Parameters:
    ///   - cardToken: The card token to charge.
    ///   - browserData: The 3DS browser data. When `nil` the SDK derives it from the device via
    ///     ``BrowserData/deviceDefault()``; `ip` and `accept_header` are filled in by the charge
    ///     either way.
    ///   - challengePreference: 3DS challenge preference forwarded to the gateway.
    func chargeWithCardToken(
        _ cardToken: String,
        browserData: BrowserData? = nil,
        challengePreference: ChallengePreference? = nil
    ) async throws -> ChargePaymentResponse {
        try await reported {
            try await sendCharge(.cardToken(
                cardToken,
                browserData: await resolveBrowserData(browserData),
                challengePreference: challengePreference
            ))
        }
    }

    /// Charges the payment with a JWE-encrypted card, the `payload` that
    /// ``GopaySDK/encryptCardData(_:)`` or ``GopaySDK/submitCardForm(formId:)`` returned, without
    /// the server-side tokenization step.
    ///
    /// Builds ``ChargePaymentRequest/encryptedCard(_:browserData:challengePreference:)`` and sends
    /// it as ``charge(_:)`` would, so the browser data is completed, and a failure reported,
    /// exactly as for a request built by hand. Read the result with ``awaitChargeState(_:)``.
    ///
    /// - Parameters:
    ///   - payload: The JWE compact serialization. The gateway accepts each one once.
    ///   - browserData: The 3DS browser data. When `nil` the SDK derives it from the device via
    ///     ``BrowserData/deviceDefault()``; `ip` and `accept_header` are filled in by the charge
    ///     either way.
    ///   - challengePreference: 3DS challenge preference forwarded to the gateway.
    func chargeWithEncryptedCard(
        _ payload: String,
        browserData: BrowserData? = nil,
        challengePreference: ChallengePreference? = nil
    ) async throws -> ChargePaymentResponse {
        try await reported {
            try await sendCharge(.encryptedCard(
                payload,
                browserData: await resolveBrowserData(browserData),
                challengePreference: challengePreference
            ))
        }
    }
}
