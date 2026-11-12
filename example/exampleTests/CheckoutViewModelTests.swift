//
//  CheckoutViewModelTests.swift
//  exampleTests
//
//  The checkout opens its payment and session when it appears, and the pay button only charges
//  that session. A decline is the one thing that replaces the payment; an error from before a
//  charge existed keeps it.
//
//  A second tap queues its own task before the disabled button renders, so the busy check inside
//  the view model is what keeps one payment from going out twice.
//

import Foundation
import Testing
import UIKit
@testable import example
@testable import GopaySDK

@MainActor
struct CheckoutViewModelTests {

    // MARK: - Fakes

    /// A session whose answers the test scripts. Nothing leaves the process.
    final class FakeSession: PaymentSessionApi, @unchecked Sendable {
        let paymentId: String
        var chargeResult: Result<ChargePaymentResponse, Error> = .success(ChargePaymentResponse(id: "ch", state: .requested))
        /// One answer per `awaitChargeState`, in order; the last one repeats.
        var waits: [Result<ChargePaymentResponse, Error>] = [.success(ChargePaymentResponse(id: "ch", state: .succeeded))]
        var outcomeResult: Result<PaymentOutcome, Error> = .failure(URLError(.notConnectedToInternet))
        private(set) var charges = 0
        private(set) var waitCalls = 0
        private(set) var outcomeReads = 0
        private(set) var chargeStateReads = 0
        private(set) var qrReads = 0
        private(set) var walletInfoReads = 0
        private(set) var closed = false
        /// Suspends `close()` until the test lets it through.
        var holdsClose = false
        var closeGate: CheckedContinuation<Void, Never>?

        init(paymentId: String) { self.paymentId = paymentId }

        func outcome(_ outcome: PaymentOutcome.Outcome, payment: PaymentState, charge: ChargeState?) -> PaymentOutcome {
            PaymentOutcome(outcome: outcome, payment: PaymentDetails(
                id: paymentId, orderNumber: "ORD-1", state: payment, amount: 1000, currency: .czk,
                gatewayUrl: "https://gw.invalid/p", customer: PaymentCustomer(email: "jan@example.com"),
                charge: charge.map { ChargePaymentResponse(id: "ch", state: $0) }
            ))
        }

        private func sendCharge() throws -> ChargePaymentResponse {
            charges += 1
            return try chargeResult.get()
        }

        func getStatus() async throws -> PaymentDetails { try outcomeResult.get().payment }
        func getPaymentOutcome() async throws -> PaymentOutcome {
            outcomeReads += 1
            return try outcomeResult.get()
        }
        func charge(_ request: ChargePaymentRequest) async throws -> ChargePaymentResponse { try sendCharge() }
        func chargeWithCardToken(
            _ cardToken: String, browserData: BrowserData?, challengePreference: ChallengePreference?
        ) async throws -> ChargePaymentResponse { try sendCharge() }
        func chargeWithEncryptedCard(
            _ payload: String, browserData: BrowserData?, challengePreference: ChallengePreference?
        ) async throws -> ChargePaymentResponse { try sendCharge() }
        func completeBrowserData(_ browserData: BrowserData) async throws -> BrowserData { browserData }
        func getChargeState() async throws -> ChargePaymentResponse {
            chargeStateReads += 1
            throw URLError(.notConnectedToInternet)
        }
        func awaitChargeState(_ options: AwaitChargeOptions) async throws -> ChargePaymentResponse {
            defer { waitCalls += 1 }
            return try waits[min(waitCalls, waits.count - 1)].get()
        }
        func getQrPaymentInfo(format: QrCodeFormat?) async throws -> QrPaymentDetails {
            qrReads += 1
            throw GopaySDKError(.networkClientError, message: "no QR in this test", httpStatus: 400)
        }
        func getWalletInfo() async throws -> GopayApplePayAppInfoResponse {
            walletInfoReads += 1
            throw GopaySDKError(.networkClientError, message: "no wallet info in this test", httpStatus: 403)
        }
        func chargeWithWallet(
            browserData: BrowserData?, challengePreference: ChallengePreference?
        ) async throws -> ChargePaymentResponse { try sendCharge() }
        func handle3dsVerification(redirectUrl: URL, returnUrl: URL?, presenting: UIViewController?) async throws {}
        func close() async {
            if holdsClose {
                await withCheckedContinuation { closeGate = $0 }
            }
            closed = true
        }
    }

    /// Stands in for the merchant backend and the session start: every payment it creates gets
    /// the next id, `p1`, `p2`, and a fake session of its own.
    @MainActor
    final class Shop {
        var createError: Error?
        var deviceCanUseWallet = true
        var tokenizeError: Error?
        /// Suspends the session start until the test lets it through.
        var gate: CheckedContinuation<Void, Never>?
        var holdsSessionStart = false
        private(set) var created = 0
        private(set) var sessions: [FakeSession] = []

        var services: CheckoutViewModel.Services {
            CheckoutViewModel.Services(
                createPayment: { [self] _, _ in
                    if let createError { throw createError }
                    created += 1
                    return .init(paymentId: "p\(created)", paymentSecret: "secret", returnUrl: nil)
                },
                startSession: { [self] paymentId, _ in
                    if holdsSessionStart {
                        await withCheckedContinuation { gate = $0 }
                    }
                    let session = FakeSession(paymentId: paymentId)
                    sessions.append(session)
                    return session
                },
                submitCardForm: { "jwe" },
                encryptCard: { _ in "jwe" },
                tokenizeCard: { [self] _ in
                    if let tokenizeError { throw tokenizeError }
                    return "token"
                },
                deviceCanUseWallet: { [self] in deviceCanUseWallet }
            )
        }
    }

    private func error(_ code: GopaySDKError.Code, status: Int? = nil, charge: ChargePaymentResponse? = nil) -> GopaySDKError {
        GopaySDKError(code, message: code.rawValue, httpStatus: status, chargeState: charge)
    }

    /// An open checkout that pays with the saved card, the method whose every step is faked.
    private func openCheckout(_ shop: Shop) async -> CheckoutViewModel {
        let model = CheckoutViewModel(services: shop.services)
        await model.open()
        model.selectedMethod = .savedCard
        return model
    }

    // MARK: - Opening

    /// The checkout creates its payment and starts the session when it opens, and only once: the
    /// view coming back on screen runs `open()` again and gets nothing new.
    @Test func openingCreatesOnePaymentAndItsSession() async {
        let shop = Shop()
        let model = CheckoutViewModel(services: shop.services)
        #expect(!model.canPay)

        await model.open()
        await model.open()

        #expect(shop.created == 1)
        #expect(shop.sessions.count == 1)
        #expect(model.paymentId == "p1")
        #expect(model.canPay)
        #expect(model.openError == nil)
        #expect(shop.sessions[0].charges == 0)
    }

    /// Two openings at once, as a view that appears twice in a row would start, make one payment.
    @Test func openingTwiceAtOnceCreatesOnePayment() async {
        let shop = Shop()
        let model = CheckoutViewModel(services: shop.services)

        async let first: Void = model.open()
        async let second: Void = model.open()
        _ = await (first, second)

        #expect(shop.created == 1)
        #expect(model.paymentId == "p1")
    }

    /// A checkout that could not open says so and cannot pay. The pay action creates nothing;
    /// only opening again does.
    @Test func aFailedOpeningIsRetriedOnlyByOpeningAgain() async {
        let shop = Shop()
        shop.createError = URLError(.notConnectedToInternet)
        let model = CheckoutViewModel(services: shop.services)

        await model.open()
        #expect(model.openError?.hasPrefix("Couldn't prepare your order: ") == true)
        #expect(!model.canPay)
        #expect(model.outcome == nil)

        shop.createError = nil
        await model.pay()
        #expect(shop.created == 0)
        #expect(model.session == nil)

        await model.open()
        #expect(shop.created == 1)
        #expect(model.openError == nil)
        #expect(model.canPay)
    }

    /// A session that cannot start is a failed opening as well, with the SDK's code in the text.
    @Test func aSessionThatCannotStartIsAFailedOpening() async {
        let model = CheckoutViewModel(services: {
            var services = Shop().services
            services.startSession = { _, _ in
                throw GopaySDKError(.networkNoConnection, message: "offline")
            }
            return services
        }())

        await model.open()

        #expect(model.openError == "Couldn't prepare your order: [NETWORK_004] offline")
        #expect(model.paymentId == nil)
        #expect(!model.canPay)
    }

    /// Leaving while the checkout is still opening closes the session that opening then gets,
    /// and the checkout keeps nothing of it.
    @Test func leavingDuringTheOpeningClosesItsSession() async {
        let shop = Shop()
        shop.holdsSessionStart = true
        let model = CheckoutViewModel(services: shop.services)

        let opening = Task { await model.open() }
        while shop.gate == nil { await Task.yield() }
        await model.finish()
        shop.gate?.resume()
        await opening.value

        #expect(shop.sessions.count == 1)
        #expect(shop.sessions[0].closed)
        #expect(model.session == nil)
        #expect(model.paymentId == nil)
    }

    /// Leaving closes the session and nothing else, and the next visit starts clean.
    @Test func leavingClosesTheSessionAndForgetsTheVisit() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        model.banner = "Payment cancelled. Pick a method and try again."
        model.locale = "de"

        await model.finish()

        #expect(model.locale == nil)
        #expect(shop.sessions[0].closed)
        #expect(shop.sessions[0].charges == 0)
        #expect(model.session == nil)
        #expect(model.paymentId == nil)
        #expect(model.selectedMethod == .card)
        #expect(model.banner == nil)

        await model.open()
        #expect(model.paymentId == "p2")
    }

    // MARK: - The wallet row

    /// The device alone decides about the row, before the checkout has opened and after.
    @Test func theWalletRowFollowsTheDeviceAlone() async {
        let shop = Shop()
        let model = CheckoutViewModel(services: shop.services)
        #expect(model.availableMethods.contains(.applePay))

        await model.open()
        #expect(model.availableMethods.contains(.applePay))

        shop.deviceCanUseWallet = false
        #expect(!model.availableMethods.contains(.applePay))
    }

    /// Opening the checkout does not ask the gateway about the wallet, and neither does paying
    /// with it: `chargeWithWallet` fetches the wallet's configuration itself.
    @Test func theCheckoutNeverAsksForTheWalletInfo() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        #expect(shop.sessions[0].walletInfoReads == 0)

        model.selectedMethod = .applePay
        await model.pay()

        #expect(shop.sessions[0].walletInfoReads == 0)
        #expect(shop.sessions[0].charges == 1)
    }

    /// A payment the wallet cannot pay is found out when the shopper picks the wallet, and is an
    /// error from before a charge: a banner on the same payment.
    @Test func aPaymentTheWalletCannotPayIsABannerOnTheSamePayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        model.selectedMethod = .applePay
        shop.sessions[0].chargeResult = .failure(error(.paymentMethodUnavailable))

        await model.pay()

        #expect(model.banner == "[PAYMENT_004] PAYMENT_004")
        #expect(model.outcome == nil)
        #expect(shop.created == 1)
        #expect(model.paymentId == "p1")
        #expect(!shop.sessions[0].closed)
        #expect(model.canPay)
    }

    // MARK: - Paying

    /// Paying charges the checkout's session: no new payment, no new session.
    @Test func payingChargesTheCheckoutsSession() async {
        let shop = Shop()
        let model = await openCheckout(shop)

        await model.pay()

        #expect(shop.created == 1)
        #expect(shop.sessions[0].charges == 1)
        #expect(model.outcome?.isSuccess == true)
        #expect(model.outcome?.paymentId == "p1")
        #expect(!shop.sessions[0].closed)
    }

    /// A declined payment is over. The result stays on screen with the declined payment's number
    /// while the checkout closes its session and opens the next payment.
    @Test func aDeclineOpensANewPaymentBehindTheResult() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let failed = ChargePaymentResponse(id: "ch", state: .failed, failReason: "insufficient funds")
        shop.sessions[0].waits = [.failure(error(.paymentDeclined, charge: failed))]

        await model.pay()

        #expect(model.outcome?.isFailure == true)
        #expect(model.outcome?.message == "insufficient funds")
        #expect(model.outcome?.paymentId == "p1")
        #expect(shop.sessions[0].closed)
        #expect(shop.created == 2)
        #expect(model.paymentId == "p2")
        #expect(!model.isBusy)

        model.resumeShopping()
        #expect(model.canPay)
        #expect(model.selectedMethod == .savedCard)
    }

    /// An error from before a charge existed is a banner on the same payment, not a result:
    /// here the wallet's PAYMENT_003 and a charge call the gateway refused.
    @Test func anErrorBeforeTheChargeKeepsThePayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)

        model.selectedMethod = .applePay
        shop.sessions[0].chargeResult = .failure(error(.paymentProcessingFailed))
        await model.pay()
        #expect(model.banner == "[PAYMENT_003] PAYMENT_003")

        model.selectedMethod = .savedCard
        shop.sessions[0].chargeResult = .failure(error(.networkClientError, status: 422))
        await model.pay()
        #expect(model.banner == "[NETWORK_002] NETWORK_002")

        #expect(model.outcome == nil)
        #expect(shop.created == 1)
        #expect(model.paymentId == "p1")
        #expect(!shop.sessions[0].closed)
        #expect(shop.sessions[0].outcomeReads == 0)
        #expect(model.canPay)
    }

    /// A saved card that cannot be tokenized never reaches the charge: a banner, the same payment.
    @Test func aFailedTokenizationKeepsThePayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        shop.tokenizeError = error(.networkClientError, status: 422)

        await model.pay()

        #expect(model.banner == "[NETWORK_002] NETWORK_002")
        #expect(model.outcome == nil)
        #expect(shop.sessions[0].charges == 0)
        #expect(shop.sessions[0].outcomeReads == 0)
        #expect(shop.created == 1)
        #expect(model.canPay)
    }

    /// A 5xx or a lost answer while `chargeWithWallet` fetches the wallet's configuration cannot
    /// be told from one of the charge itself, so the payment is read: it has no charge, which is
    /// the banner on the same payment.
    @Test(arguments: [(GopaySDKError.Code.networkServerError, 500 as Int?), (.networkTimeout, nil)])
    func aWalletConfigurationThatFailsOnTheServerIsReadAsAnInterruptedCharge(
        code: GopaySDKError.Code, status: Int?
    ) async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        model.selectedMethod = .applePay
        session.chargeResult = .failure(error(code, status: status))
        session.outcomeResult = .success(session.outcome(.notCharged, payment: .created, charge: nil))

        await model.pay()

        #expect(session.outcomeReads == 1)
        #expect(model.banner == "[\(code.rawValue)] \(code.rawValue). Pick a method and try again.")
        #expect(model.outcome == nil)
        #expect(shop.created == 1)
        #expect(!session.closed)
    }

    /// When that read fails as well, the checkout cannot know that nothing was charged: the
    /// result screen with its Refresh, and the same payment.
    @Test func aWalletConfigurationFailureThatCannotBeReadKeepsItsResultScreen() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        model.selectedMethod = .applePay
        session.chargeResult = .failure(error(.networkServerError, status: 500))
        session.outcomeResult = .failure(error(.networkNoConnection))

        await model.pay()

        #expect(model.outcome?.isUnread == true)
        #expect(shop.created == 1)
        #expect(!session.closed)
    }

    /// A wallet sheet closed without paying sent nothing: the soft banner, the same payment.
    @Test func aClosedWalletSheetKeepsThePayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        model.selectedMethod = .applePay
        shop.sessions[0].chargeResult = .failure(error(.paymentCancelled))

        await model.pay()

        #expect(model.banner == "Payment cancelled. Pick a method and try again.")
        #expect(model.outcome == nil)
        #expect(shop.created == 1)
        #expect(!shop.sessions[0].closed)
    }

    /// Leaving while a declined payment's session is being closed opens no new payment: nothing
    /// would close its session.
    @Test func leavingWhileThePaymentIsReplacedOpensNoNewPayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.waits = [.failure(error(.paymentDeclined, charge: ChargePaymentResponse(id: "ch", state: .failed)))]
        session.holdsClose = true

        let paying = Task { await model.pay() }
        while session.closeGate == nil { await Task.yield() }
        #expect(!model.canPay)
        await model.finish()
        session.closeGate?.resume()
        await paying.value

        #expect(session.closed)
        #expect(shop.created == 1)
        #expect(model.session == nil)
        #expect(model.paymentId == nil)
    }

    /// The transfer details are read on the checkout's payment, which can then still be paid by
    /// card: nothing was charged.
    @Test func theTransferDetailsUseTheCheckoutsPayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)

        model.selectedMethod = .bankTransfer
        await model.pay()
        #expect(shop.sessions[0].qrReads == 1)
        #expect(model.outcome == nil)

        model.selectedMethod = .savedCard
        await model.pay()
        #expect(shop.created == 1)
        #expect(model.outcome?.isSuccess == true)
        #expect(model.outcome?.paymentId == "p1")
    }

    // MARK: - After an interruption

    /// A charge call that may have left a charge is followed by one read of the payment. A
    /// charge waiting for 3DS is finished with `awaitChargeState`, on the same payment.
    @Test(arguments: [
        (GopaySDKError.Code.paymentChargeAlreadyExists, 409 as Int?),
        (.networkServerError, 503),
        (.networkTimeout, nil)
    ])
    func anInterruptedChargeWaitingFor3dsIsFinished(code: GopaySDKError.Code, status: Int?) async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.chargeResult = .failure(error(code, status: status))
        session.outcomeResult = .success(session.outcome(.undecided, payment: .created, charge: .actionRequired))

        await model.pay()

        #expect(session.outcomeReads == 1)
        #expect(session.chargeStateReads == 0)
        #expect(session.waitCalls == 1)
        #expect(model.outcome?.isSuccess == true)
        #expect(shop.created == 1)
        #expect(!session.closed)
    }

    /// A 3DS challenge the shopper closed leaves the charge waiting for it. Nothing failed, so
    /// there is no failure screen, but the payment is given up for a new one.
    @Test func a3dsChallengeClosedByTheShopperOpensANewPayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.waits = [.failure(error(.paymentCancelled))]
        session.outcomeResult = .success(session.outcome(.undecided, payment: .created, charge: .actionRequired))

        await model.pay()

        #expect(model.outcome == nil)
        #expect(model.banner == "Payment cancelled. Pick a method and try again.")
        #expect(session.waitCalls == 1)
        #expect(session.closed)
        #expect(model.paymentId == "p2")
    }

    /// The shopper may have confirmed at the bank before the challenge closed: a paid payment is
    /// the result, whatever closed the window.
    @Test func aClosedChallengeOnAPaidPaymentIsASuccess() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.waits = [.failure(error(.paymentCancelled))]
        session.outcomeResult = .success(session.outcome(.paid, payment: .paid, charge: .succeeded))

        await model.pay()

        #expect(model.outcome?.isSuccess == true)
        #expect(shop.created == 1)
    }

    /// A charge that turns out failed is the failure screen and a new payment, as any decline.
    @Test func anInterruptedChargeThatFailedOpensANewPayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.waits = [.failure(error(.paymentCancelled))]
        session.outcomeResult = .success(session.outcome(.declined, payment: .created, charge: .failed))

        await model.pay()

        #expect(model.outcome?.isFailure == true)
        #expect(model.outcome?.paymentId == "p1")
        #expect(model.paymentId == "p2")
    }

    /// A decline found only by the wait that follows an interrupted charge is a decline like any
    /// other: the failure screen and a new payment.
    @Test func aDeclineFoundAfterAnInterruptedChargeOpensANewPayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.chargeResult = .failure(error(.networkServerError, status: 503))
        session.outcomeResult = .success(session.outcome(.undecided, payment: .created, charge: .processing))
        session.waits = [.failure(error(.paymentDeclined, charge: ChargePaymentResponse(id: "ch", state: .failed)))]

        await model.pay()

        #expect(model.outcome?.isFailure == true)
        #expect(model.outcome?.paymentId == "p1")
        #expect(session.closed)
        #expect(shop.created == 2)
        #expect(model.paymentId == "p2")
    }

    /// A decline that arrives on the pending screen's Refresh replaces the payment as well.
    @Test func aDeclineFoundByRefreshOpensANewPayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.waits = [
            .failure(error(.paymentTimeout, charge: ChargePaymentResponse(id: "ch", state: .processing))),
            .failure(error(.paymentDeclined, charge: ChargePaymentResponse(id: "ch", state: .failed)))
        ]

        await model.pay()
        #expect(model.outcome?.resultTitle == "Payment pending")
        #expect(shop.created == 1)

        await model.refreshChargeState()

        #expect(model.outcome?.isFailure == true)
        #expect(model.outcome?.paymentId == "p1")
        #expect(session.closed)
        #expect(model.paymentId == "p2")
    }

    /// A challenge shown by the wait after an interrupted charge and closed by the shopper is
    /// read once more, and ends like any challenge the shopper closed: a banner, a new payment.
    @Test func aChallengeClosedInTheSecondWaitIsReadAgain() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.chargeResult = .failure(error(.networkServerError, status: 503))
        session.outcomeResult = .success(session.outcome(.undecided, payment: .created, charge: .actionRequired))
        session.waits = [.failure(error(.paymentCancelled))]

        await model.pay()

        #expect(session.outcomeReads == 2)
        #expect(session.waitCalls == 1)
        #expect(model.outcome == nil)
        #expect(model.banner == "Payment cancelled. Pick a method and try again.")
        #expect(session.closed)
        #expect(model.paymentId == "p2")
    }

    /// No charge on a payment the gateway has already given up: the banner and a new payment.
    @Test(arguments: [PaymentState.canceled, .timeouted])
    func anInterruptedChargeOnAPaymentThatIsOverOpensANewPayment(state: PaymentState) async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.chargeResult = .failure(error(.networkTimeout))
        session.outcomeResult = .success(session.outcome(.notCharged, payment: state, charge: nil))

        await model.pay()

        #expect(model.outcome == nil)
        #expect(model.banner == "[NETWORK_001] NETWORK_001. Pick a method and try again.")
        #expect(session.closed)
        #expect(model.paymentId == "p2")
    }

    /// An undecided payment without a charge is a state this SDK does not know: the pending
    /// screen with its Refresh, no wait and the same payment.
    @Test func anUndecidedPaymentWithoutAChargeIsPending() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.chargeResult = .failure(error(.networkTimeout))
        session.outcomeResult = .success(session.outcome(.undecided, payment: .created, charge: nil))

        await model.pay()

        #expect(model.outcome?.resultTitle == "Payment pending")
        #expect(model.outcome?.isUnread == false)
        #expect(session.waitCalls == 0)
        #expect(shop.created == 1)
        #expect(!session.closed)
    }

    /// The payment was read, and then the wait for its charge failed on the network: the state
    /// is unknown again, so the result screen says it could not be checked and keeps the payment.
    @Test func aNetworkErrorAfterTheReadIsAnUnreadResult() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.chargeResult = .failure(error(.networkServerError, status: 503))
        session.outcomeResult = .success(session.outcome(.undecided, payment: .created, charge: .processing))
        session.waits = [.failure(error(.networkNoConnection))]

        await model.pay()

        #expect(model.outcome?.isUnread == true)
        #expect(model.outcome?.resultTitle == "Couldn't check the payment")
        #expect(model.outcome?.message == "Couldn't check the payment: [NETWORK_004] NETWORK_004")
        #expect(shop.created == 1)
        #expect(!session.closed)
    }

    /// No charge on a payment that is still open: the banner and the same payment.
    @Test func anInterruptedChargeThatNeverArrivedKeepsThePayment() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.chargeResult = .failure(error(.networkTimeout))
        session.outcomeResult = .success(session.outcome(.notCharged, payment: .created, charge: nil))

        await model.pay()

        #expect(model.outcome == nil)
        #expect(model.banner == "[NETWORK_001] NETWORK_001. Pick a method and try again.")
        #expect(shop.created == 1)
        #expect(!session.closed)
    }

    /// A payment that could not be read is not offered again: the result screen says the state
    /// is unknown and keeps the payment for its Refresh.
    @Test func aPaymentThatCannotBeReadKeepsItsResultScreen() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.chargeResult = .failure(error(.networkTimeout))
        session.outcomeResult = .failure(error(.networkNoConnection))

        await model.pay()

        #expect(model.outcome?.isUnread == true)
        #expect(model.outcome?.resultTitle == "Couldn't check the payment")
        #expect(model.outcome?.paymentId == "p1")
        #expect(shop.created == 1)
        #expect(!session.closed)
    }

    /// An error that is not a failed read, here a 3DS challenge that could not be shown, does
    /// not claim the state could not be checked.
    @Test func anErrorThatIsNotAFailedReadHasANeutralHeading() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        let session = shop.sessions[0]
        session.waits = [.failure(error(.paymentVerificationUnreachable))]
        session.outcomeResult = .success(session.outcome(.undecided, payment: .created, charge: .actionRequired))

        await model.pay()

        #expect(model.outcome?.isUnread == false)
        #expect(model.outcome?.isUnfinished == true)
        #expect(model.outcome?.resultTitle == "Payment not finished")
        #expect(model.outcome?.message == "[PAYMENT_010] PAYMENT_010")
        #expect(shop.created == 1)
    }

    // MARK: - Busy

    /// While a payment is running, a second `pay()` leaves it alone: no charge, no card
    /// submitted, the banner as it was, and the busy state still held.
    @Test func payWhileBusyReturnsAtOnce() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        model.busyLabel = "Processing…"
        model.banner = "Payment cancelled. Pick a method and try again."

        await model.pay()

        #expect(model.busyLabel == "Processing…")
        #expect(model.banner == "Payment cancelled. Pick a method and try again.")
        #expect(shop.sessions[0].charges == 0)
        #expect(shop.created == 1)
        #expect(model.outcome == nil)
        #expect(model.qrDetails == nil)
    }

    /// A banner belongs to the method it was raised for: picking another method takes it down,
    /// picking the same one again does not.
    @Test func pickingAnotherMethodClearsTheBanner() {
        let model = CheckoutViewModel()
        model.selectedMethod = .applePay
        model.banner = "Payment cancelled. Pick a method and try again."

        model.selectedMethod = .applePay
        #expect(model.banner == "Payment cancelled. Pick a method and try again.")

        model.selectedMethod = .card
        #expect(model.banner == nil)
    }

    /// A charge whose state could not be read is not headed as one the bank has not confirmed:
    /// the bank was not asked. A pending charge without a message keeps "Payment pending".
    @Test func unreadStateHasItsOwnHeading() {
        let unread = CheckoutViewModel.Outcome(
            state: .unknown, response: nil, message: "Couldn't check the payment: [NETWORK_004] offline", paymentId: "p1", isUnread: true
        )
        #expect(unread.isUnread)
        #expect(unread.resultTitle == "Couldn't check the payment")
        #expect(unread.resultSubtitle.hasPrefix("The payment was sent, but we couldn't read its state"))

        let pending = CheckoutViewModel.Outcome(state: .processing, response: nil, message: nil, paymentId: "p1")
        #expect(!pending.isUnread)
        #expect(pending.resultTitle == "Payment pending")

        let failed = CheckoutViewModel.Outcome(state: .failed, response: nil, message: "declined", paymentId: "p1")
        #expect(!failed.isUnread)
        #expect(!failed.isUnfinished)
        #expect(failed.resultTitle == "Payment failed")

        let interrupted = CheckoutViewModel.Outcome(
            state: .actionRequired, response: nil, message: "[PAYMENT_010] no window", paymentId: "p1"
        )
        #expect(interrupted.resultTitle == "Payment not finished")
        #expect(interrupted.resultSubtitle.hasPrefix("The payment was sent, but it isn't finished yet"))
    }

    /// The same for Refresh on the pending screen, with a session in place so it is the busy
    /// check that stops it, not the missing session.
    @Test func refreshWhileBusyReturnsAtOnce() async {
        let shop = Shop()
        let model = await openCheckout(shop)
        model.busyLabel = "Processing…"
        model.banner = "Payment cancelled. Pick a method and try again."

        await model.refreshChargeState()

        #expect(model.busyLabel == "Processing…")
        #expect(model.banner == "Payment cancelled. Pick a method and try again.")
        #expect(model.outcome == nil)
        #expect(shop.sessions[0].waitCalls == 0)
        #expect(shop.sessions[0].outcomeReads == 0)
    }
}
