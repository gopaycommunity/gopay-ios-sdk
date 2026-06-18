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
    .package(url: "https://github.com/gopaycommunity/gopay-ios-sdk.git", from: "2.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "GopaySDK", package: "gpy-sdk-ios")
        ]
    )
]
```

### CocoaPods

```ruby
target 'YourApp' do
  use_frameworks!
  pod 'GopaySDK', '~> 2.0'
end
```

```bash
pod repo update
pod install
```

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

## Initialization

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

---

## Starting a payment session

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
    print("User dismissed Apple Pay / verification")
}
```

`chargeWithApplePay` derives the required `browser_data` from the device automatically; pass your
own `BrowserData` if you have more accurate values.

### Charging with a card token

When the user enters a card, the SDK encrypts it to a JWE (see below) that **your backend**
tokenizes via `POST /cards/tokens`. Your backend returns a card token, which you charge with:

```swift
let request = ChargePaymentRequest.cardToken(
    cardToken,
    browserData: await BrowserData.deviceDefault(),
    challengePreference: .auto,
    returnUrl: GopaySDK.chargeReturnURL   // lets handle3dsVerification detect completion
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

```swift
} catch let error as GopaySDKError {
    print("[\(error.code.rawValue)]", error.message)
}
```

User dismissal of the Apple Pay sheet or the 3DS WebView surfaces as `CancellationError`.

---

## Running the Example App

```bash
cd example
open example.xcodeproj
```

Select the `example` scheme, choose a simulator, and Run (⌘R). Fill in your `shareableKey` /
merchant `clientSecret` in `DemoConfig` (`exampleApp.swift`). The demo walks the whole flow:
create payment (simulated server) → start session → status → card-form→JWE → Apple Pay → 3DS →
charge state → QR.

---

## Maintainer Notes – Releasing New Versions

### Swift Package

```bash
git tag 2.0.0
git push origin 2.0.0
```

### CocoaPods

1. Set `spec.version` to `2.0.0` in `GopaySDK.podspec`.
2. Commit, tag, and push:

```bash
git add GopaySDK.podspec
git commit -m "Release 2.0.0"
git tag 2.0.0
git push origin main
git push origin 2.0.0
```

3. Publish:

```bash
pod lib lint GopaySDK.podspec --allow-warnings
pod trunk push GopaySDK.podspec --allow-warnings
```
