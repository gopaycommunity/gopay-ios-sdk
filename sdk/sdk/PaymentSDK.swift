import Foundation
import SwiftUI

/// Enum representing different payment methods
public enum PaymentMethod: String, CaseIterable, Identifiable {
    case creditCard = "Credit Card"
    case bankTransfer = "Bank Transfer"
    case digitalWallet = "Digital Wallet"
    case cardWebview = "Card Webview"
    
    public var id: String { self.rawValue }
    
    public var icon: String {
        switch self {
        case .creditCard:
            return "creditcard.fill"
        case .bankTransfer:
            return "building.columns.fill"
        case .digitalWallet:
            return "wallet.pass.fill"
        case .cardWebview:
            return "globe"
        }
    }
}

/// Result of a payment transaction
public struct PaymentResult {
    public let success: Bool
    public let message: String
    public let transactionId: String?
    
    public init(success: Bool, message: String, transactionId: String? = nil) {
        self.success = success
        self.message = message
        self.transactionId = transactionId
    }
}

public class GopaySDK {
    public static let shared = GopaySDK()
    
    private init() {}
    
    /**
     Returns a greeting message from the SDK
     
     - Returns: A string with the greeting message
     */
    public func getGreeting() -> String {
        return "Hello World from Gopay SDK!"
    }
    
    /**
     Process payment using specified payment method
     
     - Parameters:
        - amount: The amount to process
        - method: The payment method to use
        - paymentDetails: Dictionary containing payment details specific to the method
     - Returns: A PaymentResult object containing transaction result
     */
    public func processPayment(amount: Double, method: PaymentMethod, paymentDetails: [String: String]) -> PaymentResult {
        // Log the payment attempt
        print("Processing payment of \(amount) via \(method.rawValue)")
        
        // Mock implementation for different payment methods
        switch method {
        case .creditCard:
            return processCreditCardPayment(amount: amount, details: paymentDetails)
        case .bankTransfer:
            return processBankTransferPayment(amount: amount, details: paymentDetails)
        case .digitalWallet:
            return processDigitalWalletPayment(amount: amount, details: paymentDetails)
        case .cardWebview:
            return processCardWebviewPayment(amount: amount, details: paymentDetails)
        }
    }
    
    /**
     Legacy method for backward compatibility
     */
    public func processPayment(amount: Double) -> Bool {
        // Default to credit card payment with no details
        let result = processPayment(amount: amount, method: .creditCard, paymentDetails: [:])
        return result.success
    }
    
    // MARK: - Private Methods
    
    private func processCreditCardPayment(amount: Double, details: [String: String]) -> PaymentResult {
        // Validate card details
        guard let cardNumber = details["cardNumber"], !cardNumber.isEmpty else {
            return PaymentResult(success: false, message: "Card number is required")
        }
        
        // Simple validation - in a real implementation we would do proper validation and processing
        let isValidCard = cardNumber.count >= 15 && cardNumber.count <= 16
        if isValidCard {
            // Generate a mock transaction ID
            let transactionId = "CC-\(Int.random(in: 100000...999999))"
            return PaymentResult(
                success: true,
                message: "Credit card payment successful",
                transactionId: transactionId
            )
        } else {
            return PaymentResult(success: false, message: "Invalid card details")
        }
    }
    
    private func processBankTransferPayment(amount: Double, details: [String: String]) -> PaymentResult {
        // Validate bank details
        guard let accountNumber = details["accountNumber"], !accountNumber.isEmpty else {
            return PaymentResult(success: false, message: "Account number is required")
        }
        
        // In a real implementation, we would initiate a bank transfer
        // For this mock, we'll simulate a successful transfer 90% of the time
        let isSuccessful = Double.random(in: 0...1) < 0.9
        
        if isSuccessful {
            let transactionId = "BT-\(Int.random(in: 100000...999999))"
            return PaymentResult(
                success: true,
                message: "Bank transfer initiated successfully",
                transactionId: transactionId
            )
        } else {
            return PaymentResult(success: false, message: "Bank transfer failed. Please try again.")
        }
    }
    
    private func processDigitalWalletPayment(amount: Double, details: [String: String]) -> PaymentResult {
        // Validate wallet details
        guard let walletId = details["walletId"], !walletId.isEmpty else {
            return PaymentResult(success: false, message: "Wallet ID is required")
        }
        
        // For this mock, digital wallet payments are always successful
        let transactionId = "DW-\(Int.random(in: 100000...999999))"
        return PaymentResult(
            success: true,
            message: "Digital wallet payment successful",
            transactionId: transactionId
        )
    }
    
    private func processCardWebviewPayment(amount: Double, details: [String: String]) -> PaymentResult {
        // In a real implementation, this would launch a webview for 3D Secure or similar
        // For this mock, we'll simulate the user completing the webview flow
        
        // Simulate that the webview payment is successful 80% of the time
        let isSuccessful = Double.random(in: 0...1) < 0.8
        
        if isSuccessful {
            let transactionId = "WV-\(Int.random(in: 100000...999999))"
            return PaymentResult(
                success: true,
                message: "Webview payment completed successfully",
                transactionId: transactionId
            )
        } else {
            return PaymentResult(success: false, message: "Webview payment was cancelled or failed")
        }
    }
} 