//
//  GatewayErrorBodyTests.swift
//  sdkTests
//
//  Pins what the SDK keeps of the gateway's error body (`Error-Response-Body`): `error`,
//  `message` and `detail` in `gatewayError`, the message in the error's own message, and nothing
//  that breaks on a body that is missing, partial or not JSON. The Android SDK reads the same
//  three fields into `HttpErrorContext`.
//

import Testing
import Foundation
@testable import sdk

struct GatewayErrorParsingTests {

    /// The body production answered `apple-pay/app-info` with on 30 Sep 2026, `detail` missing
    /// although the spec lists it as required.
    @Test func aBodyWithoutDetailIsRead() throws {
        let body = Data("""
        {"code":403,"error":"FORBIDDEN","message":"Apple Pay in-app is not enabled for this merchant",
         "path":"/payments/1/apple-pay/app-info","timestamp":"2026-09-30T17:32:39.126208292Z"}
        """.utf8)

        let parsed = try #require(GopayGatewayError.parse(body))

        #expect(parsed.error == "FORBIDDEN")
        #expect(parsed.message == "Apple Pay in-app is not enabled for this merchant")
        #expect(parsed.detail == nil)
    }

    @Test func aFullBodyIsRead() throws {
        let body = Data("""
        {"code":400,"error":"BAD_REQUEST","message":"IP address of the customer's browser is required",
         "detail":"paymentInstrument.browserData.ip: IP address of the customer's browser is required",
         "path":"/payments/1/charge","timestamp":"2026-09-30T17:32:39Z"}
        """.utf8)

        let parsed = try #require(GopayGatewayError.parse(body))

        #expect(parsed.error == "BAD_REQUEST")
        #expect(parsed.detail == "paymentInstrument.browserData.ip: IP address of the customer's browser is required")
    }

    @Test(arguments: ["", "not json", "[]", "{}", #"{"code":500}"#])
    func aBodyWithNothingToReadIsNil(raw: String) {
        #expect(GopayGatewayError.parse(Data(raw.utf8)) == nil)
    }

    @Test func aFieldOfAnotherTypeIsSkipped() throws {
        let parsed = try #require(GopayGatewayError.parse(Data(#"{"error":7,"message":"m"}"#.utf8)))
        #expect(parsed.error == nil)
        #expect(parsed.message == "m")
    }
}

extension SessionNetworkTests {

    @Test func aGatewayErrorKeepsItsBodyAndSaysWhy() async throws {
        StubURLProtocol.reset { req in
            if (req.url?.path ?? "").hasSuffix("oauth2/token") { return tokenResponse() }
            return (403, json([
                "code": 403, "error": "FORBIDDEN",
                "message": "Apple Pay in-app is not enabled for this merchant",
                "path": "/payments/p1/apple-pay/app-info"
            ]))
        }
        let session = try await makeSession()

        do {
            _ = try await session.getApplePayInfo()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .networkClientError)
            #expect(error.httpStatus == 403)
            #expect(error.gatewayError?.error == "FORBIDDEN")
            #expect(error.message == "Failed to get Apple Pay info: HTTP 403: Apple Pay in-app is not enabled for this merchant")
        }
    }

    @Test func aGatewayErrorWithoutABodyKeepsTheStatusMessage() async throws {
        StubURLProtocol.reset { req in
            (req.url?.path ?? "").hasSuffix("oauth2/token") ? tokenResponse() : (502, Data("<html>bad gateway</html>".utf8))
        }
        let session = try await makeSession()

        do {
            _ = try await session.getChargeState()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .networkServerError)
            #expect(error.gatewayError == nil)
            #expect(error.message.hasSuffix("HTTP 502"))
        }
    }

    @Test func rejectedCredentialsKeepTheGatewayReason() async throws {
        StubURLProtocol.reset { _ in
            (401, json(["code": 401, "error": "UNAUTHORIZED", "message": "Invalid payment_id or payment_secret"]))
        }

        do {
            _ = try await makeSession()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentCredentialsInvalid)
            #expect(error.gatewayError?.message == "Invalid payment_id or payment_secret")
            #expect(error.message.hasSuffix(": Invalid payment_id or payment_secret"))
        }
    }

    /// The second 401 after re-authenticating carries the gateway's body too.
    @Test func aStaleTokenRejectedTwiceKeepsTheGatewayReason() async throws {
        StubURLProtocol.reset { req in
            if (req.url?.path ?? "").hasSuffix("oauth2/token") { return tokenResponse() }
            return (401, json(["code": 401, "error": "UNAUTHORIZED", "message": "Token expired"]))
        }
        let session = try await makeSession()

        do {
            _ = try await session.getChargeState()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentTokenExpired)
            #expect(error.gatewayError?.error == "UNAUTHORIZED")
            #expect(error.message.hasSuffix(": Token expired"))
        }
    }

    /// A message that is empty or only white space adds nothing to the SDK's own.
    @Test(arguments: ["", "   ", "\n"])
    func anEmptyGatewayMessageAddsNothing(message: String) async throws {
        StubURLProtocol.reset { req in
            if (req.url?.path ?? "").hasSuffix("oauth2/token") { return tokenResponse() }
            return (404, json(["code": 404, "error": "NOT_FOUND", "message": message]))
        }
        let session = try await makeSession()

        do {
            _ = try await session.getChargeState()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.gatewayError?.error == "NOT_FOUND")
            #expect(error.message.hasSuffix("HTTP 404"))
        }
    }
}
