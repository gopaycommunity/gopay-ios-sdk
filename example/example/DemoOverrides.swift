//
//  DemoOverrides.swift
//  example
//
//  Launch-time overrides for `DemoConfig`, so the demo can be pointed at another gateway — or
//  handed another merchant's credentials — without editing code and rebuilding.
//

import Foundation

/// Launch-time gateway settings for the demo app.
///
/// Every value can be supplied two ways, checked in this order:
///
/// 1. **An environment variable** — `GOPAY_DEMO_BASE_URL=https://…`. This is what Xcode's
///    *Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments ▸ Environment Variables* writes, and what
///    `XCUIApplication.launchEnvironment` sets. From the command line, `simctl` has no flag for
///    this — it forwards variables prefixed with `SIMCTL_CHILD_` instead.
/// 2. **A launch argument** in `-KEY value` form — `-GOPAY_DEMO_BASE_URL https://…`. Arguments in
///    that shape are visible through `UserDefaults`, which is what Xcode's *Arguments Passed On
///    Launch* and `XCUIApplication.launchArguments` set.
///
/// Anything not supplied keeps its compiled-in value in `DemoConfig`, so a plain ⌘R with an
/// untouched scheme behaves exactly as before.
///
/// These describe the **Development** environment only, and `DemoConfig` applies them only there.
/// Sandbox and Production keep resolving through the SDK's own built-in hosts and their own
/// (placeholder) credentials: a badge reading SANDBOX while pointing at another host, or charging
/// with another environment's merchant secret, would be worse than no override at all. To reach an
/// arbitrary gateway — the sandbox included — stay on Development and give it that URL.
///
/// These are **not** a secure credential store: a launch argument is visible in the process list,
/// and an environment variable to anything that can read the process environment. They exist so
/// that real credentials never have to be written into a tracked source file — not to protect them
/// on a running device.
///
/// Mirrors the Android example's `DemoLaunchOverrides`, which carries the same five settings under
/// the same `GOPAY_DEMO_*` names as intent extras, treats a blank value as absent the same way,
/// discards the whole set when a supplied base URL is rejected, and likewise applies them only to
/// Development.
enum DemoOverrides {

    // MARK: - Keys

    static let baseURLKey = "GOPAY_DEMO_BASE_URL"
    static let clientIdKey = "GOPAY_DEMO_CLIENT_ID"
    static let shareableKeyKey = "GOPAY_DEMO_SHAREABLE_KEY"
    static let clientSecretKey = "GOPAY_DEMO_CLIENT_SECRET"
    static let goidKey = "GOPAY_DEMO_GOID"

    // MARK: - Values

    // Resolved once, on first read. These are launch-time inputs that cannot change while the app
    // runs, and `DemoConfig.developmentBaseURL` is read from `RootView`'s body on every pass — so a
    // computed property would re-parse the URL, and re-log any warning, on each recomposition.

    private static let resolved: OverrideSet = resolveFromLaunch()

    /// Base URL for the Development environment, or `nil` to keep the built-in one.
    static var baseURL: String? { resolved.baseURL }

    static var clientId: String? { resolved.clientId }
    static var shareableKey: String? { resolved.shareableKey }
    static var clientSecret: String? { resolved.clientSecret }
    static var goid: String? { resolved.goid }

    /// The five settings as one unit, because they are resolved as one: see ``make(rawBaseURL:…)``.
    struct OverrideSet: Equatable {
        var baseURL: String?
        var clientId: String?
        var shareableKey: String?
        var clientSecret: String?
        var goid: String?

        /// Nothing overridden, so `DemoConfig` keeps every compiled-in value.
        static let none = OverrideSet()
    }

    // MARK: - Resolution

    /// Reads the five settings from the launch environment and hands them to ``make(rawBaseURL:clientId:shareableKey:clientSecret:goid:)``.
    private static func resolveFromLaunch() -> OverrideSet {
        make(
            rawBaseURL: value(for: baseURLKey),
            clientId: value(for: clientIdKey),
            shareableKey: value(for: shareableKeyKey),
            clientSecret: value(for: clientSecretKey),
            goid: value(for: goidKey)
        )
    }

    /// Decides what the supplied values add up to. Separated from the launch-argument lookup so
    /// unit tests can feed it arbitrary values; `resolveFromLaunch()` reads the process
    /// environment, which a test host has no clean way to vary.
    ///
    /// A base URL that was supplied and then **rejected** discards the whole set, credentials
    /// included. Keeping the credentials would send them, the merchant secret among them, to the
    /// compiled-in development gateway instead of the one that was asked for: a typo in the URL
    /// would produce exactly the environment mixing these overrides exist to prevent. Dropping
    /// everything leaves the demo on its built-in gateway *and* its built-in credentials, which is
    /// a state the app already handles. Mirrors the Android demo's `DemoLaunchOverrides`.
    ///
    /// A base URL that was never supplied is not a rejection: the credentials still apply, on top
    /// of the built-in development gateway they were presumably issued for.
    static func make(
        rawBaseURL: String?,
        clientId: String?,
        shareableKey: String?,
        clientSecret: String?,
        goid: String?
    ) -> OverrideSet {
        let normalized = rawBaseURL.flatMap(normalizeBaseURL)

        if rawBaseURL != nil, normalized == nil {
            print("[DemoOverrides] \(baseURLKey) was supplied but rejected, so EVERY GOPAY_DEMO_* override is being ignored, credentials included. The demo stays on its built-in gateway with its own credentials. Fix the URL and relaunch.")
            return .none
        }

        return OverrideSet(
            baseURL: normalized,
            clientId: clientId,
            shareableKey: shareableKey,
            clientSecret: clientSecret,
            goid: goid
        )
    }

    /// Validates and normalizes a supplied base URL, or returns `nil` — meaning the value is
    /// unusable — with a warning saying so.
    ///
    /// This string is never used as a URL on its own. Both the SDK's network client and
    /// `MerchantBackendSimulator` build every request by concatenating a path onto it, so it is
    /// validated against that, not against "is this a URL". Hence the trailing `/`, without which
    /// you get `…/4.0oauth2/token`, and hence the checks below — each one is a value Foundation
    /// parses happily while the concatenated request goes somewhere else entirely:
    ///
    /// - no host (`https://`) — the first path segment is read as the host, so the request goes to
    ///   `https://oauth2/token`;
    /// - empty host (`https://:8080/`);
    /// - userinfo (`https://good.example.com@evil.example/`) — everything before the `@` is a
    ///   username, so the request goes to `evil.example` while the value reads as the good host;
    /// - a port outside 1...65535 (`https://host:99999/`) — `URLComponents` accepts it, the failure
    ///   surfaces much later inside `URLSession`;
    /// - a query or fragment (`https://host/api?x=1`) — the path is appended *after* it, so the
    ///   query swallows it and every call 404s against a gateway that looks fine.
    ///
    /// The last check concatenates a representative path and confirms the host did not move. Both
    /// sides of that comparison come from `URL`, deliberately: `URLComponents` and `URL` normalize
    /// hosts differently — `URLComponents` keeps IPv6 brackets and decodes punycode to Unicode,
    /// `URL` does neither — so comparing across the two rejects legitimate URLs like
    /// `https://[::1]:8080/` for no reason.
    ///
    /// A rejected value is logged and takes the whole override set with it, see
    /// ``make(rawBaseURL:clientId:shareableKey:clientSecret:goid:)``. Silently misdirecting
    /// requests is worse to debug than not applying the override at all.
    ///
    /// Mirrors `normalizeDemoBaseUrl` in the Android example's `DemoLaunchOverrides`, which
    /// validates through OkHttp's `HttpUrl` for the same reason: check the value with whatever is
    /// going to consume it. On Android these inputs crashed the app, because OkHttp parses more
    /// strictly than Foundation; here they are silent misdirection instead.
    ///
    /// Internal rather than private so unit tests can feed it arbitrary strings through
    /// `@testable import`, the same reason ``make(rawBaseURL:clientId:shareableKey:clientSecret:goid:)``
    /// is.
    static func normalizeBaseURL(_ raw: String) -> String? {
        let normalized = raw.hasSuffix("/") ? raw : raw + "/"

        guard let components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let componentsHost = components.host, !componentsHost.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let base = URL(string: normalized),
              let baseHost = base.host,
              let probe = URL(string: normalized + "oauth2/token"),
              probe.host == baseHost
        else {
            print("[DemoOverrides] Ignoring \(baseURLKey) \"\(raw)\" — not a usable gateway base URL.")
            return nil
        }

        return normalized
    }

    /// Environment variable first, then the `-KEY value` launch arguments.
    ///
    /// A blank value counts as "not supplied", so an environment variable left empty in the scheme
    /// — Xcode's default when you add a row and don't fill it in — doesn't wipe out the built-in
    /// default.
    private static func value(for key: String) -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment[key],
            UserDefaults.standard.string(forKey: key),
        ]

        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { continue }
            return trimmed
        }
        return nil
    }
}
