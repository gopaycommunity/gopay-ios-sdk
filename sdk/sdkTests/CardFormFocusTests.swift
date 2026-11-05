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

    private func hostFocusForm() -> (UIWindow, [UITextField]) {
        GopaySDK.shared.clearCardFormData()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: GopayCardForm(locale: "en"))
        // Shown but not key: the suites run side by side in one process, and the 3DS tests present
        // their screen over the key window's top view controller, which would take the focus.
        window.isHidden = false
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return (window, textFields(in: window))
    }

    /// Focuses `field` as a tap does. The test bundle runs without a host app, where UIKit does
    /// not deliver a control's target actions, so the form hears of it through the action itself.
    private func tap(_ field: UITextField) async throws {
        field.becomeFirstResponder()
        try await settle(until: field.isFirstResponder)
        try #require(field.isFirstResponder)
        for target in field.allTargets {
            for action in field.actions(forTarget: target, forControlEvent: .editingDidBegin) ?? [] {
                _ = (target as NSObject).perform(NSSelectorFromString(action))
            }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
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

    /// A card number typed out moves the keyboard to the expiration in one step: the card number
    /// lets go of it only inside the expiration's `becomeFirstResponder`, as part of UIKit moving
    /// the focus over. Resigning on its own first, the way the form did before, took the keyboard
    /// down for a moment and let a `.medium` sheet drop. The test bundle has no host app and a
    /// hardware keyboard, where the keyboard notifications say nothing reliable, so the hand-over
    /// is read from the call that ended the card number's editing.
    @Test func aTypedOutCardNumberHandsTheKeyboardOnInOneStep() async throws {
        let (window, fields) = hostFocusForm()
        defer { window.isHidden = true }
        let (cardNumber, expiration) = (fields[0], fields[1])
        try await tap(cardNumber)

        let endings = Order()
        let observer = NotificationCenter.default.addObserver(
            forName: UITextField.textDidEndEditingNotification, object: cardNumber, queue: nil
        ) { _ in
            // Delivered synchronously, so the stack is the one that ended the editing.
            let insideHandOver = Thread.callStackSymbols.contains { $0.contains("-[UITextField becomeFirstResponder]") }
            endings.append(insideHandOver ? "handed over" : "resigned on its own")
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        type("4444444444444448", into: cardNumber)
        try await settle(until: expiration.isFirstResponder)
        #expect(expiration.isFirstResponder)
        #expect(!cardNumber.isFirstResponder)
        #expect(endings.entries == ["handed over"])
        expiration.resignFirstResponder()
    }

    /// A mistyped number, 16 digits that fail the Luhn check, keeps the focus where the user can
    /// fix it; an expiration typed out moves on to the CVV.
    @Test func aMistypedCardNumberKeepsTheFocusAndAnExpirationMovesOn() async throws {
        let (window, fields) = hostFocusForm()
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
}

/// What happened, in order, from whatever thread it is told.
private final class Order: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var entries: [String] { lock.lock(); defer { lock.unlock() }; return stored }
    func append(_ entry: String) { lock.lock(); defer { lock.unlock() }; stored.append(entry) }
}
