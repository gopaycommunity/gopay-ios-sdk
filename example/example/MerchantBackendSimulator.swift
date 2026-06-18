//
//  MerchantBackendSimulator.swift
//  example
//
//  DEMO ONLY.
//
//  In a real app these calls happen on YOUR server, authenticated with merchant
//  `client_credentials`; the app never sees the client secret. The app receives only the
//  resulting `payment_id` + `payment_secret` and hands those to the SDK
//  (`GopaySDK.shared.startPaymentSession`). This file fakes that server so the demo is
//  self-contained.
//

import Foundation
import GopaySDK

enum MerchantBackendSimulator {

    struct CreatedPayment {
        let paymentId: String
        let paymentSecret: String
    }

    /// Authenticates as the merchant and creates a payment, returning the pair the SDK needs.
    static func createPayment(amount: Int, currency: String) async throws -> CreatedPayment {
        let token = try await merchantToken()
        return try await createPayment(token: token, amount: amount, currency: currency)
    }

    /// Tokenizes a JWE-encrypted card via `POST /cards/tokens` (requires `card:write`) and returns
    /// the resulting card token. In production the app sends the JWE here and your server does this.
    static func tokenizeCard(jwe: String) async throws -> String {
        let token = try await merchantToken()
        var request = URLRequest(url: url("cards/tokens"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["payload": jwe])

        let (data, response) = try await send(request)
        try ensureOK(response, data, action: "tokenize card")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cardToken = json["token"] as? String else {
            throw error("Missing token in card token response")
        }
        return cardToken
    }

    // MARK: - Steps

    private static func merchantToken() async throws -> String {
        var request = URLRequest(url: url("oauth2/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let basic = Data("\(DemoConfig.clientId):\(DemoConfig.clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("grant_type=client_credentials&scope=payment:write%20payment:read%20card:write%20card:read".utf8)

        let (data, response) = try await send(request)
        try ensureOK(response, data, action: "acquire merchant token")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw error("No access_token in merchant token response")
        }
        return token
    }

    private static func createPayment(token: String, amount: Int, currency: String) async throws -> CreatedPayment {
        var request = URLRequest(url: url("eshops/\(DemoConfig.goid)/payments"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "amount": amount,
            "currency": currency,
            "order_number": "demo-\(Int(Date().timeIntervalSince1970))",
            "order_description": "GoPay SDK demo payment",
            "customer": ["email": "demo@example.com"],
            "callback": [
                "notification_url": "https://example.com/gopay/notify",
                // SDK intercepts this URL in the 3DS WebView to detect flow completion
                "return_url": GopaySDK.chargeReturnURL
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await send(request)
        try ensureOK(response, data, action: "create payment")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw error("Malformed payment response")
        }
        let id = (json["id"] as? String) ?? json["id"].map { "\($0)" }
        guard let paymentId = id, let secret = json["payment_secret"] as? String else {
            throw error("Missing id / payment_secret in payment response")
        }
        return CreatedPayment(paymentId: paymentId, paymentSecret: secret)
    }

    // MARK: - Helpers

    private static func url(_ path: String) -> URL {
        URL(string: DemoConfig.baseURL + path)!
    }

    /// iOS 13-safe async wrapper around `dataTask` (`URLSession.data(for:)` is iOS 15+).
    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, err in
                if let err = err {
                    continuation.resume(throwing: err)
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: error("No HTTP response"))
                }
            }.resume()
        }
    }

    private static func ensureOK(_ response: HTTPURLResponse, _ data: Data, action: String) throws {
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw error("Failed to \(action): HTTP \(response.statusCode) \(body)")
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "MerchantBackendSimulator", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
