# Gopay iOS SDK — Example App

A self-contained demo of the whole Payments 4.0 flow. It fakes the merchant backend in-app, and
shows the SDK two ways: as a realistic e-shop checkout, and as a raw call-by-call console.

## Prerequisites

- Xcode 16+ and an iOS 18.2+ simulator.
- Merchant credentials for the gateway you point the demo at.

## Running

From the repo root:

```bash
cp example/Config/Local.xcconfig.example example/Config/Local.xcconfig
open example/example.xcodeproj
```

Fill in `example/Config/Local.xcconfig` (see [Configuration](#configuration)), pick the `example`
scheme and Run (⌘R). You may also need to set your own signing team.

The `example` scheme is shared, so the app builds without opening Xcode:
`xcodebuild -project example/example.xcodeproj -scheme example -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' build`.

## Configuration

`example/Config/Local.xcconfig` is gitignored and holds the five values the demo needs.
[`Config/Demo.xcconfig`](Config/Demo.xcconfig) declares them with empty defaults and includes the
local file; the values reach the app through its Info.plist and are read in
[`DemoConfig.swift`](example/DemoConfig.swift).

```
GOPAY_DEMO_BASE_URL =
GOPAY_DEMO_CLIENT_ID =
GOPAY_DEMO_SHAREABLE_KEY =
GOPAY_DEMO_CLIENT_SECRET =
GOPAY_DEMO_GOID =
```

`GOPAY_DEMO_BASE_URL` picks the gateway. Leave it empty for the SDK's sandbox host, or set one of:

| Gateway | Base URL |
| --- | --- |
| Sandbox | `https:/$()/gw.sandbox.gopay.com/gp-gw/api/4.0/` |
| Production | `https:/$()/gate.gopay.com/gp-gw/api/4.0/` |

In an xcconfig a `//` starts a comment, even inside a value, hence the `$()` between the slashes.
A value runs to the end of the line; a missing trailing `/` is added.

`GOPAY_DEMO_CLIENT_SECRET` is a merchant secret, used here only by the in-app
`MerchantBackendSimulator`; never ship one in a real app.

## The launcher

The app opens on `RootView`: two destinations, and a tappable environment badge.

- **Demo checkout** → `CheckoutView` — see below.
- **Developer sandbox** → `ContentView` — the four-section console.
- The **environment badge** at the bottom shows the active gateway (`● SANDBOX
  gw.sandbox.gopay.com`) and opens a picker. Switching closes any live `PaymentSession` and
  re-initializes the SDK. The choice isn't persisted. Development appears in the picker only when
  `GOPAY_DEMO_BASE_URL` is set.

## Demo checkout

A deliberately ordinary-looking checkout (`CheckoutView` / `CheckoutViewModel`) for a fictional
shop, with a real cart total, that exercises every payment method the SDK offers:

- **Credit or debit card** — `GopayCardForm` (themed to match the shop) → `submitCardForm()` → a
  JWE → `charge(.encryptedCard)`. The PAN never touches this app's code.
- **Apple Pay** — `chargeWithApplePay()`. The row is hidden when `GopaySDK.canUseApplePay()` is
  `false`.
- **Saved card** — a known test card encrypted with `encryptCardData(_:)`, tokenized by
  `MerchantBackendSimulator` (simulating your server's `POST /cards/tokens`), then charged with
  `charge(.cardToken)`.
- **Bank transfer** — `getQrPaymentInfo(format: .png)` rendered as a scannable QR code plus account
  details, with a **Share** button that hands the QR image and a text summary to
  `UIActivityViewController`.

**Pay** creates a fresh payment, then runs every card-based method through the same tail: charge,
and if the response carries a 3DS `action.redirectUrl`, present the verification WebView and poll
`getChargeState()` until the gateway reports a terminal state. The result screen shows success,
failure (with "Try another method"), or pending (with a manual refresh), plus a collapsible
"Developer details" JSON dump of the last `ChargePaymentResponse`.

The **language picker** for the card form's labels sits inside the "Credit or debit card" row.
Twenty built-in languages plus a custom locale (`"xx"`, registered in `exampleApp.swift`) are
selectable there.

## Developer sandbox

Four sections, top to bottom. Sections 3 and 4 only appear once a session is live.

1. **Merchant backend (simulated)** — *Create payment on "server"* acquires a merchant token and
   creates a payment, filling in `payment_id` and `payment_secret`.
2. **Payment session** — *Start session* exchanges that pair for a payment-scoped JWT.
   *Close session* wipes the secret and token.
3. **Operations** — *Get status*, *Get Apple Pay info*, *Charge with Apple Pay*,
   *Get test card token (server)*, *Charge a payment*, *Get charge state*,
   *Handle 3DS verification*, *Get QR payment info*.
4. **Card form → JWE** — a locale picker, `GopayCardForm`, *Encrypt card → JWE*, and
   *Charge with encrypted card (JWE)*.

Every result, or a `GopaySDKError` with its code, is logged into the **Response** box at the bottom.

Apple Pay needs the Apple Pay capability and a Merchant ID entitlement added in Xcode, plus Apple
Pay in-app enabled for the merchant on the gateway. Completing a real authorization needs a
physical device with a test card in Wallet.

## Code references

- App entry: [`exampleApp.swift`](example/exampleApp.swift)
- Launcher + environment switcher: [`RootView.swift`](example/RootView.swift)
- Gateway and credentials: [`DemoConfig.swift`](example/DemoConfig.swift),
  [`Config/Demo.xcconfig`](Config/Demo.xcconfig)
- Demo checkout: [`Checkout/CheckoutView.swift`](example/Checkout/CheckoutView.swift),
  [`Checkout/CheckoutViewModel.swift`](example/Checkout/CheckoutViewModel.swift),
  [`Checkout/BankTransferSheet.swift`](example/Checkout/BankTransferSheet.swift),
  [`Checkout/CheckoutResultView.swift`](example/Checkout/CheckoutResultView.swift)
- Developer sandbox: [`ContentView.swift`](example/ContentView.swift)
- Simulated backend (token, create payment, card tokenization):
  [`MerchantBackendSimulator.swift`](example/MerchantBackendSimulator.swift)

For SDK API details see the top-level [README.md](../README.md).
