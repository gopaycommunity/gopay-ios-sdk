//
//  CardFormResetTests.swift
//  sdkTests
//
//  Covers the wipe from the form's side: a live PaymentCardForm registers it, and running it
//  empties the fields, reports the form as invalid and leaves nothing for the SDK to pick up
//  (GPMOB-140; PCI DSS 4.0.1, req. 3.3.1).
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import sdk

/// Serialized: these drive the shared SDK instance, which is what `PaymentCardForm` talks to.
@Suite(.serialized)
@MainActor
struct CardFormResetTests {

    /// Hosts `form` in a real window and waits until it is on screen.
    private func host<V: View>(_ form: V) async throws -> UIWindow {
        try await hostedWindow(form)
    }


    @Test func aLiveFormRegistersItsWipeAndSyncsOnAppear() async throws {
        GopaySDK.shared.clearCardFormData()
        let window = try await host(PaymentCardForm(formId: "reset-register"))
        defer { window.isHidden = true }

        // onAppear syncs the (empty) form, which is how the SDK learns the form exists.
        await settle(until: GopaySDK.shared.internalCardFormData["reset-register"] != nil)
        #expect(GopaySDK.shared.internalCardFormData["reset-register"] != nil)
        #expect(GopaySDK.shared.mostRecentFormId == "reset-register")
    }

    /// The whole chain: the SDK asks the form to wipe, the form empties itself and republishes
    /// its validity. Without `resetFields` writing the binding this stays `true`.
    @Test func runningTheWipeReportsTheFormAsInvalid() async throws {
        GopaySDK.shared.clearCardFormData()
        let validity = Box(false)
        let window = try await host(
            PaymentCardForm(isValid: validity.binding, formId: "reset-binding")
        )
        defer { window.isHidden = true }

        validity.value = true
        GopaySDK.shared.clearCardFormData(formId: "reset-binding")
        await settle(until: validity.value == false)

        #expect(validity.value == false)
    }

    /// A wiped form has nothing left to hand back, so the re-sync that follows carries an empty
    /// card rather than the one the user typed.
    @Test func aWipedFormSyncsBackAnInvalidCard() async throws {
        GopaySDK.shared.clearCardFormData()
        let window = try await host(PaymentCardForm(formId: "reset-resync"))
        defer { window.isHidden = true }
        // A card the SDK would take, so the check below is about what the wipe left.
        let fields = textFields(in: window)
        for (field, text) in zip(fields, ["4444444444444448", "1230", "123"]) {
            type(text, into: field)
        }
        await settle(until: GopaySDK.shared.internalCardFormData["reset-resync"]?.isValid == true)
        #expect(GopaySDK.shared.internalCardFormData["reset-resync"]?.isValid == true)

        GopaySDK.shared.clearCardFormData(formId: "reset-resync")
        // Nothing to wait for when the card stays gone: let the form lay out the wipe and run
        // what it queued, so a re-sync of the old card would have landed by now.
        await drainMainQueue(laidOut: window)

        // Whatever the form republishes after a wipe must not be submittable.
        let stored = GopaySDK.shared.internalCardFormData["reset-resync"]
        #expect(stored?.isValid != true)
    }

    /// An `.onSubmit` form left at `attempted == true` would show "required" under every emptied
    /// field, also during the 3DS challenge that follows a submit, so the wipe resets it.
    @Test func runningTheWipeSetsAttemptedBackToFalse() async throws {
        GopaySDK.shared.clearCardFormData()
        let attempted = Box(false)
        let window = try await host(
            PaymentCardForm(validation: .onSubmit, submitAttempted: attempted.binding, formId: "reset-attempted")
        )
        defer { window.isHidden = true }

        attempted.value = true
        GopaySDK.shared.clearCardFormData(formId: "reset-attempted")
        await settle(until: attempted.value == false)

        #expect(attempted.value == false)
    }

    // MARK: Two forms under one ID

    /// Two forms under the same ID share the host's binding, as a navigation transition or a
    /// `key()` churn produces. Only the registered one, the newer, writes it: the replaced one
    /// neither reports what is typed into it nor sets it back to invalid when it leaves.
    ///
    /// The checks that the replaced form wrote nothing have no state to wait for. Each waits until
    /// the form has laid out the change and run what it queued, and the registered form leaving,
    /// which does write the binding, shows the same steps are enough to see a write.
    @Test func onlyTheRegisteredFormWritesTheSharedBinding() async throws {
        GopaySDK.shared.clearCardFormData()
        let validity = Box(false)
        let older = try await host(PaymentCardForm(isValid: validity.binding, formId: "reset-shared"))
        let newer = try await host(PaymentCardForm(isValid: validity.binding, formId: "reset-shared"))
        defer {
            older.isHidden = true
            newer.isHidden = true
        }

        validity.value = true
        type("4444", into: textFields(in: older)[0])
        #expect(textFields(in: older)[0].text == "4444", "the edit did not reach the replaced form")
        await drainMainQueue(laidOut: older)
        #expect(validity.value == true, "the replaced form's edit reached the binding")
        #expect(GopaySDK.shared.internalCardFormData["reset-shared"]?.cardNumber == "")

        older.rootViewController = nil
        older.isHidden = true
        await drainMainQueue(laidOut: older)
        #expect(validity.value == true, "the replaced form's departure reached the binding")

        // The registered form leaving does leave the binding invalid.
        newer.rootViewController = nil
        await drainMainQueue(laidOut: newer)
        #expect(validity.value == false)
    }

    /// The host's `submitAttempted` binding is shared the same way: a replaced form that leaves
    /// does not lower the flag of the form that stays, whose errors would vanish with it.
    @Test func aReplacedFormLeavingKeepsTheSharedSubmitAttempted() async throws {
        GopaySDK.shared.clearCardFormData()
        let attempted = Box(false)
        let older = try await host(
            PaymentCardForm(validation: .onSubmit, submitAttempted: attempted.binding, formId: "attempted-shared")
        )
        let newer = try await host(
            PaymentCardForm(validation: .onSubmit, submitAttempted: attempted.binding, formId: "attempted-shared")
        )
        defer {
            older.isHidden = true
            newer.isHidden = true
        }

        attempted.value = true
        older.rootViewController = nil
        older.isHidden = true
        await drainMainQueue(laidOut: older)
        #expect(attempted.value == true, "the replaced form's departure lowered the shared flag")

        // The registered form leaving does lower it.
        newer.rootViewController = nil
        await settle(until: attempted.value == false)
        #expect(attempted.value == false)
    }

    // MARK: A new ID while on screen

    /// A host hands the form another ID while it stays on screen, one per payment for instance.
    /// The registration and the card move with it: what is typed after the change reaches the SDK
    /// under the new ID, and nothing stays under the old one. The Android form does the same.
    @Test func aNewFormIdMovesTheRegistrationAndTheCard() async throws {
        GopaySDK.shared.clearCardFormData()
        let host = FormIdHost()
        host.id = "reset-id-first"
        let window = try await self.host(FormIdHostView(host: host))
        defer { window.isHidden = true }
        let cardNumber = textFields(in: window)[0]
        func stored(_ id: String) -> GopayCardFormData? { GopaySDK.shared.internalCardFormData[id] }
        type("4444", into: textFields(in: window)[0])
        await settle(until: stored("reset-id-first")?.cardNumber == "4444")
        #expect(stored("reset-id-first")?.cardNumber == "4444")

        host.id = "reset-id-second"
        await settle(until: stored("reset-id-first") == nil && stored("reset-id-second") != nil)
        #expect(GopaySDK.shared.internalCardFormData["reset-id-first"] == nil)
        #expect(GopaySDK.shared.internalCardFormData["reset-id-second"]?.cardNumber == "4444", "the card moves along")
        #expect(cardNumber.text == "4444", "the fields are not emptied")

        type("4", into: textFields(in: window)[0])
        await settle(until: stored("reset-id-second")?.cardNumber == "44444")
        #expect(GopaySDK.shared.internalCardFormData["reset-id-second"]?.cardNumber == "44444")
        #expect(GopaySDK.shared.mostRecentFormId == "reset-id-second")
    }

    /// The host hands the form a new ID and takes it off the screen in the same update, so the
    /// form leaves before it has moved over. It still leaves nothing under the ID it was
    /// registered under.
    @Test func aFormLeavingAsItsIdChangesTakesItsCardFromTheOldId() async throws {
        GopaySDK.shared.clearCardFormData()
        let host = FormIdHost()
        host.id = "reset-gone-first"
        let window = try await self.host(FormIdHostView(host: host))
        defer { window.isHidden = true }
        type("4444", into: textFields(in: window)[0])
        await settle(until: GopaySDK.shared.internalCardFormData["reset-gone-first"]?.cardNumber == "4444")
        #expect(GopaySDK.shared.internalCardFormData["reset-gone-first"]?.cardNumber == "4444")

        host.id = "reset-gone-second"
        host.isShown = false
        await settle(until: GopaySDK.shared.owner(of: "reset-gone-first") == nil)
        // Nor anything under the new ID, which has no state to wait for once the form is gone.
        await drainMainQueue(laidOut: window)
        #expect(GopaySDK.shared.internalCardFormData["reset-gone-first"] == nil)
        #expect(GopaySDK.shared.owner(of: "reset-gone-first") == nil)
        #expect(GopaySDK.shared.internalCardFormData["reset-gone-second"] == nil)
    }

    // MARK: The submit switches `.onSubmit` on

    /// A live `.onSubmit` form registers what a submit does to it: the binding goes to `true`,
    /// so the host does not have to flip it before calling `submitCardForm`.
    @Test func theSubmitTurnsAttemptedOn() async throws {
        GopaySDK.shared.clearCardFormData()
        let attempted = Box(false)
        let window = try await host(
            PaymentCardForm(validation: .onSubmit, submitAttempted: attempted.binding, formId: "submit-attempted")
        )
        defer { window.isHidden = true }

        GopaySDK.shared.notifyCardFormSubmitAttempted(formId: "submit-attempted")
        await settle(until: attempted.value == true)

        #expect(attempted.value == true)
    }

    /// The `.live` mode reads the same flag, so a host that passed the binding sees the submit
    /// there too, as on Android.
    @Test func theSubmitTurnsAttemptedOnInLiveModeToo() async throws {
        GopaySDK.shared.clearCardFormData()
        let attempted = Box(false)
        let window = try await host(
            PaymentCardForm(validation: .live, submitAttempted: attempted.binding, formId: "submit-live")
        )
        defer { window.isHidden = true }

        GopaySDK.shared.notifyCardFormSubmitAttempted(formId: "submit-live")
        await settle(until: attempted.value == true)

        #expect(attempted.value == true)
    }

    /// `.hidden` has nothing to reveal, so a submit leaves the host's flag alone, as in 2.x.
    @Test func aSubmitLeavesTheFlagAloneInHiddenMode() async throws {
        GopaySDK.shared.clearCardFormData()
        let attempted = Box(false)
        let window = try await host(
            PaymentCardForm(validation: .hidden, submitAttempted: attempted.binding, formId: "submit-hidden")
        )
        defer { window.isHidden = true }

        GopaySDK.shared.notifyCardFormSubmitAttempted(formId: "submit-hidden")
        await drainMainQueue(laidOut: window)

        #expect(attempted.value == false)
    }

    /// Only the form the submit was for is told: a submit for another ID, or for one no form is
    /// on screen under, leaves an `.onSubmit` form's binding alone.
    ///
    /// The binding staying alone has no state to wait for, so the check waits until the form has
    /// laid out and run what the submit queued; ``theSubmitTurnsAttemptedOn`` shows a submit for
    /// this form does get through.
    @Test func aSubmitForAnotherFormLeavesTheBindingAlone() async throws {
        GopaySDK.shared.clearCardFormData()
        let attempted = Box(false)
        let window = try await host(
            PaymentCardForm(validation: .onSubmit, submitAttempted: attempted.binding, formId: "submit-bystander")
        )
        defer { window.isHidden = true }

        GopaySDK.shared.notifyCardFormSubmitAttempted(formId: "submit-gone")
        await drainMainQueue(laidOut: window)

        #expect(attempted.value == false)
    }
}

/// The ID a host hands the form, which the test changes while the form is on screen.
@MainActor
private final class FormIdHost: ObservableObject {
    @Published var id = ""
    @Published var isShown = true
}

private struct FormIdHostView: View {
    @ObservedObject var host: FormIdHost
    var body: some View {
        if host.isShown {
            PaymentCardForm(formId: host.id)
        }
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
