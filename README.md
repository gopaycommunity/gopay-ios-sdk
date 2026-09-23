# Gopay iOS SDK (`GopaySDK`)

## Overview

This repository contains the official **Gopay iOS SDK** and a simple example app.

The SDK implements the **Payments 4.0** per-payment session model:

- **Per-payment authentication** — the merchant backend creates a payment and hands the app a
  `payment_id` + `payment_secret`; the SDK exchanges that pair for a short-lived, payment-scoped
  JWT (`grant_type=payment_credentials`). Credentials and tokens are kept **in memory only** and
  never persisted.
- **Apple Pay** charging with an SDK-managed sheet.
- **3DS / PSD2 verification** via an SDK-managed WebView.
- **JWE card encryption** (RSA-OAEP-256 + A256GCM) — the SDK turns card data into a JWE that your
  backend tokenizes; the SDK never calls the tokenization endpoint itself.
- A secure **SwiftUI card form** (`GopayCardForm`) that keeps PAN/CVV inside the SDK.
- **Localized form labels** in 20 languages (device language, falling back to Czech), with
  per-form overrides and custom locale registration.
- **Concurrent payments** — multiple independent `PaymentSession`s, keyed by `payment_id`.

The public library product is named **`GopaySDK`** and targets **iOS 13+**. The API is built on
Swift **async/await**.

---

## Requirements

- **iOS**: 13.0 or later
- **Swift**: 5.5 or later (async/await)
- **Xcode**: 13.2 or later

---

## Installation

### Swift Package Manager (Xcode GUI)

- **File → Add Packages…**, enter `https://github.com/gopaycommunity/gopay-ios-sdk.git`, choose a
  version rule (e.g. **Up to Next Major**), and add the **`GopaySDK`** product to your app target.

### Swift Package Manager (`Package.swift`)

```swift
dependencies: [
    .package(url: "https://github.com/gopaycommunity/gopay-ios-sdk.git", from: "1.5.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "GopaySDK", package: "gopay-ios-sdk")
        ]
    )
]
```

### CocoaPods

```ruby
target 'YourApp' do
  use_frameworks!
  pod 'GopaySDK', '~> 1.5'
end
```

```bash
pod repo update
pod install
```

`1.5.0` is the newest published version — see the
[tags](https://github.com/gopaycommunity/gopay-ios-sdk/tags) for anything later.

---

## How it works

```
┌────────────┐   1. create payment (merchant creds)   ┌─────────────────┐
│  Your app  │ ─────────────────────────────────────▶ │  Your backend   │
│            │ ◀───────────────────────────────────── │ (merchant only) │
└────────────┘   2. payment_id + payment_secret        └─────────────────┘
      │
      │ 3. GopaySDK.shared.startPaymentSession(paymentId:paymentSecret:)
      ▼
┌──────────────────────────────────────────────────────────────────────┐
│ PaymentSession  →  getStatus / chargeWithApplePay /                    │
│                    handle3dsVerification / getChargeState / getQrInfo  │
└──────────────────────────────────────────────────────────────────────┘
```

Payment **creation** uses merchant credentials and must happen on **your server** — the mobile SDK
never sees the merchant secret and cannot create payments. The example app includes a
`MerchantBackendSimulator` that fakes this server so the demo is self-contained; do not ship it.

---

## Quick start

### Initialize

Initialize once on app start. `clientId` + `shareableKey` are safe to embed — they only authorize
the public `GET /cards/public-key` endpoint, never charging.

```swift
import GopaySDK

GopaySDK.shared.initialize(
    with: GopaySDKConfig(
        environment: .sandbox,                 // or .development(baseURL:) / .production
        clientId: "<your-client-id>",
        shareableKey: "<your-shareable-key>",
        enableDebugLogging: true,
        errorCallback: { error in print("GopaySDK error:", error) }
    )
)
```

`GopaySDK.version` returns the SDK's own version (e.g. `"1.5.0"`) — a compiled-in constant rather
than an Info.plist lookup, since under SPM the SDK links statically into the host app and
`Bundle(for:)` would otherwise report the *host app's* version instead.

---

### Start a session and charge

```swift
// `paymentId` and `paymentSecret` come from your backend after it created the payment.
let session = try await GopaySDK.shared.startPaymentSession(
    paymentId: paymentId,
    paymentSecret: paymentSecret
    // scope defaults to PaymentSession.defaultScope == "payment:charge payment:read"
)
```

`startPaymentSession` authenticates eagerly, so invalid credentials throw right away
(`GopaySDKError` with code `AUTH_010`). At most one live session per `payment_id` exists at a time;
reuse it via `await GopaySDK.shared.getPaymentSession(paymentId)`. When done:

```swift
await session.close() // wipes the in-memory secret + token, unregisters the session
```

---

## `PaymentSession` API

All methods are `async throws` and run through the session's payment-scoped token (re-acquired
automatically once on a 401).

```swift
// Status
let details = try await session.getStatus()                 // GET /payments/{id}
print(details.state, details.amount, details.currency)

// Charge state
let charge = try await session.getChargeState()             // GET /payments/{id}/charge

// QR (bank transfer) info
let qr = try await session.getQrPaymentInfo(format: .png)   // GET /payments/{id}/qr-payment/info

// Apple Pay config (for building a sheet manually, if needed)
let appInfo = try await session.getApplePayInfo()           // GET /payments/{id}/apple-pay/app-info
```

### Charging with Apple Pay

```swift
guard GopaySDK.canUseApplePay() else { /* hide the Apple Pay button */ return }

do {
    let charge = try await session.chargeWithApplePay()     // presents the Apple Pay sheet
    if let redirect = charge.action?.redirectUrl, let url = URL(string: redirect) {
        try await session.handle3dsVerification(redirectURL: url)   // presents the 3DS WebView
        let final = try await session.getChargeState()
        print("Final state:", final.state)
    } else {
        print("Charge state:", charge.state)
    }
} catch is CancellationError {
    print("User dismissed the 3DS verification")
} catch {
    // Dismissing the Apple Pay sheet lands here, not in the CancellationError branch
    print("Charge failed or Apple Pay was dismissed:", error.localizedDescription)
}
```

`chargeWithApplePay` derives the required `browser_data` from the device automatically; pass your
own `BrowserData` if you have more accurate values.

### Browser data / User-Agent

`BrowserData.deviceDefault()` is `async` because `user_agent` is read from a real, hidden
`WKWebView` (`navigator.userAgent`) rather than synthesized — the value the issuer sees in the 3DS
AReq then matches, byte for byte, the WebView that actually renders the challenge
(`GopayChargeVerificationViewController`). The lookup runs once per process: the result is cached,
concurrent callers share one in-flight resolution, and `initialize(with:)` prewarms it so the first
charge doesn't pay the WebView-construction latency. If the lookup ever fails, it falls back to
`BrowserData.syntheticUserAgent()` — a plausible UA built from `UIDevice` — rather than sending
`nil`.

```swift
let browserData = await BrowserData.deviceDefault()
```

### Charging with a card token

When the user enters a card, the SDK encrypts it to a JWE (see below) that **your backend**
tokenizes via `POST /cards/tokens`. Your backend returns a card token, which you charge with:

```swift
let request = ChargePaymentRequest.cardToken(
    cardToken,
    browserData: await BrowserData.deviceDefault(),
    challengePreference: .auto
)
let charge = try await session.charge(request)
if let redirect = charge.action?.redirectUrl, let url = URL(string: redirect) {
    try await session.handle3dsVerification(redirectURL: url)
}
```

### Charging with an encrypted card (JWE)

If you don't need a reusable card token, charge the JWE directly with the `ENCRYPTED_CARD`
input — this skips the server-side `POST /cards/tokens` round-trip. Encrypt the card (via
`submitCardForm()` or `encryptCardData(_:)`, see below) and pass the resulting JWE as `payload`:

```swift
let jwe = try await GopaySDK.shared.submitCardForm()   // or encryptCardData(_:)
let request = ChargePaymentRequest.encryptedCard(
    jwe,
    browserData: await BrowserData.deviceDefault(),
    challengePreference: .auto
)
let charge = try await session.charge(request)
if let redirect = charge.action?.redirectUrl, let url = URL(string: redirect) {
    try await session.handle3dsVerification(redirectURL: url)
}
```

---

## Card form → JWE

`GopayCardForm` keeps PAN/CVV inside the SDK. Submitting it returns a **JWE** (RFC 7516) that you
forward to your backend for server-side tokenization — the SDK never calls `/cards/tokens`.

```swift
import SwiftUI
import GopaySDK

struct PaymentView: View {
    @State private var isCardValid: Bool? = nil

    var body: some View {
        VStack(spacing: 16) {
            GopayCardForm(isValid: $isCardValid)

            Button("Pay") {
                Task {
                    do {
                        let jwe = try await GopaySDK.shared.submitCardForm()
                        // POST `jwe` to your backend, which calls POST /cards/tokens and
                        // returns a card token you then charge with session.charge(...).
                    } catch {
                        print("Encryption failed:", error)
                    }
                }
            }
            .disabled(!(isCardValid ?? false))
        }
        .padding()
    }
}
```

You can also encrypt card data you collected yourself:

```swift
let jwe = try await GopaySDK.shared.encryptCardData(
    GopayCardData(cardPan: "...", expMonth: "12", expYear: "30", cvv: "123")
)
```

`GopayCardForm` accepts a `GopayCardFormTheme` and a `formId` (when multiple forms are on screen,
pass the same `formId` to `submitCardForm(formId:)`).

The SDK clears the form's card data from memory after a successful `submitCardForm()` and when
the form disappears — so call `submitCardForm()` while the form is on screen and forward the
JWE promptly. The gateway accepts each JWE **once** and its payload expires 10 minutes after
creation; to retry a failed charge, have the user confirm the card again (any edit re-syncs the
form's data and the next `submitCardForm()` succeeds). To wipe the data early — e.g. when the
user abandons checkout while the form is still on screen — call
`GopaySDK.shared.clearCardFormData()`. Discard the JWE once your backend has tokenized it.

### Theming the form

**An untouched form looks like an iOS form.** The system font and colors, a plain bordered field,
sentence-case labels, ordinary spacing. The web card form is a page of its own and can afford a look
of its own; this one sits inside your screen, so you should never have to undo an SDK style to make
it fit. Theming is fully available, it is simply a choice rather than the starting point.

`GopayCardFormTheme` is **a subset of the GoPay web card form theme (cc-v4)**, carrying its
parameter names, so one design decision can be written down once and applied on the web, on iOS and
on Android. The subset is the part a native field can carry: every parameter is a property of the
text field itself or of the layout around it, and the SDK draws nothing of its own. The web keys
that only a custom-drawn form could honour are listed below, with what happens instead.

```swift
// Nothing here is required; each line moves the form one step away from the platform default.
GopayCardForm(
    theme: GopayCardFormTheme(
        labelUppercase: true,
        inputBorderColor: Color(red: 0.41, green: 0.52, blue: 0.57),
        inputBorderRadius: 0,
        inputPaddingHorizontal: 0,
        errorMinHeight: 14
    ),
    validation: .live,
    isValid: $isCardValid
)
```

These 29 parameters are the same on Android, name for name and type for type, so a design decided
once reads the same on both. One thing is Android's alone: it adds `helperTextColor` and
`helperFontSize` for a helper line neither the web form nor this SDK renders.

On iOS 13 the text inside an input keeps the system colors: `inputTextColor` and
`placeholderColor` reach a `UITextField`, and converting a SwiftUI `Color` to a `UIColor` needs
iOS 14. Everything drawn by SwiftUI itself, including the labels, the border and the error text,
is themed on iOS 13 as well.

#### Parity with the web theme

Every key of the web card form theme, what it does here, and the value you get when you leave it
alone. The parameters mirror Android name for name and type for type, with one exception:
`fontFamily` is a string here and resolves at render, while Android takes a typed `FontFamily`.

| Web key | iOS parameter | iOS default | Web default |
| --- | --- | --- | --- |
| `fontFamily` | `fontFamily` | `nil` (system font) | `system-ui` |
| `labelColor` | `labelColor` | `.primary` | `#4b5e68` |
| `labelFontSize` | `labelFontSize` | `12` (caption) | `11` |
| `labelFontWeight` | `labelFontWeight` | `400` | `600` |
| `labelLineHeight` | `labelLineHeight` | `nil` (font metrics) | unset |
| `labelUppercase` | `labelUppercase` | `false` | `true` |
| `labelLetterSpacing` | `labelLetterSpacing` | `nil` (none) | unset (`0.06em`) |
| `labelHidden` | `labelHidden` | `false` | `false` |
| `inputTextColor` | `inputTextColor` | `.primary` | `#4b5e68` |
| `inputFontSize` | `inputFontSize` | `17` (body) | `14` |
| `inputFontWeight` | `inputFontWeight` | `nil` (regular) | unset |
| `inputHeight` | `inputHeight` | `nil` (font decides) | unset |
| `placeholderColor` | `placeholderColor` | `nil` (system) | browser default |
| `inputBorderStyle` | `inputBorderStyle` | `.boxed`; `underline` renders as `boxed` | `underline` |
| `inputBorderColor` | `inputBorderColor` | `Color(.separator)` | `#698492` |
| `inputBorderWidth` | `inputBorderWidth` | `1` | `1` |
| `inputBackgroundColor` | `inputBackgroundColor` | `.clear` | `transparent` |
| `inputPaddingVertical` | `inputPaddingVertical` | `12` | `6` |
| `inputPaddingHorizontal` | `inputPaddingHorizontal` | `12` | `0` |
| `inputBorderRadius` | `inputBorderRadius` | `5` (rounded-rect field) | `0` |
| `inputErrorBorderColor` | `inputErrorBorderColor` | `.red` | `#ea3c55` |
| `errorTextColor` | `errorTextColor` | `.red` | `#cc0000` |
| `errorFontSize` | `errorFontSize` | `12` (caption) | `11` |
| `errorMinHeight` | `errorMinHeight` | `0` (no reserve) | `14` |
| `errorSpacing` | `errorSpacing` | `nil` (`fieldSpacing`) | unset (`fieldSpacing`) |
| `inputLineHeight` | — | web-only | unset |
| `inputLetterSpacing` | — | web-only | unset |
| `inputBorderCollapse` | — | web-only | `false` |
| `focusRingWidth` | — | web-only | unset |
| `focusRingColor` | — | web-only | unset |
| `focusGradientStart` | — | web-only | `#19C7D6` |
| `focusGradientEnd` | — | web-only | `#1899D6` |
| `errorHidden` | — | web-only | `false` |
| `groupSpacing` | `groupSpacing` | `16` | `16` |
| `fieldSpacing` | `fieldSpacing` | `4` | `4` |
| `formPadding` | `formPadding` | `0` (the host lays it out) | `16` |
| `formBackgroundColor` | `formBackgroundColor` | `.clear` | `transparent` |
| `submitBackgroundColor` | — | web-only | `#1899d6` |
| `submitHoverBackgroundColor` | — | web-only | `#1482ba` |
| `submitDisabledBackgroundColor` | — | web-only | `#a8b6bd` |
| `submitTextColor` | — | web-only | `#ffffff` |
| `submitDisabledTextColor` | — | web-only | `#ffffff` |
| `submitBorderRadius` | — | web-only | `4` |
| `submitFontSize` | — | web-only | `14` |

The web-only keys have no counterpart here, each for its own reason:

- The seven `submit*` keys style a button this SDK never draws. Submission is yours: you own the
  button and call `submitCardForm()`. That is the same arrangement as the web form's
  `submitMode: 'external'`, where the iframe hides its own button too.
- `errorHidden` is already a first-class parameter of the form, not of the theme: the default
  `validation: .hidden` renders no inline errors and hands you the state through the `isValid`
  binding. Web `errorHidden: true` is the iOS default.
- `focusGradientStart`, `focusGradientEnd`, `focusRingWidth`, `focusRingColor` and
  `inputBorderCollapse` all describe something a browser paints around a field: a gradient, a glow
  outside the frame, one shared line between two neighbours. A native text field has none of them,
  and neither SDK draws its own. A focused field is marked the way the platform marks it, with the
  caret and the keyboard.
- `inputLetterSpacing` would have to override how the field measures itself, which is exactly the
  kind of reach into the platform this theme avoids. `labelLetterSpacing` stays, because a label is
  ordinary text.
- `inputLineHeight` pins the height of a field across browser engines. A single-line native field
  has no such problem; `inputHeight` is here to set a minimum.

They are simply not parameters of this type, so the compiler says so where you would have set
them.

The iOS column is what the platform would do on its own, which is why it differs from the web
column: the defaults are not a GoPay style, they are the absence of one. To move towards the web
appearance, pass the web values; the demo app's `ThemeShowcase.swift` shows how far that gets, and
it cannot get all the way, because the web's default underline is not a shape a native field draws.

`inputBorderStyle` is the one parameter the web and the mobile SDKs read differently. It stays in
the type so every channel names the styles the same way, but **neither mobile platform has a native
underlined text field and neither SDK draws one, so `underline` is accepted and the input renders
as `boxed`**.

The one default worth overriding deliberately is `placeholderColor`: unset, it follows the system's
light or dark appearance rather than the theme's, so a theme that paints the form dark should set a
placeholder color of its own or the hint text can come out dark on a dark field. The demo's `Dark`
theme shows it.

A few deviations are behavioral rather than default values:

- `labelFontWeight` and `inputFontWeight` are rounded to the nearest hundred, because `Font.Weight`
  has nine steps. A weight of 450 renders as 500 here; Android passes it through to a variable font.
- `labelLetterSpacing` needs iOS 16, and it is not derived from the font size the way the web
  derives its `0.06em`.
- The border runs inside the field, so raising `inputBorderWidth` thickens the frame inwards and
  never changes how much room the form takes. It stops at half the field's height, past which a
  border would have nothing left to enclose.
- `inputHeight` is the smallest height of the input, with the vertical padding inside it rather
  than on top of it. It is a minimum, not the fixed height it is on the web, so a large font scale
  can still grow the field rather than overflow it. Android reads it the same way. A value of zero
  or less is unset.

#### The error and focus states

A field's border has two colors:

- valid: `inputBorderColor`
- invalid: `inputErrorBorderColor`

The error border only appears while the form draws inline errors at all, so with the default
`validation: .hidden` nothing about the border changes.

Neither platform marks the active field with its frame. A native text field marks focus with the
caret and the keyboard, and any more than that is something the SDK would have to paint itself, so
it does not. There is no theme parameter for it on either.

#### Migrating a 1.x theme

Version 2.0 renamed every parameter and split the composite ones. There are no aliases: a 1.x theme
stops compiling, and the table below says what to write instead. The values carry over as they are,
and 2.0 keeps almost all of the platform defaults 1.x had, so a mechanical rename leaves the form
looking much as it did. **One default changed**: `inputBackgroundColor` is now `.clear` where 1.x
filled the inputs with `Color(.systemBackground)`, so the surface behind the form shows through.
Set it back explicitly if your layout relied on the opaque fill.

| 1.x | 2.0 |
| --- | --- |
| `textColor` | `labelColor` and `inputTextColor` |
| `backgroundColor` | `inputBackgroundColor` |
| `borderColor` | `inputBorderColor` |
| `focusedBorderColor` | removed — the border no longer changes color on focus |
| `errorColor` | `errorTextColor` |
| `borderWidth` | `inputBorderWidth` |
| `cornerRadius` | `inputBorderRadius` |
| `labelFont` | `labelFontSize` and `labelFontWeight` (and `fontFamily`) |
| `font` | removed — it never reached the inputs; `fontFamily`, `inputFontSize` and `inputFontWeight` style them now |
| `spacing` | `groupSpacing` |
| `textFieldPadding` | `inputPaddingVertical` and `inputPaddingHorizontal` |

The cut to native rendering removed seven keys that 1.x never had but the 2.0 branch did carry for
a while. They are gone from the type, so setting one is a compile error rather than a surprise.

| Removed in 2.0 | Instead |
| --- | --- |
| `inputBorderCollapse` | nothing: adjacent native fields cannot share a border |
| `focusRingWidth`, `focusRingColor` | nothing: the platform marks the active field |
| `focusGradientStart`, `focusGradientEnd` | nothing: the platform marks the active field |
| `inputLetterSpacing` | `labelLetterSpacing` still applies to labels |
| `inputLineHeight` | `inputHeight` to set a minimum height |

Two behaviors change. An invalid field now takes `inputErrorBorderColor` on its border, which an
integration only sees while it renders inline errors; on the default `validation: .hidden` nothing
changes. And a focused field no longer recolors its border at all, which 1.x did through
`focusedBorderColor`.

### Localizing the form

Form labels and placeholders are localized. By default the form uses the **device language and
falls back to Czech (`cs`)** when the language has no translation. 20 languages ship built in
(`bg cs de en es et fr hr hu it lt lv nl pl pt ro ru sk sl uk`). The strings are identical to the
Android SDK's, so a screen reads the same on both.

The expiration label sits in a half-width column, so the translations are kept short enough to fit
on one line at the default text size on a 360pt screen. At the accessibility text sizes a long one
can still wrap onto a second line, which pushes the label above it rather than being cut off; the
inputs of the row keep their shared height either way.

Set a preferred locale globally on the config, or per form:

```swift
// Global default for every form (nil = follow the device language)
GopaySDK.shared.initialize(with: GopaySDKConfig(environment: .sandbox, locale: "de"))

// Per-form override (wins over the global default)
GopayCardForm(locale: "cs", isValid: $isCardValid)
```

Add your own translation with the same structure and select it by code:

```swift
var brandEnglish = GopayLocales.en
brandEnglish.panLabel = "Your card number"

GopaySDK.shared.initialize(
    with: GopaySDKConfig(environment: .sandbox, customLocales: ["en": brandEnglish])
)
// or at runtime: GopayLocales.register(brandEnglish, for: "en")
GopayCardForm(locale: "en", isValid: $isCardValid)
```

Validation error strings are localized too. The form can render them inline for you — choose when
with the `validation` parameter:

```swift
// Errors appear only after the user taps your submit button (mirrors the Android example):
@State private var attemptedSubmit = false
GopayCardForm(locale: "cs", validation: .onSubmit(attempted: $attemptedSubmit), isValid: $isCardValid)
// …then in your submit action: attemptedSubmit = true

// Or validate live as the user types:
GopayCardForm(locale: "cs", validation: .live, isValid: $isCardValid)
```

`.onSubmit` shows the localized required/pattern message for every invalid field while `attempted`
is `true`; `.live` shows a field's error once it holds non-empty, invalid content. The default is
`.hidden` — the form renders nothing and you display errors yourself from the resolved locale:

```swift
let strings = GopaySDK.shared.currentLocaleStrings(preferred: "cs")
// strings.panErrorPattern, strings.expErrorPattern, strings.cvvErrorPattern, …
```

---

## Environments

| Environment | Base URL | Status |
| --- | --- | --- |
| `.development(baseURL:)` | whatever you pass in | Use this |
| `.sandbox` | `https://gw.sandbox.gopay.com/gp-gw/api/4.0/` | Works |
| `.production` | `https://gate.gopay.com/gp-gw/api/4.0/` | Live payments |

`.sandbox` and `.production` carry their own hosts, so nothing needs configuring for them. Only
`.development(baseURL:)` takes a URL, and it has to be an absolute `http(s)` one: an empty or
scheme-less value is logged at `initialize(with:)` and fails every call with `CONFIG_006`.

`GopayEnvironment.baseURL` is `public`, so a host app can read back the URL the SDK actually
resolved for `config.environment` instead of duplicating it elsewhere. The example app's
`MerchantBackendSimulator` does exactly this — it derives its own request base URL from
`GopaySDK.shared.config?.environment.baseURL` rather than from a separate constant, so the
simulated backend and the SDK can never end up pointed at different gateways:

```swift
let baseURL = GopaySDK.shared.config?.environment.baseURL ?? ""
```

---

## Error handling

Session and config failures throw `GopaySDKError`, which carries a stable `code` (matching the
Android SDK) and a message:

| Code | Meaning |
|---|---|
| `AUTH_009` | Payment token expired and couldn't be re-acquired |
| `AUTH_010` | `payment_id` / `payment_secret` rejected |
| `AUTH_011` | `clientId` / `shareableKey` missing for a public-endpoint call |
| `AUTH_012` | A session for this `payment_id` already exists |
| `AUTH_013` | Operation on a closed session |
| `PAYMENT_008` | A 3DS verification is already in progress |
| `PAYMENT_009` | An Apple Pay sheet is already in progress |
| `NETWORK_002` | Gateway returned 4xx |
| `NETWORK_003` | Gateway returned 5xx |
| `CONFIG_001` | `initialize(with:)` was never called |
| `CONFIG_003` | A required configuration parameter is missing |
| `CONFIG_006` | The resolved base URL is empty, or not an absolute `http(s)` URL |
| `VALIDATION_007` | Invalid input — empty ids, or card-form validation failed |
| `INTERNAL_001` | Unexpected internal error |
| `INTERNAL_003` | Response could not be decoded |

```swift
} catch let error as GopaySDKError {
    print("[\(error.code.rawValue)]", error.message)
}
```

Dismissing the 3DS WebView surfaces as `CancellationError`. Dismissing the **Apple Pay** sheet
does not — it throws a `GopaySDK` `NSError` carrying "Apple Pay payment was cancelled by the
user.", so a `catch is CancellationError` branch alone will not catch it.

Every code above, with its causes and what to do about it, is in
[`sdk/docs/ERROR_CODES.md`](sdk/docs/ERROR_CODES.md). The codes are shared with the Android SDK —
the iOS surface throws the subset listed there.

---

## Example app

```bash
cp example/Config/Local.xcconfig.example example/Config/Local.xcconfig
open example/example.xcodeproj
```

Fill in `example/Config/Local.xcconfig`, then select the `example` scheme, choose a simulator, and
Run (⌘R).

The app opens on a launcher with two destinations and an environment badge:

- **Demo checkout** — a realistic e-shop checkout (`CheckoutView`/`CheckoutViewModel`) that
  exercises every payment method — card form, Apple Pay, a saved card token, and bank transfer —
  through one consistent flow: create a payment, charge, and drive any 3DS challenge automatically
  as part of polling the charge to a terminal state. Each pay attempt creates a **fresh** payment,
  since a payment is single-use and a retry after a decline needs a new one.
- **Developer sandbox** (`ContentView`) — the original four-section console described below, for
  poking at each `PaymentSession` method individually and reading the raw JSON response.
- The **environment badge** at the bottom names the gateway both surfaces talk to. It is a
  read-only indicator: `GOPAY_DEMO_BASE_URL` decides the environment at launch and it stays put
  for the whole run, so the label can never disagree with what the SDK is actually using.

`GOPAY_DEMO_BASE_URL` in `Local.xcconfig` picks the gateway: empty uses the SDK's sandbox host, a
URL selects Development and points it there. The other four keys are the merchant credentials.

The Developer sandbox has four sections — **1.** simulated merchant backend, **2.** payment
session, **3.** operations (status, Apple Pay, card token, charge, charge state, 3DS, QR), and
**4.** card form → JWE. Sections 3 and 4 appear once a session is live.

See [`example/README.md`](example/README.md) for the full walkthrough.

---

## Security notes

- `payment_secret` and the payment-scoped JWT live in memory only — never written to disk, and
  wiped by `close()`.
- `GopayCardForm` keeps PAN and CVV inside the SDK; you only ever receive a JWE.
- Card data lives in memory only while the form needs it: the SDK's copy is dropped after a
  successful `submitCardForm()`, when the form disappears, and on demand via `clearCardFormData()`
  (PCI DSS 4.0.1, req. 3.3.1 — SAD must not be retained once no longer needed). Swift strings
  cannot be securely overwritten, so this releases the references rather than zeroing bytes.
- Card data is encrypted with RSA-OAEP-256 + A256GCM using the merchant public key.
- Payment creation needs merchant credentials and must stay on your server; the SDK cannot create
  payments and never sees the merchant secret.

## Testing

```bash
cd sdk
xcodebuild test -project sdk.xcodeproj -scheme sdk \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The tests live in `sdk/sdkTests` and run through the `sdk` Xcode project — `Package.swift`
declares no test target, so `swift test` will not find them.

## Releasing

Releases are cut by **semantic-release** on `master`: it derives the version from the commit
messages, bumps `package.json`, rewrites `CHANGELOG.md`, and creates and pushes the git tag.
commitlint enforces conventional commits with a `GPMOB-` reference, so the commit message is what
picks the next version. Don't tag by hand — SPM consumers resolve the tag semantic-release made.

`@semantic-release/exec` runs [`scripts/set-version.sh`](scripts/set-version.sh) as part of that
same release, which rewrites `spec.version` in `GopaySDK.podspec` and the `GopaySDK.version`
constant in [`sdk/sdk/GopaySDK.swift`](sdk/sdk/GopaySDK.swift) to match — both are committed by
`@semantic-release/git` alongside `CHANGELOG.md` and `package.json`, so a release can't leave them
out of sync the way the podspec used to drift. Run it by hand if you ever need to (e.g. to check
what a release would rewrite):

```bash
./scripts/set-version.sh 1.6.0
```

CocoaPods publishing itself is not automated — after a release, push the podspec:

```bash
pod spec lint GopaySDK.podspec --allow-warnings   # validates against the remote tag
pod trunk push GopaySDK.podspec --allow-warnings
```

Use `pod spec lint`, not `pod lib lint` — the latter only checks local sources and passes even when
`spec.version` points at a tag that doesn't exist.

---

## License

MIT — see [`LICENSE`](LICENSE). `GopaySDK.podspec` declares the same.
