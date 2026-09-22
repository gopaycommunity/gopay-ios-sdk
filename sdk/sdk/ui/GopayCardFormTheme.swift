import SwiftUI
import UIKit

/// Border style of the inputs, carrying the values of the web `inputBorderStyle` key so one theme
/// travels between channels.
public enum GopayCardFormBorderStyle: String, Codable, Equatable {
    /// A border around the whole input.
    case boxed
    /// A bottom line only. **Not supported on iOS**, which has no native underlined text field and
    /// where the SDK draws nothing of its own: the value is accepted and the input is rendered as
    /// ``boxed``. Android renders it with the native Material indicator.
    case underline
}

/// Theme configuration for the payment card form.
///
/// The parameters are atomic and carry the names of the web card form theme (cc-v4), so the same
/// theme can be described once and applied on the web, on iOS and on Android.
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
///
/// The type is `Codable` with colors bridged to hex strings (`"#RGB"`, `"#RGBA"`, `"#RRGGBB"`,
/// `"#RRGGBBAA"` or `"transparent"`), so a JSON theme travels between channels. Decoding is deliberately tolerant:
/// unknown keys are ignored, and a key whose value cannot be used (a value of the wrong type, an
/// unusable color, a negative length, an unknown ``inputBorderStyle``) is dropped on its own while
/// the rest of the document applies, so a full web theme decodes without error. Font weights also
/// accept the CSS keywords `bold` and `normal`. Every dropped key is reported through the SDK debug
/// log, so an integrator learns about it without the theme failing. Encoding an adaptive `Color`
/// resolves it against the current trait collection, so a decoded theme is no longer light/dark
/// adaptive, and encoding needs iOS 14 because SwiftUI cannot read a `Color` back on iOS 13.
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
    /// Fixed height of the inputs, in points. `nil` derives the height from the font and the
    /// padding.
    ///
    /// On iOS this is the whole height of the field and ``inputPaddingVertical`` is dropped while
    /// it is set, as it is on the web. Android reads it as a minimum instead, and adds the padding
    /// on top, so the same value gives a taller field there. A value of zero or less is read as
    /// unset, and content taller than the height is clipped to the field.
    public var inputHeight: CGFloat?
    /// Color of the placeholder text. `nil` uses the system placeholder color.
    public var placeholderColor: Color?

    // MARK: - Input border

    /// Whether the inputs are drawn with a full border or with a bottom line only.
    public var inputBorderStyle: GopayCardFormBorderStyle
    /// Border color of an unfocused, valid input.
    public var inputBorderColor: Color
    /// Border width, in points.
    public var inputBorderWidth: CGFloat
    /// Background color of the inputs.
    public var inputBackgroundColor: Color
    /// Vertical padding inside the inputs, in points.
    public var inputPaddingVertical: CGFloat
    /// Horizontal padding inside the inputs, in points.
    public var inputPaddingHorizontal: CGFloat
    /// Corner radius of the inputs, in points.
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
    /// expiration + CVV row, and between the expiration and the CVV.
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
        inputBorderRadius: CGFloat = 8,
        inputErrorBorderColor: Color = .red,
        errorTextColor: Color = .red,
        errorFontSize: CGFloat = 12,
        errorMinHeight: CGFloat = 0,
        errorSpacing: CGFloat? = nil,
        groupSpacing: CGFloat = 12,
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

    /// Default theme: the appearance iOS gives a form of plain text fields.
    public static let standard = GopayCardFormTheme()

    /// Ceiling for any length read from a JSON theme document, in points.
    ///
    /// Well past any real design value, but low enough that the layout the lengths feed stays
    /// finite: an unbounded height or padding overflows the form. A document is read defensively
    /// and must never be able to fail the form, so the decoder drops anything beyond this rather
    /// than passing it on.
    static let lengthLimit: CGFloat = 10_000
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

// MARK: - Codable

extension GopayCardFormTheme: Codable {
    private enum CodingKeys: String, CodingKey {
        case fontFamily
        case labelColor, labelFontSize, labelFontWeight, labelLineHeight
        case labelUppercase, labelLetterSpacing, labelHidden
        case inputTextColor, inputFontSize, inputFontWeight
        case inputHeight, placeholderColor
        case inputBorderStyle, inputBorderColor, inputBorderWidth, inputBackgroundColor
        case inputPaddingVertical, inputPaddingHorizontal, inputBorderRadius
        case inputErrorBorderColor, errorTextColor, errorFontSize, errorMinHeight, errorSpacing
        case groupSpacing, fieldSpacing, formPadding, formBackgroundColor
    }

    /// Decodes a theme, keeping the default of every key the payload omits and ignoring keys the
    /// SDK does not know (the web-only `submit*` and `errorHidden` among them).
    ///
    /// A key whose value cannot be used is dropped on its own, the way a TypeScript compiler warns
    /// about one property and still builds: the rest of the document applies, and the dropped key
    /// is reported through the SDK debug log (`GopaySDKConfig.enableDebugLogging`).
    public init(from decoder: Decoder) throws {
        let keys = GopayTolerantThemeKeys(container: try decoder.container(keyedBy: CodingKeys.self))
        Self.reportRetiredKeys(in: decoder)
        // Every key the document omits keeps the base theme's value. Plain decoding has no base,
        // so it falls back to the SDK defaults; ``applying(_:)`` puts the caller's theme here.
        let fallback = decoder.userInfo[.gopayThemeBase] as? GopayCardFormTheme ?? GopayCardFormTheme()

        self.init(
            fontFamily: keys.value(String.self, .fontFamily) ?? fallback.fontFamily,
            labelColor: keys.color(.labelColor) ?? fallback.labelColor,
            labelFontSize: keys.length(.labelFontSize) ?? fallback.labelFontSize,
            labelFontWeight: keys.fontWeight(.labelFontWeight) ?? fallback.labelFontWeight,
            labelLineHeight: keys.length(.labelLineHeight) ?? fallback.labelLineHeight,
            labelUppercase: keys.value(Bool.self, .labelUppercase) ?? fallback.labelUppercase,
            labelLetterSpacing: keys.signedLength(.labelLetterSpacing) ?? fallback.labelLetterSpacing,
            labelHidden: keys.value(Bool.self, .labelHidden) ?? fallback.labelHidden,
            inputTextColor: keys.color(.inputTextColor) ?? fallback.inputTextColor,
            inputFontSize: keys.length(.inputFontSize) ?? fallback.inputFontSize,
            inputFontWeight: keys.fontWeight(.inputFontWeight) ?? fallback.inputFontWeight,
            inputHeight: keys.length(.inputHeight) ?? fallback.inputHeight,
            placeholderColor: keys.color(.placeholderColor) ?? fallback.placeholderColor,
            inputBorderStyle: keys.borderStyle(.inputBorderStyle) ?? fallback.inputBorderStyle,
            inputBorderColor: keys.color(.inputBorderColor) ?? fallback.inputBorderColor,
            inputBorderWidth: keys.length(.inputBorderWidth) ?? fallback.inputBorderWidth,
            inputBackgroundColor: keys.color(.inputBackgroundColor) ?? fallback.inputBackgroundColor,
            inputPaddingVertical: keys.length(.inputPaddingVertical) ?? fallback.inputPaddingVertical,
            inputPaddingHorizontal: keys.length(.inputPaddingHorizontal) ?? fallback.inputPaddingHorizontal,
            inputBorderRadius: keys.length(.inputBorderRadius) ?? fallback.inputBorderRadius,
            inputErrorBorderColor: keys.color(.inputErrorBorderColor) ?? fallback.inputErrorBorderColor,
            errorTextColor: keys.color(.errorTextColor) ?? fallback.errorTextColor,
            errorFontSize: keys.length(.errorFontSize) ?? fallback.errorFontSize,
            errorMinHeight: keys.length(.errorMinHeight) ?? fallback.errorMinHeight,
            errorSpacing: keys.length(.errorSpacing) ?? fallback.errorSpacing,
            groupSpacing: keys.length(.groupSpacing) ?? fallback.groupSpacing,
            fieldSpacing: keys.length(.fieldSpacing) ?? fallback.fieldSpacing,
            formPadding: keys.length(.formPadding) ?? fallback.formPadding,
            formBackgroundColor: keys.color(.formBackgroundColor) ?? fallback.formBackgroundColor
        )
    }

    /// Keys the web theme still has and this SDK no longer carries, because a native field
    /// cannot honour them. They are known rather than unknown, so a document that sets one is
    /// told it had no effect instead of having it disappear into the unknown-key branch.
    private enum RetiredKeys: String, CodingKey, CaseIterable {
        case inputBorderCollapse, focusRingWidth, focusRingColor
        case focusGradientStart, focusGradientEnd
        case inputLetterSpacing, inputLineHeight

        /// Why each one is gone, in the words the debug log uses.
        var reason: String {
            switch self {
            case .inputBorderCollapse, .focusRingWidth, .focusRingColor,
                 .focusGradientStart, .focusGradientEnd:
                return "a native field has nothing the SDK could draw it with"
            case .inputLetterSpacing:
                return "it would override how the field measures itself, labelLetterSpacing stays"
            case .inputLineHeight:
                return "a single-line native field has no such problem, see inputHeight"
            }
        }
    }

    /// Reports the keys a document set that this SDK understands but deliberately does not apply.
    private static func reportRetiredKeys(in decoder: Decoder) {
        guard let container = try? decoder.container(keyedBy: RetiredKeys.self) else { return }
        for key in RetiredKeys.allCases
        where container.contains(key) && (try? container.decodeNil(forKey: key)) == false {
            reportDroppedKey("\"\(key.stringValue)\" ignored, \(key.reason)")
        }
    }

    /// Reads the keys of a JSON theme one at a time. Every reader returns `nil` for a key that is
    /// absent or `null`, and for a value it cannot use, which it reports as a dropped key.
    private struct GopayTolerantThemeKeys {
        let container: KeyedDecodingContainer<CodingKeys>

        /// A value of exactly the expected type; anything else is dropped.
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            guard isSet(key) else { return nil }
            guard let value = try? container.decode(T.self, forKey: key) else {
                drop(key, "expected \(Self.name(of: T.self))")
                return nil
            }
            return value
        }

        /// A hex or `transparent` color string.
        func color(_ key: CodingKeys) -> Color? {
            guard let hex = value(String.self, key) else { return nil }
            guard let color = Color(gopayHex: hex) else {
                drop(key, "\"\(hex)\" is not a #RGB, #RGBA, #RRGGBB, #RRGGBBAA or transparent color")
                return nil
            }
            return color
        }

        /// A finite, non-negative number of points.
        func length(_ key: CodingKeys) -> CGFloat? {
            guard let value = signedLength(key) else { return nil }
            guard value >= 0 else {
                drop(key, "a length cannot be negative")
                return nil
            }
            return value
        }

        /// A finite number of points that may legitimately be negative, such as tighter letter
        /// spacing. Capped at ``GopayCardFormTheme/lengthLimit`` in both directions: beyond that
        /// the value is not a design decision any more, and the geometry it feeds degenerates.
        func signedLength(_ key: CodingKeys) -> CGFloat? {
            guard let value = value(CGFloat.self, key) else { return nil }
            guard value.isFinite else {
                drop(key, "a length must be a finite number")
                return nil
            }
            guard abs(value) <= GopayCardFormTheme.lengthLimit else {
                drop(key, "a length must be within \u{00b1}\(Int(GopayCardFormTheme.lengthLimit)) points")
                return nil
            }
            return value
        }

        /// A CSS font weight: a number on the 100...900 scale, or the keywords `bold` (700) and
        /// `normal` (400) the web accepts too.
        func fontWeight(_ key: CodingKeys) -> Int? {
            guard isSet(key) else { return nil }
            if let number = try? container.decode(Double.self, forKey: key), number.isFinite {
                // Clamped before the conversion, which traps on huge values, and to the CSS range
                // the property documents, so the stored value is never one the docs disallow.
                return Int(min(max(number.rounded(), 100), 900))
            }
            if let keyword = try? container.decode(String.self, forKey: key) {
                switch keyword.trimmingCharacters(in: .whitespaces).lowercased() {
                case "bold": return 700
                case "normal": return 400
                default: break
                }
            }
            drop(key, "expected a number or the keyword \"bold\" or \"normal\"")
            return nil
        }

        /// The border style, matched case-insensitively. `underline` is carried so a document
        /// travels between channels, but iOS has no native underlined field and renders it as
        /// `boxed`; every untouched web theme sets it, so say so rather than apply it in silence.
        func borderStyle(_ key: CodingKeys) -> GopayCardFormBorderStyle? {
            guard let raw = value(String.self, key) else { return nil }
            guard let style = GopayCardFormBorderStyle(rawValue: raw.lowercased()) else {
                drop(key, "\"\(raw)\" is not a border style, expected boxed or underline")
                return nil
            }
            if style == .underline {
                drop(key, "\"underline\" is not supported on iOS, the input is drawn as boxed")
            }
            return style
        }

        /// Whether the key carries a value at all. A `null` counts as omitted, not as an error.
        private func isSet(_ key: CodingKeys) -> Bool {
            container.contains(key) && (try? container.decodeNil(forKey: key)) == false
        }

        private func drop(_ key: CodingKeys, _ reason: String) {
            GopayCardFormTheme.reportDroppedKey("\"\(key.stringValue)\" ignored, \(reason)")
        }

        private static func name(of type: Any.Type) -> String {
            switch type {
            case is Bool.Type: return "true or false"
            case is String.Type: return "a string"
            default: return "a number"
            }
        }
    }

    /// Reports a JSON theme key the decoder dropped. Goes to the SDK debug log; tests observe it
    /// by swapping the handler.
    static var reportDroppedKey: (String) -> Void = { message in
        GopaySDK.shared.logWarning("GopayCardFormTheme \(message)")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fontFamily, forKey: .fontFamily)
        try container.encode(labelColor.gopayHex, forKey: .labelColor)
        try container.encode(labelFontSize, forKey: .labelFontSize)
        try container.encode(labelFontWeight, forKey: .labelFontWeight)
        try container.encodeIfPresent(labelLineHeight, forKey: .labelLineHeight)
        try container.encode(labelUppercase, forKey: .labelUppercase)
        try container.encodeIfPresent(labelLetterSpacing, forKey: .labelLetterSpacing)
        try container.encode(labelHidden, forKey: .labelHidden)
        try container.encode(inputTextColor.gopayHex, forKey: .inputTextColor)
        try container.encode(inputFontSize, forKey: .inputFontSize)
        try container.encodeIfPresent(inputFontWeight, forKey: .inputFontWeight)
        try container.encodeIfPresent(inputHeight, forKey: .inputHeight)
        try container.encodeIfPresent(placeholderColor?.gopayHex, forKey: .placeholderColor)
        try container.encode(inputBorderStyle, forKey: .inputBorderStyle)
        try container.encode(inputBorderColor.gopayHex, forKey: .inputBorderColor)
        try container.encode(inputBorderWidth, forKey: .inputBorderWidth)
        try container.encode(inputBackgroundColor.gopayHex, forKey: .inputBackgroundColor)
        try container.encode(inputPaddingVertical, forKey: .inputPaddingVertical)
        try container.encode(inputPaddingHorizontal, forKey: .inputPaddingHorizontal)
        try container.encode(inputBorderRadius, forKey: .inputBorderRadius)
        try container.encode(inputErrorBorderColor.gopayHex, forKey: .inputErrorBorderColor)
        try container.encode(errorTextColor.gopayHex, forKey: .errorTextColor)
        try container.encode(errorFontSize, forKey: .errorFontSize)
        try container.encode(errorMinHeight, forKey: .errorMinHeight)
        try container.encodeIfPresent(errorSpacing, forKey: .errorSpacing)
        try container.encode(groupSpacing, forKey: .groupSpacing)
        try container.encode(fieldSpacing, forKey: .fieldSpacing)
        try container.encode(formPadding, forKey: .formPadding)
        try container.encode(formBackgroundColor.gopayHex, forKey: .formBackgroundColor)
    }
}

extension CodingUserInfoKey {
    /// Carries the theme a document is applied over, so the tolerant decoder can fall back to it
    /// instead of the SDK defaults. See ``GopayCardFormTheme/applying(_:)-(Data)``.
    static let gopayThemeBase = CodingUserInfoKey(rawValue: "cz.gopay.sdk.themeBase")!
}

public extension GopayCardFormTheme {
    /// Applies a JSON theme document over this theme and returns the result.
    ///
    /// Every key the document does not set keeps this theme's value, so a partial document can
    /// restyle one thing without resetting a branded theme to the SDK defaults. A document that
    /// cannot be read at all leaves this theme untouched, and an unusable key drops on its own,
    /// so reading a document never fails the form. Mirrors the Android
    /// `PaymentCardFormThemeJson.parse(document).toTheme(base)`.
    func applying(_ document: Data) -> GopayCardFormTheme {
        let decoder = JSONDecoder()
        decoder.userInfo[.gopayThemeBase] = self
        guard let merged = try? decoder.decode(GopayCardFormTheme.self, from: document) else {
            GopaySDK.shared.logWarning("Theme document could not be read, the base theme is kept")
            return self
        }
        return merged
    }

    /// String convenience for ``applying(_:)-(Data)``.
    func applying(_ document: String) -> GopayCardFormTheme {
        applying(Data(document.utf8))
    }
}

// MARK: - Hex bridge

extension Color {

    /// The color resolved to components for encoding, or `nil` on iOS 13, where SwiftUI exposes
    /// neither `UIColor(Color)` nor `Color.cgColor` and a color simply cannot be read back.
    private var encodableUIColor: UIColor? {
        guard #available(iOS 14.0, *) else { return nil }
        return UIColor(self)
    }

    /// Parses `"#RGB"`, `"#RGBA"`, `"#RRGGBB"`, `"#RRGGBBAA"` and `"transparent"`. The leading
    /// `#` is required, as in CSS and as on Android, so one document reads the same everywhere.
    init?(gopayHex hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "transparent" {
            self = .clear
            return
        }
        guard value.hasPrefix("#") else { return nil }
        let digits = String(value.dropFirst())
        guard digits.allSatisfy({ $0.isHexDigit }), let packed = UInt64(digits, radix: 16) else {
            return nil
        }

        let red: Double, green: Double, blue: Double, alpha: Double
        switch digits.count {
        case 3:
            red = Double((packed >> 8) & 0xF) / 15
            green = Double((packed >> 4) & 0xF) / 15
            blue = Double(packed & 0xF) / 15
            alpha = 1
        case 4:
            red = Double((packed >> 12) & 0xF) / 15
            green = Double((packed >> 8) & 0xF) / 15
            blue = Double((packed >> 4) & 0xF) / 15
            alpha = Double(packed & 0xF) / 15
        case 6:
            red = Double((packed >> 16) & 0xFF) / 255
            green = Double((packed >> 8) & 0xFF) / 255
            blue = Double(packed & 0xFF) / 255
            alpha = 1
        case 8:
            red = Double((packed >> 24) & 0xFF) / 255
            green = Double((packed >> 16) & 0xFF) / 255
            blue = Double((packed >> 8) & 0xFF) / 255
            alpha = Double(packed & 0xFF) / 255
        default:
            return nil
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// The color as `"#RRGGBB"`, or `"#RRGGBBAA"` when it is translucent and `"transparent"` when
    /// it is fully clear. An adaptive color resolves against the current trait collection.
    ///
    /// Reading a `Color` back needs iOS 14, so on iOS 13 every color encodes as `"transparent"`.
    /// Decoding a theme works on every supported version.
    var gopayHex: String {
        guard let color = encodableUIColor else { return "transparent" }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        if alpha <= 0 { return "transparent" }

        let channel: (CGFloat) -> Int = { Int((min(max($0, 0), 1) * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
        guard alpha < 1 else { return rgb }
        return rgb + String(format: "%02X", channel(alpha))
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
