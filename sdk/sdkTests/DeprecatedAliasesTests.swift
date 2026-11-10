//
//  DeprecatedAliasesTests.swift
//  sdkTests
//
//  Code as an integration wrote it against 2.7, under the names 3.0 deprecates. That this file
//  compiles is the first half of the test: every renamed symbol still has its old name. The
//  second half is that an alias is the new name and nothing else. The file imports the SDK
//  without `@testable`, so it sees what a host sees. The deprecation warnings it raises are the
//  point; do not rename anything here.
//

import Testing
import Foundation
import SwiftUI
import sdk

struct DeprecatedAliasesTests {

    @Test func theConfigOf2xBuildsTheConfigOf3() {
        let old = GopaySDKConfig(
            environment: .development(baseURL: "https://gw.example/api/"),
            clientId: "id", shareableKey: "key", enableDebugLogging: true, locale: "cs"
        )
        let new: GopayConfig = old

        #expect(new.debugLoggingEnabled)
        #expect(old.enableDebugLogging == new.debugLoggingEnabled)
        #expect(new.environment == .development(baseUrl: "https://gw.example/api/"))
        #expect(new.environment.baseURL == new.environment.baseUrl)
        #expect(new.clientId == "id")
        #expect(new.shareableKey == "key")
        #expect(new.locale == "cs")
    }

    /// A call that names neither `enableDebugLogging` nor `debugLoggingEnabled` is not ambiguous.
    @Test func aConfigWithoutTheFlagStillBuilds() {
        let config = GopaySDKConfig(environment: .sandbox)

        #expect(config.debugLoggingEnabled == false)
        #expect(GopayEnvironment.sandbox.baseURL == GopayEnvironment.sandbox.baseUrl)
    }

    @Test func theReturnAddressKeepsItsOldSpelling() {
        let url = URL(string: "https://shop.example/return")

        var options = AwaitChargeOptions(interval: 2, returnURL: url)
        #expect(options.returnUrl == url)
        #expect(options.interval == 2)
        options.returnURL = nil
        #expect(options.returnUrl == nil)
        // Without the label the call is the initializer of 3.0, not an ambiguity.
        #expect(AwaitChargeOptions().returnURL == nil)

        #expect(GopaySDK.chargeReturnURL == GopaySDK.chargeReturnUrl)
    }

    /// `GopayCardData` and the QR models keep their names of 2.7 in 3.0, so this code builds
    /// without a warning. Only `mnbQR` is an alias, of `mnbQr`.
    @Test func theCardDataAndTheQrModelsKeepTheirNames() throws {
        let card = GopayCardData(cardPan: "4444444444444448", expMonth: "12", expYear: "28", cvv: "123")
        #expect(card.cardPan == "4444444444444448")

        let json = """
        {
          "name": "Shop",
          "bank_account": {
            "local": { "prefix": "", "account_number": "123", "bank_code": "0100", "variable_symbol": "1" },
            "international": { "iban": "CZ00", "bic": "KOMB" }
          },
          "address": { "street": "Main 1", "city": "Praha" }
        }
        """
        let recipient: QrRecipient = try JSONDecoder().decode(QrRecipient.self, from: Data(json.utf8))
        let account: QrRecipientBankAccount? = recipient.bankAccount
        let local: QrLocalBankAccount? = account?.local
        let international: QrInternationalBankAccount? = account?.international
        let address: QrRecipientAddress? = recipient.address

        #expect(recipient.name == "Shop")
        #expect(local?.accountNumber == "123")
        #expect(international?.iban == "CZ00")
        #expect(address?.city == "Praha")

        let codes = try JSONDecoder().decode(QrCodeList.self, from: Data(#"{ "mnb_qr": "HCT" }"#.utf8))
        #expect(codes.mnbQR == "HCT")
        #expect(codes.mnbQR == codes.mnbQr)
    }

    @Test func theFormNamesOf2xAreTheFormOf3() {
        let theme = GopayCardFormTheme()
        let display: GopayCardFormValidationDisplay = .live
        let form = GopayCardForm(theme: theme, locale: "en", validation: display, formId: "aliases")
        let same: PaymentCardForm = form
        let sameTheme: PaymentCardFormTheme = theme

        _ = same
        _ = sameTheme
        // A form with every argument left out is not ambiguous either.
        _ = GopayCardForm()
    }

    /// A host of 2.x that kept the validity as `Bool?` still builds: the form reads `nil` as
    /// `false` and writes `Bool`s. A `Bool` state picks the initializer of 3.0 by its type.
    @Test func aFormStillTakesTheOptionalValidityOf2x() {
        var optional: Bool? = nil
        var plain = false
        let old = Binding<Bool?>(get: { optional }, set: { optional = $0 })
        let new = Binding<Bool>(get: { plain }, set: { plain = $0 })

        let deprecated = GopayCardForm(locale: "cs", validation: .live, isValid: old, formId: "old-validity")
        let current = PaymentCardForm(locale: "cs", validation: .onSubmit, isValid: new, formId: "new-validity")

        #expect(deprecated.isValid == false)
        deprecated.isValid = true
        #expect(optional == true)
        #expect(current.isValid == false)
    }

    @Test func registeringALocaleTakesTheStringsFirstAsIn2x() {
        defer { GopayLocales.clearCustom() }

        GopayLocales.register(GopayLocales.en, for: "x1")
        GopayLocales.register("x2", strings: GopayLocales.en)

        #expect(GopayLocales.availableCodes().contains("x1"))
        #expect(GopayLocales.availableCodes().contains("x2"))
    }
}

extension SessionNetworkTests {

    /// `handle3dsVerification` under the labels of 2.x is the call of 3.0: a redirect address the
    /// WebView cannot load ends both the same way, before anything is presented, in every form
    /// the call of 2.x had.
    @Test func the3dsCallOf2xEndsLikeTheCallOf3() async throws {
        StubURLProtocol.reset(handler: Self.gatewayHandler())
        let session = try await makeSession()
        let unloadable = try #require(URL(string: "ftp://acs.example/challenge"))
        let returnAddress = URL(string: "https://shop.example/return")

        func outcome(_ call: () async throws -> Void) async -> GopaySDKError? {
            do { try await call() } catch let error as GopaySDKError { return error } catch {}
            return nil
        }

        let current = await outcome { try await session.handle3dsVerification(redirectUrl: unloadable, returnUrl: returnAddress) }
        let old = [
            await outcome { try await session.handle3dsVerification(redirectURL: unloadable) },
            await outcome { try await session.handle3dsVerification(redirectURL: unloadable, returnURL: returnAddress) },
            await outcome { try await session.handle3dsVerification(redirectURL: unloadable, presenting: nil) },
            await outcome { try await session.handle3dsVerification(redirectURL: unloadable, returnURL: returnAddress, presenting: nil) },
        ]

        #expect(current?.code == .paymentVerificationUnreachable)
        for error in old {
            #expect(error?.code == current?.code)
            #expect(error?.message == current?.message)
        }
    }
}

/// The wallet and the 3DS screen under their old names: compiled, never run, since both need a
/// payment. That they still resolve is what an integration needs to build.
@available(*, deprecated)
func deprecatedSessionCallsStillCompile(_ session: PaymentSession, redirect: URL) async throws {
    _ = try await session.getApplePayInfo()
    _ = try await session.chargeWithApplePay()
    _ = try await session.chargeWithApplePay(browserData: nil, challengePreference: nil)
    // Every form of the 3DS call 2.x had, under `redirectURL` and `returnURL`.
    try await session.handle3dsVerification(redirectURL: redirect)
    try await session.handle3dsVerification(redirectURL: redirect, returnURL: nil)
    try await session.handle3dsVerification(redirectURL: redirect, presenting: nil)
    try await session.handle3dsVerification(redirectURL: redirect, returnURL: redirect, presenting: nil)
    _ = GopaySDK.canUseApplePay()
}
