//
//  CheckoutViewModel.swift
//  example
//
//  Owns the whole checkout flow. This is the file to read if you want to see, in one place, how an
//  integration wires the SDK together:
//
//    create payment (your server) -> startPaymentSession -> charge(...) -> awaitChargeState -> result
//
//  Every payment method funnels into the same `runCharge` tail, because 3DS and result handling
//  are identical regardless of how the card data arrived: `awaitChargeState` polls the charge and
//  runs the 3DS challenge on the way.
//
//  Each tap of the pay button starts that sequence from the top with a brand-new payment — a
//  payment is single-use, so a retry after a decline needs a new one.
//

import Foundation
import SwiftUI
import GopaySDK

@MainActor
@Observable
final class CheckoutViewModel {

    // MARK: - Types

    enum Method: String, CaseIterable, Identifiable {
        case card
        case applePay
        case savedCard
        case bankTransfer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .card: "Credit or debit card"
            case .applePay: "Apple Pay"
            case .savedCard: "Saved card"
            case .bankTransfer: "Bank transfer"
            }
        }

        var subtitle: String {
            switch self {
            case .card: "Visa, Mastercard"
            case .applePay: "Pay with Face ID"
            case .savedCard: "•••• 4448 · exp 12/28"
            case .bankTransfer: "QR code and account details"
            }
        }

        var symbol: String {
            switch self {
            case .card: "creditcard.fill"
            case .applePay: "applelogo"
            case .savedCard: "checkmark.seal.fill"
            case .bankTransfer: "qrcode"
            }
        }

        /// One line explaining which part of the SDK this row exercises.
        var sdkNote: String {
            switch self {
            case .card:
                "GopayCardForm collects the card, submitCardForm() encrypts it into a JWE on device, and charge(.encryptedCard) sends it. The PAN never touches this app's code."
            case .applePay:
                "chargeWithApplePay() presents the PassKit sheet configured from the gateway's /apple-pay/app-info and charges the resulting token."
            case .savedCard:
                "A returning customer. encryptCardData() → your server's POST /cards/tokens → charge(.cardToken). Tokenization is simulated here by MerchantBackendSimulator."
            case .bankTransfer:
                "getQrPaymentInfo(format: .png) returns the recipient account and QR payloads to render for a manual transfer."
            }
        }
    }

    struct Outcome: Identifiable {
        let id = UUID()
        let state: ChargeState
        let response: ChargePaymentResponse?
        /// Populated when the flow failed before the gateway returned a charge.
        let message: String?

        var isSuccess: Bool { state == .succeeded }
        var isFailure: Bool { state == .failed }
    }

    // MARK: - State

    let cart = DemoCart.sample

    var selectedMethod: Method = .card
    /// `nil` follows the SDK/device default locale.
    var locale: String?
    var isCardFormValid: Bool?
    var didAttemptSubmit = false

    /// Non-nil while a network call or a presented SDK sheet is in flight; carries the status text.
    var busyLabel: String?
    /// Transient, non-fatal message (cancellations, QR failures).
    var banner: String?
    var outcome: Outcome?
    var qrDetails: QrPaymentDetails?

    private(set) var paymentId: String?
    private var session: PaymentSession?
    /// The `callback.return_url` the current payment was created with; the 3DS challenge ends there.
    private var returnURL: URL?
    /// Whether the current attempt's charge has gone out, which decides what a closed window means.
    private var chargeSent = false

    var isBusy: Bool { busyLabel != nil }

    /// Apple Pay is hidden rather than shown dead when the device can't pay.
    var availableMethods: [Method] {
        Method.allCases.filter { $0 != .applePay || GopaySDK.canUseApplePay() }
    }

    var payButtonTitle: String {
        switch selectedMethod {
        case .bankTransfer: "Show transfer details"
        case .applePay: "Pay with Apple Pay"
        default: "Pay \(cart.formatted(cart.total))"
        }
    }

    // MARK: - Actions

    func pay() async {
        banner = nil
        chargeSent = false
        do {
            switch selectedMethod {
            case .card:        try await payWithNewCard()
            case .applePay:    try await payWithApplePay()
            case .savedCard:   try await payWithSavedCard()
            case .bankTransfer: try await showBankTransfer()
            }
        } catch is CancellationError {
            // The checkout's own task going away, not the shopper: nothing left to show it on.
        } catch let error as GopaySDKError where error.code == .paymentCancelled || chargeSent {
            await settleAfterInterruption(error)
        } catch let error as GopaySDKError {
            fail(message: "[\(error.code.rawValue)] \(error.message)")
        } catch {
            fail(message: error.localizedDescription)
        }
        busyLabel = nil
    }

    /// The payment was interrupted: PAYMENT_011, the Apple Pay sheet or the 3DS challenge closed
    /// before it finished, or any other error once the charge had gone out, such as a read that
    /// failed on the network or a 3DS challenge that could not be presented.
    ///
    /// An Apple Pay sheet closed before its charge went out sends nothing, so a soft banner is all
    /// it takes. After the charge went out it is not necessarily a payment that did not happen:
    /// after a 3DS challenge closed by the app, or one that failed once it was on screen, the
    /// shopper may already have confirmed the payment at the bank. So the charge is read before a
    /// new payment is offered: a result is shown, an undecided charge is polled, and only a charge
    /// the gateway says does not exist, or one that did not go through, gets the soft banner. When
    /// the charge cannot be read, the pending screen with its Refresh button stays up rather than
    /// a new payment being offered.
    private func settleAfterInterruption(_ error: GopaySDKError) async {
        let pickAgain = error.code == .paymentCancelled
            ? "Payment cancelled. Pick a method and try again."
            : "[\(error.code.rawValue)] \(error.message). Pick a method and try again."
        guard chargeSent, let session else {
            banner = pickAgain
            return
        }
        var lastRead: ChargePaymentResponse?
        do {
            busyLabel = "Checking the payment…"
            let charge = try await session.getChargeState()
            lastRead = charge
            switch charge.state {
            case .succeeded:
                outcome = Outcome(state: charge.state, response: charge, message: nil)
            case .requested, .processing, .unknown:
                outcome = try await settle(session: session)
            case .failed, .actionRequired:
                // Back to the checkout, also from the pending screen's Refresh.
                outcome = nil
                banner = pickAgain
            }
        } catch let error as GopaySDKError where error.code == .networkClientError && error.httpStatus == 404 {
            // The gateway confirms there is no charge on this payment: nothing went out.
            outcome = nil
            banner = pickAgain
        } catch is CancellationError {
            // The checkout's own task going away, not the shopper: nothing left to show it on.
        } catch {
            // The charge may be through, so no new payment: the pending screen and its Refresh.
            let reason = (error as? GopaySDKError).map { "[\($0.code.rawValue)] \($0.message)" }
                ?? error.localizedDescription
            outcome = Outcome(
                state: lastRead?.state ?? .unknown,
                response: lastRead,
                message: "Couldn't check the payment: \(reason)"
            )
        }
    }

    /// Called from the result screen's "Try another method".
    func resumeShopping() {
        outcome = nil
        didAttemptSubmit = false
        isCardFormValid = nil
    }

    /// Called when the checkout is dismissed for good.
    func finish() async {
        if let session { await session.close() }
        session = nil
        paymentId = nil
    }

    /// Waits for the charge again — used by the pending result screen.
    func refreshChargeState() async {
        guard let session else { return }
        busyLabel = "Refreshing…"
        defer { busyLabel = nil }
        do {
            outcome = try await settle(session: session)
        } catch is CancellationError {
            // The checkout's own task going away, not the shopper: nothing left to show it on.
        } catch let error as GopaySDKError {
            // The charge is out, so a failed refresh goes the same way as a closed challenge: the
            // state is read once more, and the pending screen stays up when it cannot be.
            await settleAfterInterruption(error)
        } catch {
            banner = error.localizedDescription
        }
    }

    // MARK: - Flows

    private func payWithNewCard() async throws {
        // Reveal the form's inline validation before doing anything expensive.
        didAttemptSubmit = true
        guard isCardFormValid != false else { return }

        let session = try await startNewSession()
        busyLabel = "Encrypting card…"
        let jwe: String
        do {
            jwe = try await GopaySDK.shared.submitCardForm()
        } catch let error as GopaySDKError where error.message == GopaySDKErrors.noCardFormData {
            // The SDK wiped the card data after the previous successful encryption (GPMOB-140),
            // and the gateway accepts each JWE only once — so a retry needs the card confirmed
            // again. Any edit in the form re-syncs its data and the next Pay succeeds.
            busyLabel = nil
            banner = "Please re-enter your card details and try again."
            return
        }

        busyLabel = "Authorizing…"
        let request = ChargePaymentRequest.encryptedCard(
            jwe,
            browserData: await BrowserData.deviceDefault(),
            challengePreference: .auto
        )
        try await runCharge(session: session) { try await session.charge(request) }
    }

    private func payWithApplePay() async throws {
        guard GopaySDK.canUseApplePay() else {
            banner = "Apple Pay is not available on this device."
            return
        }
        let session = try await startNewSession()
        busyLabel = "Waiting for Apple Pay…"
        try await runCharge(session: session) { try await session.chargeWithApplePay() }
    }

    private func payWithSavedCard() async throws {
        let session = try await startNewSession()

        // Stands in for a card the shopper saved on a previous order. In a real integration your
        // server holds the token; here we mint one on the fly from a known test card.
        busyLabel = "Loading saved card…"
        let card = GopayCardData(cardPan: "4444444444444448", expMonth: "12", expYear: "28", cvv: "123")
        let jwe = try await GopaySDK.shared.encryptCardData(card)
        let token = try await MerchantBackendSimulator.tokenizeCard(jwe: jwe)

        busyLabel = "Authorizing…"
        let request = ChargePaymentRequest.cardToken(
            token,
            browserData: await BrowserData.deviceDefault(),
            challengePreference: .auto
        )
        try await runCharge(session: session) { try await session.charge(request) }
    }

    private func showBankTransfer() async throws {
        let session = try await startNewSession()
        busyLabel = "Fetching transfer details…"
        qrDetails = try await session.getQrPaymentInfo(format: .png)
    }

    /// Charge, then settle. Shared by every card-based method.
    private func runCharge(session: PaymentSession, _ charge: () async throws -> ChargePaymentResponse) async throws {
        _ = try await charge()
        chargeSent = true
        outcome = try await settle(session: session)
    }

    /// Drives the charge to a result with the SDK's `awaitChargeState`: it reads
    /// `GET /payments/{id}/charge` once a second, runs a 3DS challenge inline whenever the gateway
    /// hands back a new `redirect_url` (the return URL is the one the payment was created with),
    /// and returns the charge once it is `succeeded`.
    ///
    /// A charge that ended `failed` arrives as `PAYMENT_006` with the charge attached, which is
    /// the failure screen. One that is still undecided after the initial 30 seconds arrives as
    /// `PAYMENT_007`: not a result, so the pending screen shows the last state read, with a
    /// Refresh button that comes back here. Anything else, a closed 3DS screen (`PAYMENT_011`)
    /// included, propagates to the caller.
    private func settle(session: PaymentSession) async throws -> Outcome {
        busyLabel = "Confirming payment…"
        do {
            let charge = try await session.awaitChargeState(AwaitChargeOptions(
                returnURL: returnURL,
                onStateChange: { [weak self] charge in
                    if charge.state != .actionRequired { self?.busyLabel = "Confirming payment…" }
                },
                onActionRequired: { [weak self] _ in
                    self?.busyLabel = "Verifying with your bank…"
                }
            ))
            return Outcome(state: charge.state, response: charge, message: nil)
        } catch let error as GopaySDKError where error.code == .paymentDeclined {
            let charge = error.chargeState
            return Outcome(state: .failed, response: charge, message: charge?.failReason ?? error.message)
        } catch let error as GopaySDKError where error.code == .paymentTimeout {
            // Not decided yet: the pending screen, whose Refresh waits again.
            let charge = error.chargeState
            return Outcome(state: charge?.state ?? .processing, response: charge, message: nil)
        }
    }

    /// Creates a *fresh* payment on the simulated merchant backend and opens a session for it.
    ///
    /// Called on every pay attempt, not once per checkout. A payment is single-use: once it has
    /// been charged the gateway won't accept another charge on the same `payment_id`, so reusing
    /// the session would leave the shopper stuck after a decline with no way to try another
    /// method. A real shop behaves the same way — a retry means a new payment.
    private func startNewSession() async throws -> PaymentSession {
        if let session { await session.close() }
        session = nil

        busyLabel = "Preparing your order…"
        let created = try await MerchantBackendSimulator.createPayment(
            amount: cart.total,
            currency: cart.currency
        )
        let started = try await GopaySDK.shared.startPaymentSession(
            paymentId: created.paymentId,
            paymentSecret: created.paymentSecret
        )
        session = started
        paymentId = created.paymentId
        returnURL = created.returnURL
        return started
    }

    private func fail(message: String) {
        outcome = Outcome(state: .failed, response: nil, message: message)
    }
}
