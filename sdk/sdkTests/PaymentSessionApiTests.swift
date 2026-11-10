//
//  PaymentSessionApiTests.swift
//  sdkTests
//
//  An app's own test, as the README shows it: code that depends on `PaymentSessionApi` gets a
//  fake session, and the fake builds the answers through the public initializers. The file
//  imports the SDK without `@testable`, so everything it uses is what a host can use.
//

import Testing
import Foundation
import UIKit
import sdk

/// The app's code under test: it knows the session only as the protocol.
private struct Checkout {
    let session: any PaymentSessionApi

    func pay(jwe: String) async throws -> String {
        let charge = try await session.chargeWithEncryptedCard(jwe)
        if let redirect = charge.action?.redirectUrl.flatMap(URL.init(string:)) {
            try await session.handle3dsVerification(redirectURL: redirect)
        }
        _ = try await session.awaitChargeState()
        return try await resultText()
    }

    func resultText() async throws -> String {
        switch try await session.getPaymentOutcome().outcome {
        case .paid: return "Paid"
        case .declined: return "Declined"
        case .notCharged: return "Not charged"
        case .undecided: return "Waiting"
        }
    }
}

/// The app's fake: it answers what the test tells it to and records what it was asked.
private final class FakeSession: PaymentSessionApi, @unchecked Sendable {
    let paymentId = "p1"
    var outcome: PaymentOutcome.Outcome = .paid
    var chargeState: ChargeState = .succeeded
    var action: ChargeAction?
    private(set) var calls: [String] = []

    private var payment: PaymentDetails {
        PaymentDetails(
            id: paymentId, orderNumber: "ORD-1", state: .paid, amount: 1000, currency: .czk,
            gatewayUrl: "https://gw.example/p1", customer: PaymentCustomer(email: "jan@example.com"),
            charge: ChargePaymentResponse(id: "ch1", state: chargeState)
        )
    }

    func getStatus() async throws -> PaymentDetails { payment }

    func getPaymentOutcome() async throws -> PaymentOutcome {
        calls.append("getPaymentOutcome")
        return PaymentOutcome(outcome: outcome, payment: payment)
    }

    func charge(_ request: ChargePaymentRequest) async throws -> ChargePaymentResponse {
        calls.append("charge")
        return ChargePaymentResponse(id: "ch1", state: .processing)
    }

    func chargeWithCardToken(
        _ cardToken: String, browserData: BrowserData?, challengePreference: ChallengePreference?
    ) async throws -> ChargePaymentResponse {
        calls.append("chargeWithCardToken")
        return ChargePaymentResponse(id: "ch1", state: .processing)
    }

    func chargeWithEncryptedCard(
        _ payload: String, browserData: BrowserData?, challengePreference: ChallengePreference?
    ) async throws -> ChargePaymentResponse {
        calls.append("chargeWithEncryptedCard")
        return ChargePaymentResponse(id: "ch1", state: action == nil ? .processing : .actionRequired, action: action)
    }

    func completeBrowserData(_ browserData: BrowserData) async throws -> BrowserData { browserData }

    func getChargeState() async throws -> ChargePaymentResponse {
        ChargePaymentResponse(id: "ch1", state: chargeState)
    }

    func awaitChargeState(_ options: AwaitChargeOptions) async throws -> ChargePaymentResponse {
        calls.append("awaitChargeState")
        return ChargePaymentResponse(
            id: "ch1", state: chargeState,
            paymentInstrument: PaymentInstrumentData(details: InstrumentDetails(inputType: "ENCRYPTED_CARD", maskedPan: "444444******4448"))
        )
    }

    func getQrPaymentInfo(format: QrCodeFormat?) async throws -> QrPaymentDetails {
        QrPaymentDetails(
            amount: 1000, currency: .czk,
            recipient: BankTransferRecipient(
                name: "Shop",
                bankAccount: RecipientBankAccount(
                    local: BankAccountLocalDetails(prefix: "", accountNumber: "2000123456", bankCode: "2010", variableSymbol: "1"),
                    international: BankAccountInternationalDetails(bic: "FIOBCZPP", iban: "CZ65")
                ),
                address: RecipientAddress(city: "Praha")
            ),
            qrCode: QrCodeList(spayd: "SPD*1.0")
        )
    }

    func getWalletInfo() async throws -> GopayApplePayAppInfoResponse {
        GopayApplePayAppInfoResponse(
            merchantIdentifier: "merchant.example",
            applePayPaymentRequest: GopayApplePayRequest(
                merchantCapabilities: ["supports3DS"], supportedNetworks: ["visa"], countryCode: "CZ", currencyCode: "CZK",
                paymentSummaryItems: [GopayApplePayPaymentSummaryItem(label: "Shop", amount: "10.00")]
            )
        )
    }

    func chargeWithWallet(
        browserData: BrowserData?, challengePreference: ChallengePreference?
    ) async throws -> ChargePaymentResponse {
        calls.append("chargeWithWallet")
        return ChargePaymentResponse(id: "ch1", state: .processing)
    }

    func handle3dsVerification(redirectURL: URL, returnUrl: URL?, presenting: UIViewController?) async throws {
        calls.append("handle3dsVerification")
    }

    func close() async { calls.append("close") }
}

struct PaymentSessionApiTests {

    @Test func theAppsCodeRunsAgainstAFakeSession() async throws {
        let session = FakeSession()

        let text = try await Checkout(session: session).pay(jwe: "jwe")

        #expect(text == "Paid")
        #expect(session.calls == ["chargeWithEncryptedCard", "awaitChargeState", "getPaymentOutcome"])
    }

    @Test func theFakeCanAnswerA3dsChallengeAndADecline() async throws {
        let session = FakeSession()
        session.action = ChargeAction(actionType: .emv3ds, state: .challengeRequired, redirectUrl: "https://3ds.example/step")
        session.outcome = .declined
        session.chargeState = .failed

        let text = try await Checkout(session: session).pay(jwe: "jwe")

        #expect(text == "Declined")
        #expect(session.calls == ["chargeWithEncryptedCard", "handle3dsVerification", "awaitChargeState", "getPaymentOutcome"])
    }

    /// The defaults a call on `PaymentSession` has are there through the protocol too.
    @Test func theProtocolOffersTheDefaultsOfTheSession() async throws {
        let fake = FakeSession()
        let session: any PaymentSessionApi = fake

        _ = try await session.chargeWithCardToken("tok")
        _ = try await session.chargeWithCardToken("tok", challengePreference: .challengePreferred)
        _ = try await session.chargeWithEncryptedCard("jwe", browserData: nil)
        _ = try await session.chargeWithWallet()
        _ = try await session.awaitChargeState()
        _ = try await session.getQrPaymentInfo()
        try await session.handle3dsVerification(redirectURL: URL(string: "https://3ds.example")!, returnUrl: nil)
        await session.close()

        #expect(fake.calls == [
            "chargeWithCardToken", "chargeWithCardToken", "chargeWithEncryptedCard", "chargeWithWallet",
            "awaitChargeState", "handle3dsVerification", "close",
        ])
    }

    /// `charge` is not an argument of the outcome: it is the charge in the payment, as in 2.7.
    @Test func anOutcomeBuiltByHandKeepsItsChargeInThePayment() {
        let charge = ChargePaymentResponse(id: "ch9", state: .failed, failReason: "DECLINED")
        let payment = PaymentDetails(
            id: "p9", orderNumber: "o", state: .canceled, amount: 1, currency: .eur, gatewayUrl: "https://gw.example",
            customer: PaymentCustomer(email: "a@b.c"), charge: charge
        )

        let outcome = PaymentOutcome(outcome: .declined, payment: payment)

        #expect(outcome.outcome == .declined)
        #expect(outcome.charge?.id == "ch9")
        #expect(outcome.charge?.failReason == "DECLINED")
        #expect(PaymentOutcome(outcome: .notCharged, payment: PaymentDetails(
            id: "p", orderNumber: "o", state: .created, amount: 1, currency: .czk, gatewayUrl: "u",
            customer: PaymentCustomer(email: "a@b.c")
        )).charge == nil)
    }

    /// The real session is a `PaymentSessionApi`, so the app hands its code either.
    @Test func theSessionOfTheSDKIsOne() {
        func accepts<Session: PaymentSessionApi>(_: Session.Type) -> Bool { true }
        #expect(accepts(PaymentSession.self))
    }
}
