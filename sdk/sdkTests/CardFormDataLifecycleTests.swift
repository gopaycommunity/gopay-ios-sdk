//
//  CardFormDataLifecycleTests.swift
//  sdkTests
//
//  Verifies that card data held for GopayCardForm is removed from memory once it is no
//  longer needed (GPMOB-140; PCI DSS 4.0.1, req. 3.3.1).
//

import Testing
import Foundation
import Security
@testable import sdk

// MARK: - In-memory lifecycle (no network)

struct CardFormDataLifecycleTests {

    private func makeData() -> GopayCardFormData {
        GopayCardFormData(cardNumber: "4444333322221111", expirationMonth: "12", expirationYear: "30", cvv: "123")
    }

    @Test func updateStoresAndClearRemoves() {
        let sdk = GopaySDK()
        sdk.updateCardFormData(makeData(), formId: "f1")
        #expect(sdk.internalCardFormData["f1"] != nil)
        #expect(sdk.mostRecentFormId == "f1")

        sdk.clearCardFormData(formId: "f1")
        #expect(sdk.internalCardFormData.isEmpty)
        #expect(sdk.mostRecentFormId == nil)
    }

    @Test func clearingOneFormLeavesTheOther() {
        let sdk = GopaySDK()
        sdk.updateCardFormData(makeData(), formId: "f1")
        sdk.updateCardFormData(makeData(), formId: "f2")

        sdk.clearCardFormData(formId: "f1")
        #expect(sdk.internalCardFormData["f1"] == nil)
        #expect(sdk.internalCardFormData["f2"] != nil)
        // f2 was the most recent form and must stay resolvable.
        #expect(sdk.mostRecentFormId == "f2")
    }

    @Test func clearingUnknownFormIdIsANoOp() {
        let sdk = GopaySDK()
        sdk.updateCardFormData(makeData(), formId: "f1")

        sdk.clearCardFormData(formId: "ghost")
        #expect(sdk.internalCardFormData["f1"] != nil)
        #expect(sdk.mostRecentFormId == "f1")
    }

    @Test func updateAfterClearStoresAgain() {
        // Documents the deliberate semantics: a keystroke (or the form's onAppear re-sync)
        // after a clear makes the form submittable again.
        let sdk = GopaySDK()
        sdk.updateCardFormData(makeData(), formId: "f1")
        sdk.clearCardFormData(formId: "f1")

        sdk.updateCardFormData(makeData(), formId: "f1")
        #expect(sdk.internalCardFormData["f1"] != nil)
        #expect(sdk.mostRecentFormId == "f1")
    }

    @Test func clearWithoutFormIdRemovesEverything() {
        let sdk = GopaySDK()
        sdk.updateCardFormData(makeData(), formId: "f1")
        sdk.updateCardFormData(makeData(), formId: "f2")

        sdk.clearCardFormData()
        #expect(sdk.internalCardFormData.isEmpty)
        #expect(sdk.mostRecentFormId == nil)
    }
}

// MARK: - submitCardForm cleanup (network)
//
// Declared as an extension of `SessionNetworkTests` so these tests join its
// `@Suite(.serialized)` and never race other tests for the shared `StubURLProtocol` state.

private let lifecycleStubBaseURL = "https://stub.test/"

private func lifecycleStubbedClient() -> DefaultNetworkClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return DefaultNetworkClient(baseURL: lifecycleStubBaseURL, configuration: config)
}

/// Generates a throwaway RSA-2048 key and returns its public JWK as JSON, so the full
/// `submitCardForm` → JWE path can run against the stub without a backend.
private func freshPublicJWKJSON() throws -> Data {
    let attrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeySizeInBits as String: 2048,
        kSecAttrIsPermanent as String: false,
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
          let publicKey = SecKeyCopyPublicKey(key),
          let der = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
        throw error?.takeRetainedValue() ?? NSError(domain: "test", code: -1)
    }

    // PKCS#1: RSAPublicKey ::= SEQUENCE { INTEGER n, INTEGER e }
    let bytes = [UInt8](der)
    var i = 0
    func readLength() -> Int {
        let first = Int(bytes[i]); i += 1
        guard first & 0x80 != 0 else { return first }
        var length = 0
        for _ in 0..<(first & 0x7F) { length = length << 8 | Int(bytes[i]); i += 1 }
        return length
    }
    func readInteger() -> Data {
        precondition(bytes[i] == 0x02, "expected DER INTEGER"); i += 1
        var length = readLength()
        // Skip the sign padding byte DER adds when the high bit of the value is set.
        if bytes[i] == 0x00 { i += 1; length -= 1 }
        defer { i += length }
        return Data(bytes[i..<(i + length)])
    }
    func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    precondition(bytes[i] == 0x30, "expected DER SEQUENCE"); i += 1
    _ = readLength()

    let jwk: [String: Any] = [
        "kty": "RSA", "kid": "key_test", "use": "enc", "alg": "RSA-OAEP-256",
        "n": base64url(readInteger()), "e": base64url(readInteger()),
    ]
    return try JSONSerialization.data(withJSONObject: jwk)
}

extension SessionNetworkTests {

    private func lifecycleSDK() -> GopaySDK {
        let config = GopaySDKConfig(
            environment: .development(baseURL: lifecycleStubBaseURL),
            clientId: "c",
            shareableKey: "k"
        )
        return GopaySDK(config: config, networkClient: lifecycleStubbedClient())
    }

    private func filledData() -> GopayCardFormData {
        GopayCardFormData(cardNumber: "4444333322221111", expirationMonth: "12", expirationYear: "30", cvv: "123")
    }

    @Test func submitCardForm_success_returnsJweAndClearsStorage() async throws {
        let jwkJSON = try freshPublicJWKJSON()
        StubURLProtocol.reset { req in
            (req.url?.path.hasSuffix("cards/public-key") ?? false) ? (200, jwkJSON) : (404, Data())
        }
        let sdk = lifecycleSDK()
        sdk.updateCardFormData(filledData(), formId: "f1")

        let jwe = try await sdk.submitCardForm()
        #expect(jwe.split(separator: ".").count == 5) // compact JWE serialization
        #expect(sdk.internalCardFormData.isEmpty)
        #expect(sdk.mostRecentFormId == nil)

        // The data is gone, so a second submit for the same form must fail.
        do {
            _ = try await sdk.submitCardForm()
            Issue.record("expected noCardFormData")
        } catch let error as GopaySDKError {
            #expect(error.code == .validationInvalidInput)
            #expect(error.message == GopaySDKErrors.noCardFormData)
        }
    }

    @Test func submitCardForm_encryptionFailure_keepsData() async throws {
        // Key endpoint down → encryption can't happen. Authorization hasn't occurred yet,
        // so the user's input must survive for a retry (deliberate decision, GPMOB-140).
        StubURLProtocol.reset { _ in (500, Data()) }
        let sdk = lifecycleSDK()
        sdk.updateCardFormData(filledData(), formId: "f1")

        await #expect(throws: GopaySDKError.self) {
            _ = try await sdk.submitCardForm()
        }
        #expect(sdk.internalCardFormData["f1"] != nil)
        #expect(sdk.mostRecentFormId == "f1")
    }
}
