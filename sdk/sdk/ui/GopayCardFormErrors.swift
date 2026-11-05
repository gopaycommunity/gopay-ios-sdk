import Foundation

/// Pure computation of which localized validation errors ``GopayCardForm`` should display.
///
/// Extracted from the view so the display rules are unit-testable. The messages come from the
/// resolved ``GopayLocaleStrings``; when and whether they appear is governed by ``Mode``.
internal struct GopayCardFormErrors: Equatable {

    /// Controls when inline errors are revealed.
    enum Mode: Equatable {
        /// Never show inline errors (host-driven display).
        case hidden
        /// Show a field's error once the user is done with it: it holds non-empty, invalid content
        /// and is typed out (as many digits as it takes), or the user has left it, or a submit ran
        /// since the form was last emptied. A field still being typed shows nothing, and an empty
        /// one never does. The Android `CardFormErrors` applies the same rule.
        case live(submitAttempted: Bool)
        /// Show errors only once `attempted` is `true` (e.g. after a submit tap). Empty required
        /// fields surface the "required" message; non-empty invalid fields surface the pattern one.
        case onSubmit(attempted: Bool)
    }

    /// Localized card-number error, or `nil` when nothing should be shown.
    let cardNumber: String?
    /// Localized expiration error, or `nil` when nothing should be shown.
    let expiration: String?
    /// Localized CVV error, or `nil` when nothing should be shown.
    let cvv: String?

    init(
        data: GopayCardFormData,
        strings: GopayLocaleStrings,
        mode: Mode,
        cardNumberEdited: Bool,
        expirationEdited: Bool,
        cvvEdited: Bool,
        cardNumberWasLeft: Bool,
        expirationWasLeft: Bool,
        cvvWasLeft: Bool
    ) {
        func message(
            edited: Bool, isEmpty: Bool, isValid: Bool, isTypedOut: Bool, left: Bool, pattern: String
        ) -> String? {
            switch mode {
            case .hidden:
                return nil
            case .live(let submitAttempted):
                // Live: never nag about an empty field, and not about one still being typed
                // either; only once it is typed out, left, or submitted.
                guard edited, !isEmpty, !isValid, isTypedOut || left || submitAttempted else { return nil }
                return pattern
            case .onSubmit(let attempted):
                guard attempted, !isValid else { return nil }
                return isEmpty ? strings.requiredErrorMessage : pattern
            }
        }

        cardNumber = message(
            edited: cardNumberEdited,
            isEmpty: data.cardNumber.isEmpty,
            isValid: data.isCardNumberValid,
            isTypedOut: data.isCardNumberTypedOut,
            left: cardNumberWasLeft,
            pattern: strings.panErrorPattern
        )

        let expirationIsEmpty = data.expirationMonth.isEmpty && data.expirationYear.isEmpty
        expiration = message(
            edited: expirationEdited,
            isEmpty: expirationIsEmpty,
            isValid: data.isExpirationValid,
            isTypedOut: data.isExpirationTypedOut,
            left: expirationWasLeft,
            pattern: strings.expErrorPattern
        )

        cvv = message(
            edited: cvvEdited,
            isEmpty: data.cvv.isEmpty,
            isValid: data.isCvvValid,
            isTypedOut: data.isCvvTypedOut,
            left: cvvWasLeft,
            pattern: strings.cvvErrorPattern
        )
    }
}
