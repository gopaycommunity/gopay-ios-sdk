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

}
