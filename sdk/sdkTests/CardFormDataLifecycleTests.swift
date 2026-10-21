//
//  CardFormDataLifecycleTests.swift
//  sdkTests
//
//  Verifies that card data held for GopayCardForm is removed from memory once it is no
//  longer needed (GPMOB-140; PCI DSS 4.0.1, req. 3.3.1).
//

import Testing
import Foundation
import Security
@testable import sdk

// MARK: - In-memory lifecycle (no network)

struct CardFormDataLifecycleTests {

    private func makeData() -> GopayCardFormData {
        GopayCardFormData(cardNumber: "4444333322221111", expirationMonth: "12", expirationYear: "30", cvv: "123")
    }

    @Test func updateStoresAndClearRemoves() {
        let sdk = GopaySDK()
        sdk.updateCardFormData(makeData(), formId: "f1")
        #expect(sdk.internalCardFormData["f1"] != nil)
        #expect(sdk.mostRecentFormId == "f1")

        sdk.clearCardFormData(formId: "f1")
        #expect(sdk.internalCardFormData.isEmpty)
        #expect(sdk.mostRecentFormId == nil)
    }

    @Test func clearingOneFormLeavesTheOther() {
        let sdk = GopaySDK()
        sdk.updateCardFormData(makeData(), formId: "f1")
        sdk.updateCardFormData(makeData(), formId: "f2")

        sdk.clearCardFormData(formId: "f1")
        #expect(sdk.internalCardFormData["f1"] == nil)
        #expect(sdk.internalCardFormData["f2"] != nil)
        // f2 was the most recent form and must stay resolvable.
        #expect(sdk.mostRecentFormId == "f2")
    }

    @Test func clearingUnknownFormIdIsANoOp() {
        let sdk = GopaySDK()
        sdk.updateCardFormData(makeData(), formId: "f1")

        sdk.clearCardFormData(formId: "ghost")
        #expect(sdk.internalCardFormData["f1"] != nil)
        #expect(sdk.mostRecentFormId == "f1")
    }

    @Test func updateAfterClearStoresAgain() {
        // Documents the deliberate semantics: a keystroke (or the form's onAppear re-sync)
        // after a clear makes the form submittable again.
        let sdk = GopaySDK()
        sdk.updateCardFormData(makeData(), formId: "f1")
        sdk.clearCardFormData(formId: "f1")

        sdk.updateCardFormData(makeData(), formId: "f1")
        #expect(sdk.internalCardFormData["f1"] != nil)
        #expect(sdk.mostRecentFormId == "f1")
    }

    @Test func clearWithoutFormIdRemovesEverything() {
        let sdk = GopaySDK()
        sdk.updateCardFormData(makeData(), formId: "f1")
        sdk.updateCardFormData(makeData(), formId: "f2")

        sdk.clearCardFormData()
        #expect(sdk.internalCardFormData.isEmpty)
        #expect(sdk.mostRecentFormId == nil)
    }
}

// MARK: - submitCardForm cleanup (network)
//
// Declared as an extension of `SessionNetworkTests` so these tests join its
// `@Suite(.serialized)` and never race other tests for the shared `StubURLProtocol` state.

private let lifecycleStubBaseURL = "https://stub.test/"

private func lifecycleStubbedClient() -> DefaultNetworkClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return DefaultNetworkClient(baseURL: lifecycleStubBaseURL, configuration: config)
}

extension SessionNetworkTests {

    private func lifecycleSDK() -> GopaySDK {
        let config = GopaySDKConfig(
            environment: .development(baseURL: lifecycleStubBaseURL),
            clientId: "c",
            shareableKey: "k"
        )
        return GopaySDK(config: config, networkClient: lifecycleStubbedClient())
    }

    private func filledData() -> GopayCardFormData {
        GopayCardFormData(cardNumber: "4444333322221111", expirationMonth: "12", expirationYear: "30", cvv: "123")
    }

    @Test func submitCardForm_success_returnsJweAndClearsStorage() async throws {
        let jwkJSON = try TestEncryptionKey().publicJWKJSON
        StubURLProtocol.reset { req in
            (req.url?.path.hasSuffix("cards/public-key") ?? false) ? (200, jwkJSON) : (404, Data())
        }
        let sdk = lifecycleSDK()
        sdk.updateCardFormData(filledData(), formId: "f1")

        let jwe = try await sdk.submitCardForm()
        #expect(jwe.split(separator: ".").count == 5) // compact JWE serialization
        #expect(sdk.internalCardFormData.isEmpty)
        #expect(sdk.mostRecentFormId == nil)

        // The data is gone, so a second submit for the same form must fail.
        do {
            _ = try await sdk.submitCardForm()
            Issue.record("expected noCardFormData")
        } catch let error as GopaySDKError {
            #expect(error.code == .validationInvalidInput)
            #expect(error.message == GopaySDKErrors.noCardFormData)
        }

        // The emptied form syncs its empty fields back in on its next appearance or keystroke;
        // that is still a form without a card, so the answer stays noCardFormData, as on Android.
        sdk.updateCardFormData(GopayCardFormData(), formId: "f1")
        do {
            _ = try await sdk.submitCardForm(formId: "f1")
            Issue.record("expected noCardFormData")
        } catch let error as GopaySDKError {
            #expect(error.message == GopaySDKErrors.noCardFormData)
        }
    }

    /// A form on screen that nobody has typed into has synced empty fields: no card, not an
    /// invalid one. Hosts key their "enter the card" path on this message.
    @Test func submitCardForm_emptyForm_throwsNoCardFormData() async throws {
        StubURLProtocol.reset { _ in (500, Data()) }
        let sdk = lifecycleSDK()
        sdk.updateCardFormData(GopayCardFormData(), formId: "f1")

        do {
            _ = try await sdk.submitCardForm(formId: "f1")
            Issue.record("expected noCardFormData")
        } catch let error as GopaySDKError {
            #expect(error.code == .validationInvalidInput)
            #expect(error.message == GopaySDKErrors.noCardFormData)
        }
        #expect(StubURLProtocol.paths.isEmpty)
    }

    /// A card that is typed but fails validation is a different answer: the user has to fix it,
    /// not enter it.
    @Test func submitCardForm_partiallyTypedForm_throwsInvalidCardFormData() async throws {
        StubURLProtocol.reset { _ in (500, Data()) }
        let sdk = lifecycleSDK()
        sdk.updateCardFormData(GopayCardFormData(cardNumber: "4444"), formId: "f1")

        do {
            _ = try await sdk.submitCardForm(formId: "f1")
            Issue.record("expected invalidCardFormData")
        } catch let error as GopaySDKError {
            #expect(error.message == GopaySDKErrors.invalidCardFormData)
        }
    }

    @Test func aSuccessfulSubmitRunsTheRegisteredWipe() async throws {
        // Only that the wipe is invoked; that it actually empties a live form's fields is covered
        // by CardFormResetTests, which hosts a real GopayCardForm.
        // Clearing the SDK's copy leaves the digits on screen, so the form registers a wipe and
        // the card does not outlive the JWE made from it (GPMOB-140; PCI DSS 4.0.1, req. 3.3.1).
        let jwkJSON = try TestEncryptionKey().publicJWKJSON
        StubURLProtocol.reset { req in
            (req.url?.path.hasSuffix("cards/public-key") ?? false) ? (200, jwkJSON) : (404, Data())
        }
        let sdk = lifecycleSDK()
        sdk.updateCardFormData(filledData(), formId: "f1")

        let wiped = Locked(false)
        sdk.registerCardFormReset({ wiped.value = true }, formId: "f1", owner: CardFormOwner())

        _ = try await sdk.submitCardForm()
        await drainMainQueue()

        #expect(wiped.value)
    }

    @Test func aSubmitThatFailsToEncryptDoesNotRunTheWipe() async throws {
        // The mirror of the rule above: nothing is authorized yet, so the user must not have to
        // retype the card after a network drop. Android resets on success only for the same reason.
        StubURLProtocol.reset { _ in (500, Data()) }
        let sdk = lifecycleSDK()
        sdk.updateCardFormData(filledData(), formId: "f1")

        let wiped = Locked(false)
        sdk.registerCardFormReset({ wiped.value = true }, formId: "f1", owner: CardFormOwner())

        await #expect(throws: GopaySDKError.self) {
            _ = try await sdk.submitCardForm()
        }
        await drainMainQueue()

        #expect(wiped.value == false)
    }

    @Test func unregisteringWipesTheFieldsAndDropsTheHandlerAndTheCard() async throws {
        // The closure holds the form and with it the PAN, so dropping it without firing it would
        // hand the card on rather than clear it. Firing it once is also all that happens: the
        // handler and the SDK's copy are gone afterwards, so a later submit finds no card and
        // cannot reach a view that has left.
        StubURLProtocol.reset { _ in (500, Data()) }
        let sdk = lifecycleSDK()
        sdk.updateCardFormData(filledData(), formId: "f1")
        let owner = CardFormOwner()

        let wipeCount = Locked(0)
        sdk.registerCardFormReset({ wipeCount.value += 1 }, formId: "f1", owner: owner)

        sdk.unregisterCardFormReset(formId: "f1", owner: owner)
        await drainMainQueue()
        #expect(wipeCount.value == 1)
        #expect(sdk.internalCardFormData["f1"] == nil)

        await #expect(throws: GopaySDKError.self) { _ = try await sdk.submitCardForm(formId: "f1") }
        await drainMainQueue()
        #expect(wipeCount.value == 1)
        #expect(StubURLProtocol.paths.isEmpty)
    }

    /// Two forms under the same ID with overlapping lives, as a navigation transition or a
    /// `key()` churn produces: the first form's departure must not take the second form's card
    /// and handlers with it. The Android `CardFormStore` keeps the same owner token.
    @Test func aReplacedFormTakesNothingWithItWhenItLeaves() async {
        let sdk = lifecycleSDK()
        let first = CardFormOwner()
        let second = CardFormOwner()
        let firstWipes = Locked(0)
        let secondWipes = Locked(0)
        let secondAttempts = Locked(0)
        sdk.updateCardFormData(filledData(), formId: "shared")
        sdk.registerCardFormReset({ firstWipes.value += 1 }, formId: "shared", owner: first)
        sdk.updateCardFormData(filledData(), formId: "shared")
        sdk.registerCardFormReset(
            { secondWipes.value += 1 }, submitAttempted: { secondAttempts.value += 1 },
            formId: "shared", owner: second
        )

        sdk.unregisterCardFormReset(formId: "shared", owner: first)
        await drainMainQueue()

        // The card and the second form's handlers are still there, the first form was told nothing.
        #expect(sdk.internalCardFormData["shared"] != nil)
        #expect(firstWipes.value == 0)
        sdk.notifyCardFormSubmitAttempted(formId: "shared")
        sdk.clearCardFormData(formId: "shared")
        await drainMainQueue()
        #expect(secondAttempts.value == 1)
        #expect(secondWipes.value == 1)

        // The second form leaving does take its own handlers with it.
        sdk.unregisterCardFormReset(formId: "shared", owner: second)
        await drainMainQueue()
        #expect(secondWipes.value == 2)
        sdk.notifyCardFormSubmitAttempted(formId: "shared")
        await drainMainQueue()
        #expect(secondAttempts.value == 1)
    }

    /// A wipe writes SwiftUI state, so the SDK hops it to the main thread. Tests run off it, so
    /// they have to let that hop land before reading the result.
    private func drainMainQueue() async {
        await MainActor.run {
            // Nothing to do here: reaching the main actor is the point, the wipe queued before
            // this hop has landed by the time it returns.
        }
    }

    @Test func clearingEveryFormWipesEveryFieldOnScreen() async {
        // Documented as the call for "the user abandoned checkout while the form stayed up", so
        // it has to reach the fields too, not just the SDK's copy.
        let sdk = lifecycleSDK()
        sdk.updateCardFormData(filledData(), formId: "f1")
        sdk.updateCardFormData(filledData(), formId: "f2")

        let wiped = Locked(0)
        sdk.registerCardFormReset({ wiped.value += 1 }, formId: "f1", owner: CardFormOwner())
        sdk.registerCardFormReset({ wiped.value += 1 }, formId: "f2", owner: CardFormOwner())

        sdk.clearCardFormData()
        await drainMainQueue()

        #expect(wiped.value == 2)
        #expect(sdk.internalCardFormData.isEmpty)
    }

    @Test func submitCardForm_encryptionFailure_keepsData() async throws {
        // Key endpoint down → encryption can't happen. Authorization hasn't occurred yet,
        // so the user's input must survive for a retry (deliberate decision, GPMOB-140).
        StubURLProtocol.reset { _ in (500, Data()) }
        let sdk = lifecycleSDK()
        sdk.updateCardFormData(filledData(), formId: "f1")

        await #expect(throws: GopaySDKError.self) {
            _ = try await sdk.submitCardForm()
        }
        #expect(sdk.internalCardFormData["f1"] != nil)
        #expect(sdk.mostRecentFormId == "f1")
    }
}

/// A `Sendable` box for a flag a test closure sets and the test body reads.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

// MARK: - The submit tells the form first

extension SessionNetworkTests {

    /// `submitCardForm` tells the form a submit was attempted before it judges the card, whatever
    /// the outcome, so an `.onSubmit` form shows its errors for an empty or invalid card.
    ///
    /// The handler is queued on the main thread before the validation error is thrown, and the
    /// test records the error on the main thread too, so the two land there in that order; a
    /// handler queued after the throw, or not at all, would put the error first.
    @Test func submitCardFormTellsTheFormBeforeValidating() async {
        StubURLProtocol.reset { _ in (500, Data()) }
        let sdk = GopaySDK(
            config: GopaySDKConfig(environment: .development(baseURL: stubBaseURL), clientId: "c", shareableKey: "k"),
            networkClient: stubbedClient()
        )
        let events = Locked<[String]>([])
        sdk.registerCardFormReset(
            {}, submitAttempted: { events.value.append("attempted") }, formId: "f1", owner: CardFormOwner()
        )

        for data in [GopayCardFormData(), GopayCardFormData(cardNumber: "4444")] {
            sdk.updateCardFormData(data, formId: "f1")
            do {
                _ = try await sdk.submitCardForm(formId: "f1")
                Issue.record("expected a validation error")
            } catch let error as GopaySDKError {
                await MainActor.run { events.value.append(error.message) }
            } catch {
                Issue.record("expected a GopaySDKError, got \(error)")
            }
        }

        #expect(events.value == [
            "attempted", GopaySDKErrors.noCardFormData,
            "attempted", GopaySDKErrors.invalidCardFormData,
        ])

        // A form id nothing is registered for tells nobody and still fails as before.
        await #expect(throws: GopaySDKError.self) { try await sdk.submitCardForm(formId: "other") }
        await MainActor.run {}
        #expect(events.value.count == 4)
    }
}
