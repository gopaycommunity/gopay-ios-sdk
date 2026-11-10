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

/// The customer of a payment, as the merchant's backend created it. Maps to `Customer`; only
/// `email` is always present.
public struct PaymentCustomer: Codable, Sendable {
    public let email: String
    public let firstName: String?
    public let lastName: String?
    public let phoneNumber: String?
    public let city: String?
    public let street: String?
    public let postalCode: String?
    public let countryCode: String?
    public let customerId: String?

    /// Creates the value, e.g. for a test that stands in for the gateway's answer.
    public init(
        email: String,
        firstName: String? = nil,
        lastName: String? = nil,
        phoneNumber: String? = nil,
        city: String? = nil,
        street: String? = nil,
        postalCode: String? = nil,
        countryCode: String? = nil,
        customerId: String? = nil
    ) {
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        self.city = city
        self.street = street
        self.postalCode = postalCode
        self.countryCode = countryCode
        self.customerId = customerId
    }

    enum CodingKeys: String, CodingKey {
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case phoneNumber = "phone_number"
        case city
        case street
        case postalCode = "postal_code"
        case countryCode = "country_code"
        case customerId = "customer_id"
    }
}

/// Payment details returned by `GET /payments/{payment_id}`. Maps to `Payment-Details`.
///
/// `orderNumber`, `gatewayUrl` and `customer` are always present, as the API requires them and
/// as the Android SDK reads them; a payment without one of them fails to decode with
/// ``GopaySDKError/Code/decodingError``.
///
/// Includes the latest `charge` summary when one exists. `payment_secret` is echoed by the API but
/// the app already holds it from ``GopaySDK/startPaymentSession(paymentId:paymentSecret:scope:)`` —
/// never log it or embed it in URLs.
public struct PaymentDetails: Codable, Sendable {
    public let id: String
    public let orderNumber: String
    public let state: PaymentState
    public let amount: Int
    public let currency: Currency
    public let gatewayUrl: String
    public let customer: PaymentCustomer
    public let paymentSecret: String?
    public let charge: ChargePaymentResponse?

    /// Creates the value, e.g. for a test that stands in for the gateway's answer.
    public init(
        id: String,
        orderNumber: String,
        state: PaymentState,
        amount: Int,
        currency: Currency,
        gatewayUrl: String,
        customer: PaymentCustomer,
        paymentSecret: String? = nil,
        charge: ChargePaymentResponse? = nil
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.state = state
        self.amount = amount
        self.currency = currency
        self.gatewayUrl = gatewayUrl
        self.customer = customer
        self.paymentSecret = paymentSecret
        self.charge = charge
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orderNumber = "order_number"
        case state
        case amount
        case currency
        case gatewayUrl = "gw_url"
        case customer
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
        orderNumber = try container.decode(String.self, forKey: .orderNumber)
        state = try container.decode(PaymentState.self, forKey: .state)
        amount = try container.decode(Int.self, forKey: .amount)
        currency = try container.decode(Currency.self, forKey: .currency)
        gatewayUrl = try container.decode(String.self, forKey: .gatewayUrl)
        customer = try container.decode(PaymentCustomer.self, forKey: .customer)
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

/// Local bank account details for a QR payment recipient. All four fields are always present,
/// as the API requires them; `prefix` may be an empty string.
public struct BankAccountLocalDetails: Codable, Sendable {
    public let prefix: String
    public let accountNumber: String
    public let bankCode: String
    public let variableSymbol: String

    /// Creates the value, e.g. for a test that stands in for the gateway's answer.
    public init(
        prefix: String,
        accountNumber: String,
        bankCode: String,
        variableSymbol: String
    ) {
        self.prefix = prefix
        self.accountNumber = accountNumber
        self.bankCode = bankCode
        self.variableSymbol = variableSymbol
    }

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

    /// Creates the value, e.g. for a test that stands in for the gateway's answer.
    public init(bic: String? = nil, iban: String? = nil, reference: String? = nil) {
        self.bic = bic
        self.iban = iban
        self.reference = reference
    }
}

/// Bank account details for a QR payment recipient.
public struct RecipientBankAccount: Codable, Sendable {
    public let local: BankAccountLocalDetails?
    public let international: BankAccountInternationalDetails?

    /// Creates the value, e.g. for a test that stands in for the gateway's answer.
    public init(local: BankAccountLocalDetails? = nil, international: BankAccountInternationalDetails? = nil) {
        self.local = local
        self.international = international
    }
}

/// Postal address details for a QR payment recipient.
public struct RecipientAddress: Codable, Sendable {
    public let street: String?
    public let city: String?
    public let zipCode: String?
    public let country: String?

    /// Creates the value, e.g. for a test that stands in for the gateway's answer.
    public init(
        street: String? = nil,
        city: String? = nil,
        zipCode: String? = nil,
        country: String? = nil
    ) {
        self.street = street
        self.city = city
        self.zipCode = zipCode
        self.country = country
    }

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

    /// Creates the value, e.g. for a test that stands in for the gateway's answer.
    public init(
        name: String? = nil,
        bankAccount: RecipientBankAccount? = nil,
        address: RecipientAddress? = nil
    ) {
        self.name = name
        self.bankAccount = bankAccount
        self.address = address
    }

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

    /// Creates the value, e.g. for a test that stands in for the gateway's answer.
    public init(
        spayd: String? = nil,
        paybysquare: String? = nil,
        sepa: String? = nil,
        mnbQr: String? = nil
    ) {
        self.spayd = spayd
        self.paybysquare = paybysquare
        self.sepa = sepa
        self.mnbQr = mnbQr
    }

    enum CodingKeys: String, CodingKey {
        case spayd
        case paybysquare
        case sepa
        case mnbQr = "mnb_qr"
    }
}

/// Response from `GET /payments/{payment_id}/qr-payment/info`. Maps to `QR-Payment-Details`.
/// `recipient` and `qrCode` are always present; which formats `qrCode` carries depends on the payment.
public struct QrPaymentDetails: Codable, Sendable {
    public let amount: Int
    public let currency: Currency
    public let recipient: BankTransferRecipient
    public let qrCode: QrCodeList

    /// Creates the value, e.g. for a test that stands in for the gateway's answer.
    public init(
        amount: Int,
        currency: Currency,
        recipient: BankTransferRecipient,
        qrCode: QrCodeList
    ) {
        self.amount = amount
        self.currency = currency
        self.recipient = recipient
        self.qrCode = qrCode
    }

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case recipient
        case qrCode = "qr_code"
    }
}
