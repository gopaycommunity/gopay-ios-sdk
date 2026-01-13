import SwiftUI
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
    
    /// Returns the card number formatted as 4 groups separated by whitespace.
    var formattedCardNumber: String {
        let digits = cardNumber.filter { $0.isNumber }
        var formatted = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += " "
            }
            formatted += String(digit)
        }
        return formatted
    }
    
    /// Returns the expiration date formatted as MM/YY.
    var formattedExpiration: String {
        let monthDigits = expirationMonth.filter { $0.isNumber }
        let yearDigits = expirationYear.filter { $0.isNumber }
        
        var formatted = monthDigits
        if monthDigits.count >= 2 {
            formatted += "/" + yearDigits
        }
        return formatted
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
    
    // Local state for formatted display strings (for real-time formatting)
    @State private var cardNumberDisplay: String = ""
    @State private var expirationDisplay: String = ""
    
    /// Creates a payment card form.
    /// - Parameters:
    ///   - theme: Theme for customizing the appearance (default: `.standard`).
    ///   - isValid: Optional binding to track form validation state (default: `nil`).
    ///   - formId: Optional unique identifier for this form. If not provided, a UUID will be generated.
    public init(
        theme: GopayCardFormTheme = .standard,
        isValid: Binding<Bool?> = .constant(nil),
        formId: String? = nil
    ) {
        self.theme = theme
        self._isValid = isValid
        self.formId = formId ?? UUID().uuidString
        self._data = State(initialValue: GopayCardFormData())
    }
    
    public var body: some View {
        VStack(spacing: theme.spacing) {
            // Card number input (first row)
            VStack(alignment: .leading, spacing: 4) {
                Text("Card Number")
                    .font(theme.labelFont)
                    .foregroundColor(theme.textColor)
                
                TextField("1234 5678 9012 3456", text: Binding(
                    get: { cardNumberDisplay },
                    set: { newValue in
                        // Remove all non-digits and whitespace
                        let digits = newValue.filter { $0.isNumber }
                        // Limit to 16 digits
                        let limitedDigits = String(digits.prefix(16))
                        // Format immediately
                        var formatted = ""
                        for (index, digit) in limitedDigits.enumerated() {
                            if index > 0 && index % 4 == 0 {
                                formatted += " "
                            }
                            formatted += String(digit)
                        }
                        // Update display synchronously
                        cardNumberDisplay = formatted
                        // Update the underlying data
                        data.cardNumber = limitedDigits
                        // Sync to SDK internally
                        GopaySDK.shared.updateCardFormData(data, formId: formId)
                        // Update validation binding if provided
                        updateValidationBinding()
                    }
                ), onEditingChanged: { isEditing in
                    isCardNumberFocused = isEditing
                    if isEditing {
                        isExpirationFocused = false
                        isCvvFocused = false
                    }
                })
                .onAppear {
                    // Initialize display strings from data when view appears
                    // Safely access data properties
                    if cardNumberDisplay.isEmpty {
                        cardNumberDisplay = data.formattedCardNumber
                    }
                    if expirationDisplay.isEmpty {
                        expirationDisplay = data.formattedExpiration
                    }
                }
                .font(theme.font)
                .foregroundColor(theme.textColor)
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
                .keyboardType(.numberPad)
            }
            
            // Expiration and CVV inputs (second row)
            HStack(spacing: theme.spacing) {
                // Expiration input (single field with automatic slash)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expiration")
                        .font(theme.labelFont)
                        .foregroundColor(theme.textColor)
                    
                    TextField("MM/YY", text: Binding(
                        get: { expirationDisplay },
                        set: { newValue in
                            // Remove slash and keep only digits
                            let digits = newValue.filter { $0.isNumber }
                            
                            // Limit to 4 digits total (2 for month, 2 for year)
                            let limitedDigits = String(digits.prefix(4))
                            
                            if limitedDigits.count <= 2 {
                                // Only month entered so far
                                var monthString = limitedDigits
                                // Auto-validate month (prevent > 12)
                                if let month = Int(monthString), month > 12 {
                                    monthString = String(limitedDigits.prefix(1))
                                }
                                data.expirationMonth = monthString
                                data.expirationYear = ""
                            } else {
                                // Month and year entered
                                let monthString = String(limitedDigits.prefix(2))
                                // Validate month
                                if let month = Int(monthString), month >= 1 && month <= 12 {
                                    // Format month with leading zero in real-time
                                    data.expirationMonth = String(format: "%02d", month)
                                    data.expirationYear = String(limitedDigits.dropFirst(2))
                                } else {
                                    // Invalid month, keep only first digit
                                    data.expirationMonth = String(limitedDigits.prefix(1))
                                    data.expirationYear = ""
                                }
                            }
                            
                            // Format and update display immediately
                            let monthDigits = data.expirationMonth.filter { $0.isNumber }
                            let yearDigits = data.expirationYear.filter { $0.isNumber }
                            var formatted = monthDigits
                            if monthDigits.count >= 2 {
                                formatted += "/" + yearDigits
                            }
                            // Update display synchronously
                            expirationDisplay = formatted
                            // Sync to SDK internally
                            GopaySDK.shared.updateCardFormData(data, formId: formId)
                            // Update validation binding if provided
                            updateValidationBinding()
                        }
                    ), onEditingChanged: { isEditing in
                        isExpirationFocused = isEditing
                        if isEditing {
                            isCardNumberFocused = false
                            isCvvFocused = false
                        } else {
                            // Format month with leading zero when field loses focus (if not already formatted)
                            if data.expirationMonth.count == 1, let month = Int(data.expirationMonth), month >= 1 && month <= 12 {
                                data.expirationMonth = String(format: "%02d", month)
                                // Update display
                                let monthDigits = data.expirationMonth.filter { $0.isNumber }
                                let yearDigits = data.expirationYear.filter { $0.isNumber }
                                var formatted = monthDigits
                                if monthDigits.count >= 2 {
                                    formatted += "/" + yearDigits
                                }
                                expirationDisplay = formatted
                                // Sync to SDK internally
                                GopaySDK.shared.updateCardFormData(data, formId: formId)
                                // Update validation binding if provided
                                updateValidationBinding()
                            }
                        }
                    })
                    .font(theme.font)
                    .foregroundColor(theme.textColor)
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
                    .keyboardType(.numberPad)
                    .frame(maxWidth: .infinity)
                }
                
                // CVV input
                VStack(alignment: .leading, spacing: 4) {
                    Text("CVV")
                        .font(theme.labelFont)
                        .foregroundColor(theme.textColor)
                    
                    SecureField("123", text: Binding(
                        get: { data.cvv },
                        set: { newValue in
                            let digits = newValue.filter { $0.isNumber }
                            // Limit to 3 digits
                            data.cvv = String(digits.prefix(3))
                            // Sync to SDK internally
                            GopaySDK.shared.updateCardFormData(data, formId: formId)
                            // Update validation binding if provided
                            updateValidationBinding()
                        }
                    ), onCommit: {
                        isCvvFocused = false
                    })
                    .font(theme.font)
                    .foregroundColor(theme.textColor)
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
                    .keyboardType(.numberPad)
                    .onTapGesture {
                        isCardNumberFocused = false
                        isExpirationFocused = false
                        isCvvFocused = true
                    }
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

