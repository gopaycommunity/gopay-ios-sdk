//
//  CardFormResetTests.swift
//  sdkTests
//
//  Covers the wipe from the form's side: a live GopayCardForm registers it, and running it
//  empties the fields, reports the form as invalid and leaves nothing for the SDK to pick up
//  (GPMOB-140; PCI DSS 4.0.1, req. 3.3.1).
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import sdk

/// Serialized: these drive the shared SDK instance, which is what `GopayCardForm` talks to.
@Suite(.serialized)
@MainActor
struct CardFormResetTests {

    /// Hosts `form` in a real window and spins the runloop until SwiftUI has run `onAppear`.
    private func host<V: View>(_ form: V) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: form)
        window.isHidden = false
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return window
    }

    @Test func aLiveFormRegistersItsWipeAndSyncsOnAppear() {
        GopaySDK.shared.clearCardFormData()
        let window = host(GopayCardForm(formId: "reset-register"))
        defer { window.isHidden = true }

        // onAppear syncs the (empty) form, which is how the SDK learns the form exists.
        #expect(GopaySDK.shared.internalCardFormData["reset-register"] != nil)
        #expect(GopaySDK.shared.mostRecentFormId == "reset-register")
    }

    /// The whole chain: the SDK asks the form to wipe, the form empties itself and republishes
    /// its validity. Without `resetFields` writing the binding this stays `nil`.
    @Test func runningTheWipeReportsTheFormAsInvalid() {
        GopaySDK.shared.clearCardFormData()
        let validity = Box<Bool?>(nil)
        let window = host(
            GopayCardForm(isValid: validity.binding, formId: "reset-binding")
        )
        defer { window.isHidden = true }

        validity.value = nil
        GopaySDK.shared.clearCardFormData(formId: "reset-binding")
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(validity.value == false)
    }

    /// A wiped form has nothing left to hand back, so the re-sync that follows carries an empty
    /// card rather than the one the user typed.
    @Test func aWipedFormSyncsBackAnInvalidCard() {
        GopaySDK.shared.clearCardFormData()
        let window = host(GopayCardForm(formId: "reset-resync"))
        defer { window.isHidden = true }

        GopaySDK.shared.clearCardFormData(formId: "reset-resync")
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        // Whatever the form republishes after a wipe must not be submittable.
        let stored = GopaySDK.shared.internalCardFormData["reset-resync"]
        #expect(stored?.isValid != true)
    }

    /// An `.onSubmit` form left at `attempted == true` would show "required" under every emptied
    /// field, also during the 3DS challenge that follows a submit, so the wipe resets it.
    @Test func runningTheWipeSetsAttemptedBackToFalse() {
        GopaySDK.shared.clearCardFormData()
        let attempted = Box(false)
        let window = host(
            GopayCardForm(validation: .onSubmit(attempted: attempted.binding), formId: "reset-attempted")
        )
        defer { window.isHidden = true }

        attempted.value = true
        GopaySDK.shared.clearCardFormData(formId: "reset-attempted")
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(attempted.value == false)
    }

    // MARK: The submit switches `.onSubmit` on

    /// A live `.onSubmit` form registers what a submit does to it: the binding goes to `true`,
    /// so the host does not have to flip it before calling `submitCardForm`.
    @Test func theSubmitTurnsAttemptedOn() {
        GopaySDK.shared.clearCardFormData()
        let attempted = Box(false)
        let window = host(
            GopayCardForm(validation: .onSubmit(attempted: attempted.binding), formId: "submit-attempted")
        )
        defer { window.isHidden = true }

        GopaySDK.shared.notifyCardFormSubmitAttempted(formId: "submit-attempted")
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(attempted.value == true)
    }

    /// Only the form the submit was for is told: a submit for another ID, or for one no form is
    /// on screen under, leaves an `.onSubmit` form's binding alone.
    @Test func aSubmitForAnotherFormLeavesTheBindingAlone() {
        GopaySDK.shared.clearCardFormData()
        let attempted = Box(false)
        let window = host(
            GopayCardForm(validation: .onSubmit(attempted: attempted.binding), formId: "submit-bystander")
        )
        defer { window.isHidden = true }

        GopaySDK.shared.notifyCardFormSubmitAttempted(formId: "submit-gone")
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(attempted.value == false)
    }
}

/// Holds the value behind a binding the form writes, so a test can read what it wrote.
@MainActor
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
    var binding: Binding<Value> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}
