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

/// A `UITextField`-backed field that formats digits-only input in real time
/// (card number grouping, expiration slash) while keeping the cursor in the
/// right place - something a plain SwiftUI `TextField` cannot do.
struct FormattedTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var digits: String
    let formatter: CardTextFormatter
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor = .label
    var textContentType: UITextContentType? = nil
    var isSecure: Bool = false
    /// Whether this field should currently hold the keyboard focus. Setting this from the
    /// host view (e.g. after the previous field fills with a valid value) moves focus here;
    /// `onFocusChange` reports back when focus changes for other reasons (the user tapping in).
    var isFocused: Bool = false
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .numberPad
        textField.isSecureTextEntry = isSecure
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.adjustsFontForContentSizeCategory = true
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingBegan), for: .editingDidBegin)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingEnded), for: .editingDidEnd)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        textField.placeholder = placeholder
        textField.font = font
        textField.textColor = textColor
        textField.textContentType = textContentType

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
