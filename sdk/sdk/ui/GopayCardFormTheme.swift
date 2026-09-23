import SwiftUI
import UIKit

/// Border style of the inputs, named after the web `inputBorderStyle` key.
public enum GopayCardFormBorderStyle: String, Equatable {
    /// A border around the whole input.
    case boxed
    /// A bottom line only. **Not supported on iOS**, which has no native underlined text field and
    /// where the SDK draws nothing of its own: the value is accepted and the input is rendered as
    /// ``boxed``. Android renders it with the native Material indicator.
    case underline
}

/// Theme configuration for the payment card form.
///
/// The parameters are atomic and carry the names of the web card form theme (cc-v4), so a design
/// decided once reads the same on the web, on iOS and on Android.
///
/// The set is the part of the web theme a native field can carry: every parameter here is a
/// property of the text field itself or of the layout around it, and the SDK draws nothing of its
/// own. The web keys that only a custom-drawn form could honour are not part of this type; see the
/// parity table in the README.
///
/// Every parameter is optional and **an untouched form looks like an iOS form**, not like the web
/// one: the system font and colors, a plain bordered field, sentence-case labels and ordinary
/// spacing. The web form is a page of its own, while this one sits inside a merchant's screen, so
/// nobody should have to undo an SDK look to make it fit. Theming is fully available, it is just a
/// choice rather than the starting point. Passing the web's values reproduces the web appearance.
public struct GopayCardFormTheme: Equatable {

    // MARK: - Typography

    /// Name of a font registered with the app, applied to every text in the form. `nil`, or a name
    /// the app has not registered, uses the system font. Unlike the web this is a single font
    /// name, not a CSS stack.
    public var fontFamily: String?

    // MARK: - Labels

    /// Color of the field labels.
    public var labelColor: Color
    /// Font size of the field labels, in points.
    public var labelFontSize: CGFloat
    /// Font weight of the field labels, on the CSS scale 100...900.
    public var labelFontWeight: Int
    /// Line height of the field labels, in points. `nil` uses the font's own metrics.
    public var labelLineHeight: CGFloat?
    /// Whether the field labels are uppercased. The casing follows the current locale, so a
    /// Turkish label capitalizes `i` as `İ`.
    public var labelUppercase: Bool
    /// Letter spacing of the field labels, in points. `nil` means none. Needs iOS 16, below that
    /// the labels are drawn without it.
    public var labelLetterSpacing: CGFloat?
    /// Hides the labels. They take no vertical space but still name their field for VoiceOver.
    public var labelHidden: Bool

    // MARK: - Input text

    /// Color of the text typed into the inputs.
    public var inputTextColor: Color
    /// Font size of the input text, in points.
    public var inputFontSize: CGFloat
    /// Font weight of the input text, on the CSS scale 100...900. `nil` means regular.
    public var inputFontWeight: Int?
    /// Smallest height of the input, with the vertical padding inside it rather than on top of
    /// it. It is a minimum, not a fixed height, so a large font scale can still grow the field
    /// rather than overflow it. `nil` derives the height from the font and the padding alone. The
    /// Android SDK reads it the same way.
    ///
    /// A value of zero or less is read as unset. The web applies the same key as a fixed height.
    public var inputHeight: CGFloat?
    /// Color of the placeholder text. `nil` uses the system placeholder color.
    ///
    /// Set it whenever the theme paints the form dark. The system color follows the system's own
    /// light or dark appearance, not the theme's, so a dark theme on a device in light mode gets
    /// a dark placeholder on a dark field.
    public var placeholderColor: Color?

    // MARK: - Input border

    /// Whether the inputs are drawn with a full border or with a bottom line only.
    public var inputBorderStyle: GopayCardFormBorderStyle
    /// Border color of an unfocused, valid input.
    public var inputBorderColor: Color
    /// Border width, in points. Drawn inside the field, and capped at half its height, past which
    /// a border would have nothing left to enclose.
    public var inputBorderWidth: CGFloat
    /// Background color of the inputs.
    public var inputBackgroundColor: Color
    /// Vertical padding inside the inputs, in points.
    public var inputPaddingVertical: CGFloat
    /// Horizontal padding inside the inputs, in points.
    public var inputPaddingHorizontal: CGFloat
    /// Corner radius of the inputs, in points. The default `5` with a continuous curve is what
    /// `UITextField.borderStyle = .roundedRect` gives its own background view.
    public var inputBorderRadius: CGFloat
    // MARK: - Validation errors

    /// Border color of an input holding invalid content.
    public var inputErrorBorderColor: Color
    /// Color of the inline error text below an input.
    public var errorTextColor: Color
    /// Font size of the inline error text, in points.
    public var errorFontSize: CGFloat
    /// Minimum vertical space reserved for the inline error line, in points, so the layout does
    /// not shift when a message appears. A value below one rendered line of the error font is
    /// raised to that line; `0`, the default, reserves nothing and lets the form grow.
    public var errorMinHeight: CGFloat
    /// Distance from an input to its error line, in points. `nil` uses ``fieldSpacing``.
    public var errorSpacing: CGFloat?

    // MARK: - Layout

    /// Gap between the field groups, in points: between the card number row and the
    /// expiration + CVV row, and between the expiration and the CVV. `16`, the value the web form
    /// and the Android SDK also use; it is our own spacing, not a platform constant.
    public var groupSpacing: CGFloat
    /// Gap between a label and its input, in points.
    public var fieldSpacing: CGFloat
    /// Padding around the whole form, in points. `0`, because the host lays the form out; the web
    /// uses `16` because there the form sits alone in an iframe.
    public var formPadding: CGFloat
    /// Background color of the form container.
    public var formBackgroundColor: Color

    /// Creates a custom theme. Every parameter defaults to what the platform would do on its own,
    /// so anything left out keeps the native appearance.
    public init(
        fontFamily: String? = nil,
        labelColor: Color = .primary,
        labelFontSize: CGFloat = 12,
        labelFontWeight: Int = 400,
        labelLineHeight: CGFloat? = nil,
        labelUppercase: Bool = false,
        labelLetterSpacing: CGFloat? = nil,
        labelHidden: Bool = false,
        inputTextColor: Color = .primary,
        inputFontSize: CGFloat = 17,
        inputFontWeight: Int? = nil,
        inputHeight: CGFloat? = nil,
        placeholderColor: Color? = nil,
        inputBorderStyle: GopayCardFormBorderStyle = .boxed,
        inputBorderColor: Color = Color(.separator),
        inputBorderWidth: CGFloat = 1,
        inputBackgroundColor: Color = .clear,
        inputPaddingVertical: CGFloat = 12,
        inputPaddingHorizontal: CGFloat = 12,
        inputBorderRadius: CGFloat = 5,
        inputErrorBorderColor: Color = .red,
        errorTextColor: Color = .red,
        errorFontSize: CGFloat = 12,
        errorMinHeight: CGFloat = 0,
        errorSpacing: CGFloat? = nil,
        groupSpacing: CGFloat = 16,
        fieldSpacing: CGFloat = 4,
        formPadding: CGFloat = 0,
        formBackgroundColor: Color = .clear
    ) {
        self.fontFamily = fontFamily
        self.labelColor = labelColor
        self.labelFontSize = labelFontSize
        self.labelFontWeight = labelFontWeight
        self.labelLineHeight = labelLineHeight
        self.labelUppercase = labelUppercase
        self.labelLetterSpacing = labelLetterSpacing
        self.labelHidden = labelHidden
        self.inputTextColor = inputTextColor
        self.inputFontSize = inputFontSize
        self.inputFontWeight = inputFontWeight
        self.inputHeight = inputHeight
        self.placeholderColor = placeholderColor
        self.inputBorderStyle = inputBorderStyle
        self.inputBorderColor = inputBorderColor
        self.inputBorderWidth = inputBorderWidth
        self.inputBackgroundColor = inputBackgroundColor
        self.inputPaddingVertical = inputPaddingVertical
        self.inputPaddingHorizontal = inputPaddingHorizontal
        self.inputBorderRadius = inputBorderRadius
        self.inputErrorBorderColor = inputErrorBorderColor
        self.errorTextColor = errorTextColor
        self.errorFontSize = errorFontSize
        self.errorMinHeight = errorMinHeight
        self.errorSpacing = errorSpacing
        self.groupSpacing = groupSpacing
        self.fieldSpacing = fieldSpacing
        self.formPadding = formPadding
        self.formBackgroundColor = formBackgroundColor
    }

}

// MARK: - Font weights

extension GopayCardFormTheme {
    /// Maps a CSS font weight (100...900) to the closest `UIFont.Weight`. Values in between are
    /// rounded to the nearest hundred, values outside the range are clamped. Every rendered font
    /// goes through here; the SwiftUI `Font` values are built from the resolved `UIFont`.
    static func uiFontWeight(_ cssWeight: Int) -> UIFont.Weight {
        switch Self.normalizedWeight(cssWeight) {
        case 100: return .ultraLight
        case 200: return .thin
        case 300: return .light
        case 400: return .regular
        case 500: return .medium
        case 600: return .semibold
        case 700: return .bold
        case 800: return .heavy
        default: return .black
        }
    }

    private static func normalizedWeight(_ cssWeight: Int) -> Int {
        let clamped = min(max(cssWeight, 100), 900)
        return Int((Double(clamped) / 100).rounded()) * 100
    }
}

// MARK: - Resolved state

extension GopayCardFormTheme {
    /// Height reserved below an input so the form does not jump when an error appears.
    ///
    /// ``errorMinHeight`` is what the theme asked for, but a reserve shorter than one line of the
    /// error font would not hold the message it exists for, so the taller of the two wins. Both
    /// scale with the reader's text size.
    func reservedErrorHeight(for sizeCategory: ContentSizeCategory) -> CGFloat {
        guard errorMinHeight > 0 else { return 0 }
        let requested = scaledCaptionLength(errorMinHeight, for: sizeCategory)
        // The height of a rendered line, not the font's point size: a line box is about a fifth
        // taller than the size that names it, and reserving the smaller number lets the form jump
        // by that difference the moment a message appears.
        let oneLine = errorUIFont(for: sizeCategory).lineHeight
        return max(requested, oneLine)
    }

    /// Border color of an input holding valid or invalid content. Focus does not recolor the
    /// border: a native field marks focus with the caret and the keyboard rather than its frame.
    func borderColor(hasError: Bool) -> Color {
        hasError ? inputErrorBorderColor : inputBorderColor
    }

    /// Distance from an input to its error line, falling back to ``fieldSpacing``.
    var resolvedErrorSpacing: CGFloat { errorSpacing ?? fieldSpacing }

    /// Whether the slot below an input is on screen for `message`: it is while a message shows,
    /// and while ``errorMinHeight`` reserves room for one.
    func rendersErrorSlot(for message: String?) -> Bool {
        message?.isEmpty == false || errorMinHeight > 0
    }
}

// MARK: - Resolved fonts

extension GopayCardFormTheme {
    /// The label font, scaled for the given Dynamic Type category the way the caption text style
    /// scales. The form reads the category from the environment so the scaling stays live.
    func labelUIFont(for sizeCategory: ContentSizeCategory) -> UIFont {
        scaledFont(
            size: labelFontSize,
            weight: Self.uiFontWeight(labelFontWeight),
            textStyle: .caption1,
            sizeCategory: sizeCategory
        )
    }

    /// SwiftUI counterpart of ``labelUIFont(for:)``.
    func labelFont(for sizeCategory: ContentSizeCategory) -> Font {
        Font(labelUIFont(for: sizeCategory) as CTFont)
    }

    /// The inline error font: the themed error size in the theme's font family.
    func errorUIFont(for sizeCategory: ContentSizeCategory) -> UIFont {
        scaledFont(size: errorFontSize, weight: .regular, textStyle: .caption1, sizeCategory: sizeCategory)
    }

    /// SwiftUI counterpart of ``errorUIFont(for:)``.
    func errorFont(for sizeCategory: ContentSizeCategory) -> Font {
        Font(errorUIFont(for: sizeCategory) as CTFont)
    }

    /// The input font, scaled for the given Dynamic Type category the way the body text style
    /// scales. The category comes from the environment, as it does for the labels and the error
    /// text, so all three follow the same one even where a preview or a test overrides it.
    func inputUIFont(for sizeCategory: ContentSizeCategory) -> UIFont {
        scaledFont(
            size: inputFontSize,
            weight: inputFontWeight.map(Self.uiFontWeight) ?? .regular,
            textStyle: .body,
            sizeCategory: sizeCategory
        )
    }

    /// Scales a length the way the caption text style scales, so a themed line height or reserved
    /// height keeps up with Dynamic Type.
    func scaledCaptionLength(_ length: CGFloat, for sizeCategory: ContentSizeCategory) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory.uiContentSizeCategory)
        return UIFontMetrics(forTextStyle: .caption1).scaledValue(for: length, compatibleWith: traits)
    }

    private func scaledFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle,
        sizeCategory: ContentSizeCategory
    ) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory.uiContentSizeCategory)
        return UIFontMetrics(forTextStyle: textStyle)
            .scaledFont(for: baseFont(size: size, weight: weight), compatibleWith: traits)
    }

    /// The unscaled font for a size and weight: ``fontFamily`` when the app has that font
    /// registered, the system font otherwise. The family is matched by name and the bold face is
    /// requested for weights from semibold up, because a named face carries its own weight and
    /// CoreText does not synthesize a heavier one from it; a family without a bold face keeps its
    /// nearest one.
    private func baseFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        guard let fontFamily = fontFamily, let named = UIFont(name: fontFamily, size: size) else {
            return .systemFont(ofSize: size, weight: weight)
        }
        let family = UIFontDescriptor(fontAttributes: [.family: named.familyName])
        var symbolic = family.symbolicTraits
        if weight.rawValue >= UIFont.Weight.semibold.rawValue {
            symbolic.insert(.traitBold)
        } else {
            symbolic.remove(.traitBold)
        }
        let descriptor = (family.withSymbolicTraits(symbolic) ?? family)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension ContentSizeCategory {
    /// UIKit counterpart, so `UIFontMetrics` can scale against the SwiftUI environment value.
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .extraSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .extraLarge
        case .extraExtraLarge: return .extraExtraLarge
        case .extraExtraExtraLarge: return .extraExtraExtraLarge
        case .accessibilityMedium: return .accessibilityMedium
        case .accessibilityLarge: return .accessibilityLarge
        case .accessibilityExtraLarge: return .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: return .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
