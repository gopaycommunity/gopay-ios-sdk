//
//  ContentView.swift
//  example
//
//  Created by Jiří Hauser on 24.03.2025.
//

import SwiftUI
import GopaySDK

struct ContentView: View {
    // Mocked fixed values
    let customerName = "John Doe"
    let productName = "Premium Subscription"
    let amount = 99.99
    
    // Payment result
    @State private var paymentResult: String = ""
    @State private var resultColor: Color = .gray
    @State private var transactionId: String = ""
    @State private var showingResult = false
    
    // SDK
    @State private var greetingText: String = ""
    @State private var selectedPaymentMethod: PaymentMethod = .creditCard
    
    // Credit Card fields (mocked)
    let cardNumber = "4111111111111111"
    let expirationDate = "12/25"
    let cvv = "123"
    
    // Bank Transfer fields (mocked)
    let accountNumber = "2000123456"
    let bankCode = "0800"
    let accountName = "John Doe"
    
    // Digital Wallet fields (mocked)
    let walletId = "john.doe@example.com"
    let walletProvider = "Apple Pay"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading ) {
                    Text("Checkout").font(.title).fontWeight(.bold)
                }
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "bag.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .foregroundColor(.blue)
                    
                    Text(productName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("$\(String(format: "%.2f", amount))")
                        .font(.title)
                        .fontWeight(.semibold)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                )
                .padding(.horizontal)
                
                // Customer info
                HStack {
                    Text("Customer:")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(customerName)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Payment methods title
                HStack {
                    Text("Select Payment Method")
                        .font(.headline)
                        .padding(.top)
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                // Payment methods
                VStack(spacing: 15) {
                    ForEach(PaymentMethod.allCases) { method in
                        PaymentMethodButton(
                            method: method,
                            isSelected: selectedPaymentMethod == method,
                            action: {
                                selectedPaymentMethod = method
                            }
                        )
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Process Payment Button
                Button(action: {
                    processPayment()
                }) {
                    Text("Pay Now")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                // Payment Result
                if showingResult {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(paymentResult)
                            .foregroundColor(resultColor)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        
                        if !transactionId.isEmpty {
                            HStack {
                                Text("Transaction ID:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(transactionId)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(resultColor.opacity(0.1))
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
    
    private func processPayment() {
        // Prepare payment details based on selected method
        var paymentDetails = [String: String]()
        paymentDetails["customerName"] = customerName
        
        // Add method-specific details
        switch selectedPaymentMethod {
        case .creditCard:
            paymentDetails["cardNumber"] = cardNumber
            paymentDetails["expirationDate"] = expirationDate
            paymentDetails["cvv"] = cvv
            
        case .bankTransfer:
            paymentDetails["accountNumber"] = accountNumber
            paymentDetails["bankCode"] = bankCode
            paymentDetails["accountName"] = accountName
            
        case .digitalWallet:
            paymentDetails["walletId"] = walletId
            paymentDetails["provider"] = walletProvider
            
        case .cardWebview:
            paymentDetails["redirectUrl"] = "https://example.com/payment/redirect"
        }
        
        // Process the payment using the SDK
        let result = GopaySDK.shared.processPayment(
            amount: amount,
            method: selectedPaymentMethod,
            paymentDetails: paymentDetails
        )
        
        // Display result
        if result.success {
            paymentResult = result.message
            resultColor = .green
            transactionId = result.transactionId ?? ""
        } else {
            paymentResult = result.message
            resultColor = .red
            transactionId = ""
        }
        
        showingResult = true
    }
}

// Payment Method Button
struct PaymentMethodButton: View {
    let method: PaymentMethod
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: method.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(isSelected ? .white : .blue)
                
                Text(method.rawValue)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.1))
            )
        }
    }
}

#Preview {
    ContentView()
}
