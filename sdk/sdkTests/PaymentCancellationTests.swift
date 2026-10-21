//
//  PaymentCancellationTests.swift
//  sdkTests
//
//  Pins the two ways a payment window ends early. A window that closed before it finished is
//  PAYMENT_011; the awaiting task cancelled by the host closes the 3DS screen and is
//  CancellationError. The Android SDK draws the same line.
//

import Testing
import Foundation
import Network
import UIKit
@testable import sdk

/// Waits until everything already queued on the main queue has run.
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

@MainActor
struct HostCancellationTests {

    @Test func aCancellationBeforeTheFlowStartsIsSeenByIt() async {
        let cancellation = HostCancellation()
        cancellation.cancel()
        await drainMainQueue()

        var ran = 0
        cancellation.onCancel { ran += 1 }
        #expect(cancellation.isCancelled)
        #expect(ran == 1)
    }

    @Test func aCancellationAfterTheFlowStartedClosesItOnce() async {
        let cancellation = HostCancellation()
        var ran = 0
        cancellation.onCancel { ran += 1 }

        cancellation.cancel()
        cancellation.cancel()
        await drainMainQueue()

        #expect(ran == 1)
    }

    /// The flag is set at once, so an outcome the 3DS screen reports in the same main-thread pass
    /// already reads as the host's cancellation.
    @Test func aCancellationIsSeenRightAway() {
        let cancellation = HostCancellation()
        cancellation.cancel()
        #expect(cancellation.isCancelled)
    }
}

/// Accepts connections and never answers, so a WebView pointed at it keeps loading.
private final class SilentServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "silent-server")
    private var connections: [NWConnection] = []

    init() throws {
        // Loopback only: nothing outside this machine can reach the test's listener.
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [unowned self] connection in
            connections.append(connection)
            connection.start(queue: queue)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
    }

    var url: URL { URL(string: "http://127.0.0.1:\(listener.port?.rawValue ?? 0)/challenge")! }

    func stop() {
        listener.cancel()
        queue.sync { connections.forEach { $0.cancel() } }
    }
}

extension SessionNetworkTests {

    private func makeVerifyingSession() async throws -> PaymentSession {
        StubURLProtocol.reset { req in
            (req.url?.path ?? "").hasSuffix("oauth2/token") ? tokenResponse() : (404, Data())
        }
        return try await makeSession()
    }

    /// Starts a verification from a real window and returns the screen it presented.
    ///
    /// The test process has no window scene, so UIKit wires the presentation up but never runs
    /// its transition: `viewDidAppear` does not come on its own, and a dismissal never finishes.
    /// The test calls `viewDidAppear` where UIKit would; everything else, from the task's
    /// cancellation to the continuation and the in-progress guard, runs for real.
    private func startVerification(
        _ session: PaymentSession, at url: URL
    ) async throws -> (task: Task<Void, Error>, screen: GopayChargeVerificationViewController, window: UIWindow) {
        let (presenter, window) = await MainActor.run { () -> (UIViewController, UIWindow) in
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let presenter = UIViewController()
            window.rootViewController = presenter
            window.isHidden = false
            return (presenter, window)
        }
        let task = Task { try await session.handle3dsVerification(redirectURL: url, presenting: presenter) }
        var screen: GopayChargeVerificationViewController?
        for _ in 0..<50 where screen == nil {
            screen = await MainActor.run { presenter.presentedViewController as? GopayChargeVerificationViewController }
            if screen == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        }
        let shown = try #require(screen)
        await MainActor.run { shown.viewDidAppear(false) }
        return (task, shown, window)
    }

    private func outcome(of task: Task<Void, Error>) async -> Error? {
        do {
            try await task.value
            return nil
        } catch {
            return error
        }
    }

    /// Cancel, a screen closed elsewhere and a failure after rendering all report `.cancelled`.
    @Test(.timeLimit(.minutes(1)))
    func aVerificationClosedBeforeItFinishedIsPaymentCancelled() async throws {
        let server = try SilentServer()
        defer { server.stop() }
        let session = try await makeVerifyingSession()

        let (task, screen, window) = try await startVerification(session, at: server.url)
        defer { Task { @MainActor in window.isHidden = true } }

        await MainActor.run { screen.report(.cancelled) }
        let error = await outcome(of: task)

        #expect((error as? GopaySDKError)?.code == .paymentCancelled, "got \(String(describing: error))")
        #expect(await MainActor.run { !SheetGuards.verificationInProgress })
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingTheTaskClosesTheShownVerificationAndFreesTheGuard() async throws {
        let server = try SilentServer()
        defer { server.stop() }
        let session = try await makeVerifyingSession()

        let (task, _, window) = try await startVerification(session, at: server.url)
        defer { Task { @MainActor in window.isHidden = true } }
        #expect(await MainActor.run { SheetGuards.verificationInProgress })

        task.cancel()
        let error = await outcome(of: task)

        #expect(error is CancellationError, "got \(String(describing: error))")
        #expect(await MainActor.run { !SheetGuards.verificationInProgress })
    }

    /// The challenge is between the WebView and the issuer and needs neither the secret nor the
    /// token, so a closed session still shows it, as the Android SDK does (GPMOB-160, A8). Only
    /// the charge state read afterwards needs the session to be live.
    @Test(.timeLimit(.minutes(1)))
    func aVerificationStartsOnAClosedSession() async throws {
        let server = try SilentServer()
        defer { server.stop() }
        let session = try await makeVerifyingSession()
        await session.close()

        let (task, screen, window) = try await startVerification(session, at: server.url)
        defer { Task { @MainActor in window.isHidden = true } }
        #expect(await MainActor.run { screen.presentingViewController != nil })

        task.cancel()
        let error = await outcome(of: task)
        #expect(error is CancellationError, "got \(String(describing: error))")
    }

    /// The guard a cancelled verification held is free again: the next one starts and shows.
    @Test(.timeLimit(.minutes(1)))
    func afterACancelledVerificationTheNextOneStarts() async throws {
        let server = try SilentServer()
        defer { server.stop() }
        let session = try await makeVerifyingSession()

        let first = try await startVerification(session, at: server.url)
        defer { Task { @MainActor in first.window.isHidden = true } }
        first.task.cancel()
        _ = await outcome(of: first.task)

        let next = try await startVerification(session, at: server.url)
        defer { Task { @MainActor in next.window.isHidden = true } }
        #expect(await MainActor.run { SheetGuards.verificationInProgress })
        next.task.cancel()
        #expect(await outcome(of: next.task) is CancellationError)
        #expect(await MainActor.run { !SheetGuards.verificationInProgress })
    }

    @Test func aVerificationInAnAlreadyCancelledTaskShowsNothing() async throws {
        let session = try await makeVerifyingSession()

        let error = await Task { () -> Error? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await session.handle3dsVerification(redirectURL: URL(string: "https://3ds.example/step")!)
                return nil
            } catch {
                return error
            }
        }.value

        #expect(error is CancellationError, "got \(String(describing: error))")
        #expect(await MainActor.run { !SheetGuards.verificationInProgress })
    }

    @Test func anApplePayChargeInAnAlreadyCancelledTaskShowsNoSheet() async throws {
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") { return tokenResponse() }
            if path.hasSuffix("apple-pay/app-info") { return (200, json(applePayAppInfoJSON())) }
            return (404, Data())
        }
        let session = try await makeSession()
        let browserData = BrowserData(
            language: "cs", timezone: 0, screenWidth: 1, screenHeight: 1, colorDepth: 24,
            userAgent: "ua", acceptHeader: "accept", javascriptEnabled: true, ip: "192.0.2.1"
        )

        let error = await Task { () -> Error? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await session.chargeWithApplePay(browserData: browserData)
                return nil
            } catch {
                return error
            }
        }.value

        #expect(error is CancellationError, "got \(String(describing: error))")
        #expect(await MainActor.run { !SheetGuards.applePayInProgress })
    }
}
