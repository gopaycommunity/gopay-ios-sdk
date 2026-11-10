import Foundation
import UIKit

// The names 2.x documented and 3.0 renamed, kept as deprecated aliases so an integration written
// against 2.7 builds with warnings that name the new symbol. Each alias is the new name under the
// old one and does exactly the same. They leave in 4.0. The list is sdk/docs/API_3_0.md, "Renamed".

// MARK: - Types

@available(*, deprecated, renamed: "GopayConfig")
public typealias GopaySDKConfig = GopayConfig

@available(*, deprecated, renamed: "PaymentCardForm")
public typealias GopayCardForm = PaymentCardForm

@available(*, deprecated, renamed: "PaymentCardFormTheme")
public typealias GopayCardFormTheme = PaymentCardFormTheme

@available(*, deprecated, renamed: "PaymentCardFormValidationDisplay")
public typealias GopayCardFormValidationDisplay = PaymentCardFormValidationDisplay

@available(*, deprecated, renamed: "CardData")
public typealias GopayCardData = CardData

@available(*, deprecated, renamed: "BankTransferRecipient")
public typealias QrRecipient = BankTransferRecipient

@available(*, deprecated, renamed: "RecipientBankAccount")
public typealias QrRecipientBankAccount = RecipientBankAccount

@available(*, deprecated, renamed: "BankAccountLocalDetails")
public typealias QrLocalBankAccount = BankAccountLocalDetails

@available(*, deprecated, renamed: "BankAccountInternationalDetails")
public typealias QrInternationalBankAccount = BankAccountInternationalDetails

@available(*, deprecated, renamed: "RecipientAddress")
public typealias QrRecipientAddress = RecipientAddress

// MARK: - Config and environment

public extension GopayConfig {
    @available(*, deprecated, renamed: "debugLoggingEnabled")
    var enableDebugLogging: Bool { debugLoggingEnabled }

    /// The initializer of 2.x, with `enableDebugLogging`. The argument has no default here, so a
    /// call that does not name it resolves to the initializer of 3.0 without a warning.
    @available(*, deprecated, renamed: "init(environment:clientId:shareableKey:debugLoggingEnabled:errorCallback:locale:customLocales:)")
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

// MARK: - Return address

public extension GopaySDK {
    @available(*, deprecated, renamed: "chargeReturnUrl")
    static var chargeReturnURL: String { chargeReturnUrl }
}

public extension PaymentSession {
    /// ``handle3dsVerification(redirectURL:returnUrl:presenting:)`` with the label of 2.x. The
    /// argument has no default here, so a call without it resolves to the method of 3.0.
    @available(*, deprecated, renamed: "handle3dsVerification(redirectURL:returnUrl:presenting:)")
    func handle3dsVerification(
        redirectURL: URL,
        returnURL: URL?,
        presenting: UIViewController? = nil
    ) async throws {
        try await handle3dsVerification(redirectURL: redirectURL, returnUrl: returnURL, presenting: presenting)
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
