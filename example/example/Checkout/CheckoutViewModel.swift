//
//  CheckoutViewModel.swift
//  example
//
//  Owns the whole checkout flow. This is the file to read if you want to see, in one place, how an
//  integration wires the SDK together:
//
//    when the checkout opens:  create payment (your server) -> startPaymentSession
//    when the shopper pays:    chargeWith...(...) -> awaitChargeState -> result
//
//  The payment and its session exist from the moment the checkout opens, as on the web, so the SDK
//  has the payment ready before the shopper pays. The pay button never creates a payment: every
//  method charges the checkout's session.
//
//  The wallet row follows the device alone. The gateway is asked for the wallet's configuration
//  only once the shopper has picked the wallet: `chargeWithWallet` fetches it itself.
//
//  Every payment method funnels into the same `runCharge` tail, because 3DS and result handling
//  are identical regardless of how the card data arrived: `awaitChargeState` polls the charge and
//  runs the 3DS challenge on the way.
//
//  A payment is single-use: once its charge failed, paying again needs a new one. So after a
//  decline the checkout closes the session and opens a new payment at once, behind the result
//  screen. An error from before a charge existed keeps the payment and its session.
//
//  A checkout left open for a long time is not handled here: the SDK renews the session's token on
//  its own, and a payment nobody charges times out on the gateway after an hour.
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
                "PaymentCardForm collects the card, submitCardForm() encrypts it into a JWE on device, and chargeWithEncryptedCard() sends it. The PAN never touches this app's code."
            case .applePay:
                "chargeWithWallet() presents the PassKit sheet configured from the gateway's /apple-pay/app-info and charges the resulting token. The same name charges with Google Pay on Android."
            case .savedCard:
                "A returning customer. encryptCardData() → your server's POST /cards/tokens → chargeWithCardToken(). Tokenization is simulated here by MerchantBackendSimulator."
            case .bankTransfer:
                "getQrPaymentInfo(format: .png) returns the recipient account and QR payloads to render for a manual transfer."
            }
        }
    }

    struct Outcome: Identifiable {
        let id = UUID()
        let state: ChargeState
        let response: ChargePaymentResponse?
        /// Why the charge failed, or what kept the checkout from learning its result.
        let message: String?
        /// The payment this result belongs to. After a decline the checkout already holds the
        /// next payment, and the result screen keeps showing the one that was declined.
        let paymentId: String
        /// The charge went out and reading its state failed, a network error above all: not the
        /// same as a charge the bank has not confirmed yet, and the result screen says so.
        var isUnread = false

        var isSuccess: Bool { state == .succeeded }
        var isFailure: Bool { state == .failed }
        /// The charge went out and something other than the read ended the wait for it, such as a
        /// 3DS challenge that could not be shown.
        var isUnfinished: Bool { !isSuccess && !isFailure && !isUnread && message != nil }
    }

    /// What the checkout needs from outside the SDK's session: the merchant backend, the session
    /// start, the card and the device. The tests put their own in.
    struct Services {
        var createPayment: (_ amount: Int, _ currency: String) async throws -> MerchantBackendSimulator.CreatedPayment
        var startSession: (_ paymentId: String, _ paymentSecret: String) async throws -> any PaymentSessionApi
        var submitCardForm: () async throws -> String
        var encryptCard: (GopayCardData) async throws -> String
        var tokenizeCard: (_ jwe: String) async throws -> String
        /// The synchronous device check, which a view body can read.
        var deviceCanUseWallet: () -> Bool

        static let live = Services(
            createPayment: { try await MerchantBackendSimulator.createPayment(amount: $0, currency: $1) },
            startSession: { try await GopaySDK.shared.startPaymentSession(paymentId: $0, paymentSecret: $1) },
            submitCardForm: { try await GopaySDK.shared.submitCardForm() },
            encryptCard: { try await GopaySDK.shared.encryptCardData($0) },
            tokenizeCard: { try await MerchantBackendSimulator.tokenizeCard(jwe: $0) },
            deviceCanUseWallet: { GopaySDK.canUseApplePay() }
        )
    }

    // MARK: - State

    let cart = DemoCart.sample

    var selectedMethod: Method = .card {
        // A banner speaks about the method it was raised for, a closed Apple Pay sheet for
        // instance, so it goes when the shopper picks another one.
        didSet { if selectedMethod != oldValue { banner = nil } }
    }
    /// `nil` follows the SDK/device default locale.
    var locale: String?
    var isCardFormValid = false
    var didAttemptSubmit = false

    /// Non-nil while a payment is in flight, a network call or a presented SDK sheet; carries the
    /// status text.
    var busyLabel: String?
    /// Transient, non-fatal message (cancellations, errors from before a charge existed).
    var banner: String?
    var outcome: Outcome?
    var qrDetails: QrPaymentDetails?

    /// Whether the checkout is creating its payment and starting the session.
    private(set) var isOpening = false
    /// Why the checkout could not open. Shown with "Try again", which only opens again.
    private(set) var openError: String?

    private(set) var paymentId: String?
    /// The session of the checkout's payment.
    private(set) var session: (any PaymentSessionApi)?
    /// The `callback.return_url` the current payment was created with; the 3DS challenge ends there.
    private var returnUrl: URL?
    /// Whether the current attempt's charge has gone out, which decides what a closed window means.
    private var chargeSent = false
    /// Whether the current payment is over, so the checkout needs a new one.
    private var paymentSpent = false
    /// Counts the times the checkout was left, so an opening that outlives its visit knows.
    private var visit = 0

    private let services: Services

    init(services: Services = .live) {
        self.services = services
    }

    var isBusy: Bool { busyLabel != nil }

    /// Paying needs the checkout's payment and session; the pay button never creates them.
    var canPay: Bool { session != nil && !isBusy && !isOpening }

    /// Apple Pay is hidden rather than shown dead, and the device alone decides: the checkout does
    /// not ask the gateway about the wallet when it opens. The wallet's configuration is fetched
    /// once the shopper has picked the wallet, by `chargeWithWallet` itself, and a payment that
    /// cannot be paid with it ends in a banner like any error from before a charge. A view body
    /// cannot `await`, so the device is read with the synchronous `canUseApplePay()`, which
    /// answers what the shared `isWalletAvailable()` answers.
    var availableMethods: [Method] {
        let wallet = services.deviceCanUseWallet()
        return Method.allCases.filter { $0 != .applePay || wallet }
    }

    /// What the pay button says instead of its title: the running payment's step, or that the
    /// checkout is still opening.
    var payButtonStatus: String? {
        busyLabel ?? (isOpening ? "Preparing your order…" : nil)
    }

    var payButtonTitle: String {
        switch selectedMethod {
        case .bankTransfer: "Show transfer details"
        case .applePay: "Pay with Apple Pay"
        default: "Pay \(cart.formatted(cart.total))"
        }
    }

    // MARK: - Opening

    /// Creates the payment on the merchant backend and starts its session. Called when the
    /// checkout appears and from "Try again"; with a session in place, or while one is being
    /// opened, it does nothing, so the checkout holds one payment per visit however often the
    /// view comes back on screen.
    func open() async {
        guard session == nil, !isOpening else { return }
        let visit = visit
        isOpening = true
        openError = nil
        defer { isOpening = false }
        do {
            let created = try await services.createPayment(cart.total, cart.currency)
            let started = try await services.startSession(created.paymentId, created.paymentSecret)
            guard visit == self.visit else {
                // The shopper left meanwhile. The payment stays `CREATED` and times out.
                await started.close()
                return
            }
            session = started
            paymentId = created.paymentId
            returnUrl = created.returnUrl
        } catch is CancellationError {
            // The checkout's own task going away, not the shopper: nothing left to show it on.
        } catch {
            guard visit == self.visit else { return }
            openError = "Couldn't prepare your order: \(Self.describe(error))"
        }
    }

    /// Closes the session of a payment that is over and opens a new payment, behind whatever the
    /// checkout is showing. The session is taken away before it is closed, so nothing pays it
    /// meanwhile, and a shopper who leaves during the close gets no new payment.
    private func replaceSpentPayment() async {
        guard paymentSpent else { return }
        paymentSpent = false
        let visit = visit
        let spent = session
        session = nil
        if let spent { await spent.close() }
        guard visit == self.visit else { return }
        await open()
    }

    // MARK: - Actions

    func pay() async {
        // Busy before the first `await`: a second tap queues its own task before the disabled
        // button renders, and that task must find this one already running.
        guard canPay, let session else { return }
        busyLabel = "Processing…"
        banner = nil
        chargeSent = false
        do {
            switch selectedMethod {
            case .card:        try await payWithNewCard(session)
            case .applePay:    try await payWithApplePay(session)
            case .savedCard:   try await payWithSavedCard(session)
            case .bankTransfer: try await showBankTransfer(session)
            }
        } catch is CancellationError {
            // The checkout's own task going away, not the shopper: nothing left to show it on.
        } catch let error as GopaySDKError where chargeSent {
            await settleAfterInterruption(error, session: session)
        } catch let error as GopaySDKError where error.code == .paymentCancelled {
            // The Apple Pay sheet closed before its charge went out: nothing was sent.
            banner = Self.pickAgain(after: error)
        } catch {
            // No charge exists, so the payment and its session stay: a banner, not a result.
            banner = Self.describe(error)
        }
        busyLabel = nil
        await replaceSpentPayment()
    }

    /// The payment was interrupted after its charge went out: PAYMENT_011, the 3DS challenge
    /// closed before it finished, PAYMENT_013, a charge the payment already had, a charge call
    /// that got a 5xx or no answer, a read that failed on the network or a 3DS challenge that
    /// could not be presented.
    ///
    /// That is not necessarily a payment that did not happen: after a 3DS challenge closed by the
    /// app, or one that failed once it was on screen, the shopper may already have confirmed the
    /// payment at the bank. So the payment is read with `getPaymentOutcome()` before anything is
    /// offered again:
    ///
    /// - paid: the result.
    /// - undecided: the charge is followed with `awaitChargeState`, which also finishes a 3DS
    ///   challenge the interrupted charge call never got to show. Only a challenge the shopper
    ///   closed themselves is left alone: that payment is given up for a new one.
    /// - declined: the failure, and a new payment as after any decline.
    /// - not charged: the soft banner. A payment that is still open stays, one that is over is
    ///   replaced.
    ///
    /// When the payment cannot be read, the result screen with its Refresh button stays up rather
    /// than a new payment being offered.
    private func settleAfterInterruption(_ first: GopaySDKError, session: any PaymentSessionApi) async {
        var error = first
        var lastRead: ChargePaymentResponse?
        while true {
            let read: PaymentOutcome
            do {
                busyLabel = "Checking the payment…"
                read = try await session.getPaymentOutcome()
            } catch is CancellationError {
                return
            } catch let readError {
                // The charge may be through, so no new payment: the result screen and its Refresh.
                outcome = Outcome(
                    state: lastRead?.state ?? .unknown,
                    response: lastRead,
                    message: "Couldn't check the payment: \(Self.describe(readError))",
                    paymentId: session.paymentId,
                    isUnread: true
                )
                return
            }
            lastRead = read.charge

            switch read.outcome {
            case .paid:
                outcome = Outcome(state: .succeeded, response: read.charge, message: nil, paymentId: session.paymentId)
                return
            case .declined:
                outcome = Outcome(state: .failed, response: read.charge, message: nil, paymentId: session.paymentId)
                paymentSpent = true
                return
            case .notCharged:
                // Back to the checkout, also from the result screen's Refresh. A payment that
                // is still open has no charge and can be paid; one that is over cannot.
                outcome = nil
                banner = Self.pickAgain(after: error)
                paymentSpent = read.payment.state == .canceled || read.payment.state == .timeouted
                return
            case .undecided:
                guard let charge = read.charge else {
                    // A payment state this SDK does not know: the pending screen and its Refresh.
                    outcome = Outcome(state: .unknown, response: nil, message: nil, paymentId: session.paymentId)
                    return
                }
                if charge.state == .actionRequired, error.code == .paymentCancelled {
                    // The shopper closed the bank's challenge. Nothing failed, so no failure
                    // screen, but this payment is not offered again.
                    outcome = nil
                    banner = Self.pickAgain(after: error)
                    paymentSpent = true
                    return
                }
                do {
                    outcome = try await settle(session: session)
                    return
                } catch is CancellationError {
                    return
                } catch let next as GopaySDKError where next.code == .paymentCancelled {
                    // A challenge shown by this wait and closed by the shopper: read again.
                    error = next
                } catch let waitError {
                    let unread = (waitError as? GopaySDKError)?.code.rawValue.hasPrefix("NETWORK_") ?? true
                    let reason = Self.describe(waitError)
                    outcome = Outcome(
                        state: charge.state,
                        response: charge,
                        message: unread ? "Couldn't check the payment: \(reason)" : reason,
                        paymentId: session.paymentId,
                        isUnread: unread
                    )
                    return
                }
            }
        }
    }

    /// Called from the result screen's "Try another method".
    func resumeShopping() {
        outcome = nil
        didAttemptSubmit = false
        isCardFormValid = false
    }

    /// Called when the checkout is dismissed for good. Closes the session and tells nobody: a
    /// payment left unpaid stays `CREATED`, and the gateway times it out after an hour. Nothing
    /// is kept for the next visit.
    func finish() async {
        visit += 1
        let leaving = session
        session = nil
        paymentId = nil
        returnUrl = nil
        openError = nil
        banner = nil
        paymentSpent = false
        // The checkout is reached through a `NavigationLink` whose destination SwiftUI keeps, and
        // with it this view model: going back and in again runs on the same instance. So what
        // the shopper picked would otherwise still be picked next time.
        selectedMethod = .card
        locale = nil
        didAttemptSubmit = false
        isCardFormValid = false
        if let leaving { await leaving.close() }
    }

    /// Waits for the charge again — used by the pending result screen.
    func refreshChargeState() async {
        guard let session, !isBusy else { return }
        busyLabel = "Refreshing…"
        do {
            outcome = try await settle(session: session)
        } catch is CancellationError {
            // The checkout's own task going away, not the shopper: nothing left to show it on.
        } catch let error as GopaySDKError {
            // The charge is out, so a failed refresh goes the same way as a closed challenge: the
            // payment is read once more, and the result screen stays up when it cannot be.
            await settleAfterInterruption(error, session: session)
        } catch {
            banner = error.localizedDescription
        }
        busyLabel = nil
        await replaceSpentPayment()
    }

    // MARK: - Flows

    private func payWithNewCard(_ session: any PaymentSessionApi) async throws {
        // `submitCardForm` switches the form's `.onSubmit` validation on itself, so an empty or
        // invalid card shows its errors here without the view model touching the form's
        // `submitAttempted` flag, as on Android.
        busyLabel = "Encrypting card…"
        let jwe: String
        do {
            jwe = try await services.submitCardForm()
        } catch let error as GopaySDKError where error.code == .validationInvalidInput {
            // The form is showing what is wrong; nothing more to say.
            return
        } catch let error as GopaySDKError where error.code == .validationCardFormEmpty {
            // Nothing typed yet, or the SDK wiped the card after the previous successful
            // encryption (GPMOB-140): the gateway accepts each JWE only once, so a retry needs the
            // card entered again. The form shows the required fields; the banner says why.
            banner = "Please enter your card details and try again."
            return
        }

        busyLabel = "Authorizing…"
        // The browser data is left to the SDK, which derives it from the device.
        try await runCharge(session: session) {
            try await session.chargeWithEncryptedCard(jwe, challengePreference: .auto)
        }
    }

    private func payWithApplePay(_ session: any PaymentSessionApi) async throws {
        busyLabel = "Waiting for Apple Pay…"
        // `chargeWithWallet` fetches the wallet's configuration for the payment itself, so the
        // checkout asks for it nowhere else. A device or a payment that cannot use the wallet
        // is its PAYMENT_004, a banner like any error from before a charge. A 5xx or a lost
        // answer while it fetches the configuration looks like one from the charge itself, so
        // `runCharge` reads the payment then too: it has no charge, which is the banner again.
        try await runCharge(session: session) { try await session.chargeWithWallet() }
    }

    private func payWithSavedCard(_ session: any PaymentSessionApi) async throws {
        // Stands in for a card the shopper saved on a previous order. In a real integration your
        // server holds the token; here we mint one on the fly from a known test card.
        busyLabel = "Loading saved card…"
        let card = GopayCardData(cardPan: "4444444444444448", expMonth: "12", expYear: "28", cvv: "123")
        let jwe = try await services.encryptCard(card)
        let token = try await services.tokenizeCard(jwe)

        busyLabel = "Authorizing…"
        try await runCharge(session: session) {
            try await session.chargeWithCardToken(token, challengePreference: .auto)
        }
    }

    /// The transfer details of the checkout's own payment. Showing them charges nothing, so the
    /// same payment can still be paid by card afterwards.
    private func showBankTransfer(_ session: any PaymentSessionApi) async throws {
        busyLabel = "Fetching transfer details…"
        qrDetails = try await session.getQrPaymentInfo(format: .png)
    }

    /// Charge, then settle. Shared by every card-based method.
    private func runCharge(session: any PaymentSessionApi, _ charge: () async throws -> ChargePaymentResponse) async throws {
        do {
            _ = try await charge()
        } catch let error as GopaySDKError where error.chargeMayExist {
            // The charge call failed, but a charge may still be on the payment: PAYMENT_013 (the
            // gateway has one already, e.g. from a double tap), a 5xx, or no answer at all. Marked
            // as sent, so `pay()` reads the payment like one whose answer was lost instead of
            // showing a failure, as the Android demo does. Only the charge call counts, the
            // wallet's included, which fetches its configuration first: the same codes from the
            // session start or the QR info mean no charge went out.
            chargeSent = true
            throw error
        }
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
    ///
    /// A payment is single-use: a failed charge marks it spent here, for every caller, and the
    /// checkout opens a new one at once rather than when the shopper asks to try again.
    private func settle(session: any PaymentSessionApi) async throws -> Outcome {
        busyLabel = "Confirming payment…"
        do {
            let charge = try await session.awaitChargeState(AwaitChargeOptions(
                returnUrl: returnUrl,
                onStateChange: { [weak self] charge in
                    if charge.state != .actionRequired { self?.busyLabel = "Confirming payment…" }
                },
                onActionRequired: { [weak self] _ in
                    self?.busyLabel = "Verifying with your bank…"
                }
            ))
            return Outcome(state: charge.state, response: charge, message: nil, paymentId: session.paymentId)
        } catch let error as GopaySDKError where error.code == .paymentDeclined {
            let charge = error.chargeState
            paymentSpent = true
            return Outcome(
                state: .failed, response: charge, message: charge?.failReason ?? error.message, paymentId: session.paymentId
            )
        } catch let error as GopaySDKError where error.code == .paymentTimeout {
            // Not decided yet: the pending screen, whose Refresh waits again.
            let charge = error.chargeState
            return Outcome(state: charge?.state ?? .processing, response: charge, message: nil, paymentId: session.paymentId)
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? GopaySDKError).map { "[\($0.code.rawValue)] \($0.message)" } ?? error.localizedDescription
    }

    private static func pickAgain(after error: Error) -> String {
        if let error = error as? GopaySDKError, error.code == .paymentCancelled {
            return "Payment cancelled. Pick a method and try again."
        }
        return "\(describe(error)). Pick a method and try again."
    }
}

extension GopaySDKError {
    /// Whether a charge call that threw this may still have left a charge on the payment: the
    /// gateway has one already, it answered with a 5xx, or no answer arrived at all.
    var chargeMayExist: Bool {
        switch code {
        case .paymentChargeAlreadyExists, .networkServerError:
            return true
        case .networkTimeout, .networkNoConnection, .networkSSLError, .networkIOError:
            return httpStatus == nil
        default:
            return false
        }
    }
}
