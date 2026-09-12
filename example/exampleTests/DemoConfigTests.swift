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

    @Test func sandboxBaseURL_selectsSandbox() {
        #expect(DemoConfig.environment(for: "https://gw.sandbox.gopay.com/gp-gw/api/4.0/") == .sandbox)
    }

    @Test func productionBaseURL_selectsProduction() {
        #expect(DemoConfig.environment(for: "https://gate.gopay.com/gp-gw/api/4.0/") == .production)
    }

    @Test func customBaseURL_selectsDevelopment() {
        #expect(DemoConfig.environment(for: "https://host/api/4.0/") == .development)
    }
}
