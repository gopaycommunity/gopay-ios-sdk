import SwiftUI
import UIKit
import Foundation
import Combine

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
    
    /// Returns true if the card number has 16 digits and passes the Luhn check, as on Android.
    var isCardNumberValid: Bool {
        Self.completesCardNumber(cardNumber.filter { $0.isNumber })
    }

    /// Whether the card number holds as many digits as it takes, 16, whatever the check says.
    var isCardNumberTypedOut: Bool { cardNumber.filter { $0.isNumber }.count == 16 }
    /// Whether the expiration holds its four digits, whatever the date says.
    var isExpirationTypedOut: Bool { expirationMonth.count == 2 && expirationYear.count == 2 }
    /// Whether the CVV holds its three digits.
    var isCvvTypedOut: Bool { cvv.count == 3 }

    /// Whether typing these digits finishes the card number, so the focus moves on to the
    /// expiration: 16 digits that pass the Luhn check, as on Android. A mistyped number keeps the
    /// focus where the user can fix it.
    static func completesCardNumber(_ digits: String) -> Bool {
        digits.count == 16 && passesLuhn(digits)
    }

    /// The Luhn (mod 10) check every payment card number carries in its last digit, so a mistyped
    /// number is caught in the form rather than by the gateway.
    static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard let digit = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
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

    /// True when no field holds anything: a form nobody has typed into, or one the SDK emptied.
    var isEmpty: Bool {
        cardNumber.isEmpty && expirationMonth.isEmpty && expirationYear.isEmpty && cvv.isEmpty
    }
}

/// Controls whether and when ``PaymentCardForm`` renders localized inline validation errors.
public enum PaymentCardFormValidationDisplay: Sendable {
    /// Do not render inline errors — display is host-driven (default). Read the localized strings
    /// via `GopaySDK.shared.currentLocaleStrings(...)` to show your own.
    case hidden
    /// Show a field's error once the user is done with it, not while it is being typed: when it
    /// holds as many digits as it takes and still fails (a mistyped card number, a past date),
    /// when the user leaves it with something in it, or once ``GopaySDK/submitCardForm(formId:)``
    /// has been called for the form. An empty field is never flagged in this mode; the
    /// "required" message is ``onSubmit``'s. The Android form follows the same rule.
    case live
    /// Show errors only while the form's `submitAttempted` flag is `true`. The SDK raises it
    /// itself when ``GopaySDK/submitCardForm(formId:)`` is called for this form, before the card
    /// is judged, so an empty or invalid card shows its errors on the submit without the host
    /// doing anything, and the form lowers it whenever it empties its fields, e.g. after a
    /// successful submit. Pass ``PaymentCardForm``'s `submitAttempted` binding to raise or lower
    /// it yourself, e.g. when your submit button is tapped before you call the SDK. The Android
    /// form has the same mode, `ON_SUBMIT`, and the same flag.
    case onSubmit

    /// The shape of 2.x, where the mode carried the flag. The flag is the form's own parameter
    /// now, the same on both platforms.
    @available(*, unavailable, message: "Use .onSubmit and pass the binding to PaymentCardForm as submitAttempted")
    public static func onSubmit(attempted: Binding<Bool>) -> PaymentCardFormValidationDisplay { .onSubmit }
}

/// The identity a ``PaymentCardForm`` registers its handlers under: an object with no state of its
/// own, so two forms under the same form ID stay distinguishable by reference.
typealias CardFormOwner = NSObject

/// Payment card form UI component.
///
/// This view provides a complete payment card form with card number, expiration, and CVV inputs.
/// The form can be customized using a theme.
///
/// The form manages card data internally and automatically syncs it to the SDK.
/// Card data is never exposed to your app code for security.
public struct PaymentCardForm: View {
    /// Theme for customizing the appearance.
    public var theme: PaymentCardFormTheme

    /// Localized strings used for the field labels and placeholders.
    public var localeStrings: GopayLocaleStrings

    /// Controls whether and when the form renders localized inline validation errors (from
    /// `localeStrings`) beneath each field. Defaults to ``PaymentCardFormValidationDisplay/hidden``,
    /// which keeps error display host-driven.
    public var validation: PaymentCardFormValidationDisplay

    /// Binding the form writes its current validity into, for driving a submit button.
    ///
    /// The form fills it on appear and on every edit, and sets it to `false` when it leaves the
    /// screen. Start it at `false`: a form nobody has typed into is not valid.
    @Binding public var isValid: Bool

    /// The host's flag for the ``PaymentCardFormValidationDisplay/onSubmit`` and
    /// ``PaymentCardFormValidationDisplay/live`` modes, when it passed one: whether a submit was
    /// attempted since the fields were last emptied. `nil` leaves the flag to the form.
    private let hostSubmitAttempted: Binding<Bool>?
    
    /// Unique identifier for this form instance.
    /// Use this ID to submit a specific form when multiple forms are present.
    public var formId: String { explicitFormId ?? autoFormId }
    /// Explicit ID passed by the host, if any.
    private let explicitFormId: String?
    /// Stable auto-generated fallback ID. `@State` so it survives the re-inits SwiftUI performs
    /// on every parent re-render — a plain `let` would mint a fresh UUID each time, scattering
    /// card data across orphaned storage keys that no cleanup would ever reach.
    @State private var autoFormId = UUID().uuidString
    /// The token this form registers its handlers under, one object for the form's whole life,
    /// so the SDK can tell two forms under the same ID apart (see
    /// ``GopaySDK/unregisterCardFormReset(formId:owner:wipesFields:)``).
    @State private var owner = CardFormOwner()
    /// The ID the form is registered under while it is on screen, `nil` while it is not. Kept to
    /// notice the host handing the form another ID, e.g. one per payment.
    @State private var registeredFormId: String?

    /// Whether the card number and the expiration offer the system's saved-card autofill.
    ///
    /// Off by default: the fields then announce no content type, so iOS does not offer a saved card
    /// for them. On, the card number and the expiration declare themselves as card fields (the
    /// expiration from iOS 17). The CVV never takes part.
    public var allowsAutofill: Bool
    
    /// Internal state for card form data (never exposed).
    @State private var data: GopayCardFormData
    
    /// Read so the theme's fonts rescale when the user changes the Dynamic Type size.
    @Environment(\.sizeCategory) private var sizeCategory

    /// Whether the form covers itself in the app switcher and during a screen recording.
    @Environment(\.gopayCardFormCaptureProtection) private var captureProtection
    /// What the form currently covers itself for (see ``CardFormPrivacyCover``).
    @State private var privacyCover = CardFormPrivacyCover()

    /// Height of the tallest label in the expiration + CVV row. The row measures both labels and
    /// hands the taller one back down, so a label that wraps in one column does not drop that
    /// column's input below its neighbour's.
    @State private var rowLabelHeight: CGFloat = 0

    /// The fields, for the one holding the keyboard.
    private enum FocusedField { case cardNumber, expiration, cvv }

    /// The field holding the keyboard as the form knows it, `nil` for none. One value for the
    /// three fields, so a field giving the focus up can tell whether another one takes it.
    @State private var focusedField: FocusedField?

    // Tracks whether a field has been edited yet, so errors don't show on a pristine form.
    @State private var cardNumberEdited: Bool = false
    @State private var expirationEdited: Bool = false
    @State private var cvvEdited: Bool = false

    // Tracks whether the user has left a field they typed into, which is when the `.live` mode
    // starts flagging it; stays until the form is emptied.
    @State private var cardNumberWasLeft: Bool = false
    @State private var expirationWasLeft: Bool = false
    @State private var cvvWasLeft: Bool = false

    /// Whether a submit ran for this form since its fields were last emptied, kept here when the
    /// host passed no `submitAttempted` binding. See ``submitAttempted``.
    @State private var ownSubmitAttempted: Bool = false

    /// Whether a submit was attempted since the fields were last emptied: the host's binding when
    /// it passed one, the form's own state otherwise. `.onSubmit` shows every invalid field while
    /// it is `true`, `.live` flags every edited field.
    private var submitAttempted: Bool {
        get { hostSubmitAttempted?.wrappedValue ?? ownSubmitAttempted }
        nonmutating set {
            if let hostSubmitAttempted {
                if hostSubmitAttempted.wrappedValue != newValue { hostSubmitAttempted.wrappedValue = newValue }
            } else {
                ownSubmitAttempted = newValue
            }
        }
    }

    /// Creates a payment card form.
    ///
    /// Field labels and placeholders are localized. By default they follow the SDK-wide locale
    /// (`GopayConfig.locale`), then the device language, falling back to Czech. Pass `locale`
    /// to override per form, or `localeStrings` to supply strings directly.
    /// - Parameters:
    ///   - theme: Theme for customizing the appearance (default: `PaymentCardFormTheme()`).
    ///   - locale: Locale code (e.g. `"cs"`, `"de"`) for the field labels. `nil` uses the SDK
    ///             default. Ignored when `localeStrings` is supplied.
    ///   - localeStrings: Explicit locale strings to use, bypassing `locale` resolution.
    ///   - validation: When/whether to render localized inline validation errors
    ///                 (default: ``PaymentCardFormValidationDisplay/hidden``).
    ///   - submitAttempted: The flag of the `.onSubmit` and `.live` modes: whether a submit was
    ///              attempted since the fields were last emptied. The SDK raises it on
    ///              ``GopaySDK/submitCardForm(formId:)`` and the form lowers it when it empties
    ///              its fields; pass a binding to raise or lower it yourself as well. `nil`
    ///              (default) leaves the flag to the form. The Android form takes the same flag
    ///              as `submitAttempted` and `onSubmitAttemptedChange`.
    ///   - isValid: Binding the form writes its validity into, filled from the first render
    ///              onwards. Omit it if you do not need the state; the default binding discards
    ///              the writes.
    ///   - formId: Optional unique identifier for this form. If not provided, a UUID will be generated.
    ///   - allowsAutofill: Offer the system's saved-card autofill on the card number and the
    ///                     expiration (default: `false`). The CVV never takes part.
    public init(
        theme: PaymentCardFormTheme = PaymentCardFormTheme(),
        locale: String? = nil,
        localeStrings: GopayLocaleStrings? = nil,
        validation: PaymentCardFormValidationDisplay = .hidden,
        submitAttempted: Binding<Bool>? = nil,
        isValid: Binding<Bool> = .constant(false),
        formId: String? = nil,
        allowsAutofill: Bool = false
    ) {
        self.theme = theme
        self.localeStrings = localeStrings ?? GopayLocales.resolve(locale)
        self.validation = validation
        self.hostSubmitAttempted = submitAttempted
        self._isValid = isValid
        self.explicitFormId = formId
        self.allowsAutofill = allowsAutofill
        self._data = State(initialValue: GopayCardFormData())
    }

    // MARK: - Autofill

    /// What the card number announces to the system: nothing unless the host opted in with
    /// ``allowsAutofill``.
    private var cardNumberContentType: UITextContentType? {
        allowsAutofill ? .creditCardNumber : nil
    }

    /// What the expiration announces to the system. The content type only exists from iOS 17.
    private var expirationContentType: UITextContentType? {
        if allowsAutofill, #available(iOS 17.0, *) {
            return .creditCardExpiration
        }
        return nil
    }

    // MARK: - Inline validation error helpers

    /// The localized errors currently displayed under each field (see ``GopayCardFormErrors``).
    private var errors: GopayCardFormErrors {
        let mode: GopayCardFormErrors.Mode
        switch validation {
        case .hidden: mode = .hidden
        case .live: mode = .live(submitAttempted: submitAttempted)
        case .onSubmit: mode = .onSubmit(attempted: submitAttempted)
        }
        return GopayCardFormErrors(
            data: data,
            strings: localeStrings,
            mode: mode,
            cardNumberEdited: cardNumberEdited,
            expirationEdited: expirationEdited,
            cvvEdited: cvvEdited,
            cardNumberWasLeft: cardNumberWasLeft,
            expirationWasLeft: expirationWasLeft,
            cvvWasLeft: cvvWasLeft
        )
    }

    // MARK: - Themed building blocks

    /// Field label styled with the theme's label typography. Renders nothing when the theme hides
    /// the labels; the field then announces the text to VoiceOver instead.
    @ViewBuilder
    private func fieldLabel(_ text: String, sharesRowHeight: Bool) -> some View {
        if !theme.labelHidden {
            labelText(text)
                .font(theme.labelFont(for: sizeCategory))
                .foregroundColor(theme.labelColor)
                .lineSpacing(labelExtraLineSpacing)
                // Take the height the wrapped text needs. Without this a narrow column at the
                // largest text sizes truncates the label with an ellipsis instead of wrapping it,
                // which loses the word that says which field this is.
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: theme.labelLineHeight.map { theme.scaledCaptionLength($0, for: sizeCategory) })
                // Measured inside the shared reserve below, so what the row sees is the height this
                // label needs on its own. Measuring the reserved frame instead would feed its own
                // output back in, and the row could then only ever grow.
                .background(rowLabelHeightReader(active: sharesRowHeight))
                .frame(
                    minHeight: sharesRowHeight ? rowLabelHeight : nil,
                    alignment: .topLeading
                )
        }
    }

    /// Reports a label's own height to the row, for the columns that share one.
    @ViewBuilder
    private func rowLabelHeightReader(active: Bool) -> some View {
        if active {
            GeometryReader { proxy in
                Color.clear.preference(key: RowLabelHeightKey.self, value: proxy.size.height)
            }
        }
    }

    /// The label string with the theme's casing and letter spacing applied.
    private func labelText(_ text: String) -> Text {
        // Uppercased against the current locale, so Turkish keeps its dotted capital I.
        let label = Text(theme.labelUppercase ? text.uppercased(with: .current) : text)
        if #available(iOS 16.0, *), let letterSpacing = theme.labelLetterSpacing {
            return label.tracking(letterSpacing)
        }
        return label
    }

    /// How much a themed label line height adds on top of the font's own metrics.
    private var labelExtraLineSpacing: CGFloat {
        guard let lineHeight = theme.labelLineHeight else { return 0 }
        let scaled = theme.scaledCaptionLength(lineHeight, for: sizeCategory)
        return max(0, scaled - theme.labelUIFont(for: sizeCategory).lineHeight)
    }

    /// The name a field announces to VoiceOver when the theme draws no visible label.
    private func hiddenLabel(_ text: String) -> String? {
        theme.labelHidden ? text : nil
    }

    /// The slot below an input. It holds the inline error and, when the theme reserves height for
    /// it, keeps that height even while there is no message, so the layout does not jump.
    @ViewBuilder
    private func errorSlot(_ message: String?) -> some View {
        if theme.rendersErrorSlot(for: message) {
            Group {
                if let message = message {
                    Text(message)
                        .font(theme.errorFont(for: sizeCategory))
                        .foregroundColor(theme.errorTextColor)
                } else {
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            .frame(
                minHeight: theme.reservedErrorHeight(for: sizeCategory),
                alignment: .topLeading
            )
            .padding(.top, theme.resolvedErrorSpacing)
        }
    }

    /// One themed field: its label, the input in its border, and the error slot below.
    private func field<Content: View>(
        label: String,
        error: String?,
        sharesRowHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel(label, sharesRowHeight: sharesRowHeight)

            inputContainer(hasError: error != nil, content: content)
            .padding(.top, theme.labelHidden ? 0 : fieldSpacing)

            errorSlot(error)
        }
    }

    /// Wraps an input in the theme's padding, background and border.
    private func inputContainer<Content: View>(
        hasError: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let input = content()
            // The row decides how tall its fields are, so the three of them match whatever they
            // show; a field left to itself measures its own glyphs and a masked one comes out
            // shorter. A taller sibling column never stretches them either.
            .frame(height: rowInputHeight)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            // The themed minimum is the height of the whole field, padding included, which is how
            // Android reads the same key and how a browser sizes the box.
            .frame(minHeight: minimumInputHeight)

        // `.continuous` is the curve UIKit gives a rounded text field; a circular corner of the
        // same radius reads as a tighter, un-iOS box.
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return input
            .background(shape.fill(theme.inputBackgroundColor))
            // `strokeBorder` keeps the whole line inside the field, so the border needs no
            // measuring of its own and the field stays the size the layout gave it.
            .overlay(shape.strokeBorder(theme.borderColor(hasError: hasError), lineWidth: borderWidth))
            // Clipped last, so content too tall for a fixed height stays inside the field instead
            // of running into the label and the error line. The border is drawn inwards and so
            // survives the clip at its full width.
            .clipShape(shape)
    }

    /// Height the three inputs share, in points.
    ///
    /// Read from the themed font rather than from what any one field measures: a `UITextField`
    /// sizes itself to its content, and secure entry swaps digits for bullets, which measure
    /// lower, so leaving each field to itself steps the CVV out of its row. The font's line
    /// height rounded up, plus the point a text field keeps for the caret, is what the three
    /// fields took before.
    ///
    /// It lives here rather than on the theme because it is not a design decision: it is the row
    /// deciding how tall its cells are, the way a parent owns the layout of its children.
    private var rowInputHeight: CGFloat {
        ceil(theme.inputUIFont(for: sizeCategory).lineHeight) + 1
    }

    /// The minimum height of a whole field, padding included. Zero means the theme asked for
    /// none; a negative value from a theme set in code says nothing either and is read the same.
    private var minimumInputHeight: CGFloat {
        PaymentCardFormTheme.usableLength(theme.inputHeight ?? 0)
    }

    /// Padding inside a field. Both are public on the theme, so a theme built in code can carry a
    /// negative one, which would pull the text out of the field it belongs to.
    private var verticalPadding: CGFloat { PaymentCardFormTheme.usableLength(theme.inputPaddingVertical) }
    private var horizontalPadding: CGFloat { PaymentCardFormTheme.usableLength(theme.inputPaddingHorizontal) }

    /// The remaining themed lengths, read the same way: a negative or unusable one is no length.
    private var cornerRadius: CGFloat { PaymentCardFormTheme.usableLength(theme.inputBorderRadius) }
    private var groupSpacing: CGFloat { PaymentCardFormTheme.usableLength(theme.groupSpacing) }
    private var fieldSpacing: CGFloat { PaymentCardFormTheme.usableLength(theme.fieldSpacing) }
    private var formPadding: CGFloat { PaymentCardFormTheme.usableLength(theme.formPadding) }

    /// How tall a field ends up. The theme and the text size decide it between them, so nothing
    /// has to be measured to know it.
    private var resolvedInputHeight: CGFloat {
        max(minimumInputHeight, rowInputHeight + 2 * verticalPadding)
    }

    /// Width of the input border. A theme can only ask for a positive one; anything else draws
    /// nothing at all rather than a hairline the theme did not order.
    ///
    /// Capped at half the field, because `strokeBorder` insets the shape by half the width and a
    /// width past the field's height would inset it out of existence, losing the border entirely.
    private var borderWidth: CGFloat {
        min(PaymentCardFormTheme.usableLength(theme.inputBorderWidth), resolvedInputHeight / 2)
    }

    public var body: some View {
        VStack(spacing: groupSpacing) {
            // Card number input (first row)
            field(
                label: localeStrings.panLabel,
                error: errors.cardNumber
            ) {
                FormattedTextField(
                    placeholder: localeStrings.panPlaceholder,
                    digits: Binding(
                        get: { data.cardNumber },
                        set: { newDigits in
                            data.cardNumber = newDigits
                            cardNumberEdited = true
                            GopaySDK.shared.updateCardFormData(data, formId: formId, owner: owner)
                            updateValidationBinding()
                            reportInput()
                            // Not while a capture keeps the form refusing input: the focus
                            // would come back to a field under the cover.
                            if !refusesInput, GopayCardFormData.completesCardNumber(newDigits) {
                                focusedField = .expiration
                            }
                        }
                    ),
                    formatter: .cardNumber,
                    font: theme.inputUIFont(for: sizeCategory),
                    textColor: UIColor.from(theme.inputTextColor),
                    placeholderColor: theme.placeholderColor.map { UIColor.from($0, fallback: .placeholderText) },
                    accessibilityLabel: hiddenLabel(localeStrings.panLabel),
                    textContentType: cardNumberContentType,
                    refusesInput: refusesInput,
                    isFocused: focusedField == .cardNumber,
                    handsFocusToAnotherField: handsFocusToAnotherField(from: .cardNumber),
                    onFocusChange: { isFocused in
                        focus(.cardNumber, isFocused: isFocused)
                        if !isFocused { markLeft(&cardNumberWasLeft, edited: cardNumberEdited) }
                    },
                    onLeave: { isOnActiveScreen in
                        reportLeft(.pan, edited: cardNumberEdited, isOnActiveScreen: isOnActiveScreen)
                    }
                )
            }

            // Expiration and CVV inputs (second row)
            // Top-aligned so an error line under one field does not push or stretch its neighbour,
            // the way the web row behaves. Both columns reserve the taller label's height, so a
            // label that wraps keeps its input on the same line as its neighbour's.
            HStack(alignment: .top, spacing: groupSpacing) {
                // Expiration input (single field with automatic slash)
                field(
                    label: localeStrings.expLabel,
                    error: errors.expiration,
                    sharesRowHeight: true
                ) {
                    FormattedTextField(
                        placeholder: localeStrings.expPlaceholder,
                        digits: Binding(
                            get: { data.expirationMonth + data.expirationYear },
                            set: { newDigits in
                                data.expirationMonth = String(newDigits.prefix(2))
                                data.expirationYear = newDigits.count > 2 ? String(newDigits.dropFirst(2)) : ""
                                expirationEdited = true
                                GopaySDK.shared.updateCardFormData(data, formId: formId, owner: owner)
                                updateValidationBinding()
                                reportInput()
                                if !refusesInput, newDigits.count == 4 {
                                    focusedField = .cvv
                                }
                            }
                        ),
                        formatter: .expiration,
                        font: theme.inputUIFont(for: sizeCategory),
                        textColor: UIColor.from(theme.inputTextColor),
                        placeholderColor: theme.placeholderColor.map { UIColor.from($0, fallback: .placeholderText) },
                        accessibilityLabel: hiddenLabel(localeStrings.expLabel),
                        textContentType: expirationContentType,
                        refusesInput: refusesInput,
                        isFocused: focusedField == .expiration,
                        handsFocusToAnotherField: handsFocusToAnotherField(from: .expiration),
                        onFocusChange: { isFocused in
                            focus(.expiration, isFocused: isFocused)
                            if !isFocused { markLeft(&expirationWasLeft, edited: expirationEdited) }
                            if !isFocused, data.expirationMonth.count == 1,
                               let month = Int(data.expirationMonth), month >= 1 && month <= 12 {
                                // Pad a single-digit month with a leading zero once the field loses focus.
                                data.expirationMonth = String(format: "%02d", month)
                                GopaySDK.shared.updateCardFormData(data, formId: formId, owner: owner)
                                updateValidationBinding()
                            }
                        },
                        onLeave: { isOnActiveScreen in
                            reportLeft(.expiry, edited: expirationEdited, isOnActiveScreen: isOnActiveScreen)
                        }
                    )
                }
                .frame(maxWidth: .infinity)

                // CVV input
                field(
                    label: localeStrings.cvvLabel,
                    error: errors.cvv,
                    sharesRowHeight: true
                ) {
                    FormattedTextField(
                        placeholder: localeStrings.cvvPlaceholder,
                        digits: Binding(
                            get: { data.cvv },
                            set: { newDigits in
                                data.cvv = newDigits
                                cvvEdited = true
                                GopaySDK.shared.updateCardFormData(data, formId: formId, owner: owner)
                                updateValidationBinding()
                                reportInput()
                            }
                        ),
                        formatter: .cvv,
                        font: theme.inputUIFont(for: sizeCategory),
                        textColor: UIColor.from(theme.inputTextColor),
                        placeholderColor: theme.placeholderColor.map { UIColor.from($0, fallback: .placeholderText) },
                        accessibilityLabel: hiddenLabel(localeStrings.cvvLabel),
                        isSecure: true,
                        refusesInput: refusesInput,
                        isFocused: focusedField == .cvv,
                        handsFocusToAnotherField: handsFocusToAnotherField(from: .cvv),
                        onFocusChange: { isFocused in
                            focus(.cvv, isFocused: isFocused)
                            if !isFocused { markLeft(&cvvWasLeft, edited: cvvEdited) }
                        },
                        onLeave: { isOnActiveScreen in
                            reportLeft(.cvv, edited: cvvEdited, isOnActiveScreen: isOnActiveScreen)
                        }
                    )
                }
            }
            .onPreferenceChange(RowLabelHeightKey.self) { height in
                rowLabelHeight = height
            }
        }
        .padding(formPadding)
        .background(theme.formBackgroundColor)
        // Under the cover the fields are out of VoiceOver's reach too: it would otherwise read
        // their values, out loud or to the device the screen is mirrored to. `accessibility(hidden:)`
        // rather than `accessibilityHidden(_:)`, which needs iOS 14.
        .accessibility(hidden: isCovered)
        .overlay(privacyCoverView)
        .onReceive(CardFormCaptureProtection.coverChanges) { notification in
            privacyCover.receive(notification.name, screenIsCaptured: captureProtection.screenIsCaptured)
            endInputWhileCaptured()
        }
        .onAppear {
            privacyCover.refreshCapture(captureProtection.screenIsCaptured)
            endInputWhileCaptured()
            register(under: formId)
            GopaySDK.shared.telemetry.cardFormReady(owner: owner)
        }
        // A host may hand the form a new ID while it stays on screen, one per payment for
        // instance. `onAppear` does not run again for it, so the form moves its registration and
        // its card over itself, as the Android form does. `onChange` needs iOS 14.
        .onReceive(Just(formId)) { newId in
            guard let oldId = registeredFormId, oldId != newId else { return }
            GopaySDK.shared.unregisterCardFormReset(formId: oldId, owner: owner, wipesFields: false)
            register(under: newId)
        }
        .onDisappear {
            // Drop the card when the form leaves the screen, both the SDK's copy and the fields
            // themselves (PCI DSS 4.0.1, req. 3.3.1). `@State` outlives the view whenever the
            // hierarchy is only detached rather than destroyed, an inactive tab being the common
            // case, so leaving the digits in place would keep the card in memory indefinitely and
            // `onAppear` would sync them straight back into the SDK.
            //
            // The SDK drops this form's handlers and card, and runs the wipe, only while this form
            // is the one registered under its ID. When another form under the same ID has taken
            // over, as a navigation transition or a `key()` churn produces, that form's card stays
            // in the SDK and this one empties its own fields itself; it wrote nothing to the SDK
            // since it was replaced, so nothing of it is left there. `onDisappear` is on the main
            // thread, where the wipe runs synchronously, so the second call finds nothing to do
            // in the first case and does the whole job in the second.
            //
            // The telemetry goes first, so its summary describes the form as the customer left
            // it rather than as the wipe leaves it.
            GopaySDK.shared.telemetry.cardFormUnmounted(owner: owner)
            // The ID the form is registered under, which is `formId` unless a new one arrived and
            // the form left before it moved over.
            let leavingId = registeredFormId ?? formId
            // Read before the unregistration: the form that was registered leaves the bindings
            // behind it invalid and with no submit attempted; one that was replaced leaves both
            // to the other form, which shares them.
            let wasRegistered = GopaySDK.shared.owner(of: leavingId) === owner
            GopaySDK.shared.unregisterCardFormReset(formId: leavingId, owner: owner)
            registeredFormId = nil
            resetFields(keepsHostSubmitAttempted: !wasRegistered)
            if wasRegistered {
                isValid = false
            }
        }
    }
    
    /// The cover laid over the whole form while ``privacyCover`` asks for it. Opaque whatever the
    /// theme says: the form's background on top of the system background, so a themed form looks
    /// covered rather than replaced, and a form with the default clear background is covered too.
    /// It only hides the fields; the card stays where it is, and the cover goes once the app is
    /// active and the screen is no longer captured.
    @ViewBuilder
    private var privacyCoverView: some View {
        if isCovered {
            ZStack {
                Color(UIColor.systemBackground)
                theme.formBackgroundColor
                if privacyCover.showsNotice && !localeStrings.screenCaptureNotice.isEmpty {
                    Text(localeStrings.screenCaptureNotice)
                        .font(theme.labelFont(for: sizeCategory))
                        .foregroundColor(theme.labelColor)
                        .multilineTextAlignment(.center)
                        .padding(formPadding)
                }
            }
            .accessibilityElement(children: .combine)
            // The cover for the app switcher says nothing, so there is nothing to read.
            .accessibility(hidden: !privacyCover.showsNotice)
        }
    }

    /// Whether the cover is up.
    private var isCovered: Bool {
        captureProtection.isEnabled && privacyCover.isShown
    }

    /// Whether the fields refuse the keyboard: while the screen is captured. The cover hides the
    /// fields but not the keyboard, whose keys light up as they are tapped and would show the card
    /// in the recording, and a tap through the cover would otherwise focus a field nobody can see.
    /// The digits typed so far stay.
    private var refusesInput: Bool {
        captureProtection.isEnabled && privacyCover.isCaptured
    }

    /// Registers the form under `id` and hands the SDK its card. Registered first: the SDK takes
    /// a card only from the form registered under its ID. From then on the SDK empties these
    /// fields once it has turned them into a JWE, and tells the form when a submit is asked for.
    private func register(under id: String) {
        GopaySDK.shared.registerCardFormReset(
            { resetFields() }, submitAttempted: markSubmitAttempted, formId: id, owner: owner
        )
        registeredFormId = id
        GopaySDK.shared.updateCardFormData(data, formId: id, owner: owner)
        updateValidationBinding()
    }

    /// Drops the form's own focus once a capture starts, so the keyboard does not come straight
    /// back for the field that had it when the capture ends.
    private func endInputWhileCaptured() {
        guard refusesInput else { return }
        focusedField = nil
    }

    /// What a field reports about its focus. A field losing it clears the form's focus only while
    /// the form still thinks it is there: when the form has already handed the focus on to another
    /// field, UIKit resigning this one on that field's behalf must not undo the hand-over.
    private func focus(_ field: FocusedField, isFocused: Bool) {
        if isFocused {
            focusedField = field
        } else if focusedField == field {
            focusedField = nil
        }
    }

    /// Whether this form is the one registered under its ID.
    private var isRegistered: Bool {
        GopaySDK.shared.owner(of: formId) === owner
    }

    /// Notes a field losing the focus as left by the customer, for the `.live` mode: when they had
    /// typed into it, and not when the cover took the keyboard away during a capture.
    private func markLeft(_ wasLeft: inout Bool, edited: Bool) {
        if edited, !refusesInput {
            wasLeft = true
        }
    }

    /// Whether `field` is giving the focus up to another field of the form rather than to nobody.
    private func handsFocusToAnotherField(from field: FocusedField) -> Bool {
        focusedField != nil && focusedField != field
    }

    /// Returns the form to its pristine state, dropping the card the user typed.
    ///
    /// Runs on every path that clears the card, not only the one it was written for: after
    /// ``GopaySDK/submitCardForm(formId:)`` has encrypted it, so the PAN and CVV do not stay on
    /// screen once the JWE exists (PCI DSS 4.0.1, req. 3.3.1), and equally from the host's own
    /// ``GopaySDK/clearCardFormData(formId:)`` and from the form leaving the screen. Deliberately
    /// not called on a failed encryption: nothing has been authorized yet and the user should not
    /// have to retype the card after a network drop.
    ///
    /// The edited flags go with the digits, so the emptied fields come back pristine instead of
    /// lit up with validation errors, and so do the focus flags, which closes the keyboard if the
    /// user was still typing. For the same reason the `submitAttempted` flag, the host's binding
    /// included, is set back to `false`: left at `true`, every emptied field would show the
    /// "required" message in the ``PaymentCardFormValidationDisplay/onSubmit`` mode, also while
    /// the 3DS challenge runs.
    ///
    /// The SDK's own copy is already gone by this point and this does not re-sync an empty one,
    /// so a second submit fails with ``GopaySDKError/Code/validationCardFormEmpty`` until a new
    /// card is typed; the next
    /// `onAppear` or keystroke syncs the emptied fields back in, and an empty form is a form
    /// without a card, so the answer stays the same.
    ///
    /// - Parameter keepsHostSubmitAttempted: `true` only for a form leaving the screen after
    ///   another one under the same ID replaced it. Two forms under one ID share the host's
    ///   `submitAttempted` binding, and the one leaving would otherwise hide the errors of the
    ///   one that stays; it lowers its own flag and leaves the host's alone.
    private func resetFields(keepsHostSubmitAttempted: Bool = false) {
        data = GopayCardFormData()
        cardNumberEdited = false
        expirationEdited = false
        cvvEdited = false
        cardNumberWasLeft = false
        expirationWasLeft = false
        cvvWasLeft = false
        if keepsHostSubmitAttempted {
            ownSubmitAttempted = false
        } else {
            submitAttempted = false
        }
        focusedField = nil
        updateValidationBinding()
        GopaySDK.shared.telemetry.cardFormCleared(owner: owner)
    }

    // MARK: - Telemetry

    /// Tells the telemetry the states the fields are in after an edit: states only, never what
    /// the fields hold. Whatever the validation display, which only decides what the user sees.
    private func reportInput() {
        GopaySDK.shared.telemetry.cardFormInput(owner: owner, states: data.progressStates)
    }

    /// Tells the telemetry the user left `field`. It takes the blur a frame later, so a field
    /// resigned as the form leaves the screen is not reported, nor one whose screen is no longer
    /// the active one by then, and none while a screen capture keeps the form refusing input: the
    /// cover took the focus, the customer did not leave.
    private func reportLeft(_ field: CardFormProgress.Field, edited: Bool, isOnActiveScreen: @escaping () -> Bool) {
        GopaySDK.shared.telemetry.cardFormFieldLeft(
            owner: owner, field: field, edited: edited, inputRefused: refusesInput, isOnActiveScreen: isOnActiveScreen
        )
    }

    /// What ``GopaySDK/submitCardForm(formId:)`` tells the form: in the `.onSubmit` and `.live`
    /// modes the errors of every invalid field show from now on, until the fields are emptied
    /// again; `.live` still leaves an empty field alone. `.hidden` has nothing to reveal.
    private func markSubmitAttempted() {
        switch validation {
        case .onSubmit, .live:
            submitAttempted = true
        case .hidden:
            break
        }
    }

    /// Publishes the current validity to the host's binding, while this form is the one
    /// registered under its ID.
    ///
    /// The write does not depend on what the binding holds. When no binding was passed, the
    /// default is `.constant(false)` and the write is a no-op.
    ///
    /// A form another one under the same ID has replaced does not write: two forms under one ID
    /// share the host's binding, and the one leaving would otherwise overwrite the validity of
    /// the one that stays, as a navigation transition or a `key()` churn produces.
    private func updateValidationBinding() {
        guard isRegistered else { return }
        isValid = data.isValid
    }
}

// MARK: - Preview

#if DEBUG
struct PaymentCardForm_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            PaymentCardForm()
                .padding()
            
            // Custom theme example
            PaymentCardForm(
                theme: PaymentCardFormTheme(
                    labelColor: .blue,
                    inputTextColor: .blue,
                    inputBorderColor: .gray,
                    inputBackgroundColor: Color(.systemGray6),
                    inputBorderRadius: 12.0
                )
            )
            .padding()
        }
    }
}
#endif


// MARK: - Row layout

/// Carries the tallest label height in a field row up to the row that lays it out.
private struct RowLabelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
