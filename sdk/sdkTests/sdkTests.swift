//
//  sdkTests.swift
//  sdkTests
//
//  Created by Jiří Hauser on 21.03.2025.
//

import Testing
@testable import sdk

struct sdkTests {

    @Test func gopaySDKSharedIsNotNil() async throws {
        let instance = GopaySDK.shared
        #expect(instance != nil)
    }

    @Test func gopaySDKConfigurationIsSetCorrectly() async throws {
        var errorCallbackCalled = false
        let config = GopaySDKConfig(
            environment: .sandbox,
            enableDebugLogging: true,
            errorCallback: { _ in errorCallbackCalled = true },
            requestTimeoutMs: 12345
        )
        GopaySDK.shared.initialize(with: config)
        let sdkConfig = GopaySDK.shared.config
        #expect(sdkConfig != nil)
        #expect(sdkConfig?.environment == .sandbox)
        #expect(sdkConfig?.enableDebugLogging == true)
        #expect(sdkConfig?.requestTimeoutMs == 12345)
        // Simulate error callback
        sdkConfig?.errorCallback?(NSError(domain: "test", code: 1))
        #expect(errorCallbackCalled == true)
    }

}
