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
        /// Show a field's error as soon as it has been edited and holds non-empty, invalid content.
        case live
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
        cvvEdited: Bool
    ) {
        func message(edited: Bool, isEmpty: Bool, isValid: Bool, pattern: String) -> String? {
            switch mode {
            case .hidden:
                return nil
            case .live:
                // Live: never nag about an empty field, only about invalid content being typed.
                guard edited, !isEmpty, !isValid else { return nil }
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
            pattern: strings.panErrorPattern
        )

        let expirationIsEmpty = data.expirationMonth.isEmpty && data.expirationYear.isEmpty
        expiration = message(
            edited: expirationEdited,
            isEmpty: expirationIsEmpty,
            isValid: data.isExpirationValid,
            pattern: strings.expErrorPattern
        )

        cvv = message(
            edited: cvvEdited,
            isEmpty: data.cvv.isEmpty,
            isValid: data.isCvvValid,
            pattern: strings.cvvErrorPattern
        )
    }
}
