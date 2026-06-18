import Foundation
import PassKit

/// Internal coordinator that presents `PKPaymentAuthorizationController` and relays the resulting
/// `PKPaymentToken` to a caller-supplied charge closure.
///
/// Decoupled from the network layer: the owner (``PaymentSession``) injects the `charge` closure
/// that turns the extracted token fields into a ``ChargePaymentResponse``. The coordinator keeps a
/// strong reference to itself from the moment the sheet is shown until
/// `paymentAuthorizationControllerDidFinish`, so it survives the async PassKit callback chain.
final class GopayApplePayCoordinator: NSObject {

    /// Fields extracted from a `PKPaymentToken`, handed to the charge closure.
    struct TokenFields {
        let data: String
        let signature: String
        let version: String
        let header: ApplePayHeader
    }

    // MARK: - Dependencies

    private let appInfo: GopayApplePayAppInfoResponse
    private let charge: (TokenFields, @escaping (Swift.Result<ChargePaymentResponse, Error>) -> Void) -> Void
    private let completion: (Swift.Result<ChargePaymentResponse, Error>) -> Void

    // MARK: - State

    private var authorizationController: PKPaymentAuthorizationController?
    /// Result of the charge call, produced inside `didAuthorizePayment` and consumed from
    /// `didFinish` to dispatch the final completion.
    private var chargeResult: Swift.Result<ChargePaymentResponse, Error>?
    /// Self-retain to survive the async Apple Pay callback chain.
    private var selfReference: GopayApplePayCoordinator?

    // MARK: - Init

    init(
        appInfo: GopayApplePayAppInfoResponse,
        charge: @escaping (TokenFields, @escaping (Swift.Result<ChargePaymentResponse, Error>) -> Void) -> Void,
        completion: @escaping (Swift.Result<ChargePaymentResponse, Error>) -> Void
    ) {
        self.appInfo = appInfo
        self.charge = charge
        self.completion = completion
        super.init()
    }

    // MARK: - Presentation

    func start() {
        let paymentRequest = Self.makePaymentRequest(from: appInfo)

        let usableNetworks = paymentRequest.supportedNetworks
        guard !usableNetworks.isEmpty else {
            completion(.failure(GopaySDKErrors.sdkError(
                "Apple Pay is not available: backend returned no supported networks that the SDK can map."
            )))
            return
        }

        guard PKPaymentAuthorizationController.canMakePayments() else {
            completion(.failure(GopaySDKErrors.sdkError(GopaySDKErrors.applePayUnavailable)))
            return
        }

        let controller = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        controller.delegate = self
        self.authorizationController = controller
        self.selfReference = self

        controller.present { [weak self] presented in
            if !presented {
                guard let self = self else { return }
                self.finish(with: .failure(GopaySDKErrors.sdkError(
                    "Apple Pay sheet could not be presented. Enable the Apple Pay capability in Xcode (Signing & Capabilities tab) and ensure a valid Merchant ID is configured in both the entitlement and the merchantIdentifier returned by the backend."
                )))
            }
        }
    }

    // MARK: - Helpers

    private func finish(with result: Swift.Result<ChargePaymentResponse, Error>) {
        let handler = completion
        let retained = selfReference
        selfReference = nil
        DispatchQueue.main.async {
            handler(result)
            _ = retained // explicit release point
        }
    }

    // MARK: - PKPaymentRequest building

    static func makePaymentRequest(
        from appInfo: GopayApplePayAppInfoResponse
    ) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = appInfo.merchantIdentifier
        request.countryCode = appInfo.applePayPaymentRequest.countryCode
        request.currencyCode = appInfo.applePayPaymentRequest.currencyCode
        request.merchantCapabilities = mapMerchantCapabilities(
            appInfo.applePayPaymentRequest.merchantCapabilities
        )
        request.supportedNetworks = mapSupportedNetworks(
            appInfo.applePayPaymentRequest.supportedNetworks
        )
        request.paymentSummaryItems = appInfo.applePayPaymentRequest.paymentSummaryItems
            .map(mapSummaryItem)
        return request
    }

    private static func mapMerchantCapabilities(_ raw: [String]) -> PKMerchantCapability {
        var caps: PKMerchantCapability = []
        for value in raw {
            switch value {
            case "supports3DS":    caps.insert(.capability3DS)
            case "supportsCredit": caps.insert(.capabilityCredit)
            case "supportsDebit":  caps.insert(.capabilityDebit)
            case "supportsEMV":    caps.insert(.capabilityEMV)
            default: break
            }
        }
        if caps.isEmpty {
            caps.insert(.capability3DS)
        }
        return caps
    }

    private static func mapSupportedNetworks(_ raw: [String]) -> [PKPaymentNetwork] {
        return raw.compactMap { value -> PKPaymentNetwork? in
            switch value {
            case "visa":       return .visa
            case "masterCard": return .masterCard
            case "maestro":    if #available(iOS 12.0, *) { return .maestro } else { return nil }
            case "electron":   if #available(iOS 12.0, *) { return .electron } else { return nil }
            case "vPay":       if #available(iOS 12.0, *) { return .vPay } else { return nil }
            case "amex":       return .amex
            case "discover":   return .discover
            case "jcb":        return .JCB
            case "chinaUnionPay": return .chinaUnionPay
            default:
                return nil
            }
        }
    }

    private static func mapSummaryItem(
        _ item: GopayApplePayPaymentSummaryItem
    ) -> PKPaymentSummaryItem {
        let amount = NSDecimalNumber(string: item.amount)
        let type: PKPaymentSummaryItemType = (item.type?.lowercased() == "pending") ? .pending : .final
        return PKPaymentSummaryItem(
            label: item.label,
            amount: amount.isEqual(to: NSDecimalNumber.notANumber) ? .zero : amount,
            type: type
        )
    }

    // MARK: - PKPaymentToken → TokenFields

    private static func mapToken(_ token: PKPaymentToken) -> TokenFields? {
        guard !token.paymentData.isEmpty,
              let parsed = try? JSONSerialization.jsonObject(with: token.paymentData, options: []) as? [String: Any],
              let version = parsed["version"] as? String,
              let signature = parsed["signature"] as? String,
              let dataField = parsed["data"] as? String,
              let headerDict = parsed["header"] as? [String: Any],
              let ephemeralPublicKey = headerDict["ephemeralPublicKey"] as? String,
              let publicKeyHash = headerDict["publicKeyHash"] as? String,
              let transactionId = headerDict["transactionId"] as? String
        else {
            return nil
        }

        return TokenFields(
            data: dataField,
            signature: signature,
            version: version,
            header: ApplePayHeader(
                ephemeralPublicKey: ephemeralPublicKey,
                publicKeyHash: publicKeyHash,
                transactionId: transactionId
            )
        )
    }
}

// MARK: - PKPaymentAuthorizationControllerDelegate

extension GopayApplePayCoordinator: PKPaymentAuthorizationControllerDelegate {

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        guard let fields = Self.mapToken(payment.token) else {
            let error = GopaySDKErrors.sdkError(GopaySDKErrors.applePayAuthorizationFailed)
            self.chargeResult = .failure(error)
            completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
            return
        }

        charge(fields) { [weak self] result in
            guard let self = self else {
                completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                return
            }
            self.chargeResult = result
            switch result {
            case .success:
                completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
            case .failure(let error):
                completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
            }
        }
    }

    func paymentAuthorizationControllerDidFinish(
        _ controller: PKPaymentAuthorizationController
    ) {
        controller.dismiss { [weak self] in
            guard let self = self else { return }
            let result = self.chargeResult
                ?? .failure(GopaySDKErrors.sdkError(GopaySDKErrors.applePayCancelled))
            self.finish(with: result)
        }
    }
}
