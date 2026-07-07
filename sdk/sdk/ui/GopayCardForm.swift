import SwiftUI
import UIKit
import Foundation

/// Payment card form data model.
///
/// This struct holds the current values of the card form fields.
/// Internal use only - not exposed to developers for security.
internal struct GopayCardFormData {
    /// Card number (without formatting).
    var cardNumber: String
    /// Expiration month (MM format).
    var expirationMonth: String
    /// Expiration year (YY format).
    var expirationYear: String
    /// CVV code.
    var cvv: String
    
    /// Creates card form data.
    /// - Parameters:
    ///   - cardNumber: Card number (without formatting).
    ///   - expirationMonth: Expiration month (MM format).
    ///   - expirationYear: Expiration year (YY format).
    ///   - cvv: CVV code.
    init(
        cardNumber: String = "",
        expirationMonth: String = "",
        expirationYear: String = "",
        cvv: String = ""
    ) {
        self.cardNumber = cardNumber
        self.expirationMonth = expirationMonth
        self.expirationYear = expirationYear
        self.cvv = cvv
    }
    
    /// Returns true if all fields are valid.
    var isValid: Bool {
        return isCardNumberValid && isExpirationValid && isCvvValid
    }
    
    /// Returns true if the card number is valid (16 digits).
    var isCardNumberValid: Bool {
        let digits = cardNumber.filter { $0.isNumber }
        return digits.count == 16
    }
    
    /// Returns true if the expiration date is valid and in the future.
    var isExpirationValid: Bool {
        guard expirationMonth.count == 2,
              expirationYear.count == 2,
              let month = Int(expirationMonth),
              let year = Int(expirationYear),
              month >= 1 && month <= 12 else {
            return false
        }
        
        let calendar = Calendar.current
        let currentDate = Date()
        let currentYear = calendar.component(.year, from: currentDate)
        let currentMonth = calendar.component(.month, from: currentDate)
        
        // Convert YY to full year (00-99 maps to 2000-2099)
        let fullYear = 2000 + year
        
        // Check if expiration is in the future
        if fullYear > currentYear {
            return true
        } else if fullYear == currentYear {
            return month >= currentMonth
        }
        
        return false
    }
    
    /// Returns true if the CVV is valid (3 digits).
    var isCvvValid: Bool {
        return cvv.count == 3 && cvv.allSatisfy { $0.isNumber }
    }
}

/// Controls whether and when ``GopayCardForm`` renders localized inline validation errors.
public enum GopayCardFormValidationDisplay {
    /// Do not render inline errors — display is host-driven (default). Read the localized strings
    /// via `GopaySDK.shared.currentLocaleStrings(...)` to show your own.
    case hidden
    /// Show a field's error live, as soon as it holds non-empty, invalid content while typing.
    case live
    /// Show errors only while `attempted` is `true`. Flip it (e.g. when the user taps your submit
    /// button) to reveal errors for all invalid fields; set it back to `false` to hide them again.
    case onSubmit(attempted: Binding<Bool>)
}

/// Payment card form UI component.
///
/// This view provides a complete payment card form with card number, expiration, and CVV inputs.
/// The form can be customized using a theme.
///
/// The form manages card data internally and automatically syncs it to the SDK.
/// Card data is never exposed to your app code for security.
public struct GopayCardForm: View {
    /// Theme for customizing the appearance.
    public var theme: GopayCardFormTheme

    /// Localized strings used for the field labels and placeholders.
    public var localeStrings: GopayLocaleStrings

    /// Controls whether and when the form renders localized inline validation errors (from
    /// `localeStrings`) beneath each field. Defaults to ``GopayCardFormValidationDisplay/hidden``,
    /// which keeps error display host-driven.
    public var validation: GopayCardFormValidationDisplay

    /// Optional binding to track form validation state (for UI feedback).
    /// Set this if you want to enable/disable submit buttons based on form validity.
    @Binding public var isValid: Bool?
    
    /// Unique identifier for this form instance.
    /// Use this ID to submit a specific form when multiple forms are present.
    public let formId: String
    
    /// Internal state for card form data (never exposed).
    @State private var data: GopayCardFormData
    
    @State private var isCardNumberFocused: Bool = false
    @State private var isExpirationFocused: Bool = false
    @State private var isCvvFocused: Bool = false

    // Tracks whether a field has been edited yet, so errors don't show on a pristine form.
    @State private var cardNumberEdited: Bool = false
    @State private var expirationEdited: Bool = false
    @State private var cvvEdited: Bool = false

    /// Creates a payment card form.
    ///
    /// Field labels and placeholders are localized. By default they follow the SDK-wide locale
    /// (`GopaySDKConfig.locale`), then the device language, falling back to Czech. Pass `locale`
    /// to override per form, or `localeStrings` to supply strings directly.
    /// - Parameters:
    ///   - theme: Theme for customizing the appearance (default: `.standard`).
    ///   - locale: Locale code (e.g. `"cs"`, `"de"`) for the field labels. `nil` uses the SDK
    ///             default. Ignored when `localeStrings` is supplied.
    ///   - localeStrings: Explicit locale strings to use, bypassing `locale` resolution.
    ///   - validation: When/whether to render localized inline validation errors
    ///                 (default: ``GopayCardFormValidationDisplay/hidden``).
    ///   - isValid: Optional binding to track form validation state (default: `nil`).
    ///   - formId: Optional unique identifier for this form. If not provided, a UUID will be generated.
    public init(
        theme: GopayCardFormTheme = .standard,
        locale: String? = nil,
        localeStrings: GopayLocaleStrings? = nil,
        validation: GopayCardFormValidationDisplay = .hidden,
        isValid: Binding<Bool?> = .constant(nil),
        formId: String? = nil
    ) {
        self.theme = theme
        self.localeStrings = localeStrings ?? GopayLocales.resolve(locale)
        self.validation = validation
        self._isValid = isValid
        self.formId = formId ?? UUID().uuidString
        self._data = State(initialValue: GopayCardFormData())
    }

    // MARK: - Inline validation error helpers

    /// The localized errors currently displayed under each field (see ``GopayCardFormErrors``).
    private var errors: GopayCardFormErrors {
        let mode: GopayCardFormErrors.Mode
        switch validation {
        case .hidden: mode = .hidden
        case .live: mode = .live
        case .onSubmit(let attempted): mode = .onSubmit(attempted: attempted.wrappedValue)
        }
        return GopayCardFormErrors(
            data: data,
            strings: localeStrings,
            mode: mode,
            cardNumberEdited: cardNumberEdited,
            expirationEdited: expirationEdited,
            cvvEdited: cvvEdited
        )
    }

    /// Inline error label styled with the theme's error color.
    @ViewBuilder
    private func errorLabel(_ message: String?) -> some View {
        if let message = message {
            Text(message)
                .font(theme.labelFont)
                .foregroundColor(theme.errorColor)
        }
    }
    
    public var body: some View {
        VStack(spacing: theme.spacing) {
            // Card number input (first row)
            VStack(alignment: .leading, spacing: 4) {
                Text(localeStrings.panLabel)
                    .font(theme.labelFont)
                    .foregroundColor(theme.textColor)

                FormattedTextField(
                    placeholder: localeStrings.panPlaceholder,
                    digits: Binding(
                        get: { data.cardNumber },
                        set: { newDigits in
                            data.cardNumber = newDigits
                            cardNumberEdited = true
                            GopaySDK.shared.updateCardFormData(data, formId: formId)
                            updateValidationBinding()
                            if newDigits.count == 16 {
                                isCardNumberFocused = false
                                isExpirationFocused = true
                            }
                        }
                    ),
                    formatter: .cardNumber,
                    textColor: UIColor.from(theme.textColor),
                    textContentType: .creditCardNumber,
                    isFocused: isCardNumberFocused,
                    onFocusChange: { isFocused in
                        isCardNumberFocused = isFocused
                        if isFocused {
                            isExpirationFocused = false
                            isCvvFocused = false
                        }
                    }
                )
                .padding(theme.textFieldPadding)
                .background(theme.backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .stroke(
                            isCardNumberFocused ? theme.focusedBorderColor : theme.borderColor,
                            lineWidth: theme.borderWidth
                        )
                )
                .cornerRadius(theme.cornerRadius)

                errorLabel(errors.cardNumber)
            }

            // Expiration and CVV inputs (second row)
            HStack(spacing: theme.spacing) {
                // Expiration input (single field with automatic slash)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localeStrings.expLabel)
                        .font(theme.labelFont)
                        .foregroundColor(theme.textColor)

                    FormattedTextField(
                        placeholder: localeStrings.expPlaceholder,
                        digits: Binding(
                            get: { data.expirationMonth + data.expirationYear },
                            set: { newDigits in
                                data.expirationMonth = String(newDigits.prefix(2))
                                data.expirationYear = newDigits.count > 2 ? String(newDigits.dropFirst(2)) : ""
                                expirationEdited = true
                                GopaySDK.shared.updateCardFormData(data, formId: formId)
                                updateValidationBinding()
                                if newDigits.count == 4 {
                                    isExpirationFocused = false
                                    isCvvFocused = true
                                }
                            }
                        ),
                        formatter: .expiration,
                        textColor: UIColor.from(theme.textColor),
                        isFocused: isExpirationFocused,
                        onFocusChange: { isFocused in
                            isExpirationFocused = isFocused
                            if isFocused {
                                isCardNumberFocused = false
                                isCvvFocused = false
                            } else if data.expirationMonth.count == 1,
                                      let month = Int(data.expirationMonth), month >= 1 && month <= 12 {
                                // Pad a single-digit month with a leading zero once the field loses focus.
                                data.expirationMonth = String(format: "%02d", month)
                                GopaySDK.shared.updateCardFormData(data, formId: formId)
                                updateValidationBinding()
                            }
                        }
                    )
                    .padding(theme.textFieldPadding)
                    .background(theme.backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cornerRadius)
                            .stroke(
                                isExpirationFocused ? theme.focusedBorderColor : theme.borderColor,
                                lineWidth: theme.borderWidth
                            )
                    )
                    .cornerRadius(theme.cornerRadius)
                    .frame(maxWidth: .infinity)

                    errorLabel(errors.expiration)
                }

                // CVV input
                VStack(alignment: .leading, spacing: 4) {
                    Text(localeStrings.cvvLabel)
                        .font(theme.labelFont)
                        .foregroundColor(theme.textColor)

                    FormattedTextField(
                        placeholder: localeStrings.cvvPlaceholder,
                        digits: Binding(
                            get: { data.cvv },
                            set: { newDigits in
                                data.cvv = newDigits
                                cvvEdited = true
                                GopaySDK.shared.updateCardFormData(data, formId: formId)
                                updateValidationBinding()
                            }
                        ),
                        formatter: .cvv,
                        textColor: UIColor.from(theme.textColor),
                        isSecure: true,
                        isFocused: isCvvFocused,
                        onFocusChange: { isFocused in
                            isCvvFocused = isFocused
                            if isFocused {
                                isCardNumberFocused = false
                                isExpirationFocused = false
                            }
                        }
                    )
                    .padding(theme.textFieldPadding)
                    .background(theme.backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cornerRadius)
                            .stroke(
                                isCvvFocused ? theme.focusedBorderColor : theme.borderColor,
                                lineWidth: theme.borderWidth
                            )
                    )
                    .cornerRadius(theme.cornerRadius)

                    errorLabel(errors.cvv)
                }
            }
        }
        .onAppear {
            // Initial sync when form appears
            GopaySDK.shared.updateCardFormData(data, formId: formId)
            // Update validation binding if provided
            updateValidationBinding()
        }
    }
    
    /// Updates the validation binding if provided.
    private func updateValidationBinding() {
        if isValid != nil {
            isValid = data.isValid
        }
    }
}

// MARK: - Preview

#if DEBUG
struct GopayCardForm_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            GopayCardForm()
                .padding()
            
            // Custom theme example
            GopayCardForm(
                theme: GopayCardFormTheme(
                    textColor: .blue,
                    backgroundColor: Color(.systemGray6),
                    borderColor: .gray,
                    focusedBorderColor: .blue,
                    cornerRadius: 12.0
                )
            )
            .padding()
        }
    }
}
#endif

