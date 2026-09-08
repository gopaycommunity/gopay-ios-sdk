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
        // Initialize the SDK once on app start, against whichever environment DemoConfig starts
        // on rather than naming it again here. See DemoConfig.swift for the gateway and
        // credentials and the runtime switcher (RootView's badge).
        GopaySDK.shared.initialize(with: DemoConfig.buildConfig(for: DemoConfig.shared.environment))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
