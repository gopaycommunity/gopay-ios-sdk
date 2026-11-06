//
//  CardFormFocusTests.swift
//  sdkTests
//
//  The form hands the keyboard from one field to the next in one step once a field is typed out:
//  the next field takes the focus before the previous one lets it go, so the keyboard never goes
//  down on the way and a `.medium` sheet keeps its height (GPMOB-192).
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import sdk

// Part of the serialized `CardFormResetTests`: those clear every form on the shared SDK, which
// empties this one too and takes its focus, so the two must not run side by side.
extension CardFormResetTests {

    private func hostFocusForm<Form: View>(_ form: Form) -> (UIWindow, [UITextField]) {
        GopaySDK.shared.clearCardFormData()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: form)
        // Shown but not key: the suites run side by side in one process, and the 3DS tests present
        // their screen over the key window's top view controller, which would take the focus.
        window.isHidden = false
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return (window, textFields(in: window))
    }

    /// Focuses `field` as a tap does.
    private func tap(_ field: UITextField) async throws {
        field.becomeFirstResponder()
        try await settle(until: field.isFirstResponder)
        try #require(field.isFirstResponder)
        try await deliver(.editingDidBegin, to: field)
    }

    /// Runs what `field` does for `event`. The test bundle runs without a host app, where UIKit
    /// does not deliver a control's target actions, so the form hears of it through the action
    /// itself.
    private func deliver(_ event: UIControl.Event, to field: UITextField) async throws {
        for target in field.allTargets {
            for action in field.actions(forTarget: target, forControlEvent: event) ?? [] {
                _ = (target as NSObject).perform(NSSelectorFromString(action), with: field)
            }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    /// How tall the form in `window` lays out: a field showing its error is a line taller.
    private func formHeight(in window: UIWindow) -> CGFloat {
        window.rootViewController?.view.sizeThatFits(
            CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)
        ).height ?? 0
    }

    /// Types `text` into `field` the way the keyboard does, through the field's delegate.
    private func type(_ text: String, into field: UITextField) {
        let end = NSRange(location: (field.text ?? "").utf16.count, length: 0)
        _ = field.delegate?.textField?(field, shouldChangeCharactersIn: end, replacementString: text)
    }

    private func settle(until condition: @autoclosure () -> Bool) async throws {
        var attempts = 100
        while attempts > 0, !condition() {
            attempts -= 1
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// The form's height once SwiftUI has stopped changing it: the same value twice in a row,
    /// a run loop turn apart. A loaded CI runner takes many times longer than a fixed pause to
    /// get there, and a height read too early is not the form at rest.
    private func settledHeight(in window: UIWindow) async throws -> CGFloat {
        var last = formHeight(in: window)
        var attempts = 100
        while attempts > 0 {
            attempts -= 1
            try await Task.sleep(nanoseconds: 50_000_000)
            let next = formHeight(in: window)
            if next == last { return next }
            last = next
        }
        return last
    }

    /// A card number typed out moves the keyboard to the expiration in one step: the card number
    /// lets go of it only inside the expiration's `becomeFirstResponder`, as part of UIKit moving
    /// the focus over. A field resigning on its own first takes the keyboard down for a moment and
    /// lets a `.medium` sheet drop.
    ///
    /// The test bundle has no host app and the simulator a hardware keyboard, where the keyboard
    /// notifications say nothing reliable, so the hand-over is read from the call stack that ended
    /// the card number's editing. Reading symbol names is a deliberate compromise: a `UITextField`
    /// subclass that records its own calls would need the form to build its fields through a
    /// factory the tests can replace, which the SDK has no other use for.
    @Test func aTypedOutCardNumberHandsTheKeyboardOnInOneStep() async throws {
        let (window, fields) = hostFocusForm(GopayCardForm(locale: "en"))
        defer { window.isHidden = true }
        let (cardNumber, expiration) = (fields[0], fields[1])
        try await tap(cardNumber)

        let endings = Locked<[String]>([])
        let observer = NotificationCenter.default.addObserver(
            forName: UITextField.textDidEndEditingNotification, object: cardNumber, queue: nil
        ) { _ in
            // Delivered synchronously, so the stack is the one that ended the editing.
            let insideHandOver = Thread.callStackSymbols.contains { $0.contains("-[UITextField becomeFirstResponder]") }
            endings.value.append(insideHandOver ? "handed over" : "resigned on its own")
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        type("4444444444444448", into: cardNumber)
        try await settle(until: expiration.isFirstResponder)
        #expect(expiration.isFirstResponder)
        #expect(!cardNumber.isFirstResponder)
        #expect(endings.value == ["handed over"])
        expiration.resignFirstResponder()
    }

    /// A mistyped number, 16 digits that fail the Luhn check, keeps the focus where the user can
    /// fix it; an expiration typed out moves on to the CVV.
    @Test func aMistypedCardNumberKeepsTheFocusAndAnExpirationMovesOn() async throws {
        let (window, fields) = hostFocusForm(GopayCardForm(locale: "en"))
        defer { window.isHidden = true }
        let (cardNumber, expiration, cvv) = (fields[0], fields[1], fields[2])
        try await tap(cardNumber)

        type("4444444444444449", into: cardNumber)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(cardNumber.isFirstResponder)
        #expect(!expiration.isFirstResponder)

        try await tap(expiration)
        type("1230", into: expiration)
        try await settle(until: cvv.isFirstResponder)
        #expect(cvv.isFirstResponder)
        cvv.resignFirstResponder()
    }

    /// A screen capture ends the input, and that is not the customer moving on: a field typed out
    /// under the cover hands the focus nowhere, so the keyboard does not come back for the next
    /// field when the capture ends, and the field the cover took the keyboard from is not one the
    /// customer left, so `.live` shows no error for it.
    @Test func aCaptureNeitherAdvancesTheFocusNorCountsAsLeavingAField() async throws {
        let screen = CapturedScreen()
        let (window, fields) = hostFocusForm(
            GopayCardForm(locale: "en", validation: .live)
                .environment(
                    \.gopayCardFormCaptureProtection,
                    CardFormCaptureProtection(isEnabled: true, screenIsCaptured: { screen.isCaptured })
                )
        )
        defer { window.isHidden = true }
        let (cardNumber, expiration) = (fields[0], fields[1])
        func capture(_ isCaptured: Bool) async throws {
            screen.isCaptured = isCaptured
            NotificationCenter.default.post(name: UIScreen.capturedDidChangeNotification, object: nil)
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        try await tap(cardNumber)
        type("4444", into: cardNumber)
        let quiet = try await settledHeight(in: window)

        try await capture(true)
        try await settle(until: !cardNumber.isFirstResponder)
        try await deliver(.editingDidEnd, to: cardNumber)
        try await capture(false)
        let afterCapture = try await settledHeight(in: window)
        #expect(afterCapture == quiet, "the cover taking the keyboard counted as leaving the field")

        // Typed out under the cover: the focus goes nowhere, now or once the capture ends.
        try await capture(true)
        type("444444444448", into: cardNumber)
        try await capture(false)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!expiration.isFirstResponder)
        #expect(!cardNumber.isFirstResponder)

        // The customer leaving the field does show its error, so the height above says something.
        let end = NSRange(location: 0, length: (cardNumber.text ?? "").utf16.count)
        _ = cardNumber.delegate?.textField?(cardNumber, shouldChangeCharactersIn: end, replacementString: "4444")
        try await tap(cardNumber)
        cardNumber.resignFirstResponder()
        try await deliver(.editingDidEnd, to: cardNumber)
        try await settle(until: formHeight(in: window) > quiet)
        #expect(formHeight(in: window) > quiet, "an error for a field the customer left")
    }

    /// A field handing the focus to another one that cannot take it does not keep the keyboard:
    /// one turn later it lets go itself, as it would have without a hand-over.
    @Test func aHandOverNobodyTakesEndsTheInput() async throws {
        let (window, fields) = hostFocusForm(GopayCardForm(locale: "en"))
        defer { window.isHidden = true }
        let (cardNumber, expiration) = (fields[0], fields[1])
        try await tap(cardNumber)
        expiration.isEnabled = false

        type("4444444444444448", into: cardNumber)
        try await settle(until: !cardNumber.isFirstResponder)
        #expect(!cardNumber.isFirstResponder)
        #expect(!expiration.isFirstResponder)
    }
}

/// A screen the test says is being recorded or not.
private final class CapturedScreen {
    var isCaptured = false
}
