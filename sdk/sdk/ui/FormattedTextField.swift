import SwiftUI
import UIKit

extension UIColor {
    /// `UIColor(Color)` needs iOS 14; this SDK targets iOS 13, so older OSes fall back to `.label`.
    static func from(_ color: Color, fallback: UIColor = .label) -> UIColor {
        if #available(iOS 14.0, *) {
            return UIColor(color)
        }
        return fallback
    }
}

/// Formats a digits-only string for display (spacing, separators) and
/// sanitizes digits as they're typed (e.g. rejecting an invalid month).
///
/// SwiftUI's `TextField` binding has no way to control the cursor position,
/// so formatting inside a `Binding` `set` closure (mutating the bound string)
/// always causes the caret to jump. `FormattedTextField` avoids that by
/// driving a `UITextField` directly and repositioning the caret itself.
struct CardTextFormatter {
    let maxDigits: Int
    var sanitize: (String) -> String = { $0 }
    let format: (String) -> String

    static let cardNumber = CardTextFormatter(maxDigits: 16) { digits in
        stride(from: 0, to: digits.count, by: 4).map { start -> String in
            let from = digits.index(digits.startIndex, offsetBy: start)
            let to = digits.index(from, offsetBy: min(4, digits.count - start))
            return String(digits[from..<to])
        }.joined(separator: " ")
    }

    static let expiration = CardTextFormatter(
        maxDigits: 4,
        sanitize: { digits in
            if digits.count <= 2 {
                if let month = Int(digits), month > 12 {
                    return String(digits.prefix(1))
                }
                return digits
            } else {
                let monthString = String(digits.prefix(2))
                if let month = Int(monthString), month >= 1 && month <= 12 {
                    return digits
                }
                return String(digits.prefix(1))
            }
        },
        format: { digits in
            guard digits.count >= 2 else { return digits }
            let splitIndex = digits.index(digits.startIndex, offsetBy: 2)
            return "\(digits[..<splitIndex])/\(digits[splitIndex...])"
        }
    )

    static let cvv = CardTextFormatter(maxDigits: 3) { $0 }
}

/// The `UITextField` behind ``FormattedTextField``, with a height that comes from its font alone.
///
/// A plain `UITextField` sizes itself to the glyphs it shows, and secure text entry swaps in the
/// bullet glyphs, which makes a CVV field a few points shorter than the expiration next to it. The
/// font's line height, rounded up to a whole point plus the point of room a text field leaves for
/// the caret, gives the three inputs of a row the same height in every style and matches what the
/// system font measured before.
final class GopayInputTextField: UITextField {
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        if let font = font {
            size.height = Self.height(for: font)
        }
        return size
    }

    /// The height an input takes for `font`, independent of its content.
    static func height(for font: UIFont) -> CGFloat {
        ceil(font.lineHeight) + 1
    }
}

/// A `UITextField`-backed field that formats digits-only input in real time
/// (card number grouping, expiration slash) while keeping the cursor in the
/// right place - something a plain SwiftUI `TextField` cannot do.
struct FormattedTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var digits: String
    let formatter: CardTextFormatter
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor = .label
    /// Color of the placeholder text. `nil` falls back to the light grey the Android SDK and the
    /// web form use, which stays readable on a themed background of either brightness. The system
    /// placeholder color would follow the system appearance instead of the form's own.
    var placeholderColor: UIColor? = nil
    /// Extra spacing between characters, in points. `nil` means none.
    var letterSpacing: CGFloat? = nil
    /// Name announced for this field when the form draws no visible label.
    var accessibilityLabel: String? = nil
    var textContentType: UITextContentType? = nil
    var isSecure: Bool = false
    /// Whether this field should currently hold the keyboard focus. Setting this from the
    /// host view (e.g. after the previous field fills with a valid value) moves focus here;
    /// `onFocusChange` reports back when focus changes for other reasons (the user tapping in).
    var isFocused: Bool = false
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextField {
        let textField = GopayInputTextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .numberPad
        textField.isSecureTextEntry = isSecure
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.adjustsFontForContentSizeCategory = true
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingBegan), for: .editingDidBegin)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingEnded), for: .editingDidEnd)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // The placeholder is as wide as the field's intrinsic width. Under a large Dynamic Type
        // size it would otherwise push the whole form past the edge of the screen; the field can
        // always be narrower than its placeholder and scroll instead.
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        if textField.font != font {
            textField.font = font
            textField.invalidateIntrinsicContentSize()
        }
        textField.textColor = textColor
        textField.textContentType = textContentType
        textField.accessibilityLabel = accessibilityLabel
        // Written through the subscript so the font and color set above survive.
        textField.defaultTextAttributes[.kern] = letterSpacing

        // The placeholder carries the input typography too (font and letter spacing), the way
        // the web form's placeholder inherits it; the themed color is the only difference.
        var placeholderAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: placeholderColor ?? .gopayDefaultPlaceholder
        ]
        if let letterSpacing = letterSpacing {
            placeholderAttributes[.kern] = letterSpacing
        }
        textField.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: placeholderAttributes)

        let formatted = formatter.format(digits)
        if textField.text != formatted {
            textField.text = formatted
        }

        // Deferred to the next run loop turn: becomeFirstResponder()/resignFirstResponder() fire
        // editingDidBegin/editingDidEnd synchronously, which write @State via onFocusChange. Doing
        // that while still inside this SwiftUI view update triggers "Modifying state during view
        // update, this will cause undefined behavior".
        if isFocused != textField.isFirstResponder {
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak textField, weak coordinator] in
                guard let textField, let coordinator else { return }
                let shouldBeFocused = coordinator.parent.isFocused
                if shouldBeFocused, !textField.isFirstResponder {
                    textField.becomeFirstResponder()
                } else if !shouldBeFocused, textField.isFirstResponder {
                    textField.resignFirstResponder()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FormattedTextField
        init(_ parent: FormattedTextField) { self.parent = parent }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let currentText = textField.text ?? ""
            guard var editedRange = Range(range, in: currentText) else { return false }

            // Backspacing over an inserted separator should also remove the
            // adjacent digit, otherwise the field appears stuck.
            if string.isEmpty, !editedRange.isEmpty,
               currentText[editedRange].allSatisfy({ !$0.isNumber }),
               editedRange.lowerBound > currentText.startIndex {
                let newLowerBound = currentText.index(before: editedRange.lowerBound)
                editedRange = newLowerBound..<editedRange.upperBound
            }

            let proposedText = currentText.replacingCharacters(in: editedRange, with: string)
            let caretOffset = currentText.distance(from: currentText.startIndex, to: editedRange.lowerBound) + string.count
            let digitsBeforeCaret = proposedText.prefix(caretOffset).filter(\.isNumber).count

            let formatter = parent.formatter
            let cappedDigits = String(proposedText.filter(\.isNumber).prefix(formatter.maxDigits))
            let newDigits = formatter.sanitize(cappedDigits)
            let formatted = formatter.format(newDigits)

            textField.text = formatted
            parent.digits = newDigits

            let caretDigit = min(digitsBeforeCaret, newDigits.count)
            let offset = Self.offset(afterDigit: caretDigit, in: formatted)
            if let position = textField.position(from: textField.beginningOfDocument, offset: offset) {
                textField.selectedTextRange = textField.textRange(from: position, to: position)
            }
            return false
        }

        /// Index in `formatted` just after the Nth digit, skipping separators.
        private static func offset(afterDigit n: Int, in formatted: String) -> Int {
            guard n > 0 else { return 0 }
            var seen = 0
            for (index, character) in formatted.enumerated() where character.isNumber {
                seen += 1
                if seen == n { return index + 1 }
            }
            return formatted.count
        }

        @objc func editingBegan() { parent.onFocusChange(true) }
        @objc func editingEnded() { parent.onFocusChange(false) }
    }
}

extension UIColor {
    /// The placeholder grey the card form falls back to, the same value as Android's `LightGray`.
    /// A fixed color rather than `placeholderText`, because the theme paints the background and
    /// the system appearance says nothing about how light or dark that background is.
    static let gopayDefaultPlaceholder = UIColor(white: 204 / 255, alpha: 1)
}
