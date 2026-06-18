import Foundation

/// Raw card data to be encrypted into a JWE. Encodes to the `card_pan` / `exp_month` / `exp_year`
/// / `cvv` shape the GoPay encryption payload expects.
///
/// Sensitive — never persisted. Pass to ``GopaySDK/encryptCardData(_:)`` to obtain a JWE for
/// server-side tokenization.
public struct GopayCardData: Encodable {
    /// Card PAN (Primary Account Number).
    public let cardPan: String
    /// Expiration month (MM format).
    public let expMonth: String
    /// Expiration year (YY format).
    public let expYear: String
    /// Card CVV.
    public let cvv: String

    enum CodingKeys: String, CodingKey {
        case cardPan = "card_pan"
        case expMonth = "exp_month"
        case expYear = "exp_year"
        case cvv
    }

    public init(cardPan: String, expMonth: String, expYear: String, cvv: String) {
        self.cardPan = cardPan
        self.expMonth = expMonth
        self.expYear = expYear
        self.cvv = cvv
    }
}
