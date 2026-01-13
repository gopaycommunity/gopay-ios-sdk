import SwiftUI

/// Theme configuration for the payment card form.
///
/// Use this to customize the appearance of the card form UI.
public struct GopayCardFormTheme {
    /// Text color for labels and text fields.
    public var textColor: Color
    /// Background color for text fields.
    public var backgroundColor: Color
    /// Border color for text fields.
    public var borderColor: Color
    /// Border color when a field is focused.
    public var focusedBorderColor: Color
    /// Border width for text fields.
    public var borderWidth: CGFloat
    /// Corner radius for text fields.
    public var cornerRadius: CGFloat
    /// Font for text fields.
    public var font: Font
    /// Font for labels.
    public var labelFont: Font
    /// Spacing between form elements.
    public var spacing: CGFloat
    /// Padding inside text fields.
    public var textFieldPadding: CGFloat
    
    /// Creates a custom theme.
    /// - Parameters:
    ///   - textColor: Text color for labels and text fields.
    ///   - backgroundColor: Background color for text fields.
    ///   - borderColor: Border color for text fields.
    ///   - focusedBorderColor: Border color when a field is focused.
    ///   - borderWidth: Border width for text fields.
    ///   - cornerRadius: Corner radius for text fields.
    ///   - font: Font for text fields.
    ///   - labelFont: Font for labels.
    ///   - spacing: Spacing between form elements.
    ///   - textFieldPadding: Padding inside text fields.
    public init(
        textColor: Color = .primary,
        backgroundColor: Color = Color(.systemBackground),
        borderColor: Color = Color(.separator),
        focusedBorderColor: Color = .blue,
        borderWidth: CGFloat = 1.0,
        cornerRadius: CGFloat = 8.0,
        font: Font = .body,
        labelFont: Font = .caption,
        spacing: CGFloat = 12.0,
        textFieldPadding: CGFloat = 12.0
    ) {
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.focusedBorderColor = focusedBorderColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.font = font
        self.labelFont = labelFont
        self.spacing = spacing
        self.textFieldPadding = textFieldPadding
    }
    
    /// Default theme with system colors.
    public static let standard = GopayCardFormTheme()
}

