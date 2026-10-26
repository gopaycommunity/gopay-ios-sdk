//
//  TelemetryRedactionTests.swift
//  sdkTests
//
//  Pins what may leave the device in an operational event: the message scrub and the body
//  redaction, with the browser SDK's own cases, so the two producers keep dropping the same things.
//

import Testing
import Foundation
@testable import sdk

struct TelemetryMessageScrubTests {

    struct LeakCase: CustomTestStringConvertible, Sendable {
        let label: String
        let input: String
        let leak: String
        var testDescription: String { label }
    }

    @Test(arguments: [
        LeakCase(label: "an e-mail address", input: "failed for jan.novak@example.com", leak: "novak@"),
        LeakCase(
            label: "a compact JOSE token in prose",
            input: "payload eyJhbGciOiJSU0EtT0FFUCJ9.abcdefghij.klmnopqrst.uvwxyzabcd.efghijklmn rejected",
            leak: "eyJhbGciOiJ"
        ),
        LeakCase(
            label: "a token in the fragment",
            input: "redirect to https://x.test/cb#access_token=abc123def456&state=z",
            leak: "access_token=abc"
        ),
        LeakCase(
            label: "anything else in the fragment",
            input: "redirect to https://x.test/cb#sid=SESSION-9f3a2b1c",
            leak: "SESSION-9f3a2b1c"
        ),
        LeakCase(
            label: "a token ending a sentence",
            input: "rejected payload eyJhbGciOiJSU0EtT0FFUCJ9.abcdefghij.klmnopqrst.uvwxyzabcd.efghijklmn.",
            leak: "eyJhbGciOiJ"
        ),
        LeakCase(
            label: "a three-segment JWS ending a sentence",
            input: "token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27u.",
            leak: "eyJzdWIiOiI"
        ),
        LeakCase(label: "3DS fields posted as a bare pair", input: "posted MD=abc123def&PaRes=eNrtWEuTo0YM", leak: "MD=abc"),
        LeakCase(label: "a payment secret", input: "paymentSecret=abc123 was wrong", leak: "paymentSecret=abc"),
    ])
    func redacts(_ leakCase: LeakCase) {
        #expect(!TelemetryRedaction.safeErrorMessage(leakCase.input).contains(leakCase.leak))
    }

    @Test func leavesAnOrdinaryMessageAlone() {
        let message = "Request timed out after 10000 ms (v1.2.3, api 4.0)"
        #expect(TelemetryRedaction.safeErrorMessage(message) == message)
    }

    @Test func redactsAPanWholeOrInGroups() {
        #expect(TelemetryRedaction.safeErrorMessage("card 4111111111111111 declined") == "card [redacted] declined")
        #expect(
            TelemetryRedaction.safeErrorMessage("card 4111 1111 1111 1111 and 5500-0000-0000-0004 declined")
                == "card [redacted] and [redacted] declined"
        )
    }

    @Test func redactsAPairUnderAnyNameEndingInTokenOrSecret() {
        #expect(
            TelemetryRedaction.safeErrorMessage("bad payment_token=abc123 and card_token=zzz999 or clientSecret=s3")
                == "bad [redacted] and [redacted] or [redacted]"
        )
    }

    @Test func keepsAShortDigitRun() {
        #expect(TelemetryRedaction.safeErrorMessage("status 404 on attempt 2") == "status 404 on attempt 2")
    }

    @Test func dropsTheQueryString() {
        #expect(
            TelemetryRedaction.safeErrorMessage("failed https://pay.example.com/r?token=abc&email=a@b.cz")
                == "failed https://pay.example.com/r?[redacted]"
        )
    }

    @Test func keepsTheCardCommFormTypeButNotItsToken() {
        #expect(
            TelemetryRedaction.safeErrorMessage("iframe /gp-card-comm/g/eyJhbGciOiJIUzI1")
                == "iframe /gp-card-comm/g/[redacted]"
        )
    }

    @Test func capsTheLength() {
        #expect(TelemetryRedaction.safeErrorMessage(String(repeating: "x", count: 900)).count == 500)
    }

    /// A message can carry text from outside the SDK, so a pattern that backtracks would turn a long
    /// string into a stall. Linear is milliseconds here; the bound only catches a quadratic one.
    @Test func scrubsAHostileMessageWithoutStalling() {
        let runs = [
            String(repeating: "a", count: 40_000),
            "x@" + String(repeating: "a.", count: 20_000),
            String(repeating: "a", count: 40_000) + "token",
        ]
        for run in runs {
            let started = Date()
            _ = TelemetryRedaction.safeErrorMessage(run)
            #expect(Date().timeIntervalSince(started) < 1)
        }
    }

    /// ICU's `\d` and `\w` cover every script; the browser's do not, and neither do these.
    @Test func treatsOnlyAsciiDigitsAsAPan() {
        let arabicIndic = String(repeating: "\u{0664}", count: 16)
        #expect(TelemetryRedaction.safeErrorMessage("ref \(arabicIndic)") == "ref \(arabicIndic)")
    }
}

struct TelemetryBodyRedactionTests {

    private static let jwe = "eyJhbGciOiJSU0EtT0FFUC0yNTYifQ.c2VjcmV0X2tleV9zZWdtZW50.aXZfdmFsdWVfaGVyZQ.Y2lwaGVydGV4dF9oZXJl.dGFnX3ZhbHVlX2hlcmU"
    private static let pan = "4111111111111111"

    /// Everything that must never leave the device, each under the name it travels as.
    private static let secrets: [String: String] = [
        "paymentSecret": "sec-payment-AAA",
        "payment_secret": "sec-payment-BBB",
        "client_secret": "sec-client-CCC",
        "encryptedPayload": jwe,
        "card_token": "tok_card_DDD",
        "token": "tok_EEE",
        "card_number": pan,
        "cvv": "739",
        "cvc": "846",
        "email": "shopper@example.com",
        "phone_number": "+420777123456",
        "first_name": "Jana",
        "last_name": "Nováková",
        "ip": "198.51.100.23",
        "user_agent": "Mozilla/5.0 (Shopper)",
        "redirect_url": "https://acs.example-bank.com/c?creq=SECRETCREQ",
        "gw_url": "https://gate.gopay.cz/gw/v3/SECRETGW",
        "access_token": "at-SECRET-FFF",
    ]

    private func body(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private func parsed(_ text: String?) -> [String: Any]? {
        text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    @Test func neverSendsASecretAJweACardTokenAPanACvvOrPii() throws {
        var request: [String: Any] = [
            "payment_instrument": "PAYMENT_CARD",
            "input": ["input_type": "APPLE_PAY", "data": "APPLE-ENCRYPTED-CARD-DATA",
                      "header": ["ephemeralPublicKey": "EPK-SECRET"]],
            "browser_data": ["ip": Self.secrets["ip"]!, "user_agent": Self.secrets["user_agent"]!,
                             "accept_header": "application/json"],
            "customer": ["email": Self.secrets["email"]!],
            // Under a name nobody would list: caught by its shape.
            "note": "card \(Self.pan) and \(Self.jwe)",
        ]
        request.merge(Self.secrets) { $1 }
        var response: [String: Any] = [
            "state": "ACTION_REQUIRED",
            "action": ["redirect_url": Self.secrets["redirect_url"]!],
            "payment_instrument": [
                "payment_instrument": "PAYMENT_CARD",
                "details": ["masked_pan": "406821******1234", "expiration_month": "11", "expiration_year": "93",
                            "scheme": "VISA", "fingerprint": "73c8d0a48d91def89761bb"],
            ],
        ]
        response.merge(Self.secrets) { $1 }

        let req = TelemetryRedaction.serializeBody(body(request), contentType: "application/json")
        let res = TelemetryRedaction.serializeBody(body(response), contentType: "application/json")

        let wire = "\(req ?? "") \(res ?? "")"
        for value in Array(Self.secrets.values) + ["APPLE-ENCRYPTED-CARD-DATA", "EPK-SECRET", "SECRETCREQ", "73c8d0a48d91def89761bb"] {
            #expect(!wire.contains(value), "\(value) left the device")
        }
        // Redacted, not dropped: a reader still sees what was there.
        let sentRequest = try #require(parsed(req))
        #expect(sentRequest["payment_instrument"] as? String == "PAYMENT_CARD")
        #expect(sentRequest["input"] as? String == "[redacted]")
        #expect((sentRequest["browser_data"] as? [String: Any])?["accept_header"] as? String == "application/json")
        let sentResponse = try #require(parsed(res))
        #expect(sentResponse["state"] as? String == "ACTION_REQUIRED")
        #expect((sentResponse["action"] as? [String: Any])?["redirect_url"] as? String == "[redacted]")
        let details = (sentResponse["payment_instrument"] as? [String: Any])?["details"] as? [String: String]
        #expect(details == [
            "masked_pan": "[redacted]", "expiration_month": "[redacted]", "expiration_year": "[redacted]",
            "scheme": "VISA", "fingerprint": "[redacted]",
        ])
    }

    /// The QR payment's answer as the gateway sends it: the codes and the recipient's account
    /// carry the account number, the IBAN and the variable symbol.
    @Test func neverSendsTheRecipientsAccountFromAQrPayment() throws {
        let qr: [String: Any] = [
            "amount": 1000,
            "currency": "CZK",
            "recipient": [
                "name": "Northline Supply s.r.o.",
                "bank_account": [
                    "local": ["prefix": "19", "account_number": "2000145399", "bank_code": "0800", "variable_symbol": "3309579117"],
                    "international": ["bic": "GIBACZPX", "iban": "CZ6508000000192000145399", "reference": "3309579117"],
                ],
                "address": ["street": "Vodičkova 1", "city": "Praha", "zip_code": "11000", "country": "CZE"],
            ],
            "qr_code": [
                "spayd": "SPD*1.0*ACC:CZ6508000000192000145399*AM:10.00*CC:CZK*X-VS:3309579117",
                "paybysquare": "0004G0005LJ4K",
                "sepa": "BCD\n002\n1\nSCT\nGIBACZPX\nNorthline\nCZ6508000000192000145399\nEUR10.00",
                "mnb_qr": "HCT\n001\n1\nGIBACZPX\nNorthline\nHU42117730161111101800000000",
            ],
        ]

        let sent = try #require(TelemetryRedaction.serializeBody(body(qr), contentType: "application/json"))

        for leak in ["2000145399", "CZ6508000000192000145399", "3309579117", "GIBACZPX", "SPD*", "HU42", "Vodičkova"] {
            #expect(!sent.contains(leak), "\(leak) left the device")
        }
        let object = try #require(parsed(sent))
        #expect(object["amount"] as? Int == 1000)
        #expect(object["recipient"] as? String == "[redacted]")
        #expect(object["qr_code"] as? String == "[redacted]")
    }

    @Test func shipsAnOrdinaryBodyAsItIs() throws {
        let sent = TelemetryRedaction.serializeBody(
            body(["error": "PAYMENT_STATE_CONFLICT", "state": "CANCELED", "amount": 1000]),
            contentType: "application/json"
        )
        let object = try #require(parsed(sent))
        #expect(object["error"] as? String == "PAYMENT_STATE_CONFLICT")
        #expect(object["state"] as? String == "CANCELED")
        #expect(object["amount"] as? Int == 1000)
        #expect(TelemetryRedaction.serializeBody(nil, contentType: nil) == nil)
        #expect(TelemetryRedaction.serializeBody(Data(), contentType: "application/json") == nil)
    }

    @Test func cutsALongBodyAtTheCap() {
        let sent = TelemetryRedaction.serializeBody(
            body(["items": Array(repeating: "item", count: 400)]), contentType: "application/json"
        )
        #expect(sent?.count == 2000)
    }

    @Test func matchesSnakeCaseKeysAgainstTheCamelCaseList() {
        let sanitized = TelemetryRedaction.sanitizeLogData([
            "redirect_url": "x", "redirectUrl": "x", "CARD_NUMBER": "x", "state": "PAID",
        ]) as? [String: String]
        #expect(sanitized == [
            "redirect_url": "[redacted]", "redirectUrl": "[redacted]", "CARD_NUMBER": "[redacted]", "state": "PAID",
        ])
    }

    @Test func redactsJsonThatArrivedAsTextByKey() {
        let sanitized = TelemetryRedaction.sanitizeLogData(#"{"payment_secret":"S3cr3tV4lueXYZ","detail":"x"}"#)
        #expect(sanitized as? [String: String] == ["payment_secret": "[redacted]", "detail": "x"])
        #expect(TelemetryRedaction.sanitizeLogData("not json, just text") as? String == "not json, just text")
    }

    /// The token request is form-encoded; its fields are read and redacted like any others.
    @Test func readsAFormBodyAsItsFields() throws {
        let sent = TelemetryRedaction.serializeBody(
            Data("grant_type=payment_credentials&scope=payment%3Acharge+payment%3Aread".utf8),
            contentType: "application/x-www-form-urlencoded"
        )
        let object = try #require(parsed(sent))
        #expect(object["grant_type"] as? String == "payment_credentials")
        #expect(object["scope"] as? String == "payment:charge payment:read")
    }

    /// One key for every entry of the two lists, each with a value nothing else would catch. Drop
    /// an entry from the lists and its key goes out as it is.
    private static let byNameOnly: [String: Any] = [
        "response": ["note": "kept"], "payment": ["note": "kept"], "paymentData": ["note": "kept"],
        "applePayPaymentData": ["note": "kept"], "googlePaymentData": ["note": "kept"],
        "card": ["brand": "VISA"], "cards": [["brand": "VISA"]], "maskedCard": ["brand": "VISA"],
        "maskedCards": [["brand": "VISA"]], "profile": ["note": "kept"], "profiles": [["note": "kept"]],
        "srcProfile": ["note": "kept"], "consumer": ["full_name": "Jana Nováková"],
        "consumerIdentity": ["note": "kept"], "identity": ["note": "kept"], "three_ds": ["version": "2.2.0"],
        "threeDSData": ["version": "2.2.0"], "challenge": ["note": "kept"], "acs": ["note": "kept"],
        "acsData": ["note": "kept"], "credential": ["note": "kept"], "credentials": ["note": "kept"],
        "checkout": ["note": "kept"], "checkoutResponse": ["note": "kept"], "checkoutResponseSignature": "plain",
        "redirectParams": ["note": "kept"], "merchantSession": ["note": "kept"],
        "merchantSessionIdentifier": "plain", "validationData": "plain", "encryptedCard": "plain",
        "recognitionToken": "plain", "idToken": "plain", "idTokens": ["plain"], "digitalCardId": "plain",
        "recipientAddress": "plain", "accountName": "Jana Nováková", "bic": "GIBACZPX",
        "input": ["input_type": "APPLE_PAY", "data": "plain"], "customer": ["full_name": "Jana Nováková"],
        "contact": ["full_name": "Jana Nováková"], "payer": ["full_name": "Jana Nováková"],
        "ip": "198.51.100.23", "ip_address": "198.51.100.23", "user_agent": "Mozilla/5.0 (Shopper)",
        "masked_pan": "plain", "card_token": "plain", "jwe_payload": "plain", "cvv": "plain", "cvc": "plain",
        "online_cryptogram": "plain", "cavv": "plain", "payment_secret": "plain", "signature": "plain",
        "password": "plain", "identityValue": "plain", "card_number": "plain", "authentication_value": "plain",
        "otp": "plain", "billing_email": "plain", "phone": "777123456", "mobile": "777123456",
        "first_name": "Jana", "last_name": "Nováková", "account_number": "2000145399", "iban": "plain",
        "redirect_url": "https://acs.example-bank.com/challenge", "maskedValidationChannel": "plain",
        "encrypted_payload": "plain", "signedMessage": "plain", "signedKey": "plain", "public_key": "plain",
        "nonce": "plain", "gw_url": "https://gate.example.com/gw/payment", "billing_address": "Vodičkova 1",
        "card_holder": "Jana Nováková", "fingerprint": "plain", "expiration_month": "12", "expiry": "12/30",
        "exp_month": "12", "exp_year": "30", "security_code": "123",
        "card_form_url": "https://gate.example.com/form/session",
        "qr_code": ["note": "kept"], "spayd": "plain", "sepa": "plain", "mnb_qr": "plain", "paybysquare": "plain",
        "bank_account": ["note": "kept"], "recipient": ["name": "Northline"],
    ]

    private func plainJSON(_ value: Any) -> String? {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    @Test func keepsEveryValueUnderAHarmlessName() {
        // The guard on the test below: a value some other rule catches would keep it green
        // whatever the lists say.
        for value in Self.byNameOnly.values {
            #expect(TelemetryRedaction.serialize(["note": value]) == plainJSON(["note": value]))
        }
    }

    @Test(arguments: Array(byNameOnly.keys))
    func dropsAKeyByItsNameAlone(_ key: String) {
        let sanitized = TelemetryRedaction.sanitizeLogData([key: Self.byNameOnly[key]!, "kept": "plain"]) as? [String: Any]
        #expect(sanitized?[key] as? String == "[redacted]")
        #expect(sanitized?["kept"] as? String == "plain")
    }

    @Test func dropsWhatNestsPastTheDepthBoundAndAnythingThatIsNotPlainData() throws {
        let sanitized = TelemetryRedaction.sanitizeLogData([
            "a": ["b": ["c": ["d": "deep"]]],
            "when": Date(timeIntervalSince1970: 0),
        ]) as? [String: Any]
        let c = ((sanitized?["a"] as? [String: Any])?["b"] as? [String: Any])?["c"] as? [String: Any]
        #expect(c?["d"] as? String == "[redacted]")
        #expect(sanitized?["when"] as? String == "[redacted]")
    }
}

struct TelemetryPathTests {

    @Test func collapsesIdsAndDropsTheQuery() {
        #expect(TelemetryRedaction.endpointTemplate("/payments/3273103424/charge") == "/payments/{id}/charge")
        #expect(
            TelemetryRedaction.endpointTemplate("/payments/3273103424/qr-payment/info?format=png")
                == "/payments/{id}/qr-payment/info"
        )
        #expect(
            TelemetryRedaction.endpointTemplate("/x/0b8e9c1e-7a52-4c1b-9d3f-2f6a1e4d5c7b") == "/x/{id}"
        )
        #expect(TelemetryRedaction.endpointTemplate("/oauth2/token") == "/oauth2/token")
    }

    @Test func namesTheActionAfterTheLastSegmentThatNamesSomething() {
        #expect(TelemetryRedaction.action(ofTemplate: "/payments/{id}") == "payments")
        #expect(TelemetryRedaction.action(ofTemplate: "/payments/{id}/charge") == "charge")
        #expect(TelemetryRedaction.action(ofTemplate: "/cards/browser-data") == "browser-data")
    }

    @Test func keepsOnlyTheOriginAndPathOfARedirect() throws {
        let url = try #require(URL(string: "https://acs.example-bank.com:8443/challenge/step?creq=SECRET#frag"))
        #expect(TelemetryRedaction.safeTarget(url) == "https://acs.example-bank.com:8443/challenge/step")
    }
}
