//
//  CardFormProgressTests.swift
//  sdkTests
//
//  The card form's steps: the tracker ported from the browser SDK with the browser's own cases,
//  the states the form derives from its fields, what may leave as params, and the steps as the
//  telemetry sends them, budgets included.
//

import Testing
import Foundation
@testable import sdk

private typealias States = CardFormProgress.States
private typealias FieldError = CardFormProgress.FieldError

private func states(_ pan: CardFormProgress.FieldState, _ expiry: CardFormProgress.FieldState, _ cvv: CardFormProgress.FieldState) -> States {
    States(pan: pan, expiry: expiry, cvv: cvv)
}

private func errors(_ entries: (CardFormProgress.Field, CardFormProgress.ErrorCode)...) -> [FieldError] {
    entries.map { FieldError(field: $0.0, code: $0.1) }
}

/// The params as the event carries them, for comparing.
private func json(_ report: CardFormProgress.Report?) -> String? {
    report.flatMap { Telemetry.describeParams($0.params) }
}

// MARK: - The tracker

struct CardFormProgressTests {

    @Test func reportsTheStartOnceWithTheStatesItFound() throws {
        let progress = CardFormProgress()
        #expect(progress.progress(states(.empty, .empty, .empty), sinceReady: 5) == nil)
        let started = try #require(progress.progress(states(.partial, .empty, .empty), sinceReady: 10))
        #expect(progress.progress(states(.complete, .partial, .empty), sinceReady: 20) == nil)
        #expect(progress.progress(states(.complete, .complete, .complete), sinceReady: 30) == nil)

        #expect(json(started) == #"{"cvv":"empty","expiry":"empty","filled_at_once":false,"pan":"partial"}"#)
        #expect(started.message == "started typing")
    }

    @Test func marksAStartThatArrivedWholeAsFilledAtOnce() throws {
        let progress = CardFormProgress()
        let started = try #require(progress.progress(states(.complete, .empty, .empty), sinceReady: 10))
        #expect(json(started) == #"{"cvv":"empty","expiry":"empty","filled_at_once":true,"pan":"complete"}"#)
        #expect(started.message == "started with autofill or paste")
    }

    /// A field reaching complete from partial is typing; only empty to complete arrived whole.
    @Test func doesNotCallDigitsTypedOneByOneAFillAtOnce() {
        let progress = CardFormProgress()
        _ = progress.progress(states(.partial, .empty, .empty), sinceReady: 1)
        _ = progress.progress(states(.complete, .partial, .empty), sinceReady: 2)
        _ = progress.progress(states(.complete, .complete, .partial), sinceReady: 3)
        #expect(json(progress.summary(.unmount))?.contains(#""filled_at_once":false"#) == true)
    }

    /// 500 ms after the ready, 100 of them before the first digit: counted from the start.
    @Test func reportsTheCardCompletedOnceWithHowLongItTookFromTheStart() throws {
        let progress = CardFormProgress()
        _ = progress.progress(states(.partial, .empty, .empty), sinceReady: 100)
        let completed = try #require(progress.validity(true, sinceReady: 500))
        #expect(progress.validity(false, sinceReady: 550) == nil)
        #expect(progress.validity(true, sinceReady: 560) == nil)

        #expect(json(completed) == #"{"since_started_ms":400}"#)
        #expect(completed.message == "card complete")
    }

    @Test func reportsFieldErrorsOnlyForASubmitOrAProblemThatWasNotStanding() {
        let progress = CardFormProgress()
        var sent: [(String?, String)] = []
        func report(_ list: [FieldError], _ trigger: CardFormProgress.Trigger) {
            if let step = progress.fieldErrors(list, trigger: trigger) {
                sent.append((json(step), step.message))
            }
        }

        report(errors((.pan, .pattern)), .blur)
        // The same problem again, and then fixed: nothing new went wrong.
        report(errors((.pan, .pattern)), .input)
        report(errors(), .input)
        // Every submit is an attempt to pay, the same errors or not.
        report(errors((.pan, .pattern), (.cvv, .required)), .submit)
        report(errors((.pan, .pattern), (.cvv, .required)), .submit)
        report(errors((.cvv, .required)), .input)
        report(errors((.cvv, .required), (.expiry, .pattern)), .input)
        report(errors(), .submit)

        #expect(sent.map(\.0) == [
            #"{"count":1,"errors":"pan:pattern","raised":"pan:pattern","trigger":"blur"}"#,
            #"{"count":2,"errors":"pan:pattern,cvv:required","raised":"pan:pattern,cvv:required","trigger":"submit"}"#,
            #"{"count":2,"errors":"pan:pattern,cvv:required","raised":"","trigger":"submit"}"#,
            #"{"count":2,"errors":"cvv:required,expiry:pattern","raised":"expiry:pattern","trigger":"input"}"#,
            #"{"count":0,"errors":"","raised":"","trigger":"submit"}"#,
        ])
        #expect(sent.map(\.1) == ["new field errors", "submit errors", "submit errors", "new field errors", "submit ok"])
    }

    @Test func doesNotReportTheAbsenceOfErrorsTheFormStartedWith() {
        let progress = CardFormProgress()
        #expect(progress.fieldErrors([], trigger: .blur) == nil)
        #expect(progress.fieldErrors([], trigger: .input) == nil)
    }

    @Test func reportsASubmitRequestWithTheValidityItWasAskedOn() {
        let progress = CardFormProgress()
        let first = progress.submitRequest()
        _ = progress.validity(true, sinceReady: 1)
        let second = progress.submitRequest()
        #expect([json(first), json(second)] == [#"{"valid":false}"#, #"{"valid":true}"#])
        #expect([first.message, second.message] == ["pay pressed with incomplete card", "pay pressed"])
    }

    /// The browser's "summarises the visit once" case, step for step.
    @Test func summarisesTheVisit() {
        let progress = CardFormProgress()
        _ = progress.fieldErrors(errors((.pan, .required), (.expiry, .required), (.cvv, .required)), trigger: .submit)
        _ = progress.progress(states(.complete, .complete, .partial), sinceReady: 100)
        _ = progress.fieldErrors(errors((.cvv, .pattern)), trigger: .blur)
        _ = progress.submitRequest()
        _ = progress.progress(states(.complete, .complete, .complete), sinceReady: 300)
        _ = progress.validity(true, sinceReady: 300)
        _ = progress.validity(false, sinceReady: 310)
        _ = progress.validity(true, sinceReady: 320)
        _ = progress.submitRequest()

        let summary = progress.summary(.unmount)
        #expect(summary.message == "unmount: completed")
        #expect(json(summary) == """
            {"became_valid":true,"ended":"unmount","error_codes_seen":"cvv:pattern,cvv:required,expiry:required,pan:required",\
            "errors_raised":4,"filled_at_once":true,"first_valid_ms":300,"invalid_submit_requests":1,"invalid_submits":1,\
            "progress_at_end":"pan:complete,expiry:complete,cvv:complete","started_ms":100,"submit_requests":2,\
            "valid_at_end":true,"validity_flips":1}
            """)
    }

    @Test func summarisesACustomerWhoLeavesWithoutTypingAnything() {
        let summary = CardFormProgress().summary(.unmount)
        #expect(summary.message == "unmount: never started")
        #expect(json(summary) == """
            {"became_valid":false,"ended":"unmount","error_codes_seen":"","errors_raised":0,"filled_at_once":false,\
            "invalid_submit_requests":0,"invalid_submits":0,"submit_requests":0,"valid_at_end":false,"validity_flips":0}
            """)
    }

    /// Progress reports arrive, so a customer who had typed would have been seen; the errors of an
    /// empty submit alone do not say they did.
    @Test func stillCallsAFormThatOnlyEverReportedAnEmptySubmitNeverStarted() {
        let progress = CardFormProgress()
        _ = progress.progress(.untouched, sinceReady: 1)
        _ = progress.fieldErrors(errors((.pan, .required)), trigger: .submit)
        #expect(progress.summary(.unmount).message == "unmount: never started")
    }

    /// The host emptying the form is not the customer editing a complete card back to invalid.
    @Test func takesTheHostsClearAsNoFlipAndForgetsWhatWasStanding() throws {
        let progress = CardFormProgress()
        _ = progress.progress(states(.complete, .complete, .complete), sinceReady: 10)
        _ = progress.validity(true, sinceReady: 10)
        _ = progress.fieldErrors(errors((.cvv, .pattern)), trigger: .blur)
        progress.cleared()

        #expect(progress.states == .untouched)
        #expect(json(progress.submitRequest()) == #"{"valid":false}"#)
        let again = try #require(progress.fieldErrors(errors((.cvv, .pattern)), trigger: .blur))
        #expect(json(again)?.contains(#""raised":"cvv:pattern""#) == true, "raised anew once the form was emptied")
        let summary = json(progress.summary(.submit))
        #expect(summary?.contains(#""validity_flips":0"#) == true)
        #expect(summary?.contains(#""progress_at_end":"pan:empty,expiry:empty,cvv:empty""#) == true)
    }

    // MARK: Errors from states

    @Test func makesAnEmptyJudgedFieldRequiredAndAPartialOnePattern() {
        let current = states(.empty, .partial, .complete)
        #expect(current.errors(judged: []) == [])
        #expect(current.errors(judged: [.pan, .expiry, .cvv]) == errors((.pan, .required), (.expiry, .pattern)))
        #expect(current.errors(judged: [.expiry]) == errors((.expiry, .pattern)))
    }

    // MARK: States from the form's fields

    @Test func takesTheStatesFromTheFormsOwnValidators() {
        #expect(GopayCardFormData().progressStates == .untouched)
        let partial = GopayCardFormData(cardNumber: "4", expirationMonth: "1", expirationYear: "", cvv: "12")
        #expect(partial.progressStates == states(.partial, .partial, .partial))
        // A whole number the form refuses is as partial as one digit.
        let refused = GopayCardFormData(cardNumber: "444444444444444", expirationMonth: "12", expirationYear: "20", cvv: "1234")
        #expect(refused.progressStates == states(.partial, .partial, .partial))
        let card = GopayCardFormData(cardNumber: "4444444444444448", expirationMonth: "12", expirationYear: "99", cvv: "123")
        #expect(card.progressStates == states(.complete, .complete, .complete))
        #expect(card.progressStates.isValid == card.isValid)
    }

    // MARK: What may leave

    @Test func passesEveryParamTheTrackerProduces() {
        let progress = CardFormProgress()
        let reports = [
            progress.progress(states(.complete, .partial, .empty), sinceReady: 1),
            progress.fieldErrors(errors((.cvv, .required), (.expiry, .pattern)), trigger: .submit),
            progress.validity(true, sinceReady: 2),
            progress.submitRequest(),
            progress.summary(.encryptError),
            progress.summary(.submit),
            CardFormProgress().summary(.unmount),
        ].compactMap { $0 }
        for report in reports {
            #expect(CardFormProgress.vetted(report.params, message: report.message) != nil, "\(report.message)")
        }
    }

    /// A value, a length or a digit count in any param, or a message that is not the tracker's,
    /// takes the step down instead of riding along.
    @Test(arguments: [
        ["pan": Telemetry.Param.string("4444444444444448")],
        ["pan": .string("complete"), "value": .string("4444444444444448")],
        ["length": .int(16)],
        ["digits": .int(15)],
        ["errors": .string("pan:4444444444444448")],
        ["errors": .string("pan:pattern,4444444444444448")],
        ["raised": .string("cvv:123")],
        ["progress_at_end": .string("pan:complete,expiry:1228,cvv:empty")],
        ["progress_at_end": .string("")],
        ["trigger": .string("4444444444444448")],
        ["ended": .string("4444444444444448")],
        ["count": .int(-16)],
        ["count": .string("16")],
        ["valid": .string("true")],
        ["filled_at_once": .int(1)],
    ] as [[String: Telemetry.Param]])
    func refusesAnythingButStatesCodesAndCounts(params: [String: Telemetry.Param]) {
        #expect(CardFormProgress.vetted(params, message: "started typing") == nil)
    }

    @Test func refusesAMessageThatIsNotTheTrackers() {
        #expect(CardFormProgress.vetted(["valid": .bool(true)], message: "pay pressed") != nil)
        #expect(CardFormProgress.vetted(["valid": .bool(true)], message: "pay pressed 4444444444444448") == nil)
        #expect(CardFormProgress.vetted([:], message: "unmount: completed") != nil)
        #expect(CardFormProgress.vetted([:], message: "leave: completed") == nil)
    }
}

// MARK: - The steps as sent

/// Lets the main queue run what is already on it: a blur the telemetry takes one frame later.
func nextFrame() async {
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async { done.resume() }
    }
}

struct CardFormStepTelemetryTests {

    private let card = GopayCardFormData(cardNumber: "4444444444444448", expirationMonth: "12", expirationYear: "28", cvv: "123")

    private func steps(_ events: [[String: Any]]) -> [[String: Any]] {
        events.filter { ($0["function_name"] as? String).map { $0.hasPrefix("PAYMENT_CARD.") } == true }
    }

    private func names(_ events: [[String: Any]]) -> [String] {
        steps(events).compactMap { $0["function_name"] as? String }
    }

    private func summaries(_ events: [[String: Any]]) -> [[String: Any]] {
        steps(events).filter { $0["function_name"] as? String == "PAYMENT_CARD.interaction" }
    }

    /// An empty submit, then a paste, then pay: the errors of the empty submit, the start filled
    /// at once, the card complete, a clean submit, and the JWE, which ends the visit with the card
    /// as it was. The form emptied afterwards and leaving it add no second summary.
    @Test func reportsAnEmptySubmitThenAPasteThenPay() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        let telemetry = probe.telemetry
        telemetry.cardFormReady(owner: owner)
        telemetry.cardFormSubmitRequested(owner: owner)
        telemetry.cardFormInput(owner: owner, states: GopayCardFormData(cardNumber: card.cardNumber).progressStates)
        telemetry.cardFormInput(owner: owner, states: card.progressStates)
        telemetry.cardFormSubmitRequested(owner: owner)
        telemetry.cardFormSubmitted(owner: owner)
        telemetry.cardFormCleared(owner: owner)
        telemetry.cardFormUnmounted(owner: owner)

        let events = await probe.settledEvents(10)
        #expect(names(events) == [
            "PAYMENT_CARD.ready",
            "PAYMENT_CARD.submit-request", "PAYMENT_CARD.field-errors",
            "PAYMENT_CARD.started",
            "PAYMENT_CARD.completed",
            "PAYMENT_CARD.submit-request", "PAYMENT_CARD.field-errors",
            "PAYMENT_CARD.interaction",
            "PAYMENT_CARD.unmount",
        ])
        let sent = steps(events)
        #expect(sent[1]["params"] as? String == #"{"valid":false}"#)
        #expect(sent[2]["params"] as? String == #"{"count":3,"errors":"pan:required,expiry:required,cvv:required","raised":"pan:required,expiry:required,cvv:required","trigger":"submit"}"#)
        #expect(sent[2]["return_value"] as? String == "submit errors")
        #expect(sent[3]["params"] as? String == #"{"cvv":"empty","expiry":"empty","filled_at_once":true,"pan":"complete"}"#)
        #expect(sent[3]["return_value"] as? String == "started with autofill or paste")
        #expect(sent[4]["return_value"] as? String == "card complete")
        #expect(sent[5]["params"] as? String == #"{"valid":true}"#)
        #expect(sent[6]["return_value"] as? String == "submit ok")
        #expect(sent[7]["return_value"] as? String == "submit: completed")
        let summary = try #require(sent[7]["params"] as? String)
        #expect(summary.contains(#""invalid_submits":1"#) && summary.contains(#""submit_requests":2"#))
        #expect(summary.contains(#""ended":"submit""#))
        #expect(summary.contains(#""progress_at_end":"pan:complete,expiry:complete,cvv:complete""#), "the card before the SDK emptied it")
        #expect(summary.contains(#""valid_at_end":true"#))

        for step in sent {
            #expect(step["event_type"] as? String == "js_event")
            #expect(step["flow"] as? String == "return-payload")
            #expect(step["duration"] is Int, "timed from the form's ready")
        }
        // The JWE is still the submit interaction it always was, right before the summary.
        let submit = try #require(events.firstIndex { $0["event_type"] as? String == "interaction" })
        #expect(events[submit]["element_id"] as? String == "card-form")
        #expect(events[submit + 1]["function_name"] as? String == "PAYMENT_CARD.interaction")
    }

    /// The charge after the JWE was declined and the customer types a second card into the same
    /// form: a new visit, with its own start, completion and summary.
    @Test func startsANewVisitWhenTheCustomerTypesAgainAfterTheJwe() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        let telemetry = probe.telemetry
        telemetry.cardFormReady(owner: owner)
        telemetry.cardFormInput(owner: owner, states: card.progressStates)
        telemetry.cardFormSubmitRequested(owner: owner)
        telemetry.cardFormSubmitted(owner: owner)
        telemetry.cardFormCleared(owner: owner)
        // The emptied form loses its focus: no visit to judge, no new one either.
        telemetry.cardFormFieldLeft(owner: owner, field: .cvv, edited: false)
        await nextFrame()
        telemetry.cardFormInput(owner: owner, states: GopayCardFormData(cardNumber: "4").progressStates)
        telemetry.cardFormInput(owner: owner, states: card.progressStates)
        telemetry.cardFormUnmounted(owner: owner)

        let events = await probe.settledEvents(11)
        #expect(names(events) == [
            "PAYMENT_CARD.ready", "PAYMENT_CARD.started", "PAYMENT_CARD.completed",
            "PAYMENT_CARD.submit-request", "PAYMENT_CARD.field-errors", "PAYMENT_CARD.interaction",
            "PAYMENT_CARD.started", "PAYMENT_CARD.completed",
            "PAYMENT_CARD.unmount", "PAYMENT_CARD.interaction",
        ])
        let second = try #require(steps(events).dropFirst(6).first)
        #expect(second["params"] as? String == #"{"cvv":"empty","expiry":"empty","filled_at_once":false,"pan":"partial"}"#)
        let ends = summaries(events)
        #expect(ends.compactMap { $0["return_value"] as? String } == ["submit: completed", "unmount: completed"])
        let last = try #require(ends.last?["params"] as? String)
        #expect(last.contains(#""submit_requests":0"#), "the second visit counts only itself")
    }

    /// The host's pay button pressed again on the form the SDK emptied after the JWE, with nothing
    /// typed: the submit wakes a new visit, which ends as never started with every field empty.
    @Test func aSubmitOnTheFormTheSdkEmptiedAfterTheJweWakesANewVisit() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        let telemetry = probe.telemetry
        telemetry.cardFormReady(owner: owner)
        telemetry.cardFormInput(owner: owner, states: card.progressStates)
        telemetry.cardFormSubmitRequested(owner: owner)
        telemetry.cardFormSubmitted(owner: owner)
        telemetry.cardFormCleared(owner: owner)
        telemetry.cardFormSubmitRequested(owner: owner)
        telemetry.cardFormUnmounted(owner: owner)

        let ends = summaries(await probe.settledEvents(11))
        #expect(ends.compactMap { $0["return_value"] as? String } == ["submit: completed", "unmount: never started"])
        let second = try #require(ends.last?["params"] as? String)
        #expect(second.contains(#""progress_at_end":"pan:empty,expiry:empty,cvv:empty""#))
        #expect(second.contains(#""submit_requests":1"#))
        #expect(second.contains(#""invalid_submit_requests":1"#))
        #expect(second.contains(#""invalid_submits":1"#))
    }

    /// `clearCardFormData` after a failed encryption empties the form but does not end the visit
    /// another way: with nothing typed after it, the visit still ends as `encrypt-error`.
    @Test func aFailedEncryptionStillEndsTheVisitWhenTheIntegratorEmptiesTheFormAfterIt() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        let telemetry = probe.telemetry
        telemetry.cardFormReady(owner: owner)
        telemetry.cardFormInput(owner: owner, states: card.progressStates)
        telemetry.cardFormSubmitRequested(owner: owner)
        telemetry.cardFormEncryptFailed(owner: owner)
        telemetry.cardFormCleared(owner: owner)
        telemetry.cardFormUnmounted(owner: owner)

        let ends = summaries(await probe.settledEvents(7))
        #expect(ends.compactMap { $0["return_value"] as? String } == ["encrypt-error: completed"])
        let summary = try #require(ends.first?["params"] as? String)
        #expect(summary.contains(#""progress_at_end":"pan:empty,expiry:empty,cvv:empty""#))
    }

    /// A form nobody touched, or one only submitted empty, never started; its summary still
    /// carries the states it ended with.
    @Test func callsAnUntouchedFormNeverStartedWithItsStates() async throws {
        let probe = TelemetryProbe()
        let untouched = NSObject(), submitted = NSObject()
        for owner in [untouched, submitted] {
            probe.telemetry.cardFormReady(owner: owner)
        }
        probe.telemetry.cardFormSubmitRequested(owner: submitted)
        probe.telemetry.cardFormUnmounted(owner: untouched)
        probe.telemetry.cardFormUnmounted(owner: submitted)

        let ends = summaries(await probe.settledEvents(8))
        #expect(ends.compactMap { $0["return_value"] as? String } == ["unmount: never started", "unmount: never started"])
        for end in ends {
            #expect((end["params"] as? String)?.contains(#""progress_at_end":"pan:empty,expiry:empty,cvv:empty""#) == true)
        }
        #expect((ends[1]["params"] as? String)?.contains(#""invalid_submits":1"#) == true)
    }

    /// Starting to type and leaving: the start and the summary, nothing else.
    @Test func reportsAStartAndTheSummaryOfACustomerWhoLeft() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        probe.telemetry.cardFormReady(owner: owner)
        probe.telemetry.cardFormInput(owner: owner, states: GopayCardFormData(cardNumber: "4").progressStates)
        probe.telemetry.cardFormInput(owner: owner, states: GopayCardFormData(cardNumber: "44").progressStates)
        probe.telemetry.cardFormUnmounted(owner: owner)

        let events = await probe.settledEvents(4)
        #expect(names(events) == ["PAYMENT_CARD.ready", "PAYMENT_CARD.started", "PAYMENT_CARD.unmount", "PAYMENT_CARD.interaction"])
        let summary = try #require(steps(events).last)
        #expect(summary["return_value"] as? String == "unmount: not completed")
        #expect((summary["params"] as? String)?.contains(#""progress_at_end":"pan:partial,expiry:empty,cvv:empty""#) == true)
    }

    /// Typing through the fields one after another raises nothing; a field left half done does,
    /// once, and an edit that fixes it is not news.
    @Test func raisesAnErrorForAFieldLeftHalfDoneButNotForTypingThrough() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        let telemetry = probe.telemetry
        telemetry.cardFormReady(owner: owner)
        var data = GopayCardFormData()
        for digit in card.cardNumber {
            data.cardNumber.append(digit)
            telemetry.cardFormInput(owner: owner, states: data.progressStates)
        }
        telemetry.cardFormFieldLeft(owner: owner, field: .pan, edited: true)
        await nextFrame()
        data.expirationMonth = "1"
        telemetry.cardFormInput(owner: owner, states: data.progressStates)
        telemetry.cardFormFieldLeft(owner: owner, field: .expiry, edited: true)
        telemetry.cardFormFieldLeft(owner: owner, field: .expiry, edited: true)
        await nextFrame()
        data.expirationMonth = "12"
        data.expirationYear = "28"
        telemetry.cardFormInput(owner: owner, states: data.progressStates)
        // Never edited: leaving it says nothing.
        telemetry.cardFormFieldLeft(owner: owner, field: .cvv, edited: false)
        await nextFrame()
        telemetry.cardFormUnmounted(owner: owner)

        let events = await probe.settledEvents(5)
        #expect(names(events) == [
            "PAYMENT_CARD.ready", "PAYMENT_CARD.started", "PAYMENT_CARD.field-errors",
            "PAYMENT_CARD.unmount", "PAYMENT_CARD.interaction",
        ])
        #expect(steps(events)[2]["params"] as? String == #"{"count":1,"errors":"expiry:pattern","raised":"expiry:pattern","trigger":"blur"}"#)
    }

    /// A form leaving the screen resigns its field in the same frame: that blur is not the
    /// customer leaving a field half done, and it is not reported.
    @Test func dropsABlurInTheFrameTheFormLeaves() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        probe.telemetry.cardFormReady(owner: owner)
        probe.telemetry.cardFormInput(owner: owner, states: GopayCardFormData(cardNumber: "4").progressStates)
        await MainActor.run {
            probe.telemetry.cardFormFieldLeft(owner: owner, field: .pan, edited: true)
            probe.telemetry.cardFormUnmounted(owner: owner)
        }
        await nextFrame()

        let events = await probe.settledEvents(4)
        #expect(names(events) == ["PAYMENT_CARD.ready", "PAYMENT_CARD.started", "PAYMENT_CARD.unmount", "PAYMENT_CARD.interaction"])
        #expect((summaries(events).first?["params"] as? String)?.contains(#""errors_raised":0"#) == true)
    }

    /// A screen capture starting with the focus in a half-typed field: the form drops the focus
    /// itself while it refuses input, and that is not the customer leaving the field.
    @Test func doesNotReportTheBlurOfAScreenCapture() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        probe.telemetry.cardFormReady(owner: owner)
        probe.telemetry.cardFormInput(owner: owner, states: GopayCardFormData(cardNumber: "4").progressStates)
        probe.telemetry.cardFormFieldLeft(owner: owner, field: .pan, edited: true, inputRefused: true)
        await nextFrame()
        probe.telemetry.cardFormUnmounted(owner: owner)

        let events = await probe.settledEvents(4)
        #expect(names(events) == ["PAYMENT_CARD.ready", "PAYMENT_CARD.started", "PAYMENT_CARD.unmount", "PAYMENT_CARD.interaction"])
        #expect((summaries(events).first?["params"] as? String)?.contains(#""errors_raised":0"#) == true)
    }

    /// A blur taken when the field's window is no longer the key one, or the app is no longer
    /// active, is the screen going away, not the customer leaving the field; with the window still
    /// key it is reported as before.
    @Test(arguments: [false, true])
    func reportsABlurOnlyWhileTheFieldIsOnTheActiveScreen(isKey: Bool) async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        let asked = Counter()
        probe.telemetry.cardFormReady(owner: owner)
        probe.telemetry.cardFormInput(owner: owner, states: GopayCardFormData(cardNumber: "4").progressStates)
        probe.telemetry.cardFormFieldLeft(owner: owner, field: .pan, edited: true) {
            _ = asked.increment()
            return isKey
        }
        await nextFrame()
        probe.telemetry.cardFormUnmounted(owner: owner)

        let events = await probe.settledEvents(isKey ? 5 : 4)
        #expect(asked.increment() == 2, "asked once, when the blur was taken")
        let blurs = steps(events).filter { $0["function_name"] as? String == "PAYMENT_CARD.field-errors" }
        if isKey {
            #expect(blurs.compactMap { $0["params"] as? String } == [#"{"count":1,"errors":"pan:pattern","raised":"pan:pattern","trigger":"blur"}"#])
        } else {
            #expect(blurs.isEmpty)
            #expect((summaries(events).first?["params"] as? String)?.contains(#""errors_raised":0"#) == true)
        }
    }

    /// The errors standing after a submit include the fields still empty, as a form that shows
    /// them after a submit does, until one of them goes wrong in a new way.
    @Test func keepsEveryFieldJudgedAfterASubmitUntilTheFormIsEmptied() async throws {
        let probe = TelemetryProbe()
        let owner = NSObject()
        let telemetry = probe.telemetry
        telemetry.cardFormReady(owner: owner)
        telemetry.cardFormInput(owner: owner, states: GopayCardFormData(cardNumber: "4").progressStates)
        telemetry.cardFormSubmitRequested(owner: owner)
        // Emptying the number after the submit raises its "required".
        telemetry.cardFormInput(owner: owner, states: .untouched)
        telemetry.cardFormCleared(owner: owner)
        // After the host emptied the form, only what is left half done raises again.
        telemetry.cardFormInput(owner: owner, states: GopayCardFormData(cardNumber: "4").progressStates)

        let events = await probe.settledEvents(5)
        let errors = steps(events).filter { $0["function_name"] as? String == "PAYMENT_CARD.field-errors" }
        #expect(errors.compactMap { $0["params"] as? String } == [
            #"{"count":3,"errors":"pan:pattern,expiry:required,cvv:required","raised":"pan:pattern,expiry:required,cvv:required","trigger":"submit"}"#,
            #"{"count":3,"errors":"pan:required,expiry:required,cvv:required","raised":"pan:required","trigger":"input"}"#,
        ])
    }

    @Test func endsTheVisitWithAFailedEncryptionUntilTheCustomerTypesAgain() async throws {
        let probe = TelemetryProbe()
        let first = NSObject(), second = NSObject()
        for owner in [first, second] {
            probe.telemetry.cardFormReady(owner: owner)
            probe.telemetry.cardFormInput(owner: owner, states: card.progressStates)
            probe.telemetry.cardFormSubmitRequested(owner: owner)
            probe.telemetry.cardFormEncryptFailed(owner: owner)
        }
        probe.telemetry.cardFormInput(owner: second, states: GopayCardFormData(cardNumber: "4").progressStates)
        probe.telemetry.cardFormUnmounted(owner: first)
        probe.telemetry.cardFormUnmounted(owner: second)

        let ends = summaries(await probe.settledEvents(14))
        #expect(ends.compactMap { $0["return_value"] as? String } == ["encrypt-error: completed", "unmount: completed"])
    }

    /// One summary per visit: a second unmount, as SwiftUI can deliver, has nothing left to sum
    /// up, and a form that never became ready has no visit at all.
    @Test func summarisesOnceAndOnlyAFormThatBecameReady() async {
        let probe = TelemetryProbe()
        let owner = NSObject(), never = NSObject()
        probe.telemetry.cardFormReady(owner: owner)
        probe.telemetry.cardFormUnmounted(owner: owner)
        probe.telemetry.cardFormUnmounted(owner: owner)
        probe.telemetry.cardFormInput(owner: never, states: card.progressStates)
        probe.telemetry.cardFormSubmitRequested(owner: never)
        probe.telemetry.cardFormUnmounted(owner: never)

        let events = await probe.settledEvents(5)
        #expect(names(events) == [
            "PAYMENT_CARD.ready", "PAYMENT_CARD.unmount", "PAYMENT_CARD.interaction",
            "PAYMENT_CARD.unmount", "PAYMENT_CARD.unmount",
        ])
    }

    /// Typing errors spend their own 30; the errors of a submit and the other steps go on, and so
    /// does everything outside the card form.
    @Test func keepsTheCardFormBudgetsApart() async {
        let probe = TelemetryProbe()
        let owner = NSObject()
        let telemetry = probe.telemetry
        telemetry.cardFormReady(owner: owner)
        telemetry.cardFormInput(owner: owner, states: GopayCardFormData(cardNumber: "4").progressStates)
        telemetry.cardFormFieldLeft(owner: owner, field: .pan, edited: true)
        await nextFrame()
        // Every round raises a new error: emptied, then half done again.
        for round in 0..<40 {
            let current = round.isMultiple(of: 2) ? GopayCardFormData() : GopayCardFormData(cardNumber: "4")
            telemetry.cardFormInput(owner: owner, states: current.progressStates)
        }
        telemetry.cardFormSubmitRequested(owner: owner)
        telemetry.sessionStarted(paymentId: "1")
        telemetry.cardFormUnmounted(owner: owner)

        let events = await probe.settledEvents(37)
        let errors = events.filter { $0["function_name"] as? String == "PAYMENT_CARD.field-errors" }
        #expect(errors.filter { ($0["params"] as? String)?.contains(#""trigger":"submit""#) != true }.count == 30)
        #expect(errors.filter { ($0["params"] as? String)?.contains(#""trigger":"submit""#) == true }.count == 1)
        #expect(names(events).filter { $0 != "PAYMENT_CARD.field-errors" } == [
            "PAYMENT_CARD.ready", "PAYMENT_CARD.started", "PAYMENT_CARD.submit-request",
            "PAYMENT_CARD.unmount", "PAYMENT_CARD.interaction",
        ])
        #expect(events.contains { $0["navigation_type"] as? String == "navigate" })
    }

    @Test func capsTheCardFormStepsAt60() async {
        let probe = TelemetryProbe()
        let owner = NSObject()
        probe.telemetry.cardFormReady(owner: owner)
        for _ in 0..<35 {
            probe.telemetry.cardFormSubmitRequested(owner: owner)
        }
        probe.telemetry.cardFormUnmounted(owner: owner)

        let events = await probe.settledEvents(63)
        #expect(names(events).filter { $0 == "PAYMENT_CARD.submit-request" || $0 == "PAYMENT_CARD.field-errors" }.count == 60)
        #expect(names(events).suffix(2) == ["PAYMENT_CARD.unmount", "PAYMENT_CARD.interaction"])
    }

    /// The whole of a payment typed into the form: nothing the customer typed, nor its length or
    /// digit count, is in any step.
    @Test func neverSendsAValueALengthOrADigitCount() async {
        let probe = TelemetryProbe()
        let owner = NSObject()
        let telemetry = probe.telemetry
        telemetry.cardFormReady(owner: owner)
        var data = GopayCardFormData()
        for digit in card.cardNumber {
            data.cardNumber.append(digit)
            telemetry.cardFormInput(owner: owner, states: data.progressStates)
        }
        telemetry.cardFormFieldLeft(owner: owner, field: .pan, edited: true)
        data.expirationMonth = "1"
        telemetry.cardFormInput(owner: owner, states: data.progressStates)
        telemetry.cardFormFieldLeft(owner: owner, field: .expiry, edited: true)
        await nextFrame()
        telemetry.cardFormSubmitRequested(owner: owner)
        data.expirationMonth = "12"; data.expirationYear = "28"; data.cvv = "123"
        telemetry.cardFormInput(owner: owner, states: data.progressStates)
        telemetry.cardFormSubmitRequested(owner: owner)
        telemetry.cardFormSubmitted(owner: owner)
        telemetry.cardFormUnmounted(owner: owner)

        let events = await probe.settledEvents(11)
        let sent = steps(events).map { step -> String in
            var params = ((step["params"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]) ?? [:]
            params = params.filter { !$0.key.hasSuffix("_ms") }
            let text = (try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return "\(step["function_name"] ?? "") \(text) \(step["return_value"] ?? "")"
        }.joined(separator: "\n")
        #expect(!sent.isEmpty)
        for needle in ["4444", "4448", "1228", "12/28", "123", "value", "length", "digit", "16", "15"] {
            #expect(!sent.contains(needle), "\(needle) in \(sent)")
        }
    }
}
