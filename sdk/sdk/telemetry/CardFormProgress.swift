import Foundation

/// What the customer did with one visit of a card form, kept for telemetry only: the browser SDK's
/// form progress, ported one to one, with the same steps, params and messages. It mirrors the
/// browser's `form-progress.ts` line for line, branches a mobile form never reaches included (a
/// form that never reported its states), so the two can be read side by side. Mirrors the Android
/// `CardFormProgress`.
///
/// The form reports every change, each field moving between states, the errors growing and
/// shrinking as the customer types, validity flipping, and almost none of it is news. What is:
/// that they started, that a problem appeared, that they tried to pay, that the card became
/// complete. Those are the steps this reports; everything else only feeds the summary, which
/// answers the same questions in one event for when the steps did not all arrive.
///
/// Every input is a state, a code or a count. Nothing here sees a keystroke, a value, a length
/// or a number of digits, and ``vetted(_:message:)`` refuses anything else on the way out.
///
/// Not thread-safe: ``Telemetry`` holds one per visit of a form on screen and calls it under its
/// lock.
final class CardFormProgress {

    enum Field: String, CaseIterable {
        case pan, expiry, cvv
    }

    /// How far the customer has got with a field: nothing in it, something that is not yet a value
    /// the form accepts, or one it does. `partial` covers one digit and a whole number the form
    /// refuses alike.
    enum FieldState: String {
        case empty, partial, complete
    }

    /// `required` for a field left empty, `pattern` for anything else the form refuses.
    enum ErrorCode: String {
        case required, pattern
    }

    /// What ran the validation behind a set of field errors: the integrator's submit, typing in a
    /// field, or the customer leaving one.
    enum Trigger: String {
        case submit, input, blur
    }

    /// How a visit ended, as the summary reports it.
    enum End: String, CaseIterable {
        /// The form left the screen.
        case unmount
        /// The form left the screen after a submit that failed to encrypt the card, with nothing
        /// typed after it.
        case encryptError = "encrypt-error"
        /// A submit made the JWE. The SDK empties the form next, and typing into it again starts a
        /// new visit. The browser calls the same moment `encrypted`, where its form goes away.
        case submit
    }

    /// The overview each step sends as `return_value`, the column a person reads first.
    enum Message: String, CaseIterable {
        case startedWhole = "started with autofill or paste"
        case startedTyping = "started typing"
        case complete = "card complete"
        case newErrors = "new field errors"
        case submitErrors = "submit errors"
        case submitOk = "submit ok"
        case payPressed = "pay pressed"
        case payPressedIncomplete = "pay pressed with incomplete card"
    }

    /// How far a visit got, the second half of the summary's overview.
    enum Outcome: String, CaseIterable {
        case completed
        case notCompleted = "not completed"
        case neverStarted = "never started"
    }

    struct FieldError: Hashable {
        let field: Field
        let code: ErrorCode

        /// `pan:required`.
        var key: String { "\(field.rawValue):\(code.rawValue)" }
    }

    /// The state of all three fields.
    struct States: Equatable {
        var pan: FieldState
        var expiry: FieldState
        var cvv: FieldState

        /// The form before anyone touches it.
        static let untouched = States(pan: .empty, expiry: .empty, cvv: .empty)

        subscript(field: Field) -> FieldState {
            switch field {
            case .pan: return pan
            case .expiry: return expiry
            case .cvv: return cvv
            }
        }

        /// Every field holds a value the form accepts.
        var isValid: Bool { Field.allCases.allSatisfy { self[$0] == .complete } }

        /// The errors of the fields in `judged`: an empty one is `required`, a partial one is
        /// `pattern`, a complete one has none. In the form's order.
        func errors(judged: Set<Field>) -> [FieldError] {
            Field.allCases.compactMap { field in
                guard judged.contains(field) else { return nil }
                switch self[field] {
                case .empty: return FieldError(field: field, code: .required)
                case .partial: return FieldError(field: field, code: .pattern)
                case .complete: return nil
                }
            }
        }
    }

    /// What one step sends: the params for queries, and a short overview for people, which goes
    /// out as `return_value`.
    struct Report {
        let params: [String: Telemetry.Param]
        let message: String

        init(params: [String: Telemetry.Param], message: Message) {
            self.params = params
            self.message = message.rawValue
        }

        init(params: [String: Telemetry.Param], ended: End, outcome: Outcome) {
            self.params = params
            self.message = "\(ended.rawValue): \(outcome.rawValue)"
        }
    }

    private var lastStates: States?
    private var started = false
    private var startedMs: Int?
    private var filledAtOnce = false
    private var valid = false
    private var becameValid = false
    private var firstValidMs: Int?
    private var validityFlips = 0
    private var submitRequests = 0
    private var invalidSubmitRequests = 0
    private var invalidSubmits = 0
    private var errorsRaised = 0
    /// `field:code` of the errors standing; the form starts with none.
    private var shown: Set<String> = []
    private var codesSeen: Set<String> = []

    /// The states the last report gave, untouched before any.
    var states: States { lastStates ?? .untouched }

    /// `started`: the first report of a field that is no longer empty, once per form, with the
    /// states it found. `nil` for every other change: those are typing, and only the state at the
    /// end is kept.
    func progress(_ next: States, sinceReady: Int?) -> Report? {
        // Straight from empty to complete is a value that arrived whole: a paste or an autofill,
        // never digits typed one by one.
        let previous = lastStates ?? .untouched
        let jumped = Field.allCases.contains { previous[$0] == .empty && next[$0] == .complete }
        filledAtOnce = filledAtOnce || jumped
        lastStates = next
        if started || Field.allCases.allSatisfy({ next[$0] == .empty }) {
            return nil
        }
        started = true
        startedMs = sinceReady
        return Report(
            params: [
                "pan": .string(next.pan.rawValue),
                "expiry": .string(next.expiry.rawValue),
                "cvv": .string(next.cvv.rawValue),
                "filled_at_once": .bool(jumped),
            ],
            message: jumped ? .startedWhole : .startedTyping
        )
    }

    /// `completed`: the first time the whole card is valid, once per form. A card edited back to
    /// invalid and completed again is counted, not reported.
    func validity(_ nextValid: Bool, sinceReady: Int?) -> Report? {
        if valid && !nextValid {
            validityFlips += 1
        }
        valid = nextValid
        if !nextValid || becameValid {
            return nil
        }
        becameValid = true
        firstValidMs = sinceReady
        var params: [String: Telemetry.Param] = [:]
        if let sinceReady = sinceReady, let startedMs = startedMs {
            params["since_started_ms"] = .int(sinceReady - startedMs)
        }
        return Report(params: params, message: .complete)
    }

    /// `field-errors`, or `nil` when nothing went wrong that was not already standing. A submit is
    /// always reported, clean or not: it is an attempt to pay. Otherwise only an error that was not
    /// there before; errors going away while the customer fixes them are progress, not problems.
    func fieldErrors(_ errors: [FieldError], trigger: Trigger) -> Report? {
        let current = Set(errors.map(\.key))
        let raised = errors.map(\.key).filter { !shown.contains($0) }
        shown = current
        errorsRaised += raised.count
        codesSeen.formUnion(raised)
        if trigger == .submit && !errors.isEmpty {
            invalidSubmits += 1
        }
        if trigger != .submit && raised.isEmpty {
            return nil
        }
        var message = Message.newErrors
        if trigger == .submit {
            message = errors.isEmpty ? .submitOk : .submitErrors
        }
        let params: [String: Telemetry.Param] = [
            "errors": .string(errors.map(\.key).joined(separator: ",")),
            "raised": .string(raised.joined(separator: ",")),
            "count": .int(errors.count),
            "trigger": .string(trigger.rawValue),
        ]
        return Report(params: params, message: message)
    }

    /// `submit-request`: the integrator asked for a JWE, with the validity the card had then.
    func submitRequest() -> Report {
        submitRequests += 1
        if !valid {
            invalidSubmitRequests += 1
        }
        return Report(
            params: ["valid": .bool(valid)],
            message: valid ? .payPressed : .payPressedIncomplete
        )
    }

    /// The host emptied the fields mid-visit (``GopaySDK/clearCardFormData(formId:)``). The form is
    /// back where it started, with nothing standing, but nothing the customer did is undone: an
    /// emptied card is not a card edited back to invalid, so it is not counted as a flip. The
    /// browser's form has no such moment.
    func cleared() {
        lastStates = .untouched
        valid = false
        shown = []
    }

    /// `interaction`: the whole visit, ended the way `ended` says.
    func summary(_ ended: End) -> Report {
        var outcome = Outcome.neverStarted
        if becameValid {
            outcome = .completed
        } else if started || (lastStates == nil && errorsRaised > 0) {
            outcome = .notCompleted
        }
        var params: [String: Telemetry.Param] = [
            "filled_at_once": .bool(filledAtOnce),
            "became_valid": .bool(becameValid),
            "valid_at_end": .bool(valid),
            // Valid and then not any more: a card edited after it was complete, which a customer
            // who is unsure does.
            "validity_flips": .int(validityFlips),
            "submit_requests": .int(submitRequests),
            "invalid_submit_requests": .int(invalidSubmitRequests),
            // A submit with errors standing, whether or not the form shows them.
            "invalid_submits": .int(invalidSubmits),
            "errors_raised": .int(errorsRaised),
            "error_codes_seen": .string(codesSeen.sorted().joined(separator: ",")),
            "ended": .string(ended.rawValue),
        ]
        if let startedMs = startedMs {
            params["started_ms"] = .int(startedMs)
        }
        if let firstValidMs = firstValidMs {
            params["first_valid_ms"] = .int(firstValidMs)
        }
        if let states = lastStates {
            params["progress_at_end"] = .string(
                Field.allCases.map { "\($0.rawValue):\(states[$0].rawValue)" }.joined(separator: ",")
            )
        }
        return Report(params: params, ended: ended, outcome: outcome)
    }

    // MARK: - What may leave

    /// The params and message of a step as they may be sent, or `nil` when anything in them is
    /// not one of the protocol's states, codes, triggers, ends, booleans or counts. A step that
    /// does not pass is not sent at all: a value, a length or a digit count that found its way in
    /// takes the event down with it rather than riding along.
    static func vetted(_ params: [String: Telemetry.Param], message: String) -> [String: Telemetry.Param]? {
        guard allowedMessages.contains(message) else { return nil }
        for (key, value) in params {
            guard let kind = allowedParams[key], kind.admits(value) else { return nil }
        }
        return params
    }

    private enum ParamKind {
        case state, trigger, end, bool, count, duration, errorList, progressList

        func admits(_ value: Telemetry.Param) -> Bool {
            switch (self, value) {
            case (.bool, .bool):
                return true
            case (.count, .int(let number)):
                return number >= 0
            case (.duration, .int):
                // `since_started_ms` can come out negative only from clocks read out of order;
                // still a time, never a value of the card.
                return true
            case (.state, .string(let text)):
                return FieldState(rawValue: text) != nil
            case (.trigger, .string(let text)):
                return Trigger(rawValue: text) != nil
            case (.end, .string(let text)):
                return End(rawValue: text) != nil
            case (.errorList, .string(let text)):
                return ParamKind.isList(text) { pair in
                    Field(rawValue: pair.0) != nil && ErrorCode(rawValue: pair.1) != nil
                }
            case (.progressList, .string(let text)):
                // Always all three fields; an empty one is not a state of the form.
                return !text.isEmpty && ParamKind.isList(text) { pair in
                    Field(rawValue: pair.0) != nil && FieldState(rawValue: pair.1) != nil
                }
            default:
                return false
            }
        }

        /// `a:b,c:d`, or empty, with every pair passing `pairAdmitted`.
        static func isList(_ text: String, _ pairAdmitted: ((String, String)) -> Bool) -> Bool {
            guard !text.isEmpty else { return true }
            return text.split(separator: ",", omittingEmptySubsequences: false).allSatisfy { item in
                let halves = item.split(separator: ":", omittingEmptySubsequences: false)
                return halves.count == 2 && pairAdmitted((String(halves[0]), String(halves[1])))
            }
        }
    }

    private static let allowedParams: [String: ParamKind] = [
        "pan": .state, "expiry": .state, "cvv": .state,
        "filled_at_once": .bool, "valid": .bool, "became_valid": .bool, "valid_at_end": .bool,
        "since_started_ms": .duration, "started_ms": .duration, "first_valid_ms": .duration,
        "count": .count, "validity_flips": .count, "submit_requests": .count,
        "invalid_submit_requests": .count, "invalid_submits": .count, "errors_raised": .count,
        "errors": .errorList, "raised": .errorList, "error_codes_seen": .errorList,
        "trigger": .trigger, "progress_at_end": .progressList, "ended": .end,
    ]

    private static let allowedMessages: Set<String> = {
        let summaries = End.allCases.flatMap { end in
            Outcome.allCases.map { "\(end.rawValue): \($0.rawValue)" }
        }
        return Set(Message.allCases.map(\.rawValue)).union(summaries)
    }()
}

extension GopayCardFormData {

    /// The state of each field, by the form's own validators: what it accepts is `complete`.
    /// Only the states leave this property; the values it reads stay in the form.
    var progressStates: CardFormProgress.States {
        func state(isEmpty: Bool, isValid: Bool) -> CardFormProgress.FieldState {
            if isEmpty { return .empty }
            return isValid ? .complete : .partial
        }
        return CardFormProgress.States(
            pan: state(isEmpty: cardNumber.isEmpty, isValid: isCardNumberValid),
            expiry: state(isEmpty: expirationMonth.isEmpty && expirationYear.isEmpty, isValid: isExpirationValid),
            cvv: state(isEmpty: cvv.isEmpty, isValid: isCvvValid)
        )
    }
}
