import Foundation

/// Raw card data to be encrypted into a JWE. Encodes to the `card_pan` / `exp_month` / `exp_year`
/// / `cvv` shape the GoPay encryption payload expects.
///
/// Sensitive — never persisted. Pass to ``GopaySDK/encryptCardData(_:)`` to obtain a JWE for
/// server-side tokenization.
public struct GopayCardData: Encodable, Sendable {
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

/// Masked, because the default description lists every stored property and would print the full
/// PAN and CVV into any log or crash report. Same shape as the Android SDK's `CardData.toString()`.
/// The mirror is masked the same way, so `dump(_:)` and anything else that reflects over the value
/// see the masked fields too.
extension GopayCardData: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "GopayCardData(cardPan=\(Self.maskedPan(cardPan)), expMonth=\(expMonth), expYear=\(expYear), cvv=***)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "cardPan": Self.maskedPan(cardPan),
                "expMonth": expMonth,
                "expYear": expYear,
                "cvv": "***"
            ],
            displayStyle: .struct
        )
    }

    /// Last four digits, or a full mask when the value is too short to mask safely.
    static func maskedPan(_ pan: String) -> String {
        pan.count >= 13 ? "****\(pan.suffix(4))" : "****"
    }
}
