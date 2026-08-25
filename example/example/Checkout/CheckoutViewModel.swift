//
//  CheckoutViewModel.swift
//  example
//
//  Owns the whole checkout flow. This is the file to read if you want to see, in one place, how an
//  integration wires the SDK together:
//
//    create payment (your server) -> startPaymentSession -> charge(...) -> 3DS -> final state
//
//  Every payment method funnels into the same `runCharge` tail, because 3DS and result handling
//  are identical regardless of how the card data arrived.
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
        do {
            switch selectedMethod {
            case .card:        try await payWithNewCard()
            case .applePay:    try await payWithApplePay()
            case .savedCard:   try await payWithSavedCard()
            case .bankTransfer: try await showBankTransfer()
            }
        } catch is CancellationError {
            // The shopper backed out of the Apple Pay or 3DS sheet — that is not a failed payment.
            banner = "Payment cancelled. Pick a method and try again."
        } catch let error as GopaySDKError {
            fail(message: "[\(error.code.rawValue)] \(error.message)")
        } catch {
            fail(message: error.localizedDescription)
        }
        busyLabel = nil
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

    /// Re-reads the charge and resumes polling — used by the pending result screen.
    func refreshChargeState() async {
        guard let session else { return }
        busyLabel = "Refreshing…"
        defer { busyLabel = nil }
        do {
            let charge = try await session.getChargeState()
            let settled = try await settle(session: session, initial: charge)
            outcome = Outcome(state: settled.state, response: settled, message: settled.failReason)
        } catch is CancellationError {
            banner = "Verification cancelled."
        } catch let error as GopaySDKError {
            banner = "[\(error.code.rawValue)] \(error.message)"
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
        let response = try await charge()
        let settled = try await settle(session: session, initial: response)
        outcome = Outcome(state: settled.state, response: settled, message: settled.failReason)
    }

    /// Drives a charge to a terminal state, exactly the way a merchant backend would: poll
    /// `GET /payments/{id}/charge` on an interval until the gateway reports SUCCEEDED or FAILED.
    ///
    /// `ACTION_REQUIRED` is a normal step of that loop, not a failure — whenever the gateway hands
    /// back a 3DS `redirect_url` we haven't seen yet, the SDK's verification web view is presented
    /// inline and polling continues afterwards. Each redirect is run once so a gateway that keeps
    /// echoing the same action can't loop the shopper through the challenge repeatedly.
    ///
    /// If the charge is still in flight when the budget runs out we return the last response as-is;
    /// the result screen then shows "pending" with a Refresh button that re-enters this loop.
    private func settle(session: PaymentSession, initial: ChargePaymentResponse) async throws -> ChargePaymentResponse {
        var response = initial
        var handledRedirects = Set<String>()
        var attempts = 0

        while true {
            if let redirect = response.action?.redirectUrl,
               let url = URL(string: redirect),
               handledRedirects.insert(redirect).inserted {
                busyLabel = "Verifying with your bank…"
                try await session.handle3dsVerification(redirectURL: url)
            }

            switch response.state {
            case .succeeded, .failed:
                return response
            case .requested, .processing, .actionRequired:
                break
            }

            guard attempts < Self.maxPollAttempts else { return response }
            attempts += 1

            busyLabel = attempts == 1 ? "Confirming payment…" : "Still confirming… (\(attempts))"
            try await Task.sleep(for: .seconds(Self.pollInterval))
            response = try await session.getChargeState()
        }
    }

    /// ~45 s of polling — long enough for a slow issuer, short enough that the shopper isn't
    /// stranded on a spinner.
    private static let pollInterval: Double = 1.5
    private static let maxPollAttempts = 30

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
        return started
    }

    private func fail(message: String) {
        outcome = Outcome(state: .failed, response: nil, message: message)
    }
}
