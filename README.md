# Gopay iOS SDK (`GopaySDK`)

[![CocoaPods](https://img.shields.io/cocoapods/v/GopaySDK)](https://cocoapods.org/pods/GopaySDK)
[![semantic-release: angular](https://img.shields.io/badge/semantic--release-angular-e10079)](https://github.com/semantic-release/semantic-release)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

iOS SDK for charging GoPay payments from a mobile app, for the GoPay Payments 4.0 API:
[API documentation](https://api-docs.gopay.com/en/api),
[OpenAPI specification](https://api-docs.gopay.com/spec/en/payments.yaml),
[`GopaySDK` on CocoaPods](https://cocoapods.org/pods/GopaySDK).

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
- **One API with the Android SDK** — the card charges, the wallet and the card form have the
  same names and shapes on both platforms since 2.2 (see [Shared API](#shared-api-with-android)).

The public library product is named **`GopaySDK`** and targets **iOS 13+**. The API is built on
Swift **async/await**.

---

## Requirements

- **iOS**: 13.0 or later
- **Swift**: 5.7 or later
- **Xcode**: 14 or later, the first with Swift 5.7

To ship to the App Store you need Xcode 26 anyway: App Store Connect has accepted only apps built
with it since April 28, 2026 ([Apple](https://developer.apple.com/news/upcoming-requirements/)).
The SDK is built and tested with Xcode 26.

---

## Installation

### Swift Package Manager (Xcode GUI)

- **File → Add Packages…**, enter `https://github.com/gopaycommunity/gopay-ios-sdk.git`, choose a
  version rule (e.g. **Up to Next Major**), and add the **`GopaySDK`** product to your app target.

### Swift Package Manager (`Package.swift`)

```swift
dependencies: [
    .package(url: "https://github.com/gopaycommunity/gopay-ios-sdk.git", from: "2.2.0")
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
  pod 'GopaySDK', '~> 2.2'
end
```

```bash
pod repo update
pod install
```

The badge at the top of this README shows the latest version on
[CocoaPods](https://cocoapods.org/pods/GopaySDK).

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
│ PaymentSession  →  chargeWithCardToken / chargeWithEncryptedCard /     │
│                    chargeWithWallet / awaitChargeState /               │
│                    getStatus / getChargeState / handle3dsVerification / │
│                    getQrPaymentInfo                                    │
└──────────────────────────────────────────────────────────────────────┘
```

Payment **creation** uses merchant credentials and must happen on **your server** — the mobile SDK
never sees the merchant secret and cannot create payments. The example app includes a
`MerchantBackendSimulator` that fakes this server so the demo is self-contained; do not ship it.

---

## Your backend

The SDK charges a payment your server has created and settles nothing on its own. What your server
does, as the GoPay guide describes it
([Security and credentials](https://api-docs.gopay.com/en/docs/01-security.md),
[Payment states and lifecycle](https://api-docs.gopay.com/en/docs/02-payment-lifecycle.md),
[Saved cards](https://api-docs.gopay.com/en/docs/05-saved-cards.md)). The paths are relative to
the gateway host, `https://gw.sandbox.gopay.com/gp-gw/api/4.0/` on the sandbox and
`https://gate.gopay.com/gp-gw/api/4.0/` in production (see [Environments](#environments)), the
same gateway the app talks to. A payment exists only on the gateway it was created on.

1. **Get a merchant access token** with `POST /oauth2/token`: your `client_id:client_secret` as
   HTTP Basic and a form body with `grant_type=client_credentials` and the scopes you need,
   `payment:write` and `payment:read`, plus `card:write` to save cards. The token is a JWT,
   currently valid for 15 minutes; read `expires_in`. The client secret stays on your server; the
   app never sees it.
2. **Create the payment** with `POST /eshops/{goid}/payments`, under that token. The body needs
   `amount`, `currency`, `order_number`, `customer` and `callback`. `amount` is an integer in the
   currency's minor unit: 100.00 CZK is `10000`.
3. **Set both callback URLs.** `callback.return_url` and `callback.notification_url` are required.
   According to the GoPay guide both must be absolute HTTPS URLs; in production a `return_url`
   that is not HTTPS gets a 403 when the payment is created, the sandbox is more tolerant. The
   3DS screen closes when the challenge comes back to `return_url` (see
   [3DS verification](#3ds-verification)), so the URL does not have to serve anything to the app.
   `notification_url` must be reachable from GoPay's servers.
4. **Give the app `id`, `payment_secret` and the `callback.return_url`** you created the payment
   with, nothing else; `id` is the payment id the SDK calls `paymentId`. The app passes the first
   two to `startPaymentSession` and the return URL to `awaitChargeState` or
   `handle3dsVerification`. GoPay is removing `return_url` from the charge response, so the app
   should get it only from you. According to the GoPay guide, `payment_secret` must not be
   stored, logged or put in a URL, and it is valid for seven days, after which the gateway refuses
   it with a 403.
5. **Settle the payment on the server.** What the app reports is not proof of payment. GoPay
   sends a `GET` to `notification_url` with the payment `id` on every state change; answer `204`
   and read the payment with `GET /payments/{id}`. The GoPay guide treats this webhook as the
   authoritative signal. A payment nobody charges times out, after one hour by default.
6. **Save a card, if you need to,** by exchanging the JWE from the card form for a permanent token
   with `POST /cards/tokens` (merchant scope `card:write`). Tokenization is off until GoPay enables
   it for you through `integration@gopay.com`. A JWE is single-use: it pays one charge or makes one
   token, not both. An Apple Pay payload cannot be tokenized.

The example app's [`MerchantBackendSimulator`](example/example/MerchantBackendSimulator.swift)
makes the token, payment and tokenization calls from the app, so that the demo runs on its own.
Read it as a sketch of these requests; the merchant secret it needs must never ship in an app.

---

## Quick start

Your backend creates the payment first and hands the app its `id` (the API's `payment_id`),
`payment_secret` and the return URL; the calls it makes are in [Your backend](#your-backend).
Cards to try are in [Testing on the sandbox](#testing-on-the-sandbox).

### Initialize

Initialize once on app start. `clientId` + `shareableKey` are safe to embed: they authorize only the
public endpoints (`GET /cards/public-key`, `GET /cards/browser-data`) and cannot charge by
themselves. They are still needed to encrypt a card and for every charge whose `BrowserData` does
not already carry both `ip` and `acceptHeader`, because the charge fetches those first; without
them it throws `AUTH_011`.

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

`GopaySDK.version` returns the SDK's own version (e.g. `"2.2.0"`) — a compiled-in constant rather
than an Info.plist lookup, since under SPM the SDK links statically into the host app and
`Bundle(for:)` would otherwise report the *host app's* version instead.

---

### Show the card form and charge

The first card payment needs the keys above and a payment your backend has created.
`GopayCardForm` collects the card, `submitCardForm` encrypts it into a JWE,
`chargeWithEncryptedCard` sends the charge and `awaitChargeState` waits for the result: it polls
the charge once a second, as GoPay recommends, runs the 3DS challenge in an SDK-managed WebView
when the bank asks for one, and returns the charge once it is `succeeded`.

```swift
import SwiftUI
import GopaySDK

struct CheckoutView: View {
    // paymentId, paymentSecret and returnURL (its callback.return_url) come from YOUR backend
    // after it creates the payment.
    let paymentId: String
    let paymentSecret: String
    let returnURL: URL

    @State private var isCardValid: Bool? = nil
    @State private var status = ""

    var body: some View {
        VStack(spacing: 16) {
            // .live shows localized errors as the user types.
            GopayCardForm(validation: .live, isValid: $isCardValid)
            Button("Pay") { Task { status = await pay() } }
                .disabled(!(isCardValid ?? false))
            Text(status)
        }
        .padding()
    }

    /// Runs the payment and returns what the checkout tells the user.
    private func pay() async -> String {
        let session: PaymentSession
        do {
            session = try await GopaySDK.shared.startPaymentSession(
                paymentId: paymentId,
                paymentSecret: paymentSecret
            )
        } catch {
            print("GoPay session failed:", error)   // the code is for your log, not the user
            return "The payment could not start"
        }
        let message = await charge(session)
        await session.close()   // wipes the secret + token from memory
        return message
    }

    private func charge(_ session: PaymentSession) async -> String {
        let jwe: String
        do {
            // The card the form holds, encrypted into a JWE; the form empties itself.
            jwe = try await GopaySDK.shared.submitCardForm()
        } catch let error as GopaySDKError where error.code == .validationInvalidInput {
            return "Check the card details"
        } catch {
            // Anything else, such as the key not being fetched, leaves the card in the form.
            return "Could not reach GoPay, try again"
        }
        var charged = false
        do {
            _ = try await session.chargeWithEncryptedCard(jwe)
            charged = true
            _ = try await session.awaitChargeState(AwaitChargeOptions(returnURL: returnURL))
            return "Paid"
        } catch let error as GopaySDKError {
            // The code is for your log, not the user.
            print("GoPay payment did not complete:", error)
            switch error.code {
            case .paymentDeclined:
                // The charge ended failed. error.chargeState carries it, with failReason when the
                // gateway sends one. Paying again needs a new payment.
                return "Payment declined"
            case .paymentTimeout, .paymentCancelled:
                // Still undecided after 30 s, or the user closed the 3DS screen: the charge was
                // sent, so read its state again or ask your backend before offering a new
                // payment (see Reading the result).
                return "The payment is being processed"
            case _ where error.code.rawValue.hasPrefix("NETWORK_")
                && (charged || (error.httpStatus ?? 500) >= 500):
                // A NETWORK_* after the charge went out, or one without a 4xx answer, leaves
                // the result unknown: see After a network error before offering to pay again.
                return "The payment result is not known yet"
            default:
                return "The payment failed"
            }
        } catch {
            return "The payment was cancelled"   // CancellationError: the task was cancelled
        }
    }
}
```

That is the whole of a card payment in the app. Your backend creates the payment and settles it;
what the app reports is not proof of payment (see [Your backend](#your-backend)). The session
starts before the card is encrypted, so a session that cannot start leaves the card in the form.
The manual path, `getChargeState()` and `handle3dsVerification`, stays available; both are in
[Reading the result](#reading-the-result).

`startPaymentSession` authenticates eagerly, so invalid credentials throw right away
(`GopaySDKError` with code `AUTH_010`, only when the gateway rejects the pair with a 400, 401 or
403). Any other failure keeps its own code: offline is `NETWORK_004`, a 5xx is `NETWORK_003`, and so on
(see [Error handling](#error-handling)), so do not ask your backend for a new payment over it.
At most one live session per `payment_id` exists at a time; reuse it via
`await GopaySDK.shared.getPaymentSession(paymentId)`. `session.close()` wipes the in-memory secret
and token and unregisters the session.

#### Charging a saved card token instead

When your backend has saved the card as a token (`POST /cards/tokens`, step 6 under
[Your backend](#your-backend)), the same session charges the token in place of the JWE, and
everything after the charge stays as above:

```swift
_ = try await session.chargeWithCardToken(cardToken)
```

Card tokenization is off until GoPay enables it for you through `integration@gopay.com`. The card
form path above needs no such step.

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

// Charge state polled to a result, with the 3DS challenge run on the way (see Reading the result)
let result = try await session.awaitChargeState(AwaitChargeOptions(returnURL: returnURL))

// Charges, one call each (see below)                       // POST /payments/{id}/charge
_ = try await session.chargeWithCardToken(token)
_ = try await session.chargeWithEncryptedCard(jwe)
_ = try await session.chargeWithWallet()                    // the Apple Pay sheet
_ = try await session.charge(request)                       // a ChargePaymentRequest built by hand

// QR (bank transfer) info
let qr = try await session.getQrPaymentInfo(format: .png)   // GET /payments/{id}/qr-payment/info

// Wallet config (for building an Apple Pay sheet manually, if needed)
let appInfo = try await session.getWalletInfo()             // GET /payments/{id}/apple-pay/app-info

// Browser data as the charge will send it (charge() runs this step itself)
let browserData = try await session.completeBrowserData(await BrowserData.deviceDefault())
```

`getWalletInfo()` and `chargeWithWallet()` are the wallet's names shared with the Android SDK;
`getApplePayInfo()` and `chargeWithApplePay()` do the same and stay as aliases.

The enums the gateway answers with (`ChargeState`, `ChargeActionType`, `Emv3dsState`, `CardScheme`,
`PaymentState`, `Currency`) each have an `unknown` case: a value added after this SDK shipped decodes
as `unknown` instead of failing the response, and the original value goes to the debug log.

### Charging with Apple Pay

```swift
guard await GopaySDK.isWalletAvailable() else { /* hide the Apple Pay button */ return }

do {
    _ = try await session.chargeWithWallet()                 // presents the Apple Pay sheet
    let result = try await session.awaitChargeState(         // polls; presents the 3DS WebView
        AwaitChargeOptions(returnURL: returnURL)             // callback.return_url, from your backend
    )
    print("Charge state:", result.state)                     // succeeded
} catch let error as GopaySDKError where error.code == .paymentDeclined {
    print("The charge failed:", error.chargeState?.failReason ?? error.message)
} catch let error as GopaySDKError where error.code == .paymentTimeout {
    print("Still undecided; ask your backend for the payment's state before offering it again")
} catch let error as GopaySDKError where error.code == .paymentVerificationUnreachable {
    print("The 3DS challenge never reached the user; charge again for a fresh redirect")
} catch let error as GopaySDKError where error.code == .paymentCancelled {
    // The sheet or the 3DS screen closed early, but a charge may already be through:
    // read getChargeState() before offering the payment again (see Reading the result).
} catch {
    print("Charge failed:", error.localizedDescription)
}
```

`chargeWithWallet` derives the required `browser_data` from the device automatically; pass your
own `BrowserData` if you have more accurate values. When Apple Pay cannot be used it throws
`PAYMENT_004` (hide the button and offer another method); a token the SDK cannot use, such as the
empty one the iOS Simulator returns, is `PAYMENT_003`. A charge that fails keeps its own code.

`isWalletAvailable()` is `async` because its Android counterpart has to ask Play services; on iOS
it answers what `canUseApplePay()` answers, a synchronous check you can keep using from a view
body. `chargeWithWallet(browserData:challengePreference:)` is `chargeWithApplePay` under the
shared name, with the same arguments and the same codes.

#### Setting up Apple Pay

The sheet works only once your app and GoPay are set up for it. The steps are in the GoPay guide,
[Apple Pay, App setup](https://api-docs.gopay.com/en/docs/06-apple-pay.md); in short, you create
an Apple Merchant ID, enable the Apple Pay capability for the app with that ID, and exchange the
Payment Processing Certificate with GoPay through `integration@gopay.com` (GoPay supplies the CSR,
you send back the certificate and the Merchant ID).

The SDK has no Apple Pay settings of its own: the Merchant ID, the card networks and the amounts
on the sheet come from the gateway for each payment (`GET /payments/{id}/apple-pay/app-info`). The
Merchant ID the gateway sends has to be one of those in your app's Apple Pay entitlement, otherwise
the sheet cannot be shown and the call throws `PAYMENT_004`.

In the iOS Simulator the sheet comes back without a usable payment token, so the call ends with
`PAYMENT_003`. Test on a device signed in with an Apple Pay sandbox tester account, see Apple's
[Apple Pay sandbox testing](https://developer.apple.com/apple-pay/sandbox-testing/).

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

The gateway also requires `ip`, and the device cannot know its own public address, so every
`charge(_:)` on a session first calls `GET /cards/browser-data` with the SDK's `clientId` and
`shareableKey` and fills in `ip` and `accept_header` from the answer; `javascript_enabled` is
sent as `true`, because the challenge runs in a WebView with JavaScript on. The request carries
the WebView's User-Agent, so the gateway sees the same browser as the issuer later does in the
AReq and in the challenge. `user_agent` itself never comes from the answer: a `BrowserData` you
build without a `userAgent` gets the WebView's User-Agent filled in before the fetch, with a
warning in the debug log, because the SDK's own HTTP User-Agent would fail that comparison. Only
fields that are still `nil` are filled: a value you set on `BrowserData` stays, and when `ip` and
`accept_header` are both set the gateway is not asked. When the fetch fails the charge is not
sent; the error carries the underlying code (`NETWORK_002` for an HTTP 4xx, `NETWORK_003` for a
5xx, one of the transport codes when no response came, `AUTH_011` when the config has no
`shareableKey`, or whatever else the fetch produced) with the original error as `underlying`.
`session.completeBrowserData(_:)` runs the same step on its own when you want to log what goes
out; pass its result to the charge unchanged.

### Charging with a card token

When the user enters a card, the SDK encrypts it to a JWE (see below) that **your backend**
tokenizes via `POST /cards/tokens`. Your backend returns a card token, which you charge with:

```swift
_ = try await session.chargeWithCardToken(cardToken, challengePreference: .auto)
let result = try await session.awaitChargeState(   // polls, runs the 3DS challenge, returns succeeded
    AwaitChargeOptions(returnURL: returnURL)       // callback.return_url, from your backend
)
```

### Charging with an encrypted card (JWE)

If you don't need a reusable card token, charge the JWE directly with the `ENCRYPTED_CARD`
input — this skips the server-side `POST /cards/tokens` round-trip. Encrypt the card (via
`submitCardForm()` or `encryptCardData(_:)`, see below) and pass the resulting JWE:

```swift
let jwe = try await GopaySDK.shared.submitCardForm()   // or encryptCardData(_:)
_ = try await session.chargeWithEncryptedCard(jwe, challengePreference: .auto)
let result = try await session.awaitChargeState(   // polls, runs the 3DS challenge, returns succeeded
    AwaitChargeOptions(returnURL: returnURL)       // callback.return_url, from your backend
)
```

Both helpers take an optional `browserData`, derived from the device when left out, and an
optional `challengePreference`, and both return the first charge state, which you can read
instead of waiting: a `redirect_url` in `action` is the 3DS challenge for `handle3dsVerification`,
the manual path below. They are `charge(_:)` with the request built for you; to set anything the
helpers do not take, build a `ChargePaymentRequest` with `.cardToken(...)` or
`.encryptedCard(...)` and pass it to `charge(_:)`:

```swift
let request = ChargePaymentRequest.encryptedCard(
    jwe,
    browserData: await BrowserData.deviceDefault(),
    challengePreference: .auto
)
_ = try await session.charge(request)
```

### 3DS verification

`handle3dsVerification(redirectURL:returnURL:presenting:)` opens the challenge in an SDK-managed
WebView and suspends. Pass it the address your backend created the payment with
(`callback.return_url`), which the app gets from its backend together with `payment_id` and
`payment_secret`; the ACS comes back to it when the challenge is done. GoPay is removing it from the
charge response, so do not rely on `ChargePaymentResponse.returnUrl`, which is deprecated. Without a
usable one (`nil`, blank, or not an `http(s)` address with a host) the SDK waits for
`GopaySDK.chargeReturnURL` instead, and then the payment has to be created with that address,
otherwise the screen never closes on its own. The return URL should carry no fragment (`#…`): what
the gateway appends lands in front of it, and the address no longer matches.

It has three ends, not two:

- **Answered** — the ACS navigates to an address starting with the return URL, which the
  WebView intercepts without loading, and the call returns normally. Read the outcome with
  `getChargeState()`; the SDK does not decide whether the payment went through.
- **Closed** — the screen closed before the challenge returned, which throws `GopaySDKError` with
  `paymentCancelled` (`PAYMENT_011`), whether the user closed it or something other than the SDK
  did, such as your app's navigation after the return from the bank. The user may have answered
  the challenge first, so read the charge before offering to pay again; the next verification
  can start right away.
- **Unreachable** — the challenge never reached the user, so there was nothing for them to
  answer: the page never drew, for instance because the redirect URL has already been retired or
  is not an `http(s)` address, the screen could not be presented because the previous one was
  still animating away, or the challenge asked to hand off to a banking app and nothing on the
  device opened it. It throws `GopaySDKError` with `paymentVerificationUnreachable`
  (`PAYMENT_010`); when the page answered with an error status, `httpStatus` carries it.
  Charging again is the right answer to a dead redirect URL, a refused presentation can be
  retried as soon as the screen is free, and a hand-off nobody took usually means the banking
  app is not installed, so offer the user another way to authorize. This is the case that used
  to arrive as a dismissal, so hosts ticked the verification off as handled and let the payment
  lapse.

Anything that breaks *after* the challenge has drawn ends as `PAYMENT_011` too, because by then
only `getChargeState()` can say whether the issuer authorised the payment. Cancelling the task
that awaits the call is not `PAYMENT_011`: it closes the screen and throws `CancellationError`.
Only one verification runs per process at a time; a second one throws
`paymentVerificationInProgress` (`PAYMENT_008`).

```swift
// The redirect from the charge response, the return URL from your backend.
guard let url = charge.action?.redirectUrl.flatMap(URL.init(string:)) else { return }
do {
    try await session.handle3dsVerification(redirectURL: url, returnURL: returnURL)
} catch let error as GopaySDKError where error.code == .paymentVerificationUnreachable {
    retryCharge()
    return
} catch let error as GopaySDKError where error.code == .paymentCancelled {
    // Closed before it returned. The challenge may still have been answered, so the charge
    // below, not this error, says how the payment ended.
}
let result = try await settle(session)   // the manual path, see Reading the result
```

### Reading the result

A charge is decided only once its state is `succeeded` or `failed`; `actionRequired` means a 3DS
challenge is waiting, and `requested` and `processing` mean the gateway has not decided yet, which
can take a while after a 3DS challenge. `unknown` is a state this SDK does not know, so treat it
like `processing`. GoPay recommends reading the state once a second and treating the notification
it sends your backend (`notification_url`) as the authoritative signal
([Polling and notifications](https://api-docs.gopay.com/en/api)). There are two ways to wait:

**`awaitChargeState`**, the SDK's own polling, mirrored on Android. It reads
`GET /payments/{id}/charge` at once and then `interval` after each answer (1 s by default), runs
the 3DS challenge when the gateway asks for one, and returns the charge once it is `succeeded`:

```swift
do {
    let charge = try await session.awaitChargeState(AwaitChargeOptions(
        returnURL: returnURL,                    // callback.return_url, for the 3DS challenge
        onStateChange: { charge in show(charge.state) }
    ))
    // charge.state == .succeeded
} catch let error as GopaySDKError where error.code == .paymentDeclined {
    // PAYMENT_006: the charge ended failed. error.chargeState is the charge, and
    // error.chargeState?.failReason says why when the gateway sends a reason; the message is then
    // "Charge failed: <fail_reason>", without one only "Charge failed". The payment is over; a
    // retry means a new payment.
} catch let error as GopaySDKError where error.code == .paymentTimeout {
    // PAYMENT_007: still requested / processing / unknown, or actionRequired without a new
    // address, after initialTimeout (30 s by default). Not a result: error.chargeState is the
    // last state read. Read getChargeState() later, or wait for the notification on your
    // backend, before offering a new payment.
} catch let error as GopaySDKError where error.code == .paymentCancelled {
    // PAYMENT_011: the 3DS screen closed before it finished. The challenge may still have
    // been answered, so read getChargeState() before offering the payment again.
}
```

`AwaitChargeOptions` has the matching options on both platforms (milliseconds on Android):
`interval` (1 s) and `initialTimeout` (30 s), in seconds; `threeDSMode`, `.automatic` by default,
where the SDK opens `handle3dsVerification` with the options' `returnURL` and `presenting` (`nil`
finds the topmost view controller) and polls on once it returns, or `.manual`, where the SDK only
reports the redirect and polls on while you run the challenge; `onStateChange`, called on the
main actor with every state read, the last one included; and `onActionRequired`, called once per
new `redirect_url`. The initial timeout covers `requested`, `processing` and `unknown` and is
lifted the first time the charge reports `actionRequired` with a redirect URL, because a
challenge takes as long as the user needs; in `.automatic` it starts again once the challenge
returns, so a gateway that never decides after it still ends in `PAYMENT_007`, while in `.manual`
it stays lifted. A failed read or a failed challenge ends the call with that error unchanged
(`NETWORK_*`, `PAYMENT_010`, `PAYMENT_011`, `AUTH_013`); a `NETWORK_*` there does not mean the
payment failed (see [After a network error](#after-a-network-error)), and
cancelling the awaiting task stops the polling, closes a challenge that is up and throws
`CancellationError`. Two calls on the same session poll independently; only one of them can open
the challenge, the other ends with `PAYMENT_008`.

**The manual path**: after a charge, and again after `handle3dsVerification` returns or throws
`PAYMENT_011`, read the state with `getChargeState()`. Keep asking while it is `requested`,
`processing` or `unknown`; stop after a limit of your own and leave the payment to your backend
then.

```swift
func settle(_ session: PaymentSession) async throws -> ChargePaymentResponse {
    for _ in 0..<60 {
        let charge = try await session.getChargeState()
        switch charge.state {
        case .succeeded, .failed, .actionRequired:
            return charge
        case .requested, .processing, .unknown:
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    throw PaymentStillPending()   // your own error: ask your backend later
}
```

A charge that comes back in `actionRequired` with `action?.redirectUrl` needs
`handle3dsVerification`; call `settle` again once it returns. When no charge went out, for
instance after an Apple Pay sheet closed without paying, `getChargeState()` throws `NETWORK_002`
with HTTP 404, on either path. Your backend, not the app, decides whether the order is paid (see
[Your backend](#your-backend)).

The SDK keeps nothing on disk, and a payment in progress does not survive the app being
terminated, which happens above all while the user is away in a banking app during 3DS. Keep only
the payment `id`, never `payment_secret`, and when the app comes back with an `id` but no result,
ask your backend for the payment's state before offering to pay again.

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
pass the same `formId` to `submitCardForm(formId:)`). This is the card form model both SDKs share
since 2.2: the form holds the card under its `formId`, `GopaySDK.shared.submitCardForm(formId:)`
turns it into a JWE and `clearCardFormData(formId:)` drops it, with the same three `validation`
modes on both platforms.

The SDK clears the form's card data from memory after a successful `submitCardForm()` and when
the form disappears — so call `submitCardForm()` while the form is on screen and forward the
JWE promptly. **The visible fields are emptied too**: after a successful `submitCardForm()` the
form returns to its pristine state, so the user sees an empty card form and your own UI should
move on rather than wait for further input. A failed encryption leaves everything as the user
typed it, since nothing has been authorized yet.

The gateway accepts each JWE **once** and its payload expires 10 minutes after creation; to retry
a failed charge, have the user confirm the card again. A charge that never reached the gateway did
not use the JWE, see [After a network error](#after-a-network-error). To wipe
the data early — e.g. when the user abandons checkout while the form is still on screen — call
`GopaySDK.shared.clearCardFormData()`, which empties the visible fields as well. Discard the JWE
once your backend has tokenized it.

Every encryption fetches the merchant's public key afresh from `GET /cards/public-key`, and the
payload's 10 minutes run on the gateway's clock, read from that response's `Date` header, so a
device with a wrong clock still produces a JWE the gateway accepts. Should the header be missing or
unreadable, the SDK falls back to the device clock and, with `enableDebugLogging` on, says so in
the debug log.

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

These 28 parameters are the same on Android, name for name and type for type with the single
exception of `fontFamily` (see the parity table below), so a design decided once reads the same on
both. One thing is Android's alone: it adds `helperTextColor` and `helperFontSize` for a helper line
neither the web form nor this SDK renders.

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
| `inputBorderStyle` | — | web-only | `underline` |
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
  binding, which the form fills from its first render onwards and keeps current on every edit.
  Web `errorHidden: true` is the iOS default.
- `focusGradientStart`, `focusGradientEnd`, `focusRingWidth`, `focusRingColor` and
  `inputBorderCollapse` all describe something a browser paints around a field: a gradient, a glow
  outside the frame, one shared line between two neighbours. A native text field has none of them,
  and neither SDK draws its own. A focused field is marked the way the platform marks it, with the
  caret and the keyboard.
- `inputBorderStyle` names a shape rather than a color or a length. Its web default, `underline`,
  is not something a native text field draws on either mobile platform, so honouring it would mean
  the SDK painting the field itself.
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

A 1.x theme stops compiling in 2.0; what to write instead is under
[Card form theme](#card-form-theme) in [Migrating from 1.x](#migrating-from-1x).

### Localizing the form

Form labels and placeholders are localized. By default the form uses the **device language and
falls back to Czech (`cs`)** when the language has no translation. 20 languages ship built in
(`bg cs de en es et fr hr hu it lt lv nl pl pt ro ru sk sl uk`). The strings are identical to the
Android SDK's, so a screen reads the same on both.

The expiration label sits in a narrow column and carries GoPay's own wording, so nothing is
shortened to fit: a long translation wraps onto a second line rather than being cut off. The
expiration and CVV columns each reserve the height of the taller of the two labels, so a label that
wraps moves neither input and both stay on one line at every text size.

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
// Errors appear once the card is submitted (the same mode as on Android):
@State private var attemptedSubmit = false
GopayCardForm(locale: "cs", validation: .onSubmit(attempted: $attemptedSubmit), isValid: $isCardValid)
// …then in your submit action: try await GopaySDK.shared.submitCardForm()

// Or validate live as the user types:
GopayCardForm(locale: "cs", validation: .live, isValid: $isCardValid)
```

`.onSubmit` shows the localized required/pattern message for every invalid field while `attempted`
is `true`. The SDK sets `attempted` to `true` itself when `submitCardForm()` is called for the form,
before it judges the card, so an empty or invalid card shows its errors on the submit, which then
throws `VALIDATION_007`; you can also set it yourself, e.g. when your button is tapped before you
call the SDK. The form sets `attempted` back to `false` whenever it empties its fields, e.g. after a
successful `submitCardForm()`, so the emptied fields do not light up as required. `.live` shows a
field's error once it holds non-empty, invalid content. The default is `.hidden` — the form
renders nothing and you display errors yourself from the resolved locale:

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

## Testing on the sandbox

The sandbox is `.sandbox`, with its host in the table above. The GoPay guide does not list test
cards; these two were tested there with SDK 2.2.0:

| Card | Result on the sandbox |
| --- | --- |
| `4444 4444 4444 4448`, expiry `12/28`, CVV `123` | The charge ends `succeeded` |
| `4000 0000 0000 0002`, expiry `12/28`, CVV `123` | The charge ends `failed`: `awaitChargeState` throws `paymentDeclined` (`PAYMENT_006`). The sandbox may send a `fail_reason` with it or not, so the message is either `Charge failed: PAYMENT_FAILED` or only `Charge failed`, and the app has to handle both |

The sandbox does not ask for a 3DS challenge, and `ChallengePreference` does not change that, so
the challenge cannot be tried there. In production the challenge comes when the card's bank asks
for it.

---

## Error handling

Every failure throws `GopaySDKError`, which carries a stable `code` (matching the Android SDK) and
a message. A request that got no HTTP response is one too, never a bare `URLError`, with the
original error as `underlying`, and so is a card encryption that fails, with `INTERNAL_001`:

| Code | Meaning |
|---|---|
| `AUTH_009` | Payment token expired and couldn't be re-acquired |
| `AUTH_010` | `payment_id` / `payment_secret` rejected by `/oauth2/token` (HTTP 400, 401 or 403 only) |
| `AUTH_011` | `clientId` / `shareableKey` missing for a public-endpoint call, including the browser data fetch a charge runs first |
| `AUTH_012` | A session for this `payment_id` already exists |
| `AUTH_013` | Operation on a closed session |
| `PAYMENT_003` | Apple Pay produced no usable payment token (unreadable, or empty as in the iOS Simulator) |
| `PAYMENT_004` | Apple Pay cannot be used: the device cannot pay with it, no supported card network, or the sheet could not be shown |
| `PAYMENT_006` | `awaitChargeState` only: the charge ended `failed`; the charge is in `chargeState`; the message is `Charge failed: <fail_reason>` when the gateway sends a `chargeState.failReason`, otherwise only `Charge failed` |
| `PAYMENT_007` | `awaitChargeState` only: the charge stayed `requested` / `processing` / `unknown`, or `actionRequired` without a new address, for the whole `initialTimeout` (30 s); not a result, the last state read is in `chargeState`, read the charge again or wait for the notification |
| `PAYMENT_008` | A 3DS verification is already in progress |
| `PAYMENT_009` | An Apple Pay sheet is already in progress |
| `PAYMENT_010` | The 3DS challenge never reached the user: the page would not load, e.g. the redirect URL is dead or is not a web address, the screen would not present (that cause is iOS-only), or no app took the hand-off |
| `PAYMENT_011` | The Apple Pay sheet or the 3DS screen closed before it finished, or the 3DS page failed after it had drawn; read the charge before paying again |
| `NETWORK_001` | No HTTP response: the request timed out |
| `NETWORK_002` | Gateway returned 4xx |
| `NETWORK_003` | Gateway returned 5xx |
| `NETWORK_004` | No HTTP response: no connection (offline, the host does not resolve, the connection is refused) |
| `NETWORK_005` | No HTTP response: a certificate failed (any other TLS failure is `NETWORK_007`) |
| `NETWORK_007` | No HTTP response for any other reason, e.g. the connection dropped |
| `CONFIG_001` | `startPaymentSession`, `encryptCardData` or `submitCardForm` called before `initialize(with:)` |
| `CONFIG_003` | Not thrown by the SDK; deprecated, removed in 3.0 |
| `CONFIG_006` | The resolved base URL is empty, or not an absolute `http(s)` URL |
| `VALIDATION_007` | Invalid input — empty ids, a card that fails the PAN / month / year / CVV rules, a form with no card or an invalid one, or `awaitChargeState` options that are not positive |
| `INTERNAL_001` | Unexpected internal error, including a card encryption that failed after the key was fetched |
| `INTERNAL_003` | Response could not be decoded |

```swift
} catch let error as GopaySDKError {
    print("[\(error.code.rawValue)]", error.message)
}
```

When the gateway answered with an error, `httpStatus` carries the status and `gatewayError` its
error body (`error`, `message`, `detail`); the gateway's `message` is also appended to the SDK's,
e.g. `Failed to get Apple Pay info: HTTP 403: Apple Pay in-app is not enabled for this merchant`.

An Apple Pay sheet or a 3DS screen that closed before it finished throws `PAYMENT_011`
(`paymentCancelled`), and so does a 3DS page that failed after it had drawn. That is not a failed
payment, and not necessarily one that did not happen: the 3DS challenge may have been answered,
so read `getChargeState()` before offering it again.
`CancellationError` comes only from cancelling the task that awaits the call: that closes the 3DS
screen, while an Apple Pay sheet already up is not closed, and the call waits for it.

Every code above, with its causes and what to do about it, is in
[`sdk/docs/ERROR_CODES.md`](sdk/docs/ERROR_CODES.md). The codes are shared with the Android SDK —
the iOS surface throws the subset listed there.

`GopaySDKConfig.errorCallback` hears every `GopaySDKError` a public call of the SDK or of a
session throws, once per error, for central logging; the two outcomes of a payment window,
`PAYMENT_007` and `PAYMENT_011`, and a `CancellationError` stay out, and nothing that is not a
`GopaySDKError` goes in. The rule is the same on Android and spelled out at the top of
`ERROR_CODES.md`. It is not a substitute for catching the error at the call.

### After a network error

A `NETWORK_*` code means the request got no usable answer from the gateway, not that the payment
failed. What to do depends on the call that threw it.

- **`awaitChargeState` or `getChargeState`, after the charge call returned.** The charge reached
  the gateway and its result is not known yet. Read the state again with `getChargeState()` or
  `awaitChargeState` once the connection is back, and do not offer a new payment: the customer may
  already have paid. If the app cannot get through, your backend learns the result from the
  notification on `notification_url`.
- **The charge call itself** (`chargeWithEncryptedCard`, `chargeWithCardToken`,
  `chargeWithWallet`, `charge`). Before it sends the charge, the SDK fetches the browser data and,
  when the payment token has expired, a new token, so the error may come from before the charge
  went out.
  - **With an HTTP status** (`NETWORK_002` for a 4xx, `NETWORK_003` for a 5xx), the gateway
    answered, and its message says why. After a 5xx, read `getChargeState()` as well before
    anything else: the charge may exist.
  - **Without an HTTP status** (`NETWORK_001`, `NETWORK_004`, `NETWORK_005`, `NETWORK_007`), the
    charge may not have gone out, or it reached the gateway and the answer was lost. Read
    `getChargeState()`: a charge state means the charge exists, so follow it as above;
    `NETWORK_002` with HTTP status 404 means no charge exists.

```swift
import GopaySDK

/// Whether the payment has a charge, after the charge call ended with a NETWORK_* code.
func chargeExists(_ session: PaymentSession) async throws -> Bool {
    do {
        _ = try await session.getChargeState()
        return true
    } catch let error as GopaySDKError
        where error.code == .networkClientError && error.httpStatus == 404 {
        // No charge is HTTP 404; anything else, such as still being offline, does not tell.
        return false
    }
}
```

When no charge exists after a code without an HTTP status, charge again with the same JWE while it
is within its 10 minutes: no charge used it. `submitCardForm` empties the form once it has returned
the JWE, so this spares the user typing the card again. Charge on the same session if you have not
closed it, or on a new one started from the same payment id and payment secret. Keep the JWE until
a charge exists, and drop it then or once it has expired. Once the 10 minutes are over, or when the
gateway answered the charge with an error, have the user enter the card again.

---

## Shared API with Android

Since 2.2 the two SDKs offer the same calls under the same names, so an integration, or the React
Native SDK built on both, reads the same on either platform. The main path of this README is that
shared API; the platform names stay as aliases, without deprecation, and what 3.0 removes is
listed in [`sdk/docs/API_3_0.md`](sdk/docs/API_3_0.md).

| Shared name | iOS alias | What it is |
| --- | --- | --- |
| `session.chargeWithCardToken(_:browserData:challengePreference:)` | — | a card token charge in one call; `browserData` optional, derived from the device default, which needs no context; Android without an `activity` requires it |
| `session.chargeWithEncryptedCard(_:browserData:challengePreference:)` | — | a JWE charge in one call; `browserData` optional, derived from the device default, which needs no context; Android without an `activity` requires it |
| `GopaySDK.isWalletAvailable()` | `canUseApplePay()` | can the device pay with the platform wallet |
| `session.getWalletInfo()` | `getApplePayInfo()` | the wallet configuration for the payment |
| `session.chargeWithWallet(browserData:challengePreference:)` | `chargeWithApplePay(...)` | the managed wallet sheet and charge |
| `GopayCardForm(formId:)` + `submitCardForm(formId:)` + `clearCardFormData(formId:)` | — | the card form model, now on Android too |
| `GopayCardForm(validation:)` with `.hidden`, `.live`, `.onSubmit` | — | the validation display modes, now on Android too |

An alias is one body under a second name: it does exactly what the shared name does, with the
same arguments and the same codes. The response types stay platform-specific
(`GopayApplePayAppInfoResponse` here, `GooglePayInfoResponse` on Android), and so do the UI
arguments: Android takes an `activity` where the wallet, the 3DS screen and the automatic
polling need one, iOS finds the presenting view controller itself. The errors are the shared
code contract above, with one rule for `errorCallback` on both.

---

## What changed in 2.2

Nothing was removed or renamed, but a few behaviours moved to the shared contract, and an
integration written against 2.0 or 2.1 may notice:

- Errors thrown by a `PaymentSession` now reach `errorCallback`, once each, and so do the
  failures of `startPaymentSession` itself (`AUTH_010`, `VALIDATION_007`, the `NETWORK_*` codes);
  until 2.1 only the card encryption and `AUTH_012` did. The callback runs on whatever thread the
  failing call ends on, not necessarily the main thread.
- Before `initialize(with:)`, `encryptCardData` and `submitCardForm` throw `CONFIG_001` instead of
  `AUTH_011`, and `startPaymentSession` throws `CONFIG_001` instead of calling the sandbox.
- A card encryption that fails after the key was fetched throws `GopaySDKError` with
  `INTERNAL_001` instead of an `NSError` of the `GopayJWE` domain.
- `submitCardForm` switches the form's `.onSubmit` validation on itself, before it judges the
  card; the host no longer has to flip the `attempted` binding.
- `submitCardForm` on a form whose fields are all empty throws `VALIDATION_007` with the
  "no card form data" message, like a form that is not on screen, instead of the "invalid" one.
- `paymentId` and `paymentSecret` of white space only are refused with `VALIDATION_007` instead
  of going to the gateway.

---

## Migrating from 1.x

What 2.0 changes for code written against 1.x, in four parts: the error contract, card encryption,
the response enums and the card form theme.

### Error contract

| 1.x | 2.0 |
| --- | --- |
| A transport failure (offline, timeout, TLS) reached you bare (`URLError`) | `GopaySDKError` with `NETWORK_001`, `NETWORK_004`, `NETWORK_005` or `NETWORK_007`; the original error is the `underlying` |
| A 4xx or a transport failure of the token request in `startPaymentSession` was `AUTH_010` | `AUTH_010` only when the gateway turns the pair down (HTTP 400, 401 or 403); anything else keeps its `NETWORK_*` code |
| An Apple Pay failure was a `GopaySDK` `NSError` | Apple Pay unavailable or its sheet not shown: `PAYMENT_004`; a token the SDK cannot use: `PAYMENT_003` |
| `GopaySDKErrors.applePayUnavailable`, `applePayCancelled`, `applePayAuthorizationFailed`, `sdkError(_:)` | Deprecated, the SDK no longer uses them: match `GopaySDKError.code` against `PAYMENT_004`, `PAYMENT_011` and `PAYMENT_003` instead |
| Closing the Apple Pay sheet threw a `GopaySDK` `NSError`, closing the 3DS screen threw `CancellationError` | `paymentCancelled` (`PAYMENT_011`); a `CancellationError` now comes only from cancelling your own task, which also closes the 3DS screen |
| `charge.returnUrl` was the address to pass `handle3dsVerification` | Deprecated: GoPay is removing `return_url` from the charge response. Pass the `callback.return_url` your backend created the payment with |
| `configMissingParameter` (`CONFIG_003`) | Deprecated: the SDK never throws it, and 3.0 removes it |

### Card encryption

| 1.x | 2.0 |
| --- | --- |
| `getPublicEncryptionKey(forceRefresh:)`, `JweUtils`, `GopayJWK` | Gone or internal: a key fetched ahead of time, or a JWE built outside the SDK, would carry the device's clock. Call `encryptCardData(_:)` or `submitCardForm(formId:)`. |

### Response enums

| 1.x | 2.0 |
| --- | --- |
| An exhaustive `switch` over `ChargeState`, `ChargeActionType`, `Emv3dsState`, `CardScheme`, `PaymentState` or `Currency` | Each has an `unknown` case for a value the gateway added later; add a branch; for a state, treat it as not final. |

### Card form theme

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

The cut to native rendering removed eight keys that 1.x never had but the 2.0 branch did carry for
a while. They are gone from the type, so setting one is a compile error rather than a surprise.

| Removed in 2.0 | Instead |
| --- | --- |
| `inputBorderCollapse` | nothing: adjacent native fields cannot share a border |
| `inputBorderStyle` | nothing: every field renders bordered, and the web's `underline` is a shape the SDK would have to paint itself |
| `focusRingWidth`, `focusRingColor` | nothing: marking the active field is something the SDK would have to paint, so neither platform marks it |
| `focusGradientStart`, `focusGradientEnd` | nothing: marking the active field is something the SDK would have to paint, so neither platform marks it |
| `inputLetterSpacing` | `labelLetterSpacing` still applies to labels |
| `inputLineHeight` | `inputHeight` to set a minimum height |

Two behaviors change. An invalid field now takes `inputErrorBorderColor` on its border, which an
integration only sees while it renders inline errors; on the default `validation: .hidden` nothing
changes. And a focused field no longer recolors its border at all, which 1.x did through
`focusedBorderColor`.

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
  through one consistent flow: create a payment, charge, and `awaitChargeState`, which polls the
  charge to a result and runs any 3DS challenge on the way. Each pay attempt creates a **fresh** payment,
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

### Demo app against the released SDK

The demo builds against the SDK in this checkout, so a change to the SDK shows up in the demo
straight away. To build it against the released SDK instead, the Swift package an integrator gets
by following [Installation](#installation), switch the project:

```bash
./scripts/demo-sdk-source.sh released   # gopay-ios-sdk at exactly the version in GopaySDK.podspec
./scripts/demo-sdk-source.sh local      # back to this checkout
```

Close the project in Xcode before switching. The script changes only the package reference in
`example/example.xcodeproj` and removes the `Package.resolved` that `released` creates. Commit the
project in `local`: that is what development builds; CI builds only the SDK.

`released` builds only while the demo uses nothing but released API. On a branch that changes the
SDK ahead of a release, the build fails on the missing symbols, and that is expected.

See [`example/README.md`](example/README.md) for the full walkthrough.

---

## Operational data

The SDK sends GoPay basic diagnostic data about its own behaviour: which SDK operation ran, the
HTTP status it got back, how long it took, what the request and response said (redacted, see
below), and, when the SDK raises an error, the SDK's own error code and message. This is always on.
There is no switch and nothing to configure, because a signal produced only by the merchants who
opted in describes those merchants rather than the SDK. The debug log flag does not change what is
sent; with it on, the SDK logs one line per event, its type and name, without its content.

Alongside those it reports the lifecycle around a payment: the SDK being initialized, a payment
session starting and closing, the card form appearing and disappearing, and the 3DS verification
screen being opened, with the verification page's address but none of its parameters. Each step of
an Apple Pay payment is reported as it happens (the sheet opening, the authorization, the charge and
the result the sheet was given, or the sheet being closed without paying), and so is the answer to
whether the device can pay with Apple Pay. Every event carries the SDK version, the platform, which
payment method and flow it belongs to, the id of the payment being paid, your `clientId`, a random
id for the SDK instance and one for the app process, the event's position among those the SDK
instance sent, and your app's bundle identifier.

One event describes something your customer did rather than something the SDK did: that they
submitted the card form, or authorised in the Apple Pay sheet, and how long the form had been on
screen before they did. That is the whole of it: no field contents, no keystrokes, no timing of
individual fields, nothing derived from the card data, not even the length of the encrypted payload.

**What it never contains.** Card numbers, CVV, the encrypted card payload, card tokens, wallet
payment data, `payment_secret`, access tokens, credentials, 3DS or ACS redirect parameters, and
personal data such as e-mail, phone, name, address or IBAN. Request and response bodies are
redacted on the device before they are sent, and not by a field list alone: every field whose name
marks it as a secret, a token, card or wallet data, a redirect or personal data is replaced with
`[redacted]`; the payment instrument of a charge is dropped whole, whatever its fields are called;
every text value that survives is still stripped of PAN-shaped digit runs, token-shaped strings,
e-mail addresses and query strings; and each body is cut at 2 000 characters. Request paths are
sent as templates (`/payments/{id}/charge`) rather than as the URLs actually called, error messages
are the SDK's own text with the same scrub, and the token request reports only the form it sent,
never the token that came back. The payment id itself is sent as its own field: it is what ties the
events of one checkout together, and it identifies a payment rather than a person.

**What it does contain that concerns you.** Every request carries the device's IP address, as any
HTTP request does, and GoPay keeps it with the data, together with the SDK's own User-Agent (which
names the SDK and its version, not the device or the person) and your app's bundle identifier. The
data is therefore pseudonymised personal data, not anonymous. GoPay processes it under legitimate
interest to keep the payment integration working and diagnosable.

**What you should do.** Reflect this in your own privacy notice: you are the controller for your
checkout, and your customers' data is being processed in your app. The reports go to
`https://lx.gopay.com` (production) or `https://lx.sandbox.gopay.com` (sandbox); a `.development`
environment sends none.

Delivery is fire-and-forget: each report gives up after 10 seconds, nothing is retried, nothing is
stored on the device, and every failure is discarded silently. Nothing here can delay or fail a
payment. Four separate caps limit how much one payment session can produce (API reports, lifecycle
markers, Apple Pay steps and errors), so a flood of any single kind cannot crowd out the others.
The caps start over with every payment session, because the SDK lives as long as your app, not as
long as one checkout. Unit or integration tests of your own that initialize the SDK against the
sandbox send real reports to the sandbox ingest, like any other run of the SDK.

---

## Security notes

- `payment_secret` and the payment-scoped JWT live in memory only — never written to disk, and
  wiped by `close()`.
- `GopayCardForm` keeps PAN and CVV inside the SDK; you only ever receive a JWE.
- Card data lives in memory only while the form needs it: the SDK's copy is dropped after a
  successful `submitCardForm()`, when the form disappears, and on demand via `clearCardFormData()`
  (PCI DSS 4.0.1, req. 3.3.1 — SAD must not be retained once no longer needed). Each of those also
  empties the form's visible fields, so the card is not left on screen holding a reference the SDK
  has already let go of. Swift strings cannot be securely overwritten, so this releases the
  references rather than zeroing bytes.
- Card data is encrypted with RSA-OAEP-256 + A256GCM using the merchant public key, fetched for
  every encryption and never cached.
- Payment creation needs merchant credentials and must stay on your server; the SDK cannot create
  payments and never sees the merchant secret.

### App Store privacy and PCI DSS

- The SDK ships a privacy manifest (`PrivacyInfo.xcprivacy`) that declares Payment Info, used for
  app functionality and not for tracking. Xcode adds it to your app's privacy report. What you
  declare for your app in App Store Connect is yours to decide, see Apple's
  [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/), Payment Info
  in particular.
- The manifest also declares Other Diagnostic Data, for the [operational data](#operational-data)
  the SDK sends GoPay: used for app functionality and not for tracking, and linked, because the
  payment id it carries ties the data to the payment and so to the payer.
- According to the GoPay guide
  ([PCI DSS scope](https://api-docs.gopay.com/en/docs/01-security.md)), an integration where the
  GoPay SDK collects and encrypts the card and your code handles only the resulting JWE or card
  token qualifies for SAQ-A; if your code collects the card itself and builds the JWE, it is in
  SAQ-D scope. Confirm your own scope with GoPay at `integration@gopay.com`.

## Testing

```bash
cd sdk
xcodebuild test -project sdk.xcodeproj -scheme sdk \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The tests live in `sdk/sdkTests` and run through the `sdk` Xcode project — `Package.swift`
declares no test target, so `swift test` will not find them.

One suite, `TelemetryIngestValidationTests`, sends an event of every kind to an operational-data
ingest that answers schema errors with 400, and runs only when its `/events` URL is given:
`TEST_RUNNER_GOPAY_TELEMETRY_VALIDATION_URL=<url> xcodebuild test …`. Without it the suite is
skipped.

## Releasing

Releases are cut by **semantic-release** on `master`: it derives the version from the commit
messages, bumps `package.json`, rewrites `CHANGELOG.md`, and creates and pushes the git tag.
commitlint enforces conventional commits with a `GPMOB-` reference, so the commit message is what
picks the next version. Don't tag by hand — SPM consumers resolve the tag semantic-release made.

A release runs only when someone starts the manual `release` step in the Bitbucket pipeline of the
newest commit on `master`. The pipeline then pushes the release commit and its tag to GitHub, and
the CocoaPods push below follows.

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
