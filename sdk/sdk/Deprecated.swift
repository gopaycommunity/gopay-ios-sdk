import Foundation
import SwiftUI
import UIKit

// The names 2.x documented and 3.0 renamed, kept as deprecated aliases so an integration written
// against 2.7 builds with warnings that name the new symbol. Each alias is the new name under the
// old one and does exactly the same. They leave in 4.0. The list is sdk/docs/API_3_0.md, "Renamed".
// `GopayCardData` and the QR models (`QrRecipient` and the rest) are not here: they keep their
// names of 2.7 in 3.0, on both platforms.

// MARK: - Types

@available(*, deprecated, renamed: "GopayConfig")
public typealias GopaySDKConfig = GopayConfig

@available(*, deprecated, renamed: "PaymentCardForm")
public typealias GopayCardForm = PaymentCardForm

@available(*, deprecated, renamed: "PaymentCardFormTheme")
public typealias GopayCardFormTheme = PaymentCardFormTheme

@available(*, deprecated, renamed: "PaymentCardFormValidationDisplay")
public typealias GopayCardFormValidationDisplay = PaymentCardFormValidationDisplay

// MARK: - Config and environment

public extension GopayConfig {
    @available(*, deprecated, renamed: "debugLoggingEnabled")
    var enableDebugLogging: Bool { debugLoggingEnabled }

    /// The initializer of 2.x, with `enableDebugLogging`. The argument has no default here, so a
    /// call that does not name it resolves to the initializer of 3.0 without a warning.
    @available(*, deprecated, renamed: "init(environment:clientId:shareableKey:debugLoggingEnabled:errorCallback:locale:customLocales:requestTimeout:)")
    init(
        environment: GopayEnvironment,
        clientId: String? = nil,
        shareableKey: String? = nil,
        enableDebugLogging: Bool,
        errorCallback: (@Sendable (Error) -> Void)? = nil,
        locale: String? = nil,
        customLocales: [String: GopayLocaleStrings] = [:]
    ) {
        self.init(
            environment: environment,
            clientId: clientId,
            shareableKey: shareableKey,
            debugLoggingEnabled: enableDebugLogging,
            errorCallback: errorCallback,
            locale: locale,
            customLocales: customLocales
        )
    }
}

public extension GopayEnvironment {
    /// Builds ``development(baseUrl:)``. An alias for building the value only: a `switch` that
    /// matches `case .development(baseURL: let url)` has to be renamed by hand.
    @available(*, deprecated, renamed: "development(baseUrl:)")
    static func development(baseURL: String) -> GopayEnvironment { .development(baseUrl: baseURL) }

    @available(*, deprecated, renamed: "baseUrl")
    var baseURL: String { baseUrl }
}

// MARK: - Card form

public extension PaymentCardForm {
    /// The initializer of 2.x for a host that keeps the validity as `Bool?`: `nil` was only the
    /// value the host started at, so it reads as `false` here. `isValid` has no default, so a
    /// form created without it resolves to the initializer of 3.0.
    @available(*, deprecated, message: "isValid is a Binding<Bool> in 3.0; keep the validity as Bool, starting at false")
    init(
        theme: PaymentCardFormTheme = PaymentCardFormTheme(),
        locale: String? = nil,
        localeStrings: GopayLocaleStrings? = nil,
        validation: PaymentCardFormValidationDisplay = .hidden,
        isValid: Binding<Bool?>,
        formId: String? = nil,
        allowsAutofill: Bool = false
    ) {
        self.init(
            theme: theme,
            locale: locale,
            localeStrings: localeStrings,
            validation: validation,
            isValid: Binding<Bool>(get: { isValid.wrappedValue ?? false }, set: { isValid.wrappedValue = $0 }),
            formId: formId,
            allowsAutofill: allowsAutofill
        )
    }
}

// MARK: - Return address

public extension GopaySDK {
    @available(*, deprecated, renamed: "chargeReturnUrl")
    static var chargeReturnURL: String { chargeReturnUrl }
}

public extension PaymentSession {
    /// ``handle3dsVerification(redirectUrl:returnUrl:presenting:)`` with the labels of 2.x. The
    /// first label tells the two apart, so every call of 2.x resolves here, with or without the
    /// return address and the presenter.
    @available(*, deprecated, renamed: "handle3dsVerification(redirectUrl:returnUrl:presenting:)")
    func handle3dsVerification(
        redirectURL: URL,
        returnURL: URL? = nil,
        presenting: UIViewController? = nil
    ) async throws {
        try await handle3dsVerification(redirectUrl: redirectURL, returnUrl: returnURL, presenting: presenting)
    }
}

public extension AwaitChargeOptions {
    @available(*, deprecated, renamed: "returnUrl")
    var returnURL: URL? {
        get { returnUrl }
        set { returnUrl = newValue }
    }

    /// The initializer of 2.x, with `returnURL`. The argument has no default here, so a call
    /// that does not name it resolves to the initializer of 3.0 without a warning.
    @available(*, deprecated, renamed: "init(interval:initialTimeout:threeDSMode:returnUrl:presenting:onStateChange:onActionRequired:)")
    init(
        interval: TimeInterval = 1,
        initialTimeout: TimeInterval = 30,
        threeDSMode: ThreeDSMode = .automatic,
        returnURL: URL?,
        presenting: UIViewController? = nil,
        onStateChange: (@MainActor @Sendable (ChargePaymentResponse) -> Void)? = nil,
        onActionRequired: (@MainActor @Sendable (String) -> Void)? = nil
    ) {
        self.init(
            interval: interval,
            initialTimeout: initialTimeout,
            threeDSMode: threeDSMode,
            returnUrl: returnURL,
            presenting: presenting,
            onStateChange: onStateChange,
            onActionRequired: onActionRequired
        )
    }
}

// MARK: - Wallet

public extension PaymentSession {
    /// The platform name of ``getWalletInfo()``, which does the same.
    @available(*, deprecated, renamed: "getWalletInfo()")
    func getApplePayInfo() async throws -> GopayApplePayAppInfoResponse {
        try await getWalletInfo()
    }

    /// The platform name of ``chargeWithWallet(browserData:challengePreference:)``, which does
    /// the same with the same arguments.
    @available(*, deprecated, renamed: "chargeWithWallet(browserData:challengePreference:)")
    func chargeWithApplePay(
        browserData: BrowserData? = nil,
        challengePreference: ChallengePreference? = nil
    ) async throws -> ChargePaymentResponse {
        try await chargeWithWallet(browserData: browserData, challengePreference: challengePreference)
    }
}

// MARK: - QR and locales

public extension QrCodeList {
    @available(*, deprecated, renamed: "mnbQr")
    var mnbQR: String? { mnbQr }
}

public extension GopayLocales {
    @available(*, deprecated, renamed: "register(_:strings:)")
    static func register(_ strings: GopayLocaleStrings, for code: String) {
        register(code, strings: strings)
    }
}
