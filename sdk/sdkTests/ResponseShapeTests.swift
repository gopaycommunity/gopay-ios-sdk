//
//  ResponseShapeTests.swift
//  sdkTests
//
//  Pins which fields of the response models are always present and which are optional, the
//  shape 3.0 shares with the Android SDK (sdk/docs/API_3_0.md, "One shape on both platforms").
//  A field the API requires is not optional, and a response without it fails to decode.
//

import Testing
import Foundation
@testable import sdk

struct ResponseShapeTests {

    private func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: PaymentDetails

    private let payment = """
    {
      "id": "3310782449", "order_number": "ORD-1", "state": "CREATED", "amount": 1000, "currency": "CZK",
      "gw_url": "https://gw.sandbox.gopay.com/gw/pay", "payment_secret": "secret",
      "customer": { "email": "jan@example.com", "first_name": "Jan", "country_code": "CZE" }
    }
    """

    @Test func aPaymentCarriesItsOrderNumberGatewayUrlAndCustomer() throws {
        let details = try decode(PaymentDetails.self, object(payment))

        let orderNumber: String = details.orderNumber
        let gatewayUrl: String = details.gatewayUrl
        let customer: PaymentCustomer = details.customer
        #expect(orderNumber == "ORD-1")
        #expect(gatewayUrl == "https://gw.sandbox.gopay.com/gw/pay")
        #expect(customer.email == "jan@example.com")
        #expect(customer.firstName == "Jan")
        #expect(customer.countryCode == "CZE")
        #expect(customer.lastName == nil)
        #expect(details.charge == nil)
    }

    @Test(arguments: ["order_number", "gw_url", "customer"])
    func aPaymentWithoutARequiredFieldFailsToDecode(field: String) throws {
        var json = try object(payment)
        json[field] = nil

        #expect(throws: DecodingError.self) { try decode(PaymentDetails.self, json) }
    }

    @Test func aCustomerNeedsOnlyItsEmail() throws {
        let customer = try decode(PaymentCustomer.self, ["email": "a@b.c"])
        #expect(customer.email == "a@b.c")
        #expect(customer.customerId == nil)

        #expect(throws: DecodingError.self) { try decode(PaymentCustomer.self, ["first_name": "Jan"]) }
    }

    /// The customer goes back out when the payment is encoded, as the demo console prints it.
    @Test func aPaymentEncodesItsCustomer() throws {
        let details = try decode(PaymentDetails.self, object(payment))

        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(details)) as? [String: Any])

        #expect((encoded["customer"] as? [String: Any])?["email"] as? String == "jan@example.com")
        #expect(encoded["order_number"] as? String == "ORD-1")
    }

    // MARK: QrPaymentDetails

    private let qr = """
    {
      "amount": 1000, "currency": "CZK",
      "recipient": {
        "name": "Shop",
        "bank_account": {
          "local": { "prefix": "", "account_number": "2000123456", "bank_code": "2010", "variable_symbol": "3310782449" },
          "international": { "iban": "CZ6508000000192000145399", "bic": "GIBACZPX" }
        }
      },
      "qr_code": { "spayd": "SPD*1.0*ACC:CZ65" }
    }
    """

    @Test func aQrPaymentCarriesItsRecipientAndCodes() throws {
        let details = try decode(QrPaymentDetails.self, object(qr))

        let recipient: QrRecipient = details.recipient
        let codes: QrCodeList = details.qrCode
        let local = try #require(recipient.bankAccount?.local)
        let prefix: String = local.prefix
        let number: String = local.accountNumber
        let bank: String = local.bankCode
        let symbol: String = local.variableSymbol
        #expect(prefix.isEmpty)
        #expect(number == "2000123456")
        #expect(bank == "2010")
        #expect(symbol == "3310782449")
        #expect(codes.spayd == "SPD*1.0*ACC:CZ65")
        // What the API leaves optional stays optional: the address and the other formats.
        #expect(recipient.address == nil)
        #expect(codes.sepa == nil)
        #expect(codes.mnbQr == nil)
    }

    @Test(arguments: ["recipient", "qr_code"])
    func aQrPaymentWithoutARequiredFieldFailsToDecode(field: String) throws {
        var json = try object(qr)
        json[field] = nil

        #expect(throws: DecodingError.self) { try decode(QrPaymentDetails.self, json) }
    }

    @Test(arguments: ["prefix", "account_number", "bank_code", "variable_symbol"])
    func aLocalAccountWithoutOneOfItsFourFieldsFailsToDecode(field: String) throws {
        var local: [String: Any] = ["prefix": "", "account_number": "1", "bank_code": "2010", "variable_symbol": "9"]
        local[field] = nil

        #expect(throws: DecodingError.self) { try decode(QrLocalBankAccount.self, local) }
    }

    /// A recipient without a local account still decodes: only the account's own fields are
    /// required, not the account.
    @Test func aRecipientWithoutALocalAccountDecodes() throws {
        let recipient = try decode(QrRecipient.self, ["name": "Shop", "bank_account": ["international": ["iban": "CZ65"]]])

        #expect(recipient.bankAccount?.local == nil)
        #expect(recipient.bankAccount?.international?.iban == "CZ65")
    }

    // MARK: PaymentInstrumentData

    @Test func aPaymentInstrumentWithoutDetailsDecodes() throws {
        let charge = try decode(ChargePaymentResponse.self, [
            "id": "51", "state": "SUCCEEDED", "payment_instrument": ["payment_instrument": "PAYMENT_CARD"],
        ])

        #expect(charge.paymentInstrument?.paymentInstrument == "PAYMENT_CARD")
        #expect(charge.paymentInstrument?.details == nil)
    }

    @Test func aPaymentInstrumentWithDetailsKeepsThem() throws {
        let charge = try decode(ChargePaymentResponse.self, [
            "id": "51", "state": "SUCCEEDED",
            "payment_instrument": [
                "payment_instrument": "PAYMENT_CARD",
                "details": ["input_type": "ENCRYPTED_CARD", "masked_pan": "444444******4448"],
            ],
        ])

        #expect(charge.paymentInstrument?.details?.maskedPan == "444444******4448")
    }
}

// MARK: - Request timeout

struct RequestTimeoutTests {

    @Test func theDefaultIsWhatTheSDKWaitedBefore3() {
        #expect(GopayConfig(environment: .sandbox).requestTimeout == 60)
        #expect(GopayConfig.defaultRequestTimeout == URLSessionConfiguration.default.timeoutIntervalForRequest)
    }

    @Test func theConfiguredTimeoutReachesTheClient() {
        let config = GopayConfig(environment: .sandbox, requestTimeout: 12.5)
        #expect(config.requestTimeout == 12.5)

        let client = DefaultNetworkClient(baseUrl: config.environment.baseUrl, requestTimeout: config.requestTimeout)
        #expect(client.requestTimeout == 12.5)
        // The configuration handed in is copied, so the shared default is not changed behind it.
        #expect(URLSessionConfiguration.default.timeoutIntervalForRequest == 60)
    }

    @Test(arguments: [0, -1, TimeInterval.infinity, TimeInterval.nan])
    func aTimeoutThatCannotBeUsedFallsBackToTheDefault(value: TimeInterval) {
        #expect(GopayConfig(environment: .sandbox, requestTimeout: value).requestTimeout == 60)
    }
}

// Part of the serialized `SessionNetworkTests`: every test here shares the one stub.
extension SessionNetworkTests {

    /// What leaves the device: a request carries a timeout of its own, 60 seconds unless set, and
    /// the loading system reads that one, so the configured value has to be on the request.
    @Test func theConfiguredTimeoutIsOnEveryRequestThatSetsNone() async throws {
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.hasSuffix("/charge") { return (200, json(["id": "ch_1", "state": "SUCCEEDED"])) }
            return (500, Data())
        }
        let session = try await makeSession(requestTimeout: 12.5)

        _ = try await session.getChargeState()

        let token = try #require(StubURLProtocol.requests(forPathSuffix: "oauth2/token").first)
        let charge = try #require(StubURLProtocol.requests(forPathSuffix: "/charge").first)
        #expect(token.timeoutInterval == 12.5)
        #expect(charge.timeoutInterval == 12.5)
    }

    @Test func aRequestWithoutAConfiguredTimeoutWaitsTheDefault() async throws {
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            return (200, json(["id": "ch_1", "state": "SUCCEEDED"]))
        }
        let session = try await makeSession()

        _ = try await session.getChargeState()

        #expect(StubURLProtocol.requests(forPathSuffix: "/charge").first?.timeoutInterval == 60)
    }
}
