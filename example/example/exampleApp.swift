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
        // Initialize the SDK once on app start, on the development environment. See DemoConfig.swift
        // for the environment/credential bundles and the runtime switcher (RootView's badge).
        GopaySDK.shared.initialize(with: DemoConfig.buildConfig(for: .development))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
