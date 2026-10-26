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
    private let telemetry: ApplePayTelemetry
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
    /// When the sheet was asked for, which the steps up to its close are timed from.
    private var beganAt: UInt64?

    // MARK: - Init

    init(
        appInfo: GopayApplePayAppInfoResponse,
        telemetry: ApplePayTelemetry = .disabled,
        charge: @escaping (TokenFields, @escaping (Swift.Result<ChargePaymentResponse, Error>) -> Void) -> Void,
        completion: @escaping (Swift.Result<ChargePaymentResponse, Error>) -> Void
    ) {
        self.appInfo = appInfo
        self.telemetry = telemetry
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

        let probedAt = Telemetry.now()
        let canPay = PKPaymentAuthorizationController.canMakePayments()
        telemetry.readyToPay(canPay, startedAt: probedAt)
        guard canPay else {
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

        beganAt = Telemetry.now()
        telemetry.step(.begin, .start)
        controller.present { [weak self] presented in
            if !presented {
                self?.sheetWasNotPresented()
            }
        }
    }

    /// PassKit refused to show the sheet: the call ends with ``GopaySDKError/Code/paymentMethodUnavailable``.
    func sheetWasNotPresented() {
        let error = GopaySDKError(
            .paymentMethodUnavailable,
            message: "Apple Pay sheet could not be presented. Enable the Apple Pay capability in Xcode (Signing & Capabilities tab) and ensure a valid Merchant ID is configured in both the entitlement and the merchantIdentifier returned by the backend."
        )
        telemetry.step(.begin, .failure, detail: error.code.rawValue, startedAt: beganAt)
        finish(with: .failure(error))
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
            if chargeResult == nil {
                // Closed without an authorization: the time spent in the sheet before giving up.
                telemetry.step(.cancel, .info, startedAt: beganAt)
            }
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
            telemetry.step(.paymentAuthorized, .failure, detail: Telemetry.failureLabel(error), startedAt: beganAt)
            completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
            telemetry.completePayment(succeeded: false)
            return
        }

        // The user authorized and the token is usable, timed from the sheet being asked for;
        // what follows is the charge.
        telemetry.submitted()
        telemetry.step(.paymentAuthorized, .success, startedAt: beganAt)
        isChargeInFlight = true
        let checkoutAt = Telemetry.now()
        telemetry.step(.checkout, .start)
        let telemetry = self.telemetry
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
                    telemetry.step(.checkout, .success, startedAt: checkoutAt)
                    completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                    telemetry.completePayment(succeeded: true)
                case .failure(let error):
                    telemetry.step(.checkout, .failure, detail: Telemetry.failureLabel(error), startedAt: checkoutAt)
                    completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
                    telemetry.completePayment(succeeded: false)
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

// MARK: - Telemetry

/// The Apple Pay flow's operational data for one payment: `APPLE_PAY.<step>` events, the
/// availability answer and the user's authorization, with the payment they belong to.
struct ApplePayTelemetry: Sendable {
    let telemetry: Telemetry
    let paymentId: String

    /// Sends nothing, for a coordinator built outside a session.
    static let disabled = ApplePayTelemetry(telemetry: .disabled, paymentId: "")

    func step(
        _ step: Telemetry.WalletStep,
        _ status: Telemetry.StepStatus,
        detail: String? = nil,
        startedAt: UInt64? = nil,
        params: [String: Telemetry.Param] = [:]
    ) {
        telemetry.walletStep(step, status: status, paymentId: paymentId, detail: detail, startedAt: startedAt, params: params)
    }

    /// The sheet was told the charge's result: the step went through, `params.result` says which.
    func completePayment(succeeded: Bool) {
        step(.completePayment, .success, params: ["result": .string(succeeded ? "success" : "failure")])
    }

    func readyToPay(_ available: Bool, startedAt: UInt64) {
        telemetry.walletAvailability(
            caller: "chargeWithApplePay", available: available, startedAt: startedAt, paymentId: paymentId
        )
    }

    func submitted() {
        telemetry.walletSubmitted(paymentId: paymentId)
    }
}
