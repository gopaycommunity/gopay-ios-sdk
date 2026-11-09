//
//  PaymentOutcomeTests.swift
//  sdkTests
//
//  Pins `getPaymentOutcome()` (GPMOB-198): one read of `GET /payments/{id}`, the outcome for every
//  payment and charge state in the order the rules apply, and its errors. The Android SDK runs the
//  same table.
//

import Testing
import Foundation
@testable import sdk

/// The charge column of the table: what the payment's `charge` carries, and the state it decodes to.
struct ChargeColumn: Sendable {
    /// `false` for a payment without a charge.
    let present: Bool
    /// The `state` sent, `nil` for a charge whose `state` is missing.
    let state: String?
    /// What `charge?.state` decodes to.
    let decoded: ChargeState?
}

/// Every charge the payment can carry: none, the five states and a value this SDK does not know,
/// and a charge without a `state`, which decodes as `unknown` rather than failing the payment.
private let chargeColumns: [ChargeColumn] = [
    ChargeColumn(present: false, state: nil, decoded: nil),
    ChargeColumn(present: true, state: "REQUESTED", decoded: .requested),
    ChargeColumn(present: true, state: "PROCESSING", decoded: .processing),
    ChargeColumn(present: true, state: "ACTION_REQUIRED", decoded: .actionRequired),
    ChargeColumn(present: true, state: "SUCCEEDED", decoded: .succeeded),
    ChargeColumn(present: true, state: "FAILED", decoded: .failed),
    ChargeColumn(present: true, state: "SOMETHING_NEW", decoded: .unknown),
    ChargeColumn(present: true, state: nil, decoded: .unknown),
]

/// One row per payment state, one outcome per charge column above, in the same order: no charge,
/// REQUESTED, PROCESSING, ACTION_REQUIRED, SUCCEEDED, FAILED, unknown, no state. The Android SDK
/// runs the same table.
private let outcomeTable: [(payment: String, outcomes: [PaymentOutcome.Outcome])] = [
    // A settled payment is paid, whatever its charge says.
    ("PAID",                  [.paid, .paid, .paid, .paid, .paid, .paid, .paid, .paid]),
    ("AUTHORIZED",            [.paid, .paid, .paid, .paid, .paid, .paid, .paid, .paid]),
    ("REFUNDED",              [.paid, .paid, .paid, .paid, .paid, .paid, .paid, .paid]),
    ("PARTIALLY_REFUNDED",    [.paid, .paid, .paid, .paid, .paid, .paid, .paid, .paid]),
    // A closed payment is declined when its charge failed, otherwise nothing was charged.
    ("CANCELED",              [.notCharged, .notCharged, .notCharged, .notCharged, .notCharged, .declined, .notCharged, .notCharged]),
    ("TIMEOUTED",             [.notCharged, .notCharged, .notCharged, .notCharged, .notCharged, .declined, .notCharged, .notCharged]),
    // An open payment goes by its charge.
    ("CREATED",               [.notCharged, .undecided, .undecided, .undecided, .paid, .declined, .undecided, .undecided]),
    ("PAYMENT_METHOD_CHOSEN", [.notCharged, .undecided, .undecided, .undecided, .paid, .declined, .undecided, .undecided]),
    ("SOMETHING_NEW",         [.undecided, .undecided, .undecided, .undecided, .paid, .declined, .undecided, .undecided]),
]

/// One cell of the table.
struct OutcomeCase: CustomTestStringConvertible, Sendable {
    let payment: String
    let charge: ChargeColumn
    let outcome: PaymentOutcome.Outcome

    var testDescription: String {
        let charge = self.charge.present ? (self.charge.state ?? "no state") : "no charge"
        return "\(payment) + \(charge) → \(outcome.rawValue)"
    }
}

private let outcomeCases: [OutcomeCase] = outcomeTable.flatMap { row in
    zip(chargeColumns, row.outcomes).map { OutcomeCase(payment: row.payment, charge: $0, outcome: $1) }
}

/// The payment as `GET /payments/{id}` answers it, with the charge summary the sandbox sends:
/// `id`, `state` and `href`, nothing else.
private func payment(_ state: String, charge: ChargeColumn) -> [String: Any] {
    var body: [String: Any] = [
        "id": "p1", "order_number": "o1", "state": state, "amount": 100, "currency": "CZK",
        "gw_url": "https://gw.example/1", "payment_secret": "secret", "customer": ["email": "a@b.c"]
    ]
    if charge.present {
        var nested: [String: Any] = ["id": "7577", "href": "https://gw.example/payments/p1/charge"]
        nested["state"] = charge.state
        body["charge"] = nested
    }
    return body
}

private func payment(_ state: String, charge: String?) -> [String: Any] {
    payment(state, charge: ChargeColumn(present: charge != nil, state: charge, decoded: nil))
}

private func servePayment(status: Int = 200, _ body: [String: Any]) {
    StubURLProtocol.reset { req in
        let path = req.url?.path ?? ""
        if path.hasSuffix("oauth2/token") { return tokenResponse() }
        if path.hasSuffix("/payments/p1") { return (status, json(body)) }
        return (500, Data())
    }
}

// Part of the serialized `SessionNetworkTests`: every test here shares the one stub.
extension SessionNetworkTests {

    @Test func theTableCoversEveryPaymentAndChargeState() {
        #expect(outcomeCases.count == 72)
        #expect(outcomeTable.allSatisfy { $0.outcomes.count == chargeColumns.count })
    }

    @Test(arguments: outcomeCases)
    func theOutcomeFollowsThePaymentAndItsCharge(_ testCase: OutcomeCase) async throws {
        servePayment(payment(testCase.payment, charge: testCase.charge))
        let session = try await makeSession()

        let result = try await session.getPaymentOutcome()

        #expect(result.outcome == testCase.outcome)
        #expect(result.payment.id == "p1")
        #expect(result.charge?.id == (testCase.charge.present ? "7577" : nil))
        #expect(result.charge?.state == testCase.charge.decoded)
    }

    /// A nested charge with a `null` state decodes like one without it.
    @Test func aNestedChargeWithANullStateIsUnknown() async throws {
        var body = payment("CREATED", charge: "PROCESSING")
        body["charge"] = ["id": "7577", "state": NSNull(), "href": "https://gw.example/payments/p1/charge"]
        servePayment(body)
        let session = try await makeSession()

        let result = try await session.getPaymentOutcome()

        #expect(result.outcome == .undecided)
        #expect(result.charge?.state == .unknown)
    }

    /// Only the charge nested in the payment is lenient: the charge read on its own still needs a
    /// `state`.
    @Test func aChargeReadOnItsOwnStillNeedsAState() async throws {
        StubURLProtocol.reset { req in
            (req.url?.path ?? "").hasSuffix("oauth2/token") ? tokenResponse() : (200, json(["id": "7577"]))
        }
        let session = try await makeSession()

        do {
            _ = try await session.getChargeState()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .decoding)
        }
    }

    /// One read of the payment, never of the charge, and no second read while it is undecided.
    @Test func theOutcomeIsOneReadOfThePayment() async throws {
        servePayment(payment("CREATED", charge: "PROCESSING"))
        let session = try await makeSession()

        #expect(try await session.getPaymentOutcome().outcome == .undecided)

        #expect(StubURLProtocol.requestCount(forPathSuffix: "/payments/p1") == 1)
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/charge") == 0)
    }

    @Test func aPaymentThatDoesNotExistIsPaymentNotFound() async throws {
        servePayment(status: 404, ["error": "NOT_FOUND", "message": "Payment not found"])
        let session = try await makeSession()

        do {
            _ = try await session.getPaymentOutcome()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .paymentNotFound)
            #expect(error.httpStatus == 404)
            #expect(error.gatewayError?.message == "Payment not found")
        }
    }

    @Test func aClosedSessionRefusesTheOutcomeBeforeAnyRequest() async throws {
        servePayment(payment("PAID", charge: "SUCCEEDED"))
        let session = try await makeSession()
        await session.close()

        do {
            _ = try await session.getPaymentOutcome()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentSessionClosed)
        }
        #expect(StubURLProtocol.requestCount(forPathSuffix: "/payments/p1") == 0)
    }

    @Test func aFailedOutcomeIsReportedOnce() async throws {
        servePayment(status: 503, ["error": "SERVICE_UNAVAILABLE"])
        let reported = ReportedErrors()
        let sdk = reportingSDK(reported)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        defer { Task { await session.close() } }

        await #expect(throws: GopaySDKError.self) { try await session.getPaymentOutcome() }

        #expect(reported.codes == [.networkServerError])
    }
}
