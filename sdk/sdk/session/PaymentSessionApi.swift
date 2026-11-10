import Foundation
import UIKit

/// Every call an integration makes on a ``PaymentSession``, as a protocol, so an app can put its
/// own implementation in its tests. ``PaymentSession`` is the SDK's implementation, and
/// ``GopaySDK/startPaymentSession(paymentId:paymentSecret:scope:)`` keeps returning it; let your
/// code depend on `PaymentSessionApi` and hand it either. The Android SDK has the same interface
/// under the same name.
///
/// What each call does, throws and reports is documented on ``PaymentSession``. The deprecated
/// names of 2.x are not part of the protocol.
///
/// A protocol requirement cannot carry a default argument, so the defaults ``PaymentSession``
/// offers are an extension below: a call through the protocol reads the same as one on the
/// session.
public protocol PaymentSessionApi {
    /// The payment this session belongs to.
    var paymentId: String { get }

    /// See ``PaymentSession/getStatus()``.
    func getStatus() async throws -> PaymentDetails
    /// See ``PaymentSession/getPaymentOutcome()``.
    func getPaymentOutcome() async throws -> PaymentOutcome
    /// See ``PaymentSession/charge(_:)``.
    func charge(_ request: ChargePaymentRequest) async throws -> ChargePaymentResponse
    /// See ``PaymentSession/chargeWithCardToken(_:browserData:challengePreference:)``.
    func chargeWithCardToken(
        _ cardToken: String,
        browserData: BrowserData?,
        challengePreference: ChallengePreference?
    ) async throws -> ChargePaymentResponse
    /// See ``PaymentSession/chargeWithEncryptedCard(_:browserData:challengePreference:)``.
    func chargeWithEncryptedCard(
        _ payload: String,
        browserData: BrowserData?,
        challengePreference: ChallengePreference?
    ) async throws -> ChargePaymentResponse
    /// See ``PaymentSession/completeBrowserData(_:)``.
    func completeBrowserData(_ browserData: BrowserData) async throws -> BrowserData
    /// See ``PaymentSession/getChargeState()``.
    func getChargeState() async throws -> ChargePaymentResponse
    /// See ``PaymentSession/awaitChargeState(_:)``.
    func awaitChargeState(_ options: AwaitChargeOptions) async throws -> ChargePaymentResponse
    /// See ``PaymentSession/getQrPaymentInfo(format:)``.
    func getQrPaymentInfo(format: QrCodeFormat?) async throws -> QrPaymentDetails
    /// See ``PaymentSession/getWalletInfo()``.
    func getWalletInfo() async throws -> GopayApplePayAppInfoResponse
    /// See ``PaymentSession/chargeWithWallet(browserData:challengePreference:)``.
    func chargeWithWallet(
        browserData: BrowserData?,
        challengePreference: ChallengePreference?
    ) async throws -> ChargePaymentResponse
    /// See ``PaymentSession/handle3dsVerification(redirectURL:returnUrl:presenting:)``.
    func handle3dsVerification(
        redirectURL: URL,
        returnUrl: URL?,
        presenting: UIViewController?
    ) async throws
    /// See ``PaymentSession/close()``.
    func close() async
}

extension PaymentSession: PaymentSessionApi {}

// The defaults of ``PaymentSession``, for a call through the protocol. Each one names every
// argument of the requirement it calls, so it cannot call itself.
public extension PaymentSessionApi {
    func chargeWithCardToken(_ cardToken: String) async throws -> ChargePaymentResponse {
        try await chargeWithCardToken(cardToken, browserData: nil, challengePreference: nil)
    }

    func chargeWithCardToken(_ cardToken: String, browserData: BrowserData?) async throws -> ChargePaymentResponse {
        try await chargeWithCardToken(cardToken, browserData: browserData, challengePreference: nil)
    }

    func chargeWithCardToken(
        _ cardToken: String,
        challengePreference: ChallengePreference?
    ) async throws -> ChargePaymentResponse {
        try await chargeWithCardToken(cardToken, browserData: nil, challengePreference: challengePreference)
    }

    func chargeWithEncryptedCard(_ payload: String) async throws -> ChargePaymentResponse {
        try await chargeWithEncryptedCard(payload, browserData: nil, challengePreference: nil)
    }

    func chargeWithEncryptedCard(_ payload: String, browserData: BrowserData?) async throws -> ChargePaymentResponse {
        try await chargeWithEncryptedCard(payload, browserData: browserData, challengePreference: nil)
    }

    func chargeWithEncryptedCard(
        _ payload: String,
        challengePreference: ChallengePreference?
    ) async throws -> ChargePaymentResponse {
        try await chargeWithEncryptedCard(payload, browserData: nil, challengePreference: challengePreference)
    }

    func awaitChargeState() async throws -> ChargePaymentResponse {
        try await awaitChargeState(AwaitChargeOptions())
    }

    func getQrPaymentInfo() async throws -> QrPaymentDetails {
        try await getQrPaymentInfo(format: nil)
    }

    func chargeWithWallet() async throws -> ChargePaymentResponse {
        try await chargeWithWallet(browserData: nil, challengePreference: nil)
    }

    func chargeWithWallet(browserData: BrowserData?) async throws -> ChargePaymentResponse {
        try await chargeWithWallet(browserData: browserData, challengePreference: nil)
    }

    func chargeWithWallet(challengePreference: ChallengePreference?) async throws -> ChargePaymentResponse {
        try await chargeWithWallet(browserData: nil, challengePreference: challengePreference)
    }

    func handle3dsVerification(redirectURL: URL) async throws {
        try await handle3dsVerification(redirectURL: redirectURL, returnUrl: nil, presenting: nil)
    }

    func handle3dsVerification(redirectURL: URL, returnUrl: URL?) async throws {
        try await handle3dsVerification(redirectURL: redirectURL, returnUrl: returnUrl, presenting: nil)
    }

    func handle3dsVerification(redirectURL: URL, presenting: UIViewController?) async throws {
        try await handle3dsVerification(redirectURL: redirectURL, returnUrl: nil, presenting: presenting)
    }
}
