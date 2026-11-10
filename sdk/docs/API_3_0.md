# What 3.0 changes

3.0 gives the iOS and Android SDKs one public API: the same names, the same shape of data and
the same behaviour, so an integration reads the same on both and the React Native SDK can sit on
top of either. It also closes what the first integrations asked for: Android no longer needs an
Activity on every call, `PaymentSession` can be replaced in tests, and the wallet check has one
form. This list is the same in both SDKs.

A name that 2.x documented and 3.0 only renames stays in 3.0 as a deprecated alias that points
at the new name, so an integration written against 2.7 builds with warnings. What breaks a build
is listed under "Breaking" at the end.

## Renamed

The brand stays only in the entry point and in names that would be too general without it.

| | iOS 2.7 | Android 2.7 | 3.0 on both |
|---|---|---|---|
| Config | `GopaySDKConfig` | `GopayConfig` | `GopayConfig` |
| Debug logging | `enableDebugLogging` | `debug` | `debugLoggingEnabled` |
| Environment | `GopayEnvironment` | `Environment` | `GopayEnvironment` |
| Custom environment | `.development(baseURL:)` | `DEVELOPMENT(customUrl)` | `development(baseUrl)` in the platform's case style |
| API address | `baseURL` | `apiBaseUrl` | `baseUrl` |
| Error code | `code` | `errorCode` | `code` |
| HTTP status of an error | `httpStatus` | `getHttpStatusCode()` | `httpStatus` |
| Card form | `GopayCardForm` | `PaymentCardForm` | `PaymentCardForm` |
| Card form theme | `GopayCardFormTheme` | `PaymentCardFormTheme` | `PaymentCardFormTheme` |
| Validation mode | `GopayCardFormValidationDisplay` | `CardFormValidationDisplay` | `PaymentCardFormValidationDisplay` |
| Card data | `GopayCardData` | `CardData` | `CardData` |
| Return address | `returnURL`, `chargeReturnURL` | `returnUrl` | `returnUrl`, `chargeReturnUrl` |
| Result of `getStatus()` | `PaymentDetails` | `PaymentCreateResponse` | `PaymentDetails` |
| QR recipient | `QrRecipient` | `BankTransferRecipient` | `BankTransferRecipient` |
| QR recipient account | `QrRecipientBankAccount` | `RecipientBankAccount` | `RecipientBankAccount` |
| QR local account | `QrLocalBankAccount` | `BankAccountLocalDetails` | `BankAccountLocalDetails` |
| QR international account | `QrInternationalBankAccount` | `BankAccountInternationalDetails` | `BankAccountInternationalDetails` |
| QR recipient address | `QrRecipientAddress` | `RecipientAddress` | `RecipientAddress` |
| Hungarian QR code | `mnbQR` | `mnbQr` | `mnbQr` |
| `GopayLocales.register` | `(strings, for: code)` | `(code, strings)` | the code first, then the strings |

The error type keeps the name its platform expects: `GopaySDKError` on iOS, `GopaySDKException`
on Android.

## Deprecated

The platform names of the wallet, in favour of the names both SDKs share since 2.2:

- iOS `PaymentSession.getApplePayInfo()` and `chargeWithApplePay(browserData:challengePreference:)`;
  use `getWalletInfo()` and `chargeWithWallet(browserData:challengePreference:)`.
- Android `GopaySDK.isGooglePayAvailable(activity, info)`, `PaymentSession.getGooglePayInfo()` and
  `chargeWithGooglePay(activity, browserData, challengePreference)`; use `isWalletAvailable()`,
  `getWalletInfo()` and `chargeWithWallet(browserData, challengePreference)`.

iOS `GopaySDK.canUseApplePay()` stays as it is: a synchronous check a view can read, which the
`async` `isWalletAvailable()` cannot be.

## One shape on both platforms

- `isWalletAvailable`: a static call that takes no Activity, Context or environment. Android
  keeps its optional `info`. The Android forms of 2.x, the instance method with an Activity and
  the static one with a Context and the environment, are deprecated.
- Which fields are optional follows the API:
  - `PaymentDetails`: `orderNumber`, `gatewayUrl` and `customer` are always present. iOS gains
    `customer` and stops treating the other two as optional.
  - `QrPaymentDetails`: `recipient` and `qrCode` are always present, and so are the four fields
    of `BankAccountLocalDetails`. iOS stops treating them as optional, Android `recipient`.
  - `PaymentInstrumentData.details` is optional. iOS stops treating it as always present.
- An empty card form has its own error code, `VALIDATION_008`. `VALIDATION_007` stays for a
  form whose data is not valid. In 2.x both threw `VALIDATION_007` and differed only in the
  message.
- The "on submit" validation mode: today iOS takes a `Binding<Bool>` the host can raise itself,
  Android takes nothing. Both get the same shape, and the host can raise the flag on both.
- iOS `PaymentCardForm.isValid` is a `Binding<Bool>`, no longer `Binding<Bool?>`.
- The request timeout, which only Android had as `requestTimeoutMs`, is in the iOS config too,
  as `requestTimeout` in seconds.

## Added

- Android takes the Context in `GopaySDK.initialize(context, config)` and follows the current
  Activity itself. `chargeWithWallet`, `chargeWithCardToken`, `chargeWithEncryptedCard`,
  `handle3dsVerification` and `BrowserData.deviceDefault` get a form without an Activity; the
  forms with one, and `initialize(config)`, are deprecated.
- `PaymentSessionApi`: a protocol on iOS and an interface on Android that `PaymentSession`
  implements, so an app can put its own implementation in its tests.
- Public initializers for the response models on both platforms, `PaymentOutcome` included, so
  a test can build the value a call returns.

## Removed

Public only by accident, or deprecated in 2.x. Nothing here has a replacement to move to,
except where one is named.

Both platforms:

- `currentToken()`, `invalidateToken()` and `reauthenticate()` on `PaymentSession`. The session
  authenticates on its own.
- `ChargePaymentResponse.returnUrl`, deprecated in 2.x. `handle3dsVerification` takes the
  `callback.return_url` the backend created the payment with.
- `BrowserDataDetected`, which only the SDK reads.

iOS:

- `GopaySDKErrors`. The SDK throws `GopaySDKError` with a code; compare the code, not the
  message.
- `DefaultNetworkClient`, `JwtUtils`, and the deprecated `GopaySDKError.Code.configMissingParameter`
  (`CONFIG_003`).

Android:

- The old card form callbacks `onEncryptionComplete`, `onFormReady` and `onValidationError`, with
  `CardEncryptionResult` and `CardValidator.CardValidationResult`; use
  `GopaySDK.submitCardForm(formId)` and `clearCardFormData(formId)`.
- `NetworkConfig` and `GopaySDK.sslSocketFactory` / `trustManager` / `certificatePinner`.
- `JsonUtils`, `Base64Utils`, `JwtUtils`, `UrlUtils`, the validators and visual transformations of
  the card form, `HelperText`, `formatExpirationDate`, and the deprecated `GopayErrorCodes`
  constants the SDK never throws.
- `PaymentCreateRequest`, `PaymentCallback`, `AdditionalParam`, `CardFormUrl` and
  `InputFieldConfig.hasError`, which the SDK neither reads nor sends.
- `ApplePayHeader` and `PaymentCardInput.applePay`.
- The `GopaySDKException` constructor of 2.0.0 and the `PaymentCardForm` signatures of 2.1.0 and
  2.4.0, kept in the bytecode only for hosts built against an older 2.x.

## Fixed on the way

- Android checks `requestTimeoutMs` and rejects a value it cannot use.
- Android rejects an API address that carries credentials, as iOS does.
- Android telemetry knows the app's origin from `initialize` on.
- The wallet availability docs say that saved cards are not checked.
- The demo apps no longer print `payment_secret` or the encrypted card.

## Unchanged

The payment flow, every error code but the new `VALIDATION_008`, the manual wallet path
(Android `GooglePayHelper`, the iOS `applePay` card input), `GopayLocales`, the units of
`AwaitChargeOptions` (seconds on iOS, milliseconds in names ending `Ms` on Android), the
redirect of `handle3dsVerification` (`URL` on iOS, `String` on Android), and the entry point
(`GopaySDK.shared` on iOS, `GopaySDK.getInstance()` on Android).

What the React Native card form needs on top, validity per field, the form's own height and its
theme keys, comes with the React Native SDK.

## Breaking

What an integration written against 2.7 has to change before it builds:

- Android `Environment` is `GopayEnvironment`; an alias cannot cover `Environment.SANDBOX`.
- The fields under "One shape on both platforms" that changed between optional and always
  present.
- iOS `isValid` as `Binding<Bool>`, and the shape of the "on submit" validation mode.
- Code that tells an empty form from an invalid one by the error message: compare
  `VALIDATION_008` and `VALIDATION_007`.
- Everything under "Removed".
