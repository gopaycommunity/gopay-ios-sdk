import Foundation

/// Response payload from `GET /payments/{payment_id}/apple-pay/app-info`. Maps to
/// `Apple-Pay-App-Info-Response`.
///
/// All fields are BE-driven — the SDK uses them to build the native `PKPaymentRequest` and to
/// decide which card networks the sheet should accept. No Apple Pay configuration lives on the SDK
/// side.
public struct GopayApplePayAppInfoResponse: Codable {
    public let applepayVersion: Int?
    public let merchantIdentifier: String
    public let applePayPaymentRequest: GopayApplePayRequest
}

/// The `applePayPaymentRequest` sub-object mirroring the `PKPaymentRequest` shape the BE has
/// configured for this merchant.
public struct GopayApplePayRequest: Codable {
    public let merchantCapabilities: [String]
    public let supportedNetworks: [String]
    public let countryCode: String
    public let currencyCode: String
    public let paymentSummaryItems: [GopayApplePayPaymentSummaryItem]
}

/// A single line on the Apple Pay sheet. `type` is either `"final"` or `"pending"`.
public struct GopayApplePayPaymentSummaryItem: Codable {
    public let label: String
    public let amount: String
    public let type: String?
}
