//
//  ContentView.swift
//  example
//
//  Created by Jiří Hauser on 24.03.2025.
//

import SwiftUI
import GopaySDK

struct ContentView: View {
    private let sdk = GopaySDK.shared
    private let sdkConfig = GopaySDKConfig(environment: .development(baseURL: "https://gw.alpha8.dev.gopay.com/gp-gw/api/4.0/"))

    @State private var clientId: String = "SDK"
    @State private var clientSecret: String = "mHkYWtKR"
    @State private var scope: String = "payment:create payment:read card:read card:save"
    @State private var responseText: String = ""
    @State private var isLoading: Bool = false
    @State private var isGettingPublicKey: Bool = false
    @State private var isCreatingCardToken: Bool = false
    @State private var isCreatingPayment: Bool = false
    @State private var isGettingPayment: Bool = false
    @State private var isGettingPaymentChargeState: Bool = false
    @State private var isChargingPayment: Bool = false
    @State private var isSubmittingCardForm: Bool = false
    @State private var isSDKInitialized: Bool = false

    @State private var lastPaymentId: String = ""
    @State private var chargeCardToken: String = ""
    
    // Form validation states (optional - for UI feedback)
    @State private var isDefaultFormValid: Bool? = nil
    @State private var isCustomFormValid: Bool? = nil
    
    // Hardcoded card data (for API calls)
    private let cardNumber = "4444444444444448"
    private let expirationMonth = "12"
    private let expirationYear = "26"
    private let cvv = "123"
    private let goid = "8761908826"
    
    // Custom theme - Distinct purple/indigo theme
    private let customTheme = GopayCardFormTheme(
        textColor: .purple,
        backgroundColor: Color(.systemBackground),
        borderColor: .purple.opacity(0.5),
        focusedBorderColor: .indigo,
        borderWidth: 3.0,
        cornerRadius: 35.0,
        font: .title3,
        labelFont: .headline,
        spacing: 24.0,
        textFieldPadding: 18.0
    )

    @ViewBuilder
    private var defaultFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default Theme Card Form")
                .font(.title2)
                .fontWeight(.bold)

            GopayCardForm(isValid: $isDefaultFormValid)
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)

            formValidationMessage(isValid: isDefaultFormValid)

            Button(action: submitDefaultCardForm) {
                defaultFormSubmitLabel
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            .disabled(isSubmittingCardForm || (isDefaultFormValid == false))
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var defaultFormSubmitLabel: some View {
        HStack {
            if isSubmittingCardForm {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                Image(systemName: "creditcard.fill")
                Text("Submit Card Form")
                    .fontWeight(.semibold)
            }
        }
    }

    @ViewBuilder
    private var customFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Theme Card Form")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.purple)

            GopayCardForm(theme: customTheme, isValid: $isCustomFormValid)
                .padding(20)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.purple.opacity(0.1), Color.indigo.opacity(0.05)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: Color.purple.opacity(0.2), radius: 10, x: 0, y: 4)

            formValidationMessage(isValid: isCustomFormValid)

            Button(action: submitCustomCardForm) {
                customFormSubmitLabel
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.purple, Color.indigo]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundColor(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
            .shadow(color: Color.purple.opacity(0.4), radius: 12, x: 0, y: 6)
            .disabled(isSubmittingCardForm || (isCustomFormValid == false))
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var customFormSubmitLabel: some View {
        HStack(spacing: 12) {
            if isSubmittingCardForm {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                Image(systemName: "lock.shield.fill")
                Text("Submit Payment")
                    .fontWeight(.bold)
                    .font(.title3)
            }
        }
    }

    @ViewBuilder
    private func formValidationMessage(isValid: Bool?) -> some View {
        if let isValid = isValid {
            if isValid {
                Text("✓ Form is valid")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("Form validation: Please complete all fields correctly")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Gopay SDK Example")
                    .font(.title)
                    .padding(.top)
                
                // Card Forms Section
                VStack(spacing: 30) {
                    defaultFormSection
                    Divider()
                    customFormSection
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
                
                Divider()
                
                // SDK Configuration Section
                Group {
                    TextField("Client ID", text: $clientId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    SecureField("Client Secret", text: $clientSecret)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Scope", text: $scope)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack(spacing: 12) {
                    Button(action: authenticate) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Authenticate")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || isGettingPublicKey || clientId.isEmpty || clientSecret.isEmpty)
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: getPublicKey) {
                        if isGettingPublicKey {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Get Public Key")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || isGettingPublicKey)
                    .buttonStyle(.bordered)
                }
                
                Button(action: createCardToken) {
                    if isCreatingCardToken {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Create Card Token")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoading || isGettingPublicKey || isCreatingCardToken)
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(action: createPayment) {
                    if isCreatingPayment {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Create Payment")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoading || isGettingPublicKey || isCreatingCardToken || isCreatingPayment)
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button(action: getPaymentStatus) {
                    if isGettingPayment {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Get Payment Status")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(
                    isLoading ||
                    isGettingPublicKey ||
                    isCreatingCardToken ||
                    isCreatingPayment ||
                    isGettingPayment ||
                    lastPaymentId.isEmpty
                )
                .buttonStyle(.borderedProminent)
                .tint(.mint)

                Button(action: getPaymentChargeState) {
                    if isGettingPaymentChargeState {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Get Payment Charge State")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(
                    isLoading ||
                    isGettingPublicKey ||
                    isCreatingCardToken ||
                    isCreatingPayment ||
                    isGettingPayment ||
                    isGettingPaymentChargeState ||
                    lastPaymentId.isEmpty
                )
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                // Charge Payment Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Charge Payment")
                        .font(.headline)
                    TextField("Payment ID", text: $lastPaymentId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(.body, design: .monospaced))
                    TextField("Card Token (from tokenization)", text: $chargeCardToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(.caption, design: .monospaced))
                    Button(action: chargePayment) {
                        if isChargingPayment {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Charge Payment")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isChargingPayment || lastPaymentId.isEmpty || chargeCardToken.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Card Details:")
                        .font(.headline)
                    Text("Card Number: \(cardNumber)")
                        .font(.system(.body, design: .monospaced))
                    Text("Expiration: \(expirationMonth)/\(expirationYear)")
                        .font(.system(.body, design: .monospaced))
                    Text("CVV: \(cvv)")
                        .font(.system(.body, design: .monospaced))
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Response:")
                        .font(.headline)
                    ScrollView {
                        Text(responseText)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .frame(minHeight: 80, maxHeight: 200)
                }
                Spacer()
            }
            .padding()
        }
        .onAppear {
            initializeSDKIfNeeded()
        }
    }

    private func initializeSDKIfNeeded() {
        guard !isSDKInitialized else { return }
        sdk.initialize(with: sdkConfig)
        isSDKInitialized = true
    }
    
    private func authenticate() {
        initializeSDKIfNeeded()
        isLoading = true
        responseText = ""
        sdk.authenticate(clientId: clientId, clientSecret: clientSecret, scope: scope) { result in
            Task { @MainActor in
                isLoading = false
                switch result {
                case .success(let authResponse):
                    responseText = "Access Token: \(authResponse.accessToken)\nToken Type: \(authResponse.tokenType)\nRefresh Token: \(authResponse.refreshToken ?? "-")\nScope: \(authResponse.scope ?? "-")"
                case .failure(let error):
                    responseText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func getPublicKey() {
        initializeSDKIfNeeded()
        isGettingPublicKey = true
        responseText = ""

        sdk.getPublicKey { result in
            Task { @MainActor in
                isGettingPublicKey = false
                switch result {
                case .success(let jwk):
                    responseText = """
                    Public Key (JWK):
                    Key Type (kty): \(jwk.kty)
                    Key ID (kid): \(jwk.kid)
                    Usage (use): \(jwk.use)
                    Algorithm (alg): \(jwk.alg)
                    Modulus (n): \(jwk.n)
                    Exponent (e): \(jwk.e)
                    """
                case .failure(let error):
                    responseText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func createCardToken() {
        initializeSDKIfNeeded()
        isCreatingCardToken = true
        responseText = ""

        sdk.createCardToken(
            cardPan: cardNumber,
            expMonth: expirationMonth,
            expYear: expirationYear,
            cvv: cvv,
            permanent: false
        ) { result in
            Task { @MainActor in
                isCreatingCardToken = false
                switch result {
                case .success(let cardTokenResponse):
                    responseText = """
                    Card Token Created Successfully:
                    Masked PAN: \(cardTokenResponse.maskedPan)
                    Expiration Month: \(cardTokenResponse.expirationMonth)
                    Expiration Year: \(cardTokenResponse.expirationYear)
                    Scheme: \(cardTokenResponse.scheme.rawValue)
                    """
                case .failure(let error):
                    responseText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func createPayment() {
        initializeSDKIfNeeded()
        isCreatingPayment = true
        responseText = ""

        let request = GopayCreatePaymentRequest(
            amount: 10000,
            currency: .czk,
            orderNumber: "2025010199",
            orderDescription: "SDK example payment",
            additionalParams: [GopayAdditionalParam(name: "source", value: "ios-example-app")],
            customer: GopayPaymentCustomer(
                email: "john.doe@example.com",
                firstName: "John",
                lastName: "Doe",
                phoneNumber: "+420123456789",
                city: "Prague",
                street: "Example street 10",
                postalCode: "10000",
                countryCode: "CZE",
                customerId: "customer420"
            ),
            callback: GopayPaymentCallback(
                notificationURL: "https://example.com/notify",
                returnURL: "https://example.com/return"
            )
        )

        sdk.createPayment(goid: goid, request: request) { result in
            Task { @MainActor in
                isCreatingPayment = false
                switch result {
                case .success(let paymentResponse):
                    lastPaymentId = paymentResponse.id
                    responseText = """
                    Payment Created Successfully:
                    ID: \(paymentResponse.id)
                    State: \(paymentResponse.state.rawValue)
                    Gateway URL: \(paymentResponse.gatewayURL)
                    Order Number: \(paymentResponse.orderNumber)
                    Amount: \(paymentResponse.amount) \(paymentResponse.currency.rawValue)
                    Customer Email: \(paymentResponse.customer.email)
                    """
                case .failure(let error):
                    responseText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func submitDefaultCardForm() {
        initializeSDKIfNeeded()
        isSubmittingCardForm = true
        responseText = ""

        // Submit card form - data is automatically retrieved from the form
        // No need to pass card data explicitly, it's stored internally by the SDK
        sdk.submitCardForm(permanent: false) { result in
            Task { @MainActor in
                isSubmittingCardForm = false
                switch result {
                case .success(let cardTokenResponse):
                    responseText = """
                    Card Form Submitted Successfully:
                    Masked PAN: \(cardTokenResponse.maskedPan)
                    Expiration Month: \(cardTokenResponse.expirationMonth)
                    Expiration Year: \(cardTokenResponse.expirationYear)
                    Scheme: \(cardTokenResponse.scheme.rawValue)
                    
                    Note: The card data (PAN, CVV) was never exposed to your app code.
                    It was handled entirely within the SDK for security.
                    """
                case .failure(let error):
                    responseText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func getPaymentStatus() {
        initializeSDKIfNeeded()
        isGettingPayment = true
        responseText = ""

        sdk.getPayment(paymentId: lastPaymentId) { result in
            Task { @MainActor in
                isGettingPayment = false
                switch result {
                case .success(let paymentResponse):
                    var text = """
                    Payment Status:
                    ID: \(paymentResponse.id)
                    State: \(paymentResponse.state.rawValue)
                    Order Number: \(paymentResponse.orderNumber)
                    Amount: \(paymentResponse.amount) \(paymentResponse.currency.rawValue)
                    Gateway URL: \(paymentResponse.gatewayURL)
                    Customer Email: \(paymentResponse.customer.email)
                    """
                    if let charge = paymentResponse.charge {
                        text += "\nCharge ID: \(charge.id)"
                        text += "\nCharge State: \(charge.state.rawValue)"
                        text += "\nCharge Href: \(charge.href)"
                    }
                    responseText = text
                case .failure(let error):
                    responseText = "Get Payment Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func getPaymentChargeState() {
        initializeSDKIfNeeded()
        isGettingPaymentChargeState = true
        responseText = ""

        sdk.getPaymentChargeState(paymentId: lastPaymentId) { result in
            Task { @MainActor in
                isGettingPaymentChargeState = false
                switch result {
                case .success(let chargeResponse):
                    var text = """
                    Payment Charge State:
                    ID: \(chargeResponse.id)
                    State: \(chargeResponse.state.rawValue)
                    Return URL: \(chargeResponse.returnURL)
                    """
                    if let instrument = chargeResponse.paymentInstrument {
                        text += "\nInstrument: \(instrument.paymentInstrument)"
                        if let details = instrument.details {
                            text += "\nMasked PAN: \(details.maskedPan ?? "-")"
                            text += "\nScheme: \(details.scheme ?? "-")"
                        }
                    }
                    if let action = chargeResponse.action {
                        text += "\nAction Type: \(action.actionType.rawValue)"
                        text += "\nAction State: \(action.state)"
                        text += "\nRedirect URL: \(action.redirectURL ?? "-")"
                    }
                    responseText = text
                case .failure(let error):
                    responseText = "Get Payment Charge State Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func chargePayment() {
        initializeSDKIfNeeded()
        isChargingPayment = true
        responseText = ""

        sdk.chargePayment(
            paymentId: lastPaymentId,
            cardToken: chargeCardToken,
            challengePreference: .auto
        ) { result in
            Task { @MainActor in
                isChargingPayment = false
                switch result {
                case .success(let chargeResponse):
                    var text = """
                    Charge Response:
                    ID: \(chargeResponse.id)
                    State: \(chargeResponse.state.rawValue)
                    Return URL: \(chargeResponse.returnURL)
                    """
                    if let instrument = chargeResponse.paymentInstrument {
                        text += "\nInstrument: \(instrument.paymentInstrument)"
                        if let details = instrument.details {
                            text += "\nMasked PAN: \(details.maskedPan ?? "-")"
                            text += "\nScheme: \(details.scheme ?? "-")"
                        }
                    }
                    if let action = chargeResponse.action {
                        text += "\nAction Type: \(action.actionType.rawValue)"
                        text += "\nAction State: \(action.state)"
                        text += "\nRedirect URL: \(action.redirectURL ?? "-")"
                        text += "\n\n(3DS verification WebView was handled by SDK)"
                    }
                    responseText = text
                case .failure(let error):
                    responseText = "Charge Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func submitCustomCardForm() {
        initializeSDKIfNeeded()
        isSubmittingCardForm = true
        responseText = ""

        // Submit card form - demonstrates that button can be styled separately
        // The form data is automatically synced to the SDK, no need to pass it
        sdk.submitCardForm(permanent: false) { result in
            Task { @MainActor in
                isSubmittingCardForm = false
                switch result {
                case .success(let cardTokenResponse):
                    responseText = """
                    Custom Form Submitted Successfully:
                    Masked PAN: \(cardTokenResponse.maskedPan)
                    Expiration Month: \(cardTokenResponse.expirationMonth)
                    Expiration Year: \(cardTokenResponse.expirationYear)
                    Scheme: \(cardTokenResponse.scheme.rawValue)
                    
                    This demonstrates that the submit button can be:
                    - Styled completely independently from the form
                    - Placed anywhere in your UI
                    - The card data remains secure within the SDK
                    """
                case .failure(let error):
                    responseText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
