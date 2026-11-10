import Foundation

/// Supported currencies. Maps to `Currency`.
public enum Currency: String, Codable, GatewayEnum, Sendable {
    case czk = "CZK"
    case eur = "EUR"
    case pln = "PLN"
    case usd = "USD"
    case gbp = "GBP"
    case huf = "HUF"
    case ron = "RON"
    /// A currency this SDK does not know yet. The raw value is in the debug log.
    case unknown = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        self = try Self.decodingUnknownValues(from: decoder)
    }
}

/// Payment lifecycle state. Maps to `Payment-State`.
public enum PaymentState: String, Codable, GatewayEnum, Sendable {
    case created = "CREATED"
    case paid = "PAID"
    case canceled = "CANCELED"
    case paymentMethodChosen = "PAYMENT_METHOD_CHOSEN"
    case timeouted = "TIMEOUTED"
    case authorized = "AUTHORIZED"
    case refunded = "REFUNDED"
    case partiallyRefunded = "PARTIALLY_REFUNDED"
    /// A state this SDK does not know yet. It is not a final state: read the payment again, or
    /// settle it on your backend.
    case unknown = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        self = try Self.decodingUnknownValues(from: decoder)
    }
}

/// Payment details returned by `GET /payments/{payment_id}`. Maps to `Payment-Details`.
///
/// Includes the latest `charge` summary when one exists. `payment_secret` is echoed by the API but
/// the app already holds it from ``GopaySDK/startPaymentSession(paymentId:paymentSecret:scope:)`` —
/// never log it or embed it in URLs.
public struct PaymentDetails: Codable, Sendable {
    public let id: String
    public let orderNumber: String?
    public let state: PaymentState
    public let amount: Int
    public let currency: Currency
    public let gatewayUrl: String?
    public let paymentSecret: String?
    public let charge: ChargePaymentResponse?

    enum CodingKeys: String, CodingKey {
        case id
        case orderNumber = "order_number"
        case state
        case amount
        case currency
        case gatewayUrl = "gw_url"
        case paymentSecret = "payment_secret"
        case charge
    }
}

extension PaymentDetails {
    /// Decodes the payment as the synthesized decoder would, except for the nested `charge`: one
    /// without a `state` decodes with ``ChargeState/unknown`` rather than failing the whole
    /// payment, see ``ChargePaymentResponse/init(from:missingStateIsUnknown:)``.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        orderNumber = try container.decodeIfPresent(String.self, forKey: .orderNumber)
        state = try container.decode(PaymentState.self, forKey: .state)
        amount = try container.decode(Int.self, forKey: .amount)
        currency = try container.decode(Currency.self, forKey: .currency)
        gatewayUrl = try container.decodeIfPresent(String.self, forKey: .gatewayUrl)
        paymentSecret = try container.decodeIfPresent(String.self, forKey: .paymentSecret)
        charge = try container.decodeIfPresent(NestedCharge.self, forKey: .charge)?.charge
    }

    /// The charge nested in the payment, decoded leniently about its `state`.
    private struct NestedCharge: Decodable {
        let charge: ChargePaymentResponse

        init(from decoder: Decoder) throws {
            charge = try ChargePaymentResponse(from: decoder, missingStateIsUnknown: true)
        }
    }
}

// MARK: - QR payment info

/// Output format for QR payment info payloads.
public enum QrCodeFormat: String, Codable, Sendable {
    case png
    case svg
}

/// Local bank account details for a QR payment recipient.
public struct BankAccountLocalDetails: Codable, Sendable {
    public let prefix: String?
    public let accountNumber: String?
    public let bankCode: String?
    public let variableSymbol: String?

    enum CodingKeys: String, CodingKey {
        case prefix
        case accountNumber = "account_number"
        case bankCode = "bank_code"
        case variableSymbol = "variable_symbol"
    }
}

/// International bank account details for a QR payment recipient.
public struct BankAccountInternationalDetails: Codable, Sendable {
    public let bic: String?
    public let iban: String?
    public let reference: String?
}

/// Bank account details for a QR payment recipient.
public struct RecipientBankAccount: Codable, Sendable {
    public let local: BankAccountLocalDetails?
    public let international: BankAccountInternationalDetails?
}

/// Postal address details for a QR payment recipient.
public struct RecipientAddress: Codable, Sendable {
    public let street: String?
    public let city: String?
    public let zipCode: String?
    public let country: String?

    enum CodingKeys: String, CodingKey {
        case street
        case city
        case zipCode = "zip_code"
        case country
    }
}

/// Recipient details for a QR payment.
public struct BankTransferRecipient: Codable, Sendable {
    public let name: String?
    public let bankAccount: RecipientBankAccount?
    public let address: RecipientAddress?

    enum CodingKeys: String, CodingKey {
        case name
        case bankAccount = "bank_account"
        case address
    }
}

/// Encoded QR payload variants returned by the API.
public struct QrCodeList: Codable, Sendable {
    public let spayd: String?
    public let paybysquare: String?
    public let sepa: String?
    public let mnbQr: String?

    enum CodingKeys: String, CodingKey {
        case spayd
        case paybysquare
        case sepa
        case mnbQr = "mnb_qr"
    }
}

/// Response from `GET /payments/{payment_id}/qr-payment/info`. Maps to `QR-Payment-Details`.
public struct QrPaymentDetails: Codable, Sendable {
    public let amount: Int
    public let currency: Currency
    public let recipient: BankTransferRecipient?
    public let qrCode: QrCodeList?

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case recipient
        case qrCode = "qr_code"
    }
}
