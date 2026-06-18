import Foundation

/// Card scheme. Maps to `Card-Scheme` in Payments.yaml.
public enum CardScheme: String, Codable {
    case visa = "VISA"
    case mastercard = "MASTERCARD"
}

/// State of a charge. Maps to `Charge-State`.
public enum ChargeState: String, Codable {
    case requested = "REQUESTED"
    case processing = "PROCESSING"
    case actionRequired = "ACTION_REQUIRED"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
}

/// 3DS challenge preference forwarded to the gateway. Maps to `Payment-Card-Challenge-Preference`.
public enum ChallengePreference: String, Codable {
    case challengePreferred = "CHALLENGE_PREFERRED"
    case noChallengePreferred = "NO_CHALLENGE_PREFERRED"
    case auto = "AUTO"
}

/// Follow-up action type required to complete a charge. Maps to the `action_type` of
/// `Payment-Charge-Action` (currently only `EMV3DS`).
public enum ChargeActionType: String, Codable {
    case emv3ds = "EMV3DS"
}

/// EMV 3DS sub-state reported on a charge action. Maps to the `state` of `Payment-Charge-Action`.
public enum Emv3dsState: String, Codable {
    case created = "CREATED"
    case challengeRequired = "CHALLENGE_REQUIRED"
    case authenticatedChallenge = "AUTHENTICATED_CHALLENGE"
    case authenticatedFrictionless = "AUTHENTICATED_FRICTIONLESS"
    case notAuthenticated = "NOT_AUTHENTICATED"
    case failed = "FAILED"
}

/// Browser data collected for 3DS authentication. Required on every card charge regardless of the
/// input type. Maps to `Browser-Data`.
public struct BrowserData: Encodable {
    public let language: String
    public let timezone: Int
    public let screenWidth: Int
    public let screenHeight: Int
    public let colorDepth: Int
    public let userAgent: String?
    public let acceptHeader: String?
    public let javascriptEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case language
        case timezone
        case screenWidth = "screen_width"
        case screenHeight = "screen_height"
        case colorDepth = "color_depth"
        case userAgent = "user_agent"
        case acceptHeader = "accept_header"
        case javascriptEnabled = "javascript_enabled"
    }

    public init(
        language: String,
        timezone: Int,
        screenWidth: Int,
        screenHeight: Int,
        colorDepth: Int,
        userAgent: String? = nil,
        acceptHeader: String? = nil,
        javascriptEnabled: Bool? = nil
    ) {
        self.language = language
        self.timezone = timezone
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.colorDepth = colorDepth
        self.userAgent = userAgent
        self.acceptHeader = acceptHeader
        self.javascriptEnabled = javascriptEnabled
    }
}

/// Header fields embedded in an Apple Pay payment token. Maps to the nested `header` object on
/// `Apple-Pay-Input` (camelCase keys, as carried in the PassKit token).
public struct ApplePayHeader: Encodable {
    public let ephemeralPublicKey: String
    public let publicKeyHash: String
    public let transactionId: String

    public init(ephemeralPublicKey: String, publicKeyHash: String, transactionId: String) {
        self.ephemeralPublicKey = ephemeralPublicKey
        self.publicKeyHash = publicKeyHash
        self.transactionId = transactionId
    }
}

/// Card-payment input — the discriminated `oneOf` over `input_type`. Maps to `Payment-Card-Input`.
///
/// iOS exposes the `CARD_TOKEN` and `APPLE_PAY` variants (Google Pay is Android-only). Optional
/// fields that don't belong to the active variant are `nil` and omitted from the encoded JSON.
/// Use the factories rather than the memberwise initializer.
public struct PaymentCardInput: Encodable {
    public let inputType: String
    // CARD_TOKEN
    public let cardToken: String?
    // APPLE_PAY
    public let data: String?
    public let signature: String?
    public let version: String?
    public let header: ApplePayHeader?

    enum CodingKeys: String, CodingKey {
        case inputType = "input_type"
        case cardToken = "card_token"
        case data
        case signature
        case version
        case header
    }

    private init(
        inputType: String,
        cardToken: String? = nil,
        data: String? = nil,
        signature: String? = nil,
        version: String? = nil,
        header: ApplePayHeader? = nil
    ) {
        self.inputType = inputType
        self.cardToken = cardToken
        self.data = data
        self.signature = signature
        self.version = version
        self.header = header
    }

    /// `CARD_TOKEN` input — a permanent card token the merchant tokenized server-side.
    public static func cardToken(_ cardToken: String) -> PaymentCardInput {
        PaymentCardInput(inputType: "CARD_TOKEN", cardToken: cardToken)
    }

    /// `APPLE_PAY` input — fields extracted from a `PKPaymentToken`.
    public static func applePay(
        data: String,
        signature: String,
        version: String,
        header: ApplePayHeader
    ) -> PaymentCardInput {
        PaymentCardInput(
            inputType: "APPLE_PAY",
            data: data,
            signature: signature,
            version: version,
            header: header
        )
    }
}

/// Card-instrument variant of the `Payment-Charge-Data` union. Carries the input together with the
/// required browser data and an optional 3DS challenge preference. Maps to
/// `Payment-Card-Charge-Data`.
///
/// The current Payments 4.0 schema only defines `PAYMENT_CARD` for `payment_instrument`.
public struct PaymentChargeInstrument: Encodable {
    public let paymentInstrument: String
    public let input: PaymentCardInput
    public let browserData: BrowserData
    public let challengePreference: ChallengePreference?

    enum CodingKeys: String, CodingKey {
        case paymentInstrument = "payment_instrument"
        case input
        case browserData = "browser_data"
        case challengePreference = "challenge_preference"
    }

    public init(
        input: PaymentCardInput,
        browserData: BrowserData,
        challengePreference: ChallengePreference? = nil,
        paymentInstrument: String = "PAYMENT_CARD"
    ) {
        self.paymentInstrument = paymentInstrument
        self.input = input
        self.browserData = browserData
        self.challengePreference = challengePreference
    }
}

/// Request body for `POST /payments/{payment_id}/charge`. Maps to `Payment-Charge-Input`.
///
/// Use the factories for the common card-token and Apple Pay flows.
public struct ChargePaymentRequest: Encodable {
    public let paymentInstrument: PaymentChargeInstrument

    enum CodingKeys: String, CodingKey {
        case paymentInstrument = "payment_instrument"
    }

    public init(paymentInstrument: PaymentChargeInstrument) {
        self.paymentInstrument = paymentInstrument
    }

    /// Charge with a permanent card token.
    public static func cardToken(
        _ cardToken: String,
        browserData: BrowserData,
        challengePreference: ChallengePreference? = nil
    ) -> ChargePaymentRequest {
        ChargePaymentRequest(
            paymentInstrument: PaymentChargeInstrument(
                input: .cardToken(cardToken),
                browserData: browserData,
                challengePreference: challengePreference
            )
        )
    }

    /// Charge with an Apple Pay token.
    public static func applePay(
        data: String,
        signature: String,
        version: String,
        header: ApplePayHeader,
        browserData: BrowserData,
        challengePreference: ChallengePreference? = nil
    ) -> ChargePaymentRequest {
        ChargePaymentRequest(
            paymentInstrument: PaymentChargeInstrument(
                input: .applePay(data: data, signature: signature, version: version, header: header),
                browserData: browserData,
                challengePreference: challengePreference
            )
        )
    }
}

/// Output card details returned in a charge response. Maps to `Payment-Card-Charge-Details`.
public struct InstrumentDetails: Codable {
    public let inputType: String
    public let maskedPan: String?
    public let expirationMonth: String?
    public let expirationYear: String?
    public let scheme: CardScheme?
    public let fingerprint: String?

    enum CodingKeys: String, CodingKey {
        case inputType = "input_type"
        case maskedPan = "masked_pan"
        case expirationMonth = "expiration_month"
        case expirationYear = "expiration_year"
        case scheme
        case fingerprint
    }
}

/// Payment instrument block in a charge response. `paymentInstrument` is always `PAYMENT_CARD` for
/// the current Payments 4.0 schema.
public struct PaymentInstrumentData: Codable {
    public let paymentInstrument: String
    public let details: InstrumentDetails

    enum CodingKeys: String, CodingKey {
        case paymentInstrument = "payment_instrument"
        case details
    }
}

/// Follow-up action required to complete a charge (e.g. a 3DS redirect). Maps to
/// `Payment-Charge-Action`.
public struct ChargeAction: Codable {
    public let actionType: ChargeActionType
    public let state: Emv3dsState?
    public let redirectUrl: String?

    enum CodingKeys: String, CodingKey {
        case actionType = "action_type"
        case state
        case redirectUrl = "redirect_url"
    }
}

/// Response for POST/GET `/payments/{payment_id}/charge`, and the value of `Payment-Details.charge`
/// returned by `GET /payments/{payment_id}`. Maps to `Payment-Charge-Status-Response`.
///
/// Per the spec only `id`, `state`, and `return_url` are required; instrument details and the
/// follow-up action are absent in early states, and `fail_reason` is only present when
/// `state == failed`.
public struct ChargePaymentResponse: Codable {
    public let id: String
    public let state: ChargeState
    public let returnUrl: String
    public let paymentInstrument: PaymentInstrumentData?
    public let action: ChargeAction?
    public let failReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case returnUrl = "return_url"
        case paymentInstrument = "payment_instrument"
        case action
        case failReason = "fail_reason"
    }
}
