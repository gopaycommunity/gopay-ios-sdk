import Foundation

/// Localized strings for the payment card form (``GopayCardForm``).
///
/// A locale must provide every field — there are no defaults, so a partially translated locale
/// cannot leak an untranslated fallback string into the middle of an otherwise localized form.
/// The one exception is ``screenCaptureNotice``, which defaults to empty so that a locale written
/// before it existed still compiles; an empty notice leaves the cover over the form without text
/// rather than in another language.
///
/// The label / placeholder / error-pattern fields mirror the shared GoPay web SDK locale keys;
/// ``panPlaceholder``, ``cvvLabel`` and ``cvvPlaceholder`` are additional fields the native form
/// renders that the web key set does not localize (they are kept constant across the built-in
/// locales).
///
/// To supply your own translation, build a `GopayLocaleStrings` with the same structure and
/// register it via ``GopayLocales/register(_:for:)`` (or `GopaySDKConfig.customLocales`), then
/// select it by code.
public struct GopayLocaleStrings: Equatable, Sendable {
    /// Card number field label. Web key `cc.pan.label`.
    public var panLabel: String
    /// Card number field placeholder (not localized in the web SDK).
    public var panPlaceholder: String
    /// Expiration field label. Web key `cc.exp.label`.
    public var expLabel: String
    /// Expiration field placeholder, e.g. `MM/YY`. Web key `cc.exp.placeholder`.
    public var expPlaceholder: String
    /// CVV field label (not localized in the web SDK).
    public var cvvLabel: String
    /// CVV field placeholder (not localized in the web SDK).
    public var cvvPlaceholder: String
    /// Pay-button label. Web key `cc.pay`. The SDK form has no button; exposed for host apps.
    public var pay: String
    /// Invalid card-number error message. Web key `cc.pan.error.pattern`.
    public var panErrorPattern: String
    /// Invalid expiration error message. Web key `cc.exp.error.pattern`.
    public var expErrorPattern: String
    /// Invalid CVV error message. Web key `cc.cvv.error.pattern`.
    public var cvvErrorPattern: String
    /// Generic "value has the wrong format" message. Web key `cc.patternErrorMessage`.
    public var patternErrorMessage: String
    /// Generic "this field is required" message. Web key `cc.requiredErrorMessage`.
    public var requiredErrorMessage: String
    /// Shown over the form while the screen is recorded or mirrored, when the form hides its
    /// fields (not localized in the web SDK, which has no such cover). Empty shows the cover alone.
    public var screenCaptureNotice: String

    /// Creates a complete set of localized form strings.
    public init(
        panLabel: String,
        panPlaceholder: String,
        expLabel: String,
        expPlaceholder: String,
        cvvLabel: String,
        cvvPlaceholder: String,
        pay: String,
        panErrorPattern: String,
        expErrorPattern: String,
        cvvErrorPattern: String,
        patternErrorMessage: String,
        requiredErrorMessage: String,
        screenCaptureNotice: String = ""
    ) {
        self.panLabel = panLabel
        self.panPlaceholder = panPlaceholder
        self.expLabel = expLabel
        self.expPlaceholder = expPlaceholder
        self.cvvLabel = cvvLabel
        self.cvvPlaceholder = cvvPlaceholder
        self.pay = pay
        self.panErrorPattern = panErrorPattern
        self.expErrorPattern = expErrorPattern
        self.cvvErrorPattern = cvvErrorPattern
        self.patternErrorMessage = patternErrorMessage
        self.requiredErrorMessage = requiredErrorMessage
        self.screenCaptureNotice = screenCaptureNotice
    }
}
