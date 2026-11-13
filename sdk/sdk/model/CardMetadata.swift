import Foundation

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
