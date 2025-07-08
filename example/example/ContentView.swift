//
//  ContentView.swift
//  example
//
//  Created by Jiří Hauser on 24.03.2025.
//

import SwiftUI
import GopaySDK

struct ContentView: View {
    @State private var clientId: String = "SDK"
    @State private var clientSecret: String = "hE8e8KNP"
    @State private var scope: String = "payment:create payment:read card:read"
    @State private var responseText: String = ""
    @State private var isLoading: Bool = false
    
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
                Button(action: authenticate) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Authenticate")
                    }
                }
                .disabled(isLoading || clientId.isEmpty || clientSecret.isEmpty)
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
        let config = GopaySDKConfig(environment: .development)
        GopaySDK.shared.initialize(with: config)
        GopaySDK.shared.authenticate(clientId: clientId, clientSecret: clientSecret, scope: scope) { result in
            DispatchQueue.main.async {
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
}

#Preview {
    ContentView()
}
