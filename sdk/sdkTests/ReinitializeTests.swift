//
//  ReinitializeTests.swift
//  sdkTests
//
//  A second `initialize(with:)` (GPMOB-177): with the same connection the open sessions, the
//  gateway and the telemetry stay and only the callback and the locales change; with another
//  connection every open session is closed first. React Native calls `initialize` again on every
//  reload. The Android SDK runs the shared scenarios under the same names (see the notes of
//  GPMOB-177); what only one platform can do is tested there alone.
//

import Testing
import Foundation
@testable import sdk

/// A gateway that hands out a token and answers everything else with a 404, each request kept.
private func tokenGateway(holdingTokenOn gate: AsyncGate? = nil) -> ScriptedGateway {
    ScriptedGateway { request in
        guard request.url?.path.hasSuffix("oauth2/token") == true else { return (404, "{}") }
        try await gate?.wait()
        let (status, body) = tokenResponse()
        return (status, String(decoding: body, as: UTF8.self))
    }
}

/// The configuration these tests initialize with; another `shareableKey` is another connection.
func reinitConfig(
    environment: GopayEnvironment = .development(baseUrl: "https://gw.example/api/"),
    clientId: String? = "c",
    shareableKey: String? = "k",
    debugLoggingEnabled: Bool = false,
    locale: String? = nil,
    customLocales: [String: GopayLocaleStrings] = [:],
    requestTimeout: TimeInterval = GopayConfig.defaultRequestTimeout,
    errorCallback: (@Sendable (Error) -> Void)? = nil
) -> GopayConfig {
    GopayConfig(
        environment: environment,
        clientId: clientId,
        shareableKey: shareableKey,
        debugLoggingEnabled: debugLoggingEnabled,
        errorCallback: errorCallback,
        locale: locale,
        customLocales: customLocales,
        requestTimeout: requestTimeout
    )
}

/// A configuration to initialize with first, by default ``reinitConfig``'s, and a second one.
struct ConnectionCase: CustomTestStringConvertible, Sendable {
    let name: String
    var first: GopayConfig = reinitConfig()
    let config: GopayConfig
    var testDescription: String { name }
}

private var customStrings: GopayLocaleStrings {
    var strings = GopayLocales.en
    strings.panLabel = "Custom"
    return strings
}

/// Each field of the connection changed alone.
let connectionFieldChanges: [ConnectionCase] = [
    ConnectionCase(name: "environment", config: reinitConfig(environment: .sandbox)),
    ConnectionCase(name: "development base URL", config: reinitConfig(environment: .development(baseUrl: "https://gw.example/other/"))),
    ConnectionCase(name: "clientId", config: reinitConfig(clientId: "c2")),
    ConnectionCase(name: "shareableKey", config: reinitConfig(shareableKey: "k2")),
    ConnectionCase(name: "request timeout", config: reinitConfig(requestTimeout: 30)),
    ConnectionCase(name: "debugLoggingEnabled", config: reinitConfig(debugLoggingEnabled: true)),
]

/// Changes that keep the connection: what the host may change at run time, and the spellings of
/// the same connection.
let runtimeFieldChanges: [ConnectionCase] = [
    ConnectionCase(name: "locale", config: reinitConfig(locale: "de")),
    ConnectionCase(name: "customLocales", config: reinitConfig(customLocales: ["xx": GopayLocales.en])),
    ConnectionCase(name: "errorCallback", config: reinitConfig(errorCallback: { _ in })),
    ConnectionCase(name: "development base URL with a trailing slash", config: reinitConfig(environment: .development(baseUrl: "https://gw.example/api"))),
    ConnectionCase(name: "clientId missing or blank", first: reinitConfig(clientId: nil), config: reinitConfig(clientId: " ")),
    ConnectionCase(name: "clientId empty or blank", first: reinitConfig(clientId: ""), config: reinitConfig(clientId: "\t")),
    ConnectionCase(name: "shareableKey missing or blank", first: reinitConfig(shareableKey: nil), config: reinitConfig(shareableKey: "")),
    ConnectionCase(
        name: "request timeout the SDK replaces by the default",
        first: reinitConfig(requestTimeout: 0),
        config: reinitConfig(requestTimeout: GopayConfig.defaultRequestTimeout)
    ),
]

/// An SDK whose every initialize takes the next of `gateways` and of `probes`, counting both.
private final class ReinitializableSDK {
    let sdk = GopaySDK()
    let gatewaysMade = Counter()
    let telemetriesMade = Counter()

    init(gateways: [ScriptedGateway], probes: [TelemetryProbe] = []) {
        sdk.makeNetworkClient = { [gatewaysMade] _ in gateways[gatewaysMade.increment() - 1] }
        sdk.makeTelemetry = { [telemetriesMade] _ in
            let made = telemetriesMade.increment()
            return made <= probes.count ? probes[made - 1].telemetry : .disabled
        }
    }
}

/// Whether `session` has been closed: every call that would send a request is refused.
private func isClosed(_ session: PaymentSession) async -> Bool {
    do {
        try await session.ensureOpen()
        return false
    } catch {
        return true
    }
}

/// The navigation types `probe` has received so far, in order; read without the schema checks of
/// ``TelemetryProbe/events(_:)``, which expect a count.
private func navigations(_ probe: TelemetryProbe) -> [String] {
    probe.uploads.compactMap { upload in
        let body = (try? JSONSerialization.jsonObject(with: upload.body)) as? [String: Any]
        return (body?["event"] as? [String: Any])?["navigation_type"] as? String
    }
}

private func code(of error: Error) -> GopaySDKError.Code? { (error as? GopaySDKError)?.code }

/// In the locale suite because ``GopaySDK/initialize(with:)`` writes the SDK-wide default locale
/// those tests read, and only a suite of its own is serialized.
extension GopayLocalesTests {

    @Test func reinitializeWithTheSameConnectionKeepsTheOpenSessions() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let gateway = tokenGateway()
        let made = ReinitializableSDK(gateways: [gateway])
        let sdk = made.sdk
        sdk.initialize(with: reinitConfig())
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        sdk.initialize(with: reinitConfig(errorCallback: { _ in }))

        #expect(await sdk.getPaymentSession("p1") === session)
        #expect(await !isClosed(session))
        _ = try? await session.getStatus()
        #expect(gateway.requests(to: "payments/p1").count == 1, "the session goes on over the same gateway")
        do {
            _ = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
            Issue.record("the open session must still hold the payment")
        } catch {
            #expect(code(of: error) == .authPaymentSessionAlreadyExists)
        }
        #expect(made.gatewaysMade.count == 1, "one gateway made, by the first initialize")
        await session.close()
    }

    @Test func reinitializeWithTheSameConnectionSendsNoSecondInit() async {
        defer { GopayLocales.setDefaultLocale(nil) }
        let probe = TelemetryProbe(clientId: "c")
        let made = ReinitializableSDK(gateways: [tokenGateway()], probes: [probe])
        let sdk = made.sdk

        sdk.initialize(with: reinitConfig())
        sdk.initialize(with: reinitConfig(locale: "de"))
        sdk.initialize(with: reinitConfig())

        #expect(await settle(until: navigations(probe) == ["init"]))
        #expect(made.telemetriesMade.count == 1, "one telemetry made, by the first initialize")
        #expect(sdk.telemetry === probe.telemetry)
    }

    @Test func reinitializeWithTheSameConnectionReportsErrorsOfAnOlderSessionToTheNewErrorCallback() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let before = ReportedErrors()
        let after = ReportedErrors()
        let gateway = tokenGateway()
        let sdk = ReinitializableSDK(gateways: [gateway]).sdk
        sdk.initialize(with: reinitConfig(errorCallback: { before.append($0) }))
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        sdk.initialize(with: reinitConfig(errorCallback: { after.append($0) }))
        await #expect(throws: GopaySDKError.self) { _ = try await session.getStatus() }

        #expect(gateway.requests(to: "payments/p1").count == 1, "the old session still reached the gateway")
        #expect(before.all.isEmpty, "the callback of before the reload is not called any more")
        #expect(after.codes == [.paymentNotFound], "the gateway's 404, reported to the new callback")
        await session.close()
    }

    @Test func reinitializeWithTheSameConnectionAppliesTheNewLocale() {
        defer { GopayLocales.setDefaultLocale(nil) }
        let sdk = ReinitializableSDK(gateways: [tokenGateway()]).sdk
        sdk.initialize(with: reinitConfig(locale: "cs"))

        sdk.initialize(with: reinitConfig(locale: "de"))

        #expect(sdk.config?.locale == "de")
        #expect(sdk.currentLocaleStrings() == GopayLocales.de)
    }

    @Test func reinitializeWithAnotherConnectionClosesTheOpenSessions() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let old = TelemetryProbe(clientId: "c")
        let new = TelemetryProbe(clientId: "c")
        let sdk = ReinitializableSDK(gateways: [tokenGateway(), tokenGateway()], probes: [old, new]).sdk
        sdk.initialize(with: reinitConfig())
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        sdk.initialize(with: reinitConfig(shareableKey: "k2"))

        #expect(await sdk.getPaymentSession("p1") == nil, "gone from the SDK at once")
        #expect(await settle(until: await isClosed(session)), "closed in the background")
        #expect(await !session.holdsCredentials, "the payment_secret and the token are wiped")
        // The leave goes through the telemetry the session was started with.
        #expect(await settle(until: navigations(old) == ["init", "navigate", "leave"]))
        #expect(navigations(new) == ["init"])
        #expect(old.telemetry.attachedPayments.isEmpty)
        #expect(sdk.telemetry === new.telemetry)
    }

    @Test func reinitializeWithAnotherConnectionLetsTheSamePaymentStartAgain() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let first = tokenGateway()
        let second = tokenGateway()
        let sdk = ReinitializableSDK(gateways: [first, second]).sdk
        sdk.initialize(with: reinitConfig())
        let old = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        sdk.initialize(with: reinitConfig(shareableKey: "k2"))
        // Right away, without waiting for the old session to close.
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        #expect(session !== old)
        #expect(await sdk.getPaymentSession("p1") === session)
        #expect(second.requests(to: "oauth2/token").count == 1, "the new session asks the new gateway")
        #expect(first.requests(to: "oauth2/token").count == 1)
        await session.close()
    }

    @Test func aSessionClosedByReinitializeFailsAsOneClosedByClose() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let first = tokenGateway()
        let sdk = ReinitializableSDK(gateways: [first, tokenGateway()]).sdk
        sdk.initialize(with: reinitConfig())
        let closedByClose = try await sdk.startPaymentSession(paymentId: "p0", paymentSecret: "s")
        await closedByClose.close()
        let closedByReinitialize = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        sdk.initialize(with: reinitConfig(shareableKey: "k2"))
        try #require(await settle(until: await isClosed(closedByReinitialize)))

        var errors: [GopaySDKError] = []
        for session in [closedByClose, closedByReinitialize] {
            do {
                _ = try await session.getStatus()
            } catch let error as GopaySDKError {
                errors.append(error)
            }
        }
        #expect(errors.map(\.code) == [.authPaymentSessionClosed, .authPaymentSessionClosed])
        #expect(errors.last?.message == "PaymentSession for p1 is closed")
        #expect(first.requests(to: "payments/p1").isEmpty, "refused before anything is sent")
    }

    @Test func attachingTheSamePaymentTwiceLeavesOneEntry() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let probe = TelemetryProbe(clientId: "c")
        let sdk = ReinitializableSDK(gateways: [tokenGateway()], probes: [probe]).sdk
        sdk.initialize(with: reinitConfig())
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        do {
            _ = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
            Issue.record("a second session for the same payment must be refused")
        } catch {
            #expect(code(of: error) == .authPaymentSessionAlreadyExists)
        }

        #expect(probe.telemetry.attachedPayments == ["p1"], "the refused start leaves the open session attributed")
        await session.close()
        #expect(probe.telemetry.attachedPayments.isEmpty)
    }

    /// Another connection while a session is still starting over the old one: the start fails
    /// with AUTH_013, the session being closed by the switch. Nothing is left open over the old
    /// connection, no `navigate` goes out for it, and the payment can start again. A `leave` goes
    /// out when the background close takes the session before the start sees the switch, as on
    /// Android; when the start sees it first, the session closes without one.
    @Test func reinitializeDuringStartPaymentSession() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let gate = AsyncGate()
        let old = TelemetryProbe(clientId: "c")
        let sdk = ReinitializableSDK(
            gateways: [tokenGateway(holdingTokenOn: gate), tokenGateway()], probes: [old]
        ).sdk
        sdk.initialize(with: reinitConfig())
        let starting = Task { try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s") }
        try #require(await settle(until: gate.hasWaiter))

        sdk.initialize(with: reinitConfig(shareableKey: "k2"))
        gate.open()

        do {
            _ = try await starting.value
            Issue.record("a start overtaken by another connection must fail")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentSessionClosed)
            #expect(error.message == "PaymentSession for p1 is closed: initialize switched to another connection while it started.")
        }
        #expect(await sdk.getPaymentSession("p1") == nil)
        #expect(old.telemetry.attachedPayments.isEmpty)
        #expect(!navigations(old).contains("navigate"), "the session never started as far as GoPay knows")
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        await session.close()
    }

    /// The other order of the same race: the start registers its session in the replaced registry
    /// before the background close retires it, here held until then. The start sees the switch
    /// itself, closes the session without a `leave` and fails as above.
    @Test func reinitializeClosesASessionThatRegisteredWhileItStarted() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let tokenGate = AsyncGate()
        let retireGate = AsyncGate()
        let old = TelemetryProbe(clientId: "c")
        let after = ReportedErrors()
        let sdk = ReinitializableSDK(
            gateways: [tokenGateway(holdingTokenOn: tokenGate), tokenGateway()], probes: [old]
        ).sdk
        sdk.beforeRetiringReplacedSessions = { try? await retireGate.wait() }
        sdk.initialize(with: reinitConfig())
        let starting = Task { try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s") }
        try #require(await settle(until: tokenGate.hasWaiter))

        sdk.initialize(with: reinitConfig(shareableKey: "k2", errorCallback: { after.append($0) }))
        try #require(await settle(until: retireGate.hasWaiter), "the old registry is not retired yet")
        tokenGate.open()

        do {
            _ = try await starting.value
            Issue.record("a session registered over the replaced connection must not be handed out")
        } catch let error as GopaySDKError {
            #expect(error.code == .authPaymentSessionClosed)
            #expect(error.message == "PaymentSession for p1 is closed: initialize switched to another connection while it started.")
        }
        #expect(after.codes == [.authPaymentSessionClosed], "reported once, to the new callback")
        #expect(old.telemetry.attachedPayments.isEmpty)
        retireGate.open()
        await sdk.closeAllPaymentSessions()
        #expect(navigations(old) == ["init"], "no navigate and no leave: it closed before it started")
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
        #expect(await sdk.getPaymentSession("p1") === session)
        await session.close()
    }

    /// A blank `clientId` or `shareableKey` is a missing one, in what the SDK sends as in the
    /// comparison of connections: an initialize with a blank key and then without it keeps the
    /// connection, and a card encryption over it stops with AUTH_011 before anything is sent, as
    /// it does after a fresh initialize without the key. The same rule as on Android.
    @Test func aBlankKeyIsMissingInTheCallsAsInTheComparison() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let card = GopayCardData(cardPan: "4444333322221111", expMonth: "12", expYear: "30", cvv: "123")
        for (first, second) in [
            (reinitConfig(shareableKey: " "), reinitConfig(shareableKey: nil)),
            (reinitConfig(clientId: "\t"), reinitConfig(clientId: nil)),
        ] {
            let gateway = tokenGateway()
            let made = ReinitializableSDK(gateways: [gateway])
            made.sdk.initialize(with: first)
            made.sdk.initialize(with: second)
            do {
                _ = try await made.sdk.encryptCardData(card)
                Issue.record("a blank key must stop the encryption")
            } catch {
                #expect(code(of: error) == .authShareableKeyMissing)
            }
            #expect(made.gatewaysMade.count == 1, "the same connection")
            #expect(gateway.requests.isEmpty, "nothing sent with a blank key")
        }
    }

    @Test(arguments: connectionFieldChanges)
    func reinitializeClosesTheOpenSessionsWhenOneConnectionFieldChanges(_ change: ConnectionCase) async throws {
        defer { GopayLocales.setDefaultLocale(nil); GopayLocales.clearCustom() }
        let sdk = ReinitializableSDK(gateways: [tokenGateway(), tokenGateway()]).sdk
        sdk.initialize(with: reinitConfig())
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        sdk.initialize(with: change.config)

        #expect(await sdk.getPaymentSession("p1") == nil)
        #expect(await settle(until: await isClosed(session)))
    }

    @Test(arguments: runtimeFieldChanges)
    func reinitializeKeepsTheOpenSessionsWhenOnlyARuntimeFieldChanges(_ change: ConnectionCase) async throws {
        defer { GopayLocales.setDefaultLocale(nil); GopayLocales.clearCustom() }
        let made = ReinitializableSDK(gateways: [tokenGateway()])
        let sdk = made.sdk
        sdk.initialize(with: change.first)
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        sdk.initialize(with: change.config)

        #expect(await sdk.getPaymentSession("p1") === session)
        #expect(await !isClosed(session))
        #expect(made.gatewaysMade.count == 1)
        await session.close()
    }

    @Test func twoConcurrentInitializeCallsWithTheSameNewConnectionMakeOne() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let made = ReinitializableSDK(gateways: [tokenGateway(), tokenGateway(), tokenGateway()])
        let sdk = made.sdk
        sdk.initialize(with: reinitConfig())
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask { sdk.initialize(with: reinitConfig(shareableKey: "k2")) }
            }
        }
        #expect(await sdk.getPaymentSession("p1") == nil)
        let next = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        #expect(await settle(until: await isClosed(session)))
        // Both may build a gateway before the lock, but only one is kept: the session started
        // after them finds nothing in its way, and a second start for it is refused.
        do {
            _ = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")
            Issue.record("one registry for the new connection")
        } catch {
            #expect(code(of: error) == .authPaymentSessionAlreadyExists)
        }
        #expect(await !isClosed(next))
        await next.close()
    }

    @Test func reinitializeWithTheSameConnectionRegistersTheNewCustomLocales() async throws {
        defer { GopayLocales.setDefaultLocale(nil); GopayLocales.clearCustom() }
        let sdk = ReinitializableSDK(gateways: [tokenGateway()]).sdk
        sdk.initialize(with: reinitConfig())
        let session = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        sdk.initialize(with: reinitConfig(customLocales: ["xx": customStrings]))

        #expect(GopayLocales.resolve("xx").panLabel == "Custom")
        #expect(await sdk.getPaymentSession("p1") === session)
        await session.close()
    }

    /// The background close of an initialize with another connection is part of what
    /// `closeAllPaymentSessions()` waits for: once it returns, no session is open.
    @Test func closeAllPaymentSessionsWaitsForTheSessionsReinitializeCloses() async throws {
        defer { GopayLocales.setDefaultLocale(nil) }
        let sdk = ReinitializableSDK(gateways: [tokenGateway(), tokenGateway()]).sdk
        sdk.initialize(with: reinitConfig())
        let old = try await sdk.startPaymentSession(paymentId: "p1", paymentSecret: "s")

        sdk.initialize(with: reinitConfig(shareableKey: "k2"))
        await sdk.closeAllPaymentSessions()

        #expect(await isClosed(old))
    }
}
