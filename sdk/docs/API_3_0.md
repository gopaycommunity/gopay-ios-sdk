# What 3.0 changes

The 2.2 release added the API the iOS and Android SDKs share, next to the platform names it
replaces, and changed no existing name: the first integrations of 2.x should see no deprecation
warning. This list is where those platform names, and the rest of the public surface that 3.0
removes or unifies, are written down instead. It is the same list in both SDKs. No dates.

## Removed in 3.0

Platform names of the wallet, replaced by the shared names since 2.2:

- iOS `GopaySDK.canUseApplePay()`, `PaymentSession.getApplePayInfo()`,
  `PaymentSession.chargeWithApplePay(browserData:challengePreference:)`; use `isWalletAvailable()`,
  `getWalletInfo()`, `chargeWithWallet(browserData:challengePreference:)`.
- Android `GopaySDK.isGooglePayAvailable(activity, info)`, `PaymentSession.getGooglePayInfo()`, `PaymentSession.chargeWithGooglePay(activity, browserData, challengePreference)`;
  use `isWalletAvailable(activity, info)`, `getWalletInfo()`, `chargeWithWallet(activity, browserData, challengePreference)`.

The old Android card form callbacks, replaced by the `formId` model the iOS form has had since 2.0:

- `PaymentCardForm` `onEncryptionComplete`, `onFormReady`, `onValidationError`; use
  `GopaySDK.submitCardForm(formId)` and `clearCardFormData(formId)`.

Types public only by accident, which no integration needs:

- iOS `GopaySDKErrors` (the SDK throws `GopaySDKError` with a code; the members it still reads
  move inside; `jweError(_:)` and `jweDomain` are not thrown since 2.2, card encryption fails
  with `INTERNAL_001`), `DefaultNetworkClient` (the SDK cannot be given one), `JwtUtils`,
  `GopayCardForm.isValid` as `Binding<Bool?>` (becomes `Binding<Bool>`), the deprecated
  `GopaySDKError.Code.configMissingParameter` (`CONFIG_003`).
- Android `NetworkConfig` and `GopaySDK.sslSocketFactory` / `trustManager` / `certificatePinner`
  (cannot be set), `JsonUtils`, `Base64Utils`, `JwtUtils`, `UrlUtils`, the validators and visual
  transformations of the card form, `HelperText`, `formatExpirationDate`, the deprecated
  `GopayErrorCodes` constants the SDK never throws.
- Models neither SDK reads or sends: Android `PaymentCreateRequest`, `PaymentCustomer`,
  `PaymentCallback`, `AdditionalParam`, `CardFormUrl`, `InputFieldConfig.hasError`.

The token provider of `PaymentSession`, public only because an internal protocol needs it:

- `currentToken()`, `invalidateToken()`, `reauthenticate()` on both platforms. The session
  authenticates on its own; nothing an integration calls needs them.

## Unified in 3.0

Names and shapes that differ between the platforms today and change on one or both of them:

- The config and its fields: `GopaySDKConfig` / `GopayConfig`, `enableDebugLogging` / `debug`,
  the Android-only `requestTimeoutMs`.
- The environment: `GopayEnvironment.sandbox` / `.development(baseURL:)` and `baseURL` against
  `Environment.SANDBOX` / `DEVELOPMENT(customUrl)` and `apiBaseUrl`.
- The card data type: `GopayCardData` / `CardData`.
- The result of `getStatus()`: `PaymentDetails` / `PaymentCreateResponse`, their field names and
  which fields are optional.
- The QR payment models: names, `mnbQR` / `mnbQr`, and which fields are optional.
- `PaymentInstrumentData.details`: optional on one platform, not on the other.
- `handle3dsVerification`: `URL` on iOS, `String` on Android.
- `AwaitChargeOptions`: seconds on iOS, milliseconds on Android.
- `GopayLocales.register`: the order of its two arguments.
- The response models get a public initializer on iOS, as the Android data classes have.
