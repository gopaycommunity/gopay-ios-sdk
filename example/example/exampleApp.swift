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
    // Initialize the app and SDK
    init() {
        // Any SDK initialization can be performed here
        print("Gopay SDK is ready to use")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
