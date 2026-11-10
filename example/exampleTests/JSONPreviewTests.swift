//
//  JSONPreviewTests.swift
//  exampleTests
//
//  The demo console prints SDK responses, and a payment carries its `payment_secret` and the
//  customer's e-mail and phone. The printer hides them, whatever the response and however deep
//  they sit.
//

import Testing
import Foundation
import GopaySDK
@testable import example

struct JSONPreviewTests {

    @Test func aPaymentIsPrintedWithoutItsSecret() {
        let payment = PaymentDetails(
            id: "p1", orderNumber: "ORD-1", state: .created, amount: 100, currency: .czk,
            gatewayUrl: "https://gw.example/p1", customer: PaymentCustomer(email: "jan@example.com"),
            paymentSecret: "s3cr3t-value"
        )

        let printed = JSONPreview.string(payment)

        #expect(!printed.contains("s3cr3t-value"))
        #expect(printed.contains("\"payment_secret\" : \"(hidden)\""))
        #expect(printed.contains("\"order_number\" : \"ORD-1\""))
    }

    @Test func aPaymentIsPrintedWithoutTheCustomersContact() {
        let payment = PaymentDetails(
            id: "p1", orderNumber: "ORD-1", state: .paid, amount: 100, currency: .czk,
            gatewayUrl: "https://gw.example/p1",
            customer: PaymentCustomer(email: "jan@example.com", phoneNumber: "+420777123456")
        )

        let printed = JSONPreview.string(payment)

        #expect(!printed.contains("jan@example.com"))
        #expect(!printed.contains("777123456"))
        #expect(printed.contains("\"email\" : \"(hidden)\""))
        #expect(printed.contains("\"phone_number\" : \"(hidden)\""))
    }

    @Test func aSecretNestedInAnOutcomeOrAListIsHiddenToo() {
        struct Wrapper: Encodable {
            let items: [[String: String]]
        }

        let printed = JSONPreview.string(Wrapper(items: [["payment_secret": "s3cr3t-value", "id": "p1"]]))

        #expect(!printed.contains("s3cr3t-value"))
        #expect(printed.contains("\"id\" : \"p1\""))
    }

    @Test func aResponseWithoutASecretIsPrintedAsItIs() {
        let printed = JSONPreview.string(ChargePaymentResponse(id: "ch1", state: .succeeded))

        #expect(printed.contains("\"state\" : \"SUCCEEDED\""))
        #expect(!printed.contains("(hidden)"))
    }
}
