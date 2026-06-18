//
//  exampleApp.swift
//  example
//
//  Created by Jiří Hauser on 24.03.2025.
//

import SwiftUI
import GopaySDK

@main
struct exampleApp: App {
    init() {
        // Initialize the SDK once on app start. `clientId` + `shareableKey` are safe to embed —
        // they only authorize the public `/cards/public-key` endpoint, never charging.
        GopaySDK.shared.initialize(
            with: GopaySDKConfig(
                environment: .development(baseURL: DemoConfig.baseURL),
                clientId: DemoConfig.clientId,
                shareableKey: DemoConfig.shareableKey,
                enableDebugLogging: true
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Demo constants. Replace with your own merchant values.
enum DemoConfig {
    static let baseURL = "https://gw.alpha8.dev.gopay.com/gp-gw/api/4.0/"
    static let clientId = "SDK"
    /// Public shareable key — safe to ship in the app.
    static let shareableKey = "YOUR_SHAREABLE_KEY"
    /// Merchant secret — **never ship this in a real app.** Used here only by the in-app
    /// `MerchantBackendSimulator` to stand in for your server while demoing.
    static let clientSecret = "YOUR_CLIENT_SECRET"
    static let goid = "8761908826"
}
