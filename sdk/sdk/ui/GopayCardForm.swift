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
    public var formId: String { explicitFormId ?? autoFormId }
    /// Explicit ID passed by the host, if any.
    private let explicitFormId: String?
    /// Stable auto-generated fallback ID. `@State` so it survives the re-inits SwiftUI performs
    /// on every parent re-render — a plain `let` would mint a fresh UUID each time, scattering
    /// card data across orphaned storage keys that no cleanup would ever reach.
    @State private var autoFormId = UUID().uuidString
    
    /// Internal state for card form data (never exposed).
    @State private var data: GopayCardFormData
    
    /// Read so the theme's fonts rescale when the user changes the Dynamic Type size.
    @Environment(\.sizeCategory) private var sizeCategory

    /// Read so the underline focus gradient starts at the leading edge and a collapsed block hands
    /// the same edge to the same field in a right-to-left layout too.
    @Environment(\.layoutDirection) private var layoutDirection

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
        self.explicitFormId = formId
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

    // MARK: - Themed building blocks

    /// Field label styled with the theme's label typography. Renders nothing when the theme hides
    /// the labels; the field then announces the text to VoiceOver instead.
    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        if !theme.labelHidden {
            labelText(text)
                .font(theme.labelFont(for: sizeCategory))
                .foregroundColor(theme.labelColor)
                .lineSpacing(labelExtraLineSpacing)
                .frame(minHeight: theme.labelLineHeight.map { theme.scaledCaptionLength($0, for: sizeCategory) })
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
        isFocused: Bool,
        position: GopayCollapsedInputPosition,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel(label)

            inputContainer(
                isFocused: isFocused,
                hasError: error != nil,
                position: position,
                content: content
            )
            .padding(.top, theme.labelHidden ? 0 : theme.fieldSpacing)

            errorSlot(error)
        }
        .zIndex(elevation(isFocused: isFocused, hasError: error != nil))
    }

    /// A collapsed field in a state paints over the line it shares with a neighbour, so it has to
    /// draw after that neighbour. Outside a collapsed block nothing overlaps and the order is moot.
    ///
    /// Focus outranks an error, matching the border colour rule: on a tie SwiftUI paints in
    /// declaration order, which would let an invalid neighbour repaint the focused field's shared
    /// side in the error colour and break the "one closed box" the focused state promises.
    private func elevation(isFocused: Bool, hasError: Bool) -> Double {
        guard isCollapsed else { return 0 }
        if isFocused { return 2 }
        return hasError ? 1 : 0
    }

    /// Elevation of the expiration and CVV row against the card number above it, ranked the same
    /// way as a single cell.
    private var bottomRowElevation: Double {
        guard isCollapsed else { return 0 }
        if isExpirationFocused || isCvvFocused { return 2 }
        return errors.expiration != nil || errors.cvv != nil ? 1 : 0
    }

    /// Wraps an input in the theme's padding, background and border.
    private func inputContainer<Content: View>(
        isFocused: Bool,
        hasError: Bool,
        position: GopayCollapsedInputPosition,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let input = content()
            // The text field is flexible in both directions; keep its intrinsic height so a taller
            // sibling column (label or error text) never stretches it.
            .fixedSize(horizontal: false, vertical: true)
            // A fixed input height takes precedence over the vertical padding, as it does on the web.
            .padding(.vertical, theme.inputHeight == nil ? theme.inputPaddingVertical : 0)
            .padding(.horizontal, theme.inputPaddingHorizontal)
            .frame(height: theme.inputHeight)

        return Group {
            if isCollapsed {
                // A collapsed cell is not clipped: its background and its owned edges are shapes
                // resolved to physical sides, so a cell in a state can paint over the seam it shares
                // and its corner rounding cannot be mirrored a second time in a right-to-left layout.
                input
                    .background(collapsedBackground(position: position))
                    .overlay(collapsedBorder(isFocused: isFocused, hasError: hasError, position: position))
                    .overlay(seamCover(isFocused: isFocused, hasError: hasError, position: position))
            } else {
                input
                    .background(theme.inputBackgroundColor)
                    .overlay(inputBorder(isFocused: isFocused, hasError: hasError))
                    .clipShape(RoundedRectangle(cornerRadius: theme.inputBorderRadius))
            }
        }
        // Drawn after the corner clip so the ring can sit outside the border.
        .overlay(focusRing(isFocused: isFocused, position: position))
    }

    /// Whether the theme asks for one collapsed block of inputs. Only the boxed style can collapse;
    /// an underline has no shared edges to merge.
    private var isCollapsed: Bool {
        theme.inputBorderCollapse && theme.inputBorderStyle == .boxed
    }

    /// The sides and corners a collapsed field draws, for the current layout direction and for
    /// whichever neighbours it actually touches right now: an inline error under the card number
    /// opens the gap between the rows for as long as it is on screen.
    private func collapsedEdges(_ position: GopayCollapsedInputPosition) -> GopayCollapsedBorderEdges {
        gopayCollapsedBorderEdges(
            position: position,
            layoutDirection: layoutDirection,
            rowsTouch: theme.collapsedRowsTouch(cardNumberError: errors.cardNumber),
            bottomRowTouches: theme.collapsedBottomRowTouches
        )
    }

    /// The background of a collapsed input, rounded only on the corners that sit on the outside of
    /// the block.
    private func collapsedBackground(position: GopayCollapsedInputPosition) -> some View {
        GopayPartiallyRoundedRectangle(
            radius: theme.inputBorderRadius,
            corners: collapsedEdges(position).corners
        )
        .fill(theme.inputBackgroundColor)
        .physicalSides()
    }

    /// The edges a collapsed input owns, in the color of its state.
    @ViewBuilder
    private func collapsedBorder(
        isFocused: Bool,
        hasError: Bool,
        position: GopayCollapsedInputPosition
    ) -> some View {
        if theme.inputBorderWidth > 0 {
            GopayCollapsedInputBorder(
                radius: theme.inputBorderRadius,
                lineWidth: theme.inputBorderWidth,
                edges: collapsedEdges(position)
            )
            .stroked(theme.borderColor(isFocused: isFocused, hasError: hasError))
            .physicalSides()
        }
    }

    /// The neighbour's side of every line a focused or invalid collapsed input shares, repainted
    /// in the color of its state, so the seam shows one line the way the web recolors the single
    /// border of a cell in a state.
    @ViewBuilder
    private func seamCover(
        isFocused: Bool,
        hasError: Bool,
        position: GopayCollapsedInputPosition
    ) -> some View {
        if theme.inputBorderWidth > 0, isFocused || hasError {
            GopayCollapsedSeamCover(lineWidth: theme.inputBorderWidth, edges: collapsedEdges(position))
                .fill(theme.borderColor(isFocused: isFocused, hasError: hasError))
                .physicalSides()
        }
    }

    /// The border of a standalone input, in whichever style the theme asks for.
    @ViewBuilder
    private func inputBorder(isFocused: Bool, hasError: Bool) -> some View {
        switch theme.inputBorderStyle {
        case _ where theme.inputBorderWidth <= 0:
            EmptyView()
        case .boxed:
            // Inset by half the width: the stroke is centred on the path, and the container clips
            // to the same shape, so without this the outer half is cut and the line renders at
            // half the requested weight. Android and the web draw the whole line. The inset needs
            // the field's size, because past a point it has to be clamped, see
            // ``GopayCardFormTheme/boxedBorderInset(in:)``.
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: theme.inputBorderRadius)
                    .inset(by: theme.boxedBorderInset(in: proxy.size))
                    .stroke(
                        theme.borderColor(isFocused: isFocused, hasError: hasError),
                        lineWidth: theme.inputBorderWidth
                    )
            }
        case .underline:
            underline(isFocused: isFocused, hasError: hasError)
        }
    }

    /// The bottom line of an underlined input. It follows the rounded bottom corners the way a CSS
    /// `border-bottom` follows a `border-radius`. A focused field draws it as a gradient from
    /// `focusGradientStart` to `focusGradientEnd`; the web animates that gradient, mobile does not.
    private func underline(isFocused: Bool, hasError: Bool) -> some View {
        let line = GopayInputUnderline(radius: theme.inputBorderRadius, lineWidth: theme.inputBorderWidth)
        return Group {
            if isFocused {
                line.stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [theme.focusGradientStart, theme.focusGradientEnd]),
                        startPoint: underlineGradientStart,
                        endPoint: underlineGradientEnd
                    ),
                    lineWidth: theme.inputBorderWidth
                )
            } else {
                line.stroke(
                    theme.borderColor(isFocused: false, hasError: hasError),
                    lineWidth: theme.inputBorderWidth
                )
            }
        }
    }

    /// Where the focus gradient starts: the leading edge. A `UnitPoint` is a physical position that
    /// SwiftUI does not mirror, so a right-to-left layout has to start it on the right by hand.
    private var underlineGradientStart: UnitPoint {
        layoutDirection == .rightToLeft ? .trailing : .leading
    }

    private var underlineGradientEnd: UnitPoint {
        layoutDirection == .rightToLeft ? .leading : .trailing
    }

    /// The optional ring outside the border of a focused field. It is drawn as an overlay, so it
    /// never moves the surrounding layout. Inside a collapsed block it rounds only the corners the
    /// field itself rounds, so it follows the outline of the block.
    @ViewBuilder
    private func focusRing(isFocused: Bool, position: GopayCollapsedInputPosition) -> some View {
        if isFocused, let ring = theme.resolvedFocusRing {
            // The border is drawn inside the field now, so the ring only has to clear itself.
            let inset = ring.width / 2
            GopayPartiallyRoundedRectangle(
                radius: theme.inputBorderRadius + inset,
                corners: isCollapsed ? collapsedEdges(position).corners : .allCorners
            )
            .stroke(ring.color, lineWidth: ring.width)
            .padding(-inset)
            .physicalSides()
        }
    }

    public var body: some View {
        VStack(spacing: theme.groupSpacing) {
            // Card number input (first row)
            field(
                label: localeStrings.panLabel,
                error: errors.cardNumber,
                isFocused: isCardNumberFocused,
                position: .top
            ) {
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
                        font: theme.inputUIFont,
                        textColor: UIColor.from(theme.inputTextColor),
                        placeholderColor: theme.placeholderColor.map { UIColor.from($0, fallback: .gopayDefaultPlaceholder) },
                        letterSpacing: theme.inputLetterSpacing,
                        accessibilityLabel: hiddenLabel(localeStrings.panLabel),
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
            }

            // Expiration and CVV inputs (second row)
            // Top-aligned so an error line under one field does not push or stretch its neighbour,
            // the way the web row behaves.
            HStack(alignment: .top, spacing: theme.groupSpacing) {
                // Expiration input (single field with automatic slash)
                field(
                    label: localeStrings.expLabel,
                    error: errors.expiration,
                    isFocused: isExpirationFocused,
                    position: .bottomStart
                ) {
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
                            font: theme.inputUIFont,
                            textColor: UIColor.from(theme.inputTextColor),
                            placeholderColor: theme.placeholderColor.map { UIColor.from($0, fallback: .gopayDefaultPlaceholder) },
                            letterSpacing: theme.inputLetterSpacing,
                            accessibilityLabel: hiddenLabel(localeStrings.expLabel),
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
                }
                .frame(maxWidth: .infinity)

                // CVV input
                field(
                    label: localeStrings.cvvLabel,
                    error: errors.cvv,
                    isFocused: isCvvFocused,
                    position: .bottomEnd
                ) {
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
                            font: theme.inputUIFont,
                            textColor: UIColor.from(theme.inputTextColor),
                            placeholderColor: theme.placeholderColor.map { UIColor.from($0, fallback: .gopayDefaultPlaceholder) },
                            letterSpacing: theme.inputLetterSpacing,
                            accessibilityLabel: hiddenLabel(localeStrings.cvvLabel),
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
                }
            }
            // The row rises as a whole, so a field in a state also paints over the row above it.
            .zIndex(bottomRowElevation)
        }
        .padding(theme.formPadding)
        .background(theme.formBackgroundColor)
        .onAppear {
            // Initial sync when form appears
            GopaySDK.shared.updateCardFormData(data, formId: formId)
            // Update validation binding if provided
            updateValidationBinding()
        }
        .onDisappear {
            // Drop the SDK-held copy of the card data when the form leaves the screen;
            // `onAppear` re-syncs it if the form comes back (PCI DSS 4.0.1, req. 3.3.1).
            GopaySDK.shared.clearCardFormData(formId: formId)
        }
    }
    
    /// Updates the validation binding if provided.
    private func updateValidationBinding() {
        if isValid != nil {
            isValid = data.isValid
        }
    }
}

private extension View {
    /// Keeps a shape that is already resolved to physical sides from being mirrored again in a
    /// right-to-left layout, which SwiftUI does to shapes by default.
    func physicalSides() -> some View {
        environment(\.layoutDirection, .leftToRight)
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
                    labelColor: .blue,
                    inputTextColor: .blue,
                    inputBorderColor: .gray,
                    inputBackgroundColor: Color(.systemGray6),
                    inputBorderRadius: 12.0,
                    focusGradientStart: .blue
                )
            )
            .padding()
        }
    }
}
#endif

