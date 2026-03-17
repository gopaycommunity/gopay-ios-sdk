import Foundation

/// Supported currencies for payment creation.
public enum GopayPaymentCurrency: String, Codable {
    case czk = "CZK"
    case eur = "EUR"
    case pln = "PLN"
    case usd = "USD"
    case gbp = "GBP"
    case huf = "HUF"
    case ron = "RON"
}

/// Available payment states returned by the API.
public enum GopayPaymentState: String, Codable {
    case created = "CREATED"
    case paid = "PAID"
    case canceled = "CANCELED"
    case paymentMethodChosen = "PAYMENT_METHOD_CHOSEN"
    case timeouted = "TIMEOUTED"
    case authorized = "AUTHORIZED"
    case refunded = "REFUNDED"
    case partiallyRefunded = "PARTIALLY_REFUNDED"
}

/// Additional key-value parameter attached to payment creation.
public struct GopayAdditionalParam: Codable {
    public let name: String?
    public let value: String?

    public init(name: String? = nil, value: String? = nil) {
        self.name = name
        self.value = value
    }
}

/// Customer object used when creating a payment.
public struct GopayPaymentCustomer: Codable {
    public let email: String
    public let firstName: String?
    public let lastName: String?
    public let phoneNumber: String?
    public let city: String?
    public let street: String?
    public let postalCode: String?
    public let countryCode: String?
    public let customerId: String?

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
}

/// Callback URLs sent as part of payment creation.
public struct GopayPaymentCallback: Codable {
    public let notificationURL: String
    public let returnURL: String

    enum CodingKeys: String, CodingKey {
        case notificationURL = "notification_url"
        case returnURL = "return_url"
    }

    public init(notificationURL: String, returnURL: String) {
        self.notificationURL = notificationURL
        self.returnURL = returnURL
    }
}

/// Request payload for creating a payment in an e-shop.
public struct GopayCreatePaymentRequest: Encodable {
    public let amount: Int
    public let currency: GopayPaymentCurrency
    public let orderNumber: String
    public let orderDescription: String?
    public let additionalParams: [GopayAdditionalParam]?
    public let customer: GopayPaymentCustomer
    public let callback: GopayPaymentCallback

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case orderNumber = "order_number"
        case orderDescription = "order_description"
        case additionalParams = "additional_params"
        case customer
        case callback
    }

    public init(
        amount: Int,
        currency: GopayPaymentCurrency,
        orderNumber: String,
        orderDescription: String? = nil,
        additionalParams: [GopayAdditionalParam]? = nil,
        customer: GopayPaymentCustomer,
        callback: GopayPaymentCallback
    ) {
        self.amount = amount
        self.currency = currency
        self.orderNumber = orderNumber
        self.orderDescription = orderDescription
        self.additionalParams = additionalParams
        self.customer = customer
        self.callback = callback
    }
}

/// Response payload from payment creation.
public struct GopayCreatePaymentResponse: Decodable {
    public let id: String
    public let orderNumber: String
    public let state: GopayPaymentState
    public let amount: Int
    public let currency: GopayPaymentCurrency
    public let customer: GopayPaymentCustomer
    public let gatewayURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case orderNumber = "order_number"
        case state
        case amount
        case currency
        case customer
        case gatewayURL = "gw_url"
    }
}

public class GopayPaymentService {
    private let networkClient: NetworkClientProtocol
    private let keychainStorage: KeychainStorageProtocol

    public init(networkClient: NetworkClientProtocol, keychainStorage: KeychainStorageProtocol) {
        self.networkClient = networkClient
        self.keychainStorage = keychainStorage
    }

    /// Creates a payment for a specific e-shop (goid).
    /// - Parameters:
    ///   - goid: E-shop identifier.
    ///   - requestBody: Payment creation payload.
    ///   - completion: Completion handler with created payment or an error.
    public func createPayment(
        goid: String,
        requestBody: GopayCreatePaymentRequest,
        completion: @escaping (Result<GopayCreatePaymentResponse, Error>) -> Void
    ) {
        guard let accessToken = keychainStorage.getAccessToken() else {
            completion(.failure(GopaySDKErrors.paymentServiceError(GopaySDKErrors.noAccessToken)))
            return
        }

        if let isExpired = JwtUtils.isExpired(jwt: accessToken), isExpired {
            completion(.failure(GopaySDKErrors.paymentServiceError(GopaySDKErrors.accessTokenExpired)))
            return
        }

        let endpoint = "eshops/\(goid)/payments"
        guard let url = networkClient.makeURL(path: endpoint) else {
            completion(.failure(GopaySDKErrors.paymentServiceError(GopaySDKErrors.invalidPaymentURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.failure(GopaySDKErrors.paymentServiceError(GopaySDKErrors.encodingErrorMessage)))
            return
        }

        networkClient.sendRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(GopayCreatePaymentResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
