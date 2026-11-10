//
//  CardFormPrivacyCoverTests.swift
//  sdkTests
//
//  The card form covers itself while the app leaves the foreground, so the app switcher snapshot
//  shows no card, and while the screen is recorded or mirrored. Off in a debug build of the host,
//  the way the Android SDK keeps FLAG_SECURE off in a debuggable one.
//

import Testing
import SwiftUI
import UIKit
@testable import sdk

struct CardFormPrivacyCoverTests {

    @Test func resigningActiveCoversWithoutANotice() {
        var cover = CardFormPrivacyCover()
        cover.receive(UIApplication.willResignActiveNotification, screenIsCaptured: { false })
        #expect(cover.isShown)
        #expect(!cover.showsNotice)
    }

    @Test func enteringTheBackgroundCovers() {
        var cover = CardFormPrivacyCover()
        cover.receive(UIApplication.didEnterBackgroundNotification, screenIsCaptured: { false })
        #expect(cover.isShown)
    }

    @Test func becomingActiveUncovers() {
        var cover = CardFormPrivacyCover()
        cover.receive(UIApplication.willResignActiveNotification, screenIsCaptured: { false })
        cover.receive(UIApplication.didEnterBackgroundNotification, screenIsCaptured: { false })
        cover.receive(UIApplication.didBecomeActiveNotification, screenIsCaptured: { false })
        #expect(!cover.isShown)
    }

    @Test func aRecordingCoversWithANoticeUntilItStops() {
        var cover = CardFormPrivacyCover()
        cover.receive(UIScreen.capturedDidChangeNotification, screenIsCaptured: { true })
        #expect(cover.isShown)
        #expect(cover.showsNotice)
        cover.receive(UIScreen.capturedDidChangeNotification, screenIsCaptured: { false })
        #expect(!cover.isShown)
    }

    @Test func becomingActiveKeepsARecordingCovered() {
        var cover = CardFormPrivacyCover()
        cover.receive(UIScreen.capturedDidChangeNotification, screenIsCaptured: { true })
        cover.receive(UIApplication.willResignActiveNotification, screenIsCaptured: { true })
        cover.receive(UIApplication.didBecomeActiveNotification, screenIsCaptured: { true })
        #expect(cover.isShown)
        #expect(cover.showsNotice)
    }

    @Test func aFormAppearingDuringARecordingStartsCovered() {
        var cover = CardFormPrivacyCover()
        cover.refreshCapture { true }
        #expect(cover.isShown)
        #expect(cover.showsNotice)
    }

    @Test func becomingActiveRereadsTheCapture() {
        var cover = CardFormPrivacyCover()
        cover.receive(UIApplication.willResignActiveNotification, screenIsCaptured: { false })
        // The recording started while the app was away and its notification never arrived.
        cover.receive(UIApplication.didBecomeActiveNotification, screenIsCaptured: { true })
        #expect(cover.isShown)
        #expect(cover.showsNotice)
    }

    @Test func otherNotificationsChangeNothing() {
        var cover = CardFormPrivacyCover()
        cover.receive(UIApplication.willEnterForegroundNotification, screenIsCaptured: { true })
        #expect(!cover.isInactive)
        #expect(!cover.isCaptured)
    }

    @Test func protectionIsOffInADebugBuild() {
        // The test target builds in Debug, which is where the host's own tests and screenshots run.
        #expect(!CardFormCaptureProtection.live.isEnabled)
    }
}

/// Serialized: the hosted forms receive the same process-wide notifications.
@Suite(.serialized)
@MainActor
struct CardFormPrivacyCoverHostedTests {

    private final class FakeScreen {
        var isCaptured = false
    }

    /// Hosts a form with the cover switched on and a fake capture state, and returns the window and
    /// the card number field.
    /// The window is hidden again at the end of the test: the suites run side by side in one
    /// process, and a form left on screen keeps hearing the notifications the next tests post.
    private func host(isEnabled: Bool, screen: FakeScreen) async throws -> (UIWindow, UITextField) {
        let window = try await hostedWindow(
            PaymentCardForm(locale: "en")
                .environment(
                    \.gopayCardFormCaptureProtection,
                    CardFormCaptureProtection(isEnabled: isEnabled, screenIsCaptured: { screen.isCaptured })
                ),
            size: CGSize(width: 380, height: 400)
        )
        return (window, textFields(in: window)[0])
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    /// Whether `field` ends up `visible` or covered within the limit; the caller expects it.
    private func fieldSettles(_ field: UITextField, in window: UIWindow, visible: Bool) async -> Bool {
        await settle(until: isVisible(field, in: window) == visible)
    }

    @Test func theFieldsAreVisibleWhileNothingCoversThem() async throws {
        let (window, field) = try await host(isEnabled: true, screen: FakeScreen())
        defer { window.isHidden = true }
        #expect(isVisible(field, in: window))
    }

    @Test func resigningActiveCoversTheFieldsAndBecomingActiveUncoversThem() async throws {
        let (window, field) = try await host(isEnabled: true, screen: FakeScreen())
        defer { window.isHidden = true }
        post(UIApplication.willResignActiveNotification)
        #expect(await fieldSettles(field, in: window, visible: false), "resigning active did not cover the fields")
        post(UIApplication.didBecomeActiveNotification)
        #expect(await fieldSettles(field, in: window, visible: true), "becoming active did not uncover the fields")
    }

    @Test func aRecordingCoversTheFieldsUntilItStops() async throws {
        let screen = FakeScreen()
        let (window, field) = try await host(isEnabled: true, screen: screen)
        defer { window.isHidden = true }
        screen.isCaptured = true
        post(UIScreen.capturedDidChangeNotification)
        #expect(await fieldSettles(field, in: window, visible: false), "the recording did not cover the fields")
        screen.isCaptured = false
        post(UIScreen.capturedDidChangeNotification)
        #expect(await fieldSettles(field, in: window, visible: true), "the end of the recording did not uncover them")
    }

    /// Checked after every notification: a cover that never goes up has no state to wait for, so
    /// each check waits until the form has laid out what the notification changed instead.
    @Test func switchedOffTheFormNeverCoversItself() async throws {
        let screen = FakeScreen()
        screen.isCaptured = true
        let (window, field) = try await host(isEnabled: false, screen: screen)
        defer { window.isHidden = true }
        for name in [
            UIApplication.willResignActiveNotification,
            UIScreen.capturedDidChangeNotification,
            UIApplication.didBecomeActiveNotification,
        ] {
            post(name)
            await drainMainQueue(laidOut: window)
            #expect(isVisible(field, in: window), "covered after \(name.rawValue)")
        }
    }

    /// Async like the rest of the hosted suite: the field moves the focus in a block it queues on
    /// the main queue, and a test running on that queue only lets it run while it is suspended.
    @Test func aRecordingEndsTheInput() async throws {
        let screen = FakeScreen()
        let (window, field) = try await host(isEnabled: true, screen: screen)
        defer { window.isHidden = true }
        window.makeKeyAndVisible()
        field.becomeFirstResponder()
        await settle(until: field.isFirstResponder)
        try #require(field.isFirstResponder)
        screen.isCaptured = true
        NotificationCenter.default.post(name: UIScreen.capturedDidChangeNotification, object: nil)
        await settle(until: !field.isFirstResponder)
        #expect(!field.isFirstResponder)
        // A tap through the cover does not bring the keyboard back.
        #expect(!field.becomeFirstResponder())
        screen.isCaptured = false
        NotificationCenter.default.post(name: UIScreen.capturedDidChangeNotification, object: nil)
        // The field accepts the focus again only once the form has read the capture's end.
        await settle(until: field.becomeFirstResponder())
        #expect(field.isFirstResponder)
        field.resignFirstResponder()
    }
}
