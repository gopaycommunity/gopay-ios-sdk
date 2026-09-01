//
//  EnvironmentBaseURLTests.swift
//  sdkTests
//
//  What each `GopayEnvironment` resolves to, and what the network client does with it. The built-in
//  hosts are pinned here because a silent change of either would send live traffic elsewhere; the
//  rest covers an unusable `.development(baseURL:)` being refused at the point a request URL is
//  built, instead of failing later inside URLSession.
//

import Testing
import Foundation
@testable import sdk

struct EnvironmentBaseURLTests {

    @Test func sandbox_resolvesToTheGateway40Host() {
        #expect(GopayEnvironment.sandbox.baseURL == "https://gw.sandbox.gopay.com/gp-gw/api/4.0/")
    }

    @Test func production_resolvesToTheLiveGatewayHost() {
        #expect(GopayEnvironment.production.baseURL == "https://gate.gopay.com/gp-gw/api/4.0/")
    }

    @Test func development_resolvesToWhateverItWasGiven() {
        #expect(GopayEnvironment.development(baseURL: "https://gw.example.test/api/").baseURL == "https://gw.example.test/api/")
    }

    @Test(arguments: [
        (GopayEnvironment.sandbox, "https://gw.sandbox.gopay.com/gp-gw/api/4.0/oauth2/token"),
        (GopayEnvironment.production, "https://gate.gopay.com/gp-gw/api/4.0/oauth2/token"),
    ])
    func builtInEnvironment_buildsAnAbsoluteRequestURL(environment: GopayEnvironment, expected: String) {
        let client = DefaultNetworkClient(baseURL: environment.baseURL)
        #expect(client.makeURL(path: "oauth2/token")?.absoluteString == expected)
    }

    /// An empty `.development(baseURL:)`. `URL(string:)` accepts the concatenation as a *relative*
    /// URL, so without the guard in `makeURL` the request reaches URLSession and fails there as
    /// `unsupported URL`; callers turn this `nil` into `CONFIG_006` instead.
    @Test func emptyBaseURL_buildsNoRequestURL() {
        let client = DefaultNetworkClient(baseURL: GopayEnvironment.development(baseURL: "").baseURL)
        #expect(client.makeURL(path: "oauth2/token") == nil)
    }

    @Test(arguments: [
        "gw.sandbox.gopay.com/gp-gw/api/4.0/",   // no scheme, so the host reads as a path
        "//gw.sandbox.gopay.com/gp-gw/api/4.0/", // scheme-relative
        "/gp-gw/api/4.0/",                       // path only
        "https:///gp-gw/api/4.0/",               // scheme but no host
        "ftp://gw.sandbox.gopay.com/",           // not HTTP
    ])
    func unusableBaseURL_buildsNoRequestURL(base: String) {
        #expect(DefaultNetworkClient(baseURL: base).makeURL(path: "oauth2/token") == nil)
    }
}
