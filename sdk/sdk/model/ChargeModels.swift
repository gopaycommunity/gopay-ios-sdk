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
/// input type. Maps to `Browser-Data` in the published spec.
///
/// The gateway requires every field, ``ip`` included, and rejects a charge without it. The device
/// cannot know its own public address, and the issuer expects ``acceptHeader`` to come from the
/// same request that produced the address, so the SDK fetches the two from
/// `GET /cards/browser-data` right before it charges and fills in whichever of them is `nil`; see
/// ``PaymentSession/charge(_:)``. ``userAgent`` never comes from that answer: when `nil` it is
/// filled in before the fetch with the challenge WebView's User-Agent, which the fetch then
/// carries. A value you set yourself is kept, so pass ``ip`` only if you collected it in the
/// customer's own browser. ``javascriptEnabled`` is filled as `true` when `nil`, because the
/// challenge runs in a WebView with JavaScript on.
public struct BrowserData: Encodable {
    public let language: String
    public let timezone: Int
    public let screenWidth: Int
    public let screenHeight: Int
    public let colorDepth: Int
    public let userAgent: String?
    public let acceptHeader: String?
    public let javascriptEnabled: Bool?
    /// Public address of the customer's browser, at most 45 characters.
    public let ip: String?

    enum CodingKeys: String, CodingKey {
        case language
        case timezone
        case screenWidth = "screen_width"
        case screenHeight = "screen_height"
        case colorDepth = "color_depth"
        case userAgent = "user_agent"
        case acceptHeader = "accept_header"
        case javascriptEnabled = "javascript_enabled"
        case ip
    }

    public init(
        language: String,
        timezone: Int,
        screenWidth: Int,
        screenHeight: Int,
        colorDepth: Int,
        userAgent: String? = nil,
        acceptHeader: String? = nil,
        javascriptEnabled: Bool? = nil,
        ip: String? = nil
    ) {
        self.language = language
        self.timezone = timezone
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.colorDepth = colorDepth
        self.userAgent = userAgent
        self.acceptHeader = acceptHeader
        self.javascriptEnabled = javascriptEnabled
        self.ip = ip
    }

    /// The two fields only the gateway can supply present, so a charge needs no
    /// `GET /cards/browser-data`. ``userAgent`` is not part of it: the SDK fills that one in from
    /// the challenge WebView before it asks, as the Android SDK does.
    var hasGatewayFields: Bool {
        ip != nil && acceptHeader != nil
    }

    /// A copy with ``userAgent`` replaced; every other field stays.
    func withUserAgent(_ userAgent: String) -> BrowserData {
        BrowserData(
            language: language,
            timezone: timezone,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            colorDepth: colorDepth,
            userAgent: userAgent,
            acceptHeader: acceptHeader,
            javascriptEnabled: javascriptEnabled,
            ip: ip
        )
    }

    /// A copy with every `nil` among ``ip`` and ``acceptHeader`` taken from `detected`, and
    /// ``javascriptEnabled`` set to `true` when `nil`. A value already set stays. ``userAgent`` is
    /// left alone: the gateway only echoes the one the fetch sent, and the SDK fills it in before
    /// the fetch, so the echo is never the source.
    func filled(from detected: BrowserDataDetected?) -> BrowserData {
        BrowserData(
            language: language,
            timezone: timezone,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            colorDepth: colorDepth,
            userAgent: userAgent,
            acceptHeader: acceptHeader ?? detected?.acceptHeader,
            javascriptEnabled: javascriptEnabled ?? true,
            ip: ip ?? detected?.ip
        )
    }
}

/// Response of `GET /cards/browser-data`: the ``BrowserData`` fields the device cannot determine on
/// its own, derived by the gateway from the request that fetched them. Maps to
/// `Browser-Data-Detected`. The SDK merges it into the charge's ``BrowserData``.
public struct BrowserDataDetected: Codable {
    public let ip: String
    public let userAgent: String
    public let acceptHeader: String

    enum CodingKeys: String, CodingKey {
        case ip
        case userAgent = "user_agent"
        case acceptHeader = "accept_header"
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
/// iOS exposes the `CARD_TOKEN`, `ENCRYPTED_CARD`, and `APPLE_PAY` variants (Google Pay is
/// Android-only). `payload` is the JWE for the `ENCRYPTED_CARD` variant. Optional fields that
/// don't belong to the active variant are `nil` and omitted from the encoded JSON. Use the
/// factories rather than the memberwise initializer.
public struct PaymentCardInput: Encodable {
    public let inputType: String
    // CARD_TOKEN
    public let cardToken: String?
    // ENCRYPTED_CARD
    public let payload: String?
    // APPLE_PAY
    public let data: String?
    public let signature: String?
    public let version: String?
    public let header: ApplePayHeader?

    enum CodingKeys: String, CodingKey {
        case inputType = "input_type"
        case cardToken = "card_token"
        case payload
        case data
        case signature
        case version
        case header
    }

    private init(
        inputType: String,
        cardToken: String? = nil,
        payload: String? = nil,
        data: String? = nil,
        signature: String? = nil,
        version: String? = nil,
        header: ApplePayHeader? = nil
    ) {
        self.inputType = inputType
        self.cardToken = cardToken
        self.payload = payload
        self.data = data
        self.signature = signature
        self.version = version
        self.header = header
    }

    /// `CARD_TOKEN` input — a permanent card token the merchant tokenized server-side.
    public static func cardToken(_ cardToken: String) -> PaymentCardInput {
        PaymentCardInput(inputType: "CARD_TOKEN", cardToken: cardToken)
    }

    /// `ENCRYPTED_CARD` input — a JWE produced by `encryptCardData` / `submitCardForm`. Charges
    /// the encrypted card directly, skipping the server-side `POST /cards/tokens` round-trip.
    public static func encryptedCard(_ payload: String) -> PaymentCardInput {
        PaymentCardInput(inputType: "ENCRYPTED_CARD", payload: payload)
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
/// Use the factories for the common card-token, encrypted-card, and Apple Pay flows.
public struct ChargePaymentRequest: Encodable {
    public let paymentInstrument: PaymentChargeInstrument
    /// `return_url` is defined on `Payment-Charge-Input` in the spec, but the deployed Payments 4.0
    /// gateway rejects it ("Unrecognized field return_url"). Leave `nil` so it's omitted from the
    /// request — the 3DS redirect comes from the charge response's `action.redirectUrl`, and
    /// ``PaymentSession/handle3dsVerification(redirectURL:presenting:)`` detects completion using
    /// ``GopaySDK/chargeReturnURL`` internally.
    public let returnUrl: String?

    enum CodingKeys: String, CodingKey {
        case paymentInstrument = "payment_instrument"
        case returnUrl = "return_url"
    }

    public init(paymentInstrument: PaymentChargeInstrument, returnUrl: String? = nil) {
        self.paymentInstrument = paymentInstrument
        self.returnUrl = returnUrl
    }

    /// Charge with a permanent card token.
    public static func cardToken(
        _ cardToken: String,
        browserData: BrowserData,
        challengePreference: ChallengePreference? = nil,
        returnUrl: String? = nil
    ) -> ChargePaymentRequest {
        ChargePaymentRequest(
            paymentInstrument: PaymentChargeInstrument(
                input: .cardToken(cardToken),
                browserData: browserData,
                challengePreference: challengePreference
            ),
            returnUrl: returnUrl
        )
    }

    /// Charge directly with a JWE-encrypted card (`payload`), skipping the server-side
    /// `POST /cards/tokens` tokenization step. `payload` is the JWE produced by
    /// ``GopaySDK/encryptCardData(_:)`` / ``GopaySDK/submitCardForm()``.
    public static func encryptedCard(
        _ payload: String,
        browserData: BrowserData,
        challengePreference: ChallengePreference? = nil,
        returnUrl: String? = nil
    ) -> ChargePaymentRequest {
        ChargePaymentRequest(
            paymentInstrument: PaymentChargeInstrument(
                input: .encryptedCard(payload),
                browserData: browserData,
                challengePreference: challengePreference
            ),
            returnUrl: returnUrl
        )
    }

    /// Charge with an Apple Pay token.
    public static func applePay(
        data: String,
        signature: String,
        version: String,
        header: ApplePayHeader,
        browserData: BrowserData,
        challengePreference: ChallengePreference? = nil,
        returnUrl: String? = nil
    ) -> ChargePaymentRequest {
        ChargePaymentRequest(
            paymentInstrument: PaymentChargeInstrument(
                input: .applePay(data: data, signature: signature, version: version, header: header),
                browserData: browserData,
                challengePreference: challengePreference
            ),
            returnUrl: returnUrl
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
/// `state == failed`. The charge block inside `GET /payments/{payment_id}` comes without
/// `return_url`, hence its optionality below.
public struct ChargePaymentResponse: Codable {
    public let id: String
    public let state: ChargeState

    /// Where the gateway sends the browser once verification finishes.
    ///
    /// Optional because it is not always there: the charge block nested in
    /// `GET /payments/{payment_id}` arrives as just `{id, state, href}`. The type says so rather
    /// than substituting an empty string, which silently broke the obvious use:
    /// `url.hasPrefix(charge.returnUrl)` matches every URL against `""`, so the first navigation
    /// of a challenge page reads as a finished verification, and `URL(string: "")` is `nil`. For
    /// the same reason a blank `return_url` from the gateway decodes as `nil` rather than as the
    /// string that breaks that check.
    ///
    /// On the charge endpoints it is the address the backend created the payment with
    /// (`callback.return_url`). Pass it to
    /// ``PaymentSession/handle3dsVerification(redirectURL:returnURL:presenting:)`` together with
    /// `action.redirectUrl`: the verification ends when the challenge navigates there. Without it
    /// the SDK waits for ``GopaySDK/chargeReturnURL``, and then the payment has to be created with
    /// that address.
    public let returnUrl: String?
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

    /// Decodes the charge, tolerating a missing `return_url`.
    ///
    /// The spec marks `return_url` required, but the charge block nested in `GET /payments/{id}`
    /// arrives as just `{id, state, href}`. Failing the whole decode over it would take the
    /// payment state with it, so the field decodes to `nil` and the omission is reported through
    /// ``reportMissingField``. A blank value is treated as missing too, since an empty string is
    /// exactly what `url.hasPrefix` cannot be trusted with. Whitespace around a value is dropped,
    /// so the address can be parsed and matched as it is meant. The Android SDK tolerates all of
    /// it the same way.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        state = try container.decode(ChargeState.self, forKey: .state)
        paymentInstrument = try container.decodeIfPresent(PaymentInstrumentData.self, forKey: .paymentInstrument)
        action = try container.decodeIfPresent(ChargeAction.self, forKey: .action)
        failReason = try container.decodeIfPresent(String.self, forKey: .failReason)

        let rawReturnUrl = try container.decodeIfPresent(String.self, forKey: .returnUrl)
        let trimmed = rawReturnUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        returnUrl = trimmed?.isEmpty == false ? trimmed : nil
        // Only the charge endpoints are worth a warning. The charge block nested in
        // `GET /payments/{id}` never carries the field, so reporting it there would fire on
        // every single status read. An empty coding path means this is the response body itself
        // rather than a value inside another one.
        if returnUrl == nil, decoder.codingPath.isEmpty {
            ChargePaymentResponse.reportMissingField(
                rawReturnUrl == nil
                    ? "charge \(id) came back without the required return_url, decoding it as nil"
                    : "charge \(id) came back with a blank return_url, decoding it as nil"
            )
        }
    }

    /// Reports a required field the decoder had to substitute. The default sends it to the SDK
    /// debug log through `GopaySDK.logWarning(_:)`; tests observe the reports by swapping it.
    ///
    /// A swappable hook rather than a call written straight into the decoder: decoding runs on
    /// the URLSession thread, and a test has no other way to see what was substituted without
    /// turning on debug logging and reading stdout.
    static var reportMissingField: (String) -> Void = { message in
        GopaySDK.shared.logWarning(message)
    }
}
