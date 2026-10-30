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
    private func host(isEnabled: Bool, screen: FakeScreen) -> (UIWindow, UITextField) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 380, height: 400))
        window.rootViewController = UIHostingController(
            rootView: GopayCardForm(locale: "en")
                .environment(
                    \.gopayCardFormCaptureProtection,
                    CardFormCaptureProtection(isEnabled: isEnabled, screenIsCaptured: { screen.isCaptured })
                )
        )
        window.isHidden = false
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        return (window, textFields(in: window)[0])
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    /// Whether `field` is visible on screen: its area as drawn holds more than one color, the
    /// placeholder's glyphs over the background. Under the cover the area is a single flat color.
    /// Measured on what is drawn, since what a cover is for is what a snapshot or a recording sees.
    private func isVisible(_ field: UITextField, in window: UIWindow) -> Bool {
        let area = field.convert(field.bounds, to: window)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // `layer.render` rather than `drawHierarchy`, which draws nothing in a test process.
        let image = UIGraphicsImageRenderer(bounds: area, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return false }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        var colors = Set<UInt32>()
        for y in 0..<cgImage.height {
            for x in 0..<cgImage.width {
                let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
                colors.insert(UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]))
                if colors.count > 1 { return true }
            }
        }
        return false
    }

    @Test func theFieldsAreVisibleWhileNothingCoversThem() {
        let (window, field) = host(isEnabled: true, screen: FakeScreen())
        #expect(isVisible(field, in: window))
    }

    @Test func resigningActiveCoversTheFieldsAndBecomingActiveUncoversThem() {
        let (window, field) = host(isEnabled: true, screen: FakeScreen())
        post(UIApplication.willResignActiveNotification)
        #expect(!isVisible(field, in: window))
        post(UIApplication.didBecomeActiveNotification)
        #expect(isVisible(field, in: window))
    }

    @Test func aRecordingCoversTheFieldsUntilItStops() {
        let screen = FakeScreen()
        let (window, field) = host(isEnabled: true, screen: screen)
        screen.isCaptured = true
        post(UIScreen.capturedDidChangeNotification)
        #expect(!isVisible(field, in: window))
        screen.isCaptured = false
        post(UIScreen.capturedDidChangeNotification)
        #expect(isVisible(field, in: window))
    }

    @Test func switchedOffTheFormNeverCoversItself() {
        let screen = FakeScreen()
        screen.isCaptured = true
        let (window, field) = host(isEnabled: false, screen: screen)
        post(UIApplication.willResignActiveNotification)
        post(UIScreen.capturedDidChangeNotification)
        post(UIApplication.didBecomeActiveNotification)
        #expect(isVisible(field, in: window))
    }

    /// Async, unlike the rest of the suite: the field moves the focus in a block it queues on the
    /// main queue, and a test running on that queue only lets it run while it is suspended.
    private func settle() async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    @Test func aRecordingEndsTheInput() async throws {
        let screen = FakeScreen()
        let (window, field) = host(isEnabled: true, screen: screen)
        window.makeKeyAndVisible()
        field.becomeFirstResponder()
        try await settle()
        try #require(field.isFirstResponder)
        screen.isCaptured = true
        NotificationCenter.default.post(name: UIScreen.capturedDidChangeNotification, object: nil)
        try await settle()
        #expect(!field.isFirstResponder)
        // A tap through the cover does not bring the keyboard back.
        #expect(!field.becomeFirstResponder())
        screen.isCaptured = false
        NotificationCenter.default.post(name: UIScreen.capturedDidChangeNotification, object: nil)
        try await settle()
        #expect(field.becomeFirstResponder())
        field.resignFirstResponder()
    }
}
