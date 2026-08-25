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

### Localizing the form

Form labels and placeholders are localized. By default the form uses the **device language and
falls back to Czech (`cs`)** when the language has no translation. 20 languages ship built in
(`bg cs de en es et fr hr hu it lt lv nl pl pt ro ru sk sl uk`).

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
| `.production` | *(empty)* | No URL configured |

`.production` resolves to an empty base URL, so calls fail with `unsupported URL`
(`NSURLErrorUnsupportedURL`). Pass the production gateway through `.development(baseURL:)` until a
real URL is set.

`GopayEnvironment.baseURL` is `public`, so a host app can read back the URL the SDK actually
resolved for `config.environment` instead of duplicating it elsewhere. The example app's
`MerchantBackendSimulator` does exactly this — it derives its own request base URL from
`GopaySDK.shared.config?.environment.baseURL` rather than from a separate constant, so a runtime
environment switch can never leave the simulated backend and the SDK pointed at different
gateways:

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
| `CONFIG_006` | The resolved base URL is not a valid URL |
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
cd example
open example.xcodeproj
```

Select the `example` scheme, choose a simulator, and Run (⌘R).

The app opens on a launcher with two destinations and an environment badge:

- **Demo checkout** — a realistic e-shop checkout (`CheckoutView`/`CheckoutViewModel`) that
  exercises every payment method — card form, Apple Pay, a saved card token, and bank transfer —
  through one consistent flow: create a payment, charge, and drive any 3DS challenge automatically
  as part of polling the charge to a terminal state. Each pay attempt creates a **fresh** payment,
  since a payment is single-use and a retry after a decline needs a new one.
- **Developer sandbox** (`ContentView`) — the original four-section console described below, for
  poking at each `PaymentSession` method individually and reading the raw JSON response.
- The **environment badge** at the bottom is tappable — switch between Development / Sandbox /
  Production at runtime. Switching closes any live session and re-initializes the SDK, so nothing
  keeps talking to the old gateway. The choice is **not persisted**; the app always starts on
  Development.

The demo's Development environment is meant to be pointed at whatever gateway you're testing
against — its base URL and credentials are freely editable in `DemoConfig.swift`. It ships pointed
at an internal gateway with working credentials, used primarily for contributing to this repo.
Sandbox and Production ship with **empty credential placeholders** — selecting them before filling
those in fails clearly at the gateway rather than silently mixing environments.

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
