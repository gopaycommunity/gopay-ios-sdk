import Foundation

/// What ``GopaySDK/submitCardFormWithMetadata(formId:)`` returns: the JWE of the card, as
/// ``GopaySDK/submitCardForm(formId:)`` returns it, and what the gateway knows about the card. The
/// same names on Android and in the browser SDK.
public struct EncryptedCardPayloadWithMetadata: Sendable, Equatable {
    /// JWE compact serialization (RFC 7516) ready to send to the merchant backend, good for a
    /// single charge.
    public let encryptedPayload: String
    /// The metadata of the card, or `nil` when the gateway knows none, the lookup failed or took
    /// longer than 3 seconds. The payload is good either way.
    public let cardMetadata: CardMetadata?

    public init(encryptedPayload: String, cardMetadata: CardMetadata?) {
        self.encryptedPayload = encryptedPayload
        self.cardMetadata = cardMetadata
    }
}

/// Masked, because the default description lists every stored property and would print the JWE
/// into any log, which must not be logged. Same shape as the Android SDK's `toString()`. The
/// mirror is masked the same way, so `dump(_:)` and anything else that reflects over the value
/// see the masked payload too.
extension EncryptedCardPayloadWithMetadata: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "EncryptedCardPayloadWithMetadata(encryptedPayload=***, cardMetadata=\(cardMetadata.map { "\($0)" } ?? "nil"))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["encryptedPayload": "***", "cardMetadata": cardMetadata as Any],
            displayStyle: .struct
        )
    }
}

/// What the gateway knows about a card from the start of its number: the answer of
/// `POST /cards/bin-lookup`, returned beside the JWE by
/// ``GopaySDK/submitCardFormWithMetadata(formId:)``. Shown to the customer or used to pick a flow;
/// a payment never depends on it. `CardMetadata` on Android and in the browser SDK too.
public struct CardMetadata: Sendable, Equatable {
    /// The card scheme, ``CardScheme/visa`` or ``CardScheme/mastercard``; the gateway knows no
    /// other here. The SDK never puts ``CardScheme/unknown`` here: unlike the enums of other
    /// answers, which read a value they do not know as `unknown`, an answer with any other scheme
    /// is read as no metadata at all, on purpose, as the browser SDK reads it.
    public let scheme: CardScheme
    /// Whether the card is a corporate one.
    public let corporate: Bool
    /// The product level of the card, e.g. `GOLD`; `nil` when the gateway does not say.
    public let brand: String?
    /// Debit or credit; `nil` when the gateway does not say, or says a value this version of the
    /// SDK does not know.
    public let serviceType: CardServiceType?
    /// The name of the bank that issued the card; `nil` when the gateway does not say.
    public let issuer: String?
    /// The issuer's country, ISO 3166-1 alpha-3, e.g. `CZE`; `nil` when the gateway does not say.
    public let issuerCountry: String?

    public init(
        scheme: CardScheme,
        corporate: Bool,
        brand: String? = nil,
        serviceType: CardServiceType? = nil,
        issuer: String? = nil,
        issuerCountry: String? = nil
    ) {
        self.scheme = scheme
        self.corporate = corporate
        self.brand = brand
        self.serviceType = serviceType
        self.issuer = issuer
        self.issuerCountry = issuerCountry
    }
}

/// Whether a card is a debit or a credit card, ``CardMetadata/serviceType``. The raw values are
/// the gateway's, and the names of the Android cases.
public enum CardServiceType: String, Sendable {
    case debit = "DEBIT"
    case credit = "CREDIT"
}
