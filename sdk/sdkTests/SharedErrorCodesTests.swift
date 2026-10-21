//
//  SharedErrorCodesTests.swift
//  sdkTests
//
//  Pins the error codes both SDKs throw for the same condition where a platform exception used to
//  leak out (GPMOB-160): CONFIG_001 before initialize, VALIDATION_007 for bad input, INTERNAL_001
//  for a card encryption that fails. The Android SDK has the matching tests.
//

import Testing
import Foundation
@testable import sdk

// MARK: - CONFIG_001 before initialize

/// `GopaySDK()` stands in for `GopaySDK.shared` before `initialize(with:)`: the same `nil` config
/// over the same sandbox-backed internals. The config guard throws before anything could reach
/// the network, which is what keeps these tests off the real sandbox.
struct NotInitializedTests {

    private func code(of error: Error) -> GopaySDKError.Code? { (error as? GopaySDKError)?.code }

    @Test func startPaymentSessionThrowsNotInitialized() async {
        let sdk = GopaySDK()
        do {
            _ = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
            Issue.record("expected failure")
        } catch {
            #expect(code(of: error) == .sdkNotInitialized)
        }
    }

    /// The config is checked before the credentials, as the Android `getInstance()` runs before
    /// the `require`: an uninitialized SDK says so whatever else is wrong.
    @Test func startPaymentSessionChecksTheConfigBeforeTheCredentials() async {
        let sdk = GopaySDK()
        do {
            _ = try await sdk.startPaymentSession(paymentId: "", paymentSecret: "")
            Issue.record("expected failure")
        } catch {
            #expect(code(of: error) == .sdkNotInitialized)
        }
    }

    @Test func encryptCardDataThrowsNotInitialized() async {
        let sdk = GopaySDK()
        let card = GopayCardData(cardPan: "4444333322221111", expMonth: "12", expYear: "30", cvv: "123")
        do {
            _ = try await sdk.encryptCardData(card)
            Issue.record("expected failure")
        } catch {
            #expect(code(of: error) == .sdkNotInitialized)
        }
    }

    @Test func submitCardFormThrowsNotInitializedAndKeepsTheCard() async {
        let sdk = GopaySDK()
        sdk.updateCardFormData(
            GopayCardFormData(cardNumber: "4444333322221111", expirationMonth: "12", expirationYear: "30", cvv: "123"),
            formId: "f1"
        )
        do {
            _ = try await sdk.submitCardForm(formId: "f1")
            Issue.record("expected failure")
        } catch {
            #expect(code(of: error) == .sdkNotInitialized)
        }
        // Nothing was authorized, so the form keeps what the user typed, as after any failure.
        #expect(sdk.internalCardFormData["f1"] != nil)
    }
}

// MARK: - VALIDATION_007 for bad input

/// One card `encryptCardData` has to refuse, and why. The same table runs on Android.
struct InvalidCardCase: CustomTestStringConvertible, Sendable {
    let name: String
    let pan: String
    let month: String
    let year: String
    let cvv: String

    var testDescription: String { name }
}

let invalidCardCases: [InvalidCardCase] = [
    InvalidCardCase(name: "empty PAN", pan: "", month: "12", year: "30", cvv: "123"),
    InvalidCardCase(name: "PAN of 12 digits", pan: "444433332222", month: "12", year: "30", cvv: "123"),
    InvalidCardCase(name: "PAN of 20 digits", pan: "44443333222211110000", month: "12", year: "30", cvv: "123"),
    InvalidCardCase(name: "PAN with a letter", pan: "4444333322221111a", month: "12", year: "30", cvv: "123"),
    InvalidCardCase(name: "month 00", pan: "4444333322221111", month: "00", year: "30", cvv: "123"),
    InvalidCardCase(name: "month 13", pan: "4444333322221111", month: "13", year: "30", cvv: "123"),
    InvalidCardCase(name: "month of one digit", pan: "4444333322221111", month: "1", year: "30", cvv: "123"),
    InvalidCardCase(name: "year of one digit", pan: "4444333322221111", month: "12", year: "3", cvv: "123"),
    InvalidCardCase(name: "year of five digits", pan: "4444333322221111", month: "12", year: "20300", cvv: "123"),
    InvalidCardCase(name: "CVV of two digits", pan: "4444333322221111", month: "12", year: "30", cvv: "12"),
    InvalidCardCase(name: "CVV of five digits", pan: "4444333322221111", month: "12", year: "30", cvv: "12345"),
    InvalidCardCase(name: "CVV with a letter", pan: "4444333322221111", month: "12", year: "30", cvv: "12a"),
]

// Part of the serialized `SessionNetworkTests`: these build the SDK over the shared stub, and a
// request that did get out would be answered by it, never by the sandbox.
extension SessionNetworkTests {

    private func validationSDK() -> GopaySDK {
        GopaySDK(
            config: GopaySDKConfig(environment: .development(baseURL: stubBaseURL), clientId: "c", shareableKey: "k"),
            networkClient: stubbedClient()
        )
    }

    /// Refused before the key is fetched: the stub answers 500 to anything, so a fetch would fail
    /// with another code and the request would show in the recorded paths.
    @Test(arguments: invalidCardCases)
    func encryptCardDataRefusesAnInvalidCard(_ testCase: InvalidCardCase) async {
        StubURLProtocol.reset { _ in (500, Data()) }
        let card = GopayCardData(cardPan: testCase.pan, expMonth: testCase.month, expYear: testCase.year, cvv: testCase.cvv)
        do {
            _ = try await validationSDK().encryptCardData(card)
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .validationInvalidInput)
        } catch {
            Issue.record("expected a GopaySDKError, got \(error)")
        }
        #expect(StubURLProtocol.paths.isEmpty)
    }

    /// Empty and blank alike, as the Android `isBlank` check: nothing goes to the gateway.
    @Test(arguments: [("", "secret"), ("p1", ""), ("   ", "secret"), ("p1", " \n")])
    func startPaymentSessionRefusesEmptyOrBlankCredentials(paymentId: String, paymentSecret: String) async {
        StubURLProtocol.reset { _ in tokenResponse() }
        do {
            _ = try await validationSDK().startPaymentSession(paymentId: paymentId, paymentSecret: paymentSecret)
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .validationInvalidInput)
        } catch {
            Issue.record("expected a GopaySDKError, got \(error)")
        }
        #expect(StubURLProtocol.paths.isEmpty)
    }

    // MARK: INTERNAL_001 for a failed encryption

    /// The gateway serves a key the SDK cannot build a public key from: the fetch succeeded, so
    /// its codes do not apply, and the encryption step that failed is named in the message.
    @Test func anUnusableKeyFailsEncryptCardDataWithAnUnexpectedError() async {
        let brokenKey = json(["kty": "RSA", "kid": "k", "use": "enc", "alg": "RSA-OAEP-256", "n": "!!!", "e": "AQAB"])
        StubURLProtocol.reset { req in
            (req.url?.path.hasSuffix("cards/public-key") ?? false) ? (200, brokenKey) : (404, Data())
        }
        let card = GopayCardData(cardPan: "4444333322221111", expMonth: "12", expYear: "30", cvv: "123")

        do {
            _ = try await validationSDK().encryptCardData(card)
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .unexpected)
            #expect(error.message.contains(GopaySDKErrors.jwePublicKeyCreationFailed))
        } catch {
            Issue.record("expected a GopaySDKError, got \(error)")
        }
        #expect(StubURLProtocol.requestCount(forPathSuffix: "cards/public-key") == 1)
    }
}

struct CardEncryptionFailureTests {

    /// The system's error, when the step produced one, rides along as `underlying`.
    @Test func aFailedStepKeepsTheSystemErrorAsUnderlying() {
        let cause = NSError(domain: "test", code: 7)
        let error = JweUtils.encryptionError(GopaySDKErrors.jweEncryptionFailed, underlying: cause)
        #expect(error.code == .unexpected)
        #expect(error.message.hasPrefix("Card encryption failed: "))
        #expect((error.underlying as NSError?)?.code == 7)
    }
}
