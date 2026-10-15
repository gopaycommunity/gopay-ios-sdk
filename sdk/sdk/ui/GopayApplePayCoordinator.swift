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
    /// `didFinish` to dispatch the final completion. Main thread only.
    private var chargeResult: Swift.Result<ChargePaymentResponse, Error>?
    /// True from the moment the token goes to the charge until its result is back. Main thread
    /// only. PassKit closes the sheet on its own after a time limit, which a slow charge can
    /// outlast, so the sheet can finish while the charge is still running.
    private var isChargeInFlight = false
    /// Set when the sheet closed while the charge was still running: the call then ends with the
    /// charge's result as soon as it is back. Main thread only.
    private var finishesWhenTheChargeReturns = false
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
            completion(.failure(GopaySDKError(
                .paymentMethodUnavailable,
                message: "Apple Pay is not available: the payment allows no card network the SDK can map"
            )))
            return
        }

        guard PKPaymentAuthorizationController.canMakePayments() else {
            completion(.failure(GopaySDKError(
                .paymentMethodUnavailable,
                message: "Apple Pay is not available on this device"
            )))
            return
        }

        let controller = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        controller.delegate = self
        self.authorizationController = controller
        self.selfReference = self

        controller.present { [weak self] presented in
            if !presented {
                guard let self = self else { return }
                self.finish(with: .failure(GopaySDKError(
                    .paymentMethodUnavailable,
                    message: "Apple Pay sheet could not be presented. Enable the Apple Pay capability in Xcode (Signing & Capabilities tab) and ensure a valid Merchant ID is configured in both the entitlement and the merchantIdentifier returned by the backend."
                )))
            }
        }
    }

    // MARK: - Helpers

    /// What the call ends with once the sheet has closed and no charge is running: the last
    /// charge's result, or ``GopaySDKError/Code/paymentCancelled`` when nothing was charged.
    func resultOnceTheSheetCloses() -> Swift.Result<ChargePaymentResponse, Error> {
        chargeResult ?? .failure(GopaySDKError(
            .paymentCancelled,
            message: "The Apple Pay sheet was closed without paying"
        ))
    }

    /// The sheet is gone. With a charge still running the call waits for it and ends with its
    /// result, so a charge that goes through is never reported as a closed sheet; otherwise it
    /// ends now. Main thread only.
    func sheetDidClose() {
        if isChargeInFlight {
            finishesWhenTheChargeReturns = true
        } else {
            finish(with: resultOnceTheSheetCloses())
        }
    }

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

    /// Reads the fields the charge needs from the token, or throws
    /// ``GopaySDKError/Code/paymentProcessingFailed`` when there is nothing usable in it.
    static func mapToken(_ token: PKPaymentToken) throws -> TokenFields {
        // The iOS Simulator authorizes the sheet but hands back no payment data, so this is what
        // a developer trying Apple Pay there runs into first.
        guard !token.paymentData.isEmpty else {
            throw GopaySDKError(
                .paymentProcessingFailed,
                message: "Apple Pay returned an empty payment token. The iOS Simulator does not produce a real one; test on a device with an Apple Pay sandbox tester account"
            )
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: token.paymentData, options: []) as? [String: Any],
              let version = parsed["version"] as? String,
              let signature = parsed["signature"] as? String,
              let dataField = parsed["data"] as? String,
              let headerDict = parsed["header"] as? [String: Any],
              let ephemeralPublicKey = headerDict["ephemeralPublicKey"] as? String,
              let publicKeyHash = headerDict["publicKeyHash"] as? String,
              let transactionId = headerDict["transactionId"] as? String
        else {
            throw GopaySDKError(
                .paymentProcessingFailed,
                message: "Apple Pay returned a payment token the SDK cannot read"
            )
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
        _: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        // A new authorization after a failed one starts over: the earlier failure is not this
        // attempt's result.
        chargeResult = nil
        let fields: TokenFields
        do {
            fields = try Self.mapToken(payment.token)
        } catch {
            self.chargeResult = .failure(error)
            completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
            return
        }

        isChargeInFlight = true
        charge(fields) { [weak self] result in
            // The charge answers on whatever thread its task ran on; the state it lands in is read
            // on the main thread, where PassKit calls `didFinish`.
            DispatchQueue.main.async {
                guard let self = self else {
                    completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                    return
                }
                self.isChargeInFlight = false
                self.chargeResult = result
                switch result {
                case .success:
                    completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                case .failure(let error):
                    completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
                }
                if self.finishesWhenTheChargeReturns {
                    self.finish(with: result)
                }
            }
        }
    }

    func paymentAuthorizationControllerDidFinish(
        _ controller: PKPaymentAuthorizationController
    ) {
        controller.dismiss { [weak self] in
            self?.sheetDidClose()
        }
    }
}
