//
//  ContentView.swift
//  example
//
//  Created by Jiří Hauser on 24.03.2025.
//

import SwiftUI
import GopaySDK

struct ContentView: View {
    @State private var clientId: String = "1836340462"
    @State private var clientSecret: String = "NUBTBzPH"
    @State private var scope: String = "payment:create payment:read card:read"
    @State private var responseText: String = ""
    @State private var isLoading: Bool = false
    @State private var isGettingPublicKey: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Gopay SDK Example")
                    .font(.title)
                    .padding(.top)
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
    }
    
    private func authenticate() {
        isLoading = true
        responseText = ""
        // Example: Use sandbox environment for testing
        let config = GopaySDKConfig(environment: .sandbox)
        GopaySDK.shared.initialize(with: config)
        GopaySDK.shared.authenticate(clientId: clientId, clientSecret: clientSecret, scope: scope) { result in
            Task { @MainActor in
                isLoading = false
                switch result {
                case .success(let authResponse):
                    responseText = "Access Token: \(authResponse.access_token)\nToken Type: \(authResponse.token_type)\nRefresh Token: \(authResponse.refresh_token ?? "-")\nScope: \(authResponse.scope ?? "-")"
                case .failure(let error):
                    responseText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func getPublicKey() {
        isGettingPublicKey = true
        responseText = ""
        // Ensure SDK is initialized
        let config = GopaySDKConfig(environment: .sandbox)
        GopaySDK.shared.initialize(with: config)
        
        GopaySDK.shared.getPublicKey { result in
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
}

#Preview {
    ContentView()
}
