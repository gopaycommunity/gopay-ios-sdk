//
//  DemoOverridesTests.swift
//  exampleTests
//
//  Tests for `DemoOverrides.normalizeBaseURL(_:)` — the gate that decides whether a launch-time
//  gateway override is usable. The inputs mirror the failure modes documented on the function:
//  values Foundation parses happily while the concatenated request goes somewhere else entirely.
//
//  The Android example covers the same contract with 13 tests on
//  `DemoLaunchOverrides.normalizeDemoBaseUrl`; this is the core subset, full parity comes later.
//
//  Also covers `DemoOverrides.make(...)`, the set-level rule: a base URL that was supplied and
//  rejected takes the credentials down with it.
//

import Testing
@testable import example

struct DemoOverridesTests {

    // MARK: - Rejected inputs (override ignored, built-in gateway kept)

    @Test func rejects_schemeOnly_noHost() {
        #expect(DemoOverrides.normalizeBaseURL("https://") == nil)
    }

    @Test func rejects_emptyHostWithPort() {
        #expect(DemoOverrides.normalizeBaseURL("https://:8080/") == nil)
    }

    @Test func rejects_portOutOfRange() {
        #expect(DemoOverrides.normalizeBaseURL("https://host:99999/") == nil)
    }

    @Test func rejects_query() {
        #expect(DemoOverrides.normalizeBaseURL("https://host/api?x=1") == nil)
    }

    @Test func rejects_fragment() {
        #expect(DemoOverrides.normalizeBaseURL("https://host/api#frag") == nil)
    }

    @Test func rejects_spaceInHost() {
        #expect(DemoOverrides.normalizeBaseURL("https://gw bad.com/") == nil)
    }

    @Test func rejects_nonHTTPScheme() {
        #expect(DemoOverrides.normalizeBaseURL("ftp://host/") == nil)
    }

    /// Userinfo makes the value read as one host while the request goes to another: everything
    /// before the `@` is a username, so `good.example.com` here is a credential, not the target.
    @Test(arguments: [
        "https://good.example.com@evil.example/",
        "https://user:pass@evil.example/",
        "https://good.example.com@evil.example/gp-gw/api/4.0/",
    ])
    func rejects_userinfo(raw: String) {
        #expect(DemoOverrides.normalizeBaseURL(raw) == nil)
    }

    // MARK: - Accepted inputs (returned normalized, with a trailing slash)

    @Test func accepts_underscoreInHost() {
        #expect(DemoOverrides.normalizeBaseURL("https://gw_local.dev.gopay.com/")
            == "https://gw_local.dev.gopay.com/")
    }

    @Test func accepts_explicitPort() {
        #expect(DemoOverrides.normalizeBaseURL("https://host:8080/") == "https://host:8080/")
    }

    @Test func accepts_ipv6Loopback() {
        #expect(DemoOverrides.normalizeBaseURL("https://[::1]:8080/") == "https://[::1]:8080/")
    }

    @Test func accepts_punycodeHost() {
        // Valid punycode ("háčkyčárky.cz"). URLComponents decodes it to Unicode while URL keeps the
        // ASCII form — the exact parser mismatch the host comparison must not trip over.
        #expect(DemoOverrides.normalizeBaseURL("https://xn--hkyrky-ptac70bc.cz/")
            == "https://xn--hkyrky-ptac70bc.cz/")
    }

    @Test func appendsTrailingSlashWhenMissing() {
        #expect(DemoOverrides.normalizeBaseURL("https://gw.alpha8.dev.gopay.com/gp-gw/api/4.0")
            == "https://gw.alpha8.dev.gopay.com/gp-gw/api/4.0/")
    }

    @Test func keepsExistingTrailingSlash() {
        #expect(DemoOverrides.normalizeBaseURL("https://gw.alpha8.dev.gopay.com/gp-gw/api/4.0/")
            == "https://gw.alpha8.dev.gopay.com/gp-gw/api/4.0/")
    }

    // MARK: - The set-level rule

    private static let credentials = (
        clientId: "test_client_id",
        shareableKey: "test_shareable_key",
        clientSecret: "test_client_secret",
        goid: "test_goid"
    )

    private static func makeSet(rawBaseURL: String?) -> DemoOverrides.OverrideSet {
        DemoOverrides.make(
            rawBaseURL: rawBaseURL,
            clientId: credentials.clientId,
            shareableKey: credentials.shareableKey,
            clientSecret: credentials.clientSecret,
            goid: credentials.goid
        )
    }

    /// The point of the rule: a typo in the URL must not leave the merchant secret pointed at the
    /// compiled-in gateway. Every rejected form takes the credentials with it.
    @Test(arguments: [
        "https://",
        "https://good.example.com@evil.example/",
        "https://host/api?x=1",
        "https://host:99999/",
        "not a url at all",
    ])
    func rejectedBaseURL_discardsTheWholeSet(raw: String) {
        #expect(Self.makeSet(rawBaseURL: raw) == .none)
    }

    @Test func acceptedBaseURL_keepsEverything() {
        let set = Self.makeSet(rawBaseURL: "https://gw.sandbox.gopay.com/gp-gw/api/4.0")
        #expect(set.baseURL == "https://gw.sandbox.gopay.com/gp-gw/api/4.0/")
        #expect(set.clientId == Self.credentials.clientId)
        #expect(set.shareableKey == Self.credentials.shareableKey)
        #expect(set.clientSecret == Self.credentials.clientSecret)
        #expect(set.goid == Self.credentials.goid)
    }

    /// No URL supplied is not a rejection: the credentials still apply, on top of the built-in
    /// development gateway.
    @Test func absentBaseURL_keepsCredentials() {
        let set = Self.makeSet(rawBaseURL: nil)
        #expect(set.baseURL == nil)
        #expect(set.clientId == Self.credentials.clientId)
        #expect(set.clientSecret == Self.credentials.clientSecret)
    }

    @Test func nothingSupplied_isAnEmptySet() {
        #expect(DemoOverrides.make(rawBaseURL: nil, clientId: nil, shareableKey: nil,
                                   clientSecret: nil, goid: nil) == .none)
    }
}
