//
//  DemoConfigTests.swift
//  exampleTests
//

import Testing
@testable import example

struct DemoConfigTests {

    // MARK: - Base URL normalization

    @Test func emptyBaseURL_staysEmpty() {
        #expect(DemoConfig.normalizedBaseURL("") == "")
        #expect(DemoConfig.normalizedBaseURL("   ") == "")
    }

    @Test func baseURL_getsATrailingSlash() {
        #expect(DemoConfig.normalizedBaseURL("https://host/api/4.0") == "https://host/api/4.0/")
    }

    @Test func baseURL_keepsAnExistingTrailingSlash() {
        #expect(DemoConfig.normalizedBaseURL("  https://host/api/4.0/  ") == "https://host/api/4.0/")
    }

    // MARK: - Environment mapping

    @Test func emptyBaseURL_selectsSandbox() {
        #expect(DemoConfig.environment(for: "") == .sandbox)
    }

    @Test func configuredBaseURL_selectsDevelopment() {
        #expect(DemoConfig.environment(for: "https://host/api/4.0/") == .development)
    }

    // MARK: - Picker contents

    @Test func picker_withoutABaseURL_omitsDevelopment() {
        #expect(DemoEnvironment.selectable(for: "") == [.sandbox, .production])
    }

    @Test func picker_withABaseURL_offersDevelopment() {
        #expect(DemoEnvironment.selectable(for: "https://host/api/4.0/")
            == [.development, .sandbox, .production])
    }
}
