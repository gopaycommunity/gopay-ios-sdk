import Combine
import SwiftUI
import UIKit

/// When the card form covers its fields: while the app is leaving the foreground, so the snapshot
/// iOS takes for the app switcher does not show the card, and while the screen is recorded or
/// mirrored.
///
/// iOS cannot keep a view out of a screenshot or a recording the way Android's `FLAG_SECURE` does,
/// so this reacts instead: it hides the form once the system says the screen is being captured,
/// and cannot hide what was captured before that. Nothing here touches the card data, it only
/// decides what the form draws on top of itself.
struct CardFormPrivacyCover {
    /// The app resigned active or went to the background and has not become active again.
    private(set) var isInactive = false
    /// The screen is being recorded, mirrored or sent to another display.
    private(set) var isCaptured = false

    /// Whether the form is covered at all.
    var isShown: Bool { isInactive || isCaptured }

    /// Whether the cover explains itself. Only for a capture, which can last; the cover for the app
    /// switcher is up for a moment and is meant to show nothing.
    var showsNotice: Bool { isCaptured }

    /// The notifications that change the cover.
    static let notifications: [Notification.Name] = [
        UIApplication.willResignActiveNotification,
        UIApplication.didEnterBackgroundNotification,
        UIApplication.didBecomeActiveNotification,
        UIScreen.capturedDidChangeNotification
    ]

    /// Updates the cover for one of ``notifications``.
    mutating func receive(_ name: Notification.Name, screenIsCaptured: () -> Bool) {
        switch name {
        case UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification:
            isInactive = true
        case UIApplication.didBecomeActiveNotification:
            isInactive = false
            // A recording can start or stop while the app is away, and the change notification
            // is not guaranteed to reach an app that was not active to hear it.
            isCaptured = screenIsCaptured()
        case UIScreen.capturedDidChangeNotification:
            isCaptured = screenIsCaptured()
        default:
            break
        }
    }

    /// Reads the capture state afresh, for a form that appears while a recording is already running.
    mutating func refreshCapture(_ screenIsCaptured: () -> Bool) {
        isCaptured = screenIsCaptured()
    }
}

/// Whether the card form covers itself, and where it learns that the screen is captured.
struct CardFormCaptureProtection {
    /// Whether the form covers itself at all.
    var isEnabled: Bool
    /// Whether the screen is being recorded or mirrored right now.
    var screenIsCaptured: () -> Bool

    /// Off in a debug build of the SDK, the way the Android SDK keeps `FLAG_SECURE` off in a
    /// debuggable build: screenshots and recordings of the form keep working while it is being
    /// developed and tested, UI tests and snapshot tests included. Decided when the SDK is
    /// compiled, so it follows the configuration the host builds the SDK in, not a runtime flag.
    static let `default` = CardFormCaptureProtection(
        isEnabled: {
            #if DEBUG
            return false
            #else
            return true
            #endif
        }(),
        screenIsCaptured: { UIScreen.main.isCaptured }
    )

    /// Every notification that changes the cover, as one stream for `onReceive`.
    static var coverChanges: AnyPublisher<Notification, Never> {
        Publishers.MergeMany(
            CardFormPrivacyCover.notifications.map { NotificationCenter.default.publisher(for: $0) }
        )
        .eraseToAnyPublisher()
    }
}

// MARK: - Test hook

private struct CardFormCaptureProtectionKey: EnvironmentKey {
    static let defaultValue = CardFormCaptureProtection.default
}

extension EnvironmentValues {
    /// Internal, so tests can switch the cover on in a debug build and fake a recording.
    var gopayCardFormCaptureProtection: CardFormCaptureProtection {
        get { self[CardFormCaptureProtectionKey.self] }
        set { self[CardFormCaptureProtectionKey.self] = newValue }
    }
}
