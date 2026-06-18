import Foundation

/// Supported currencies. Maps to `Currency`.
public enum Currency: String, Codable {
    case czk = "CZK"
    case eur = "EUR"
    case pln = "PLN"
    case usd = "USD"
    case gbp = "GBP"
    case huf = "HUF"
    case ron = "RON"
}

/// Payment lifecycle state. Maps to `Payment-State`.
public enum PaymentState: String, Codable {
    case created = "CREATED"
    case paid = "PAID"
    case canceled = "CANCELED"
    case paymentMethodChosen = "PAYMENT_METHOD_CHOSEN"
    case timeouted = "TIMEOUTED"
    case authorized = "AUTHORIZED"
    case refunded = "REFUNDED"
    case partiallyRefunded = "PARTIALLY_REFUNDED"
}

/// Payment details returned by `GET /payments/{payment_id}`. Maps to `Payment-Details`.
///
/// Includes the latest `charge` summary when one exists. `payment_secret` is echoed by the API but
/// the app already holds it from ``GopaySDK/startPaymentSession(paymentId:paymentSecret:scope:)`` —
/// never log it or embed it in URLs.
public struct PaymentDetails: Codable {
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

// MARK: - QR payment info

/// Output format for QR payment info payloads.
public enum QrCodeFormat: String, Codable {
    case png
    case svg
}

/// Local bank account details for a QR payment recipient.
public struct QrLocalBankAccount: Codable {
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
public struct QrInternationalBankAccount: Codable {
    public let bic: String?
    public let iban: String?
    public let reference: String?
}

/// Bank account details for a QR payment recipient.
public struct QrRecipientBankAccount: Codable {
    public let local: QrLocalBankAccount?
    public let international: QrInternationalBankAccount?
}

/// Postal address details for a QR payment recipient.
public struct QrRecipientAddress: Codable {
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
public struct QrRecipient: Codable {
    public let name: String?
    public let bankAccount: QrRecipientBankAccount?
    public let address: QrRecipientAddress?

    enum CodingKeys: String, CodingKey {
        case name
        case bankAccount = "bank_account"
        case address
    }
}

/// Encoded QR payload variants returned by the API.
public struct QrCodeList: Codable {
    public let spayd: String?
    public let paybysquare: String?
    public let sepa: String?
    public let mnbQR: String?

    enum CodingKeys: String, CodingKey {
        case spayd
        case paybysquare
        case sepa
        case mnbQR = "mnb_qr"
    }
}

/// Response from `GET /payments/{payment_id}/qr-payment/info`. Maps to `QR-Payment-Details`.
public struct QrPaymentDetails: Codable {
    public let amount: Int
    public let currency: Currency
    public let recipient: QrRecipient?
    public let qrCode: QrCodeList?

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case recipient
        case qrCode = "qr_code"
    }
}
