# Gopay iOS SDK — Example App

A self-contained demo of the whole Payments 4.0 flow. It fakes the merchant backend in-app, and
shows the SDK two ways: as a realistic e-shop checkout, and as a raw call-by-call console.

## Prerequisites

- Xcode 13.2+ and an iOS 13+ simulator (the project's own deployment target is higher — Xcode will
  tell you if your simulator is too old).
- Network access to whichever gateway the Development environment points at (see
  [Configuration](#configuration)) — the demo ships pointed at an internal gateway used for
  contributing to this repo, reachable only from inside GoPay. If you're outside that network,
  point `DemoConfig`'s Development entry at your own gateway.

## Running

```bash
cd example
open example.xcodeproj
```

Pick the `example` scheme and Run (⌘R). You may also need to set your own signing team.

The `example` scheme is checked in as a shared scheme, so the app also builds straight from a fresh
clone without opening Xcode:

```bash
xcodebuild -project example/example.xcodeproj -scheme example \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' build
```

## The launcher

The app opens on `RootView`: two destinations, and a tappable environment badge.

- **Demo checkout** → `CheckoutView` — see below.
- **Developer sandbox** → `ContentView` — the original four-section console, unchanged in spirit
  from earlier versions of this app.
- The **environment badge** at the bottom shows which gateway is active (`● DEVELOPMENT
  your.gateway.example.com`) and opens a picker for Development / Sandbox / Production. Switching
  closes any live `PaymentSession` first — otherwise it would keep talking to the old gateway,
  since each session captures its own API client at creation — then re-initializes the SDK and
  updates the badge. **The choice isn't persisted**: every launch starts on Development.

## Demo checkout

A deliberately ordinary-looking checkout (`CheckoutView` / `CheckoutViewModel`) for a fictional
shop, with a real cart total, that exercises every payment method the SDK offers:

- **Credit or debit card** — `GopayCardForm` (themed to match the shop) → `submitCardForm()` → a
  JWE → `charge(.encryptedCard)`. The PAN never touches this app's code.
- **Apple Pay** — `chargeWithApplePay()`. The row is hidden when `GopaySDK.canUseApplePay()` is
  `false`.
- **Saved card** — stands in for a card the shopper saved on a previous order: a known test card
  is encrypted with `encryptCardData(_:)`, tokenized by `MerchantBackendSimulator` (simulating your
  server's `POST /cards/tokens`), then charged with `charge(.cardToken)`.
- **Bank transfer** — `getQrPaymentInfo(format: .png)` rendered as a scannable QR code plus account
  details, with a **Share** button (`square.and.arrow.up` in the sheet's toolbar) that hands the QR
  image and a text summary of the amount/account to `UIActivityViewController`.

Tapping **Pay** always creates a **fresh payment** first (a payment is single-use, so a decline
needs a new one to retry), then runs every card-based method through the same tail: charge, and if
the response carries a 3DS `action.redirectUrl`, present the verification WebView and keep polling
`getChargeState()` until the gateway reports a terminal state — 3DS is just a step in that loop,
not a separate button. The result screen shows success, failure (with "Try another method"), or
pending (with a manual refresh), plus a collapsible "Developer details" JSON dump of the last
`ChargePaymentResponse`.

The **language picker** for the card form's labels sits next to the form itself (inside the
"Credit or debit card" row), not in the checkout header — it's the only thing it actually
localizes. Twenty built-in languages plus a joke custom locale (`"xx"`, registered in
`exampleApp.swift`) are selectable there.

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

Every result — or a `GopaySDKError` with its code — is logged into the **Response** box at the
bottom.

Two operations need setup the demo doesn't ship with. Apple Pay needs the Apple Pay capability and
a Merchant ID entitlement added in Xcode, and the merchant must have Apple Pay in-app enabled on
the gateway; without that, *Get Apple Pay info* returns `NETWORK_002` / HTTP 403. Completing a real
Apple Pay authorization also needs a physical device with a test card in Wallet.

## Configuration

All demo values live in [`DemoConfig.swift`](example/DemoConfig.swift), keyed by `DemoEnvironment`
(`.development` / `.sandbox` / `.production`) rather than as flat constants — an environment is a
whole credential bundle (base URL, `clientId`, `shareableKey`, `clientSecret`, `goid`), since each
one genuinely needs its own. `DemoConfig.buildConfig(for:)` is the single factory both app launch
and the environment picker go through, so a runtime switch reproduces the same custom locale,
debug flag, etc. as a cold start.

- **Development** is meant to be pointed at whatever gateway you're testing against — its base URL
  and credentials are freely editable in `DemoConfig`. It ships pointed at an internal gateway with
  working credentials, used primarily for contributing to this repo; replace both if you're
  integrating the SDK elsewhere and want a Development target of your own.
- **Sandbox** and **Production** ship with **empty placeholder credentials**. Selecting either
  before filling them in isn't blocked — you'll just get a clear auth failure from the gateway
  instead of a payment silently charged against the wrong environment.

### Launch-time overrides

The Development environment's URL and credentials can all be replaced at launch, so you can point
the demo at a different gateway — the sandbox, a branch deployment, a mock — without editing code
and rebuilding. See [`DemoOverrides.swift`](example/DemoOverrides.swift).

| Key | Overrides |
| --- | --- |
| `GOPAY_DEMO_BASE_URL` | Development's base URL |
| `GOPAY_DEMO_CLIENT_ID` | Development's `clientId` |
| `GOPAY_DEMO_SHAREABLE_KEY` | Development's `shareableKey` |
| `GOPAY_DEMO_CLIENT_SECRET` | Development's `clientSecret` |
| `GOPAY_DEMO_GOID` | Development's `goid` |

Each is read as an environment variable first, then as a `-KEY value` launch argument. Anything you
don't supply keeps its compiled-in value, so a plain ⌘R with an untouched scheme behaves exactly as
before.

The five are resolved as one set: if you supply a `GOPAY_DEMO_BASE_URL` that gets **rejected**, the
credentials you supplied alongside it are dropped too, and the demo runs on its built-in gateway
with its own built-in credentials. A typo in the URL would otherwise send your merchant secret to
the compiled-in development gateway, which is the environment mixing these overrides exist to
prevent. Not supplying a URL at all is different: the credentials then apply on top of the built-in
gateway, as before.

Overrides apply to **Development only**. Sandbox and Production keep resolving through the SDK's
own built-in hosts and their own placeholder credentials — switching the badge can never send one
environment's merchant secret to another's gateway. To reach an arbitrary gateway, including the
sandbox, stay on Development and give it that URL; the badge shows the host it is actually pointed
at, so nothing is hidden.

**From Xcode:** *Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments*, in either *Environment
Variables* or *Arguments Passed On Launch*.

> ⚠️ The `example` scheme is a **shared, version-controlled** scheme
> (`example.xcodeproj/xcshareddata/xcschemes/example.xcscheme`). Anything you type into Edit Scheme
> is written into that file, so filling a real `GOPAY_DEMO_CLIENT_SECRET` in there and committing
> would leak exactly what these overrides exist to keep out of the repo. Either check `git status`
> before committing, or keep your values on the command line instead.

**From the command line**, against an already-built app on a booted simulator. `simctl` has no
`--setenv` flag — it forwards variables prefixed with `SIMCTL_CHILD_`:

```bash
SIMCTL_CHILD_GOPAY_DEMO_BASE_URL="https://gw.your-gateway.example.com/gp-gw/api/4.0/" \
  xcrun simctl launch 'iPhone 17' com.gopay.sdk
```

Launch arguments need no prefix, and can be combined:

```bash
xcrun simctl launch 'iPhone 17' com.gopay.sdk \
  -GOPAY_DEMO_BASE_URL "https://gw.your-gateway.example.com/gp-gw/api/4.0/" \
  -GOPAY_DEMO_GOID "8761908826"
```

The environment badge follows the override — it renders the host of whatever URL `DemoConfig`
resolved — so you can see at a glance which gateway is live.

Three things worth knowing. A base URL gets a trailing `/` appended if you leave it off, because
both the SDK's network client and `MerchantBackendSimulator` build requests by concatenating a path
onto it. A value that isn't a usable `http`/`https` URL is rejected with a console warning, taking
the rest of the set with it as described above, rather than being passed through to fail later in a
less obvious place.
And App Transport Security still applies: a plain `http://` gateway on anything other than
`localhost` is blocked by the OS, and the resulting failure does not mention ATS — use `https`, or
add an ATS exception if you really need a cleartext mock.

These overrides are not a secure credential store — a launch argument is visible in the process
list. They exist so real credentials never have to be written into a tracked source file.

If the Development credentials you're using ever stop working, every call fails with
`401 UNAUTHORIZED — Invalid client_id or client_secret`, which looks like a code bug but isn't;
check with a token request before debugging anything else:

```bash
curl -s -X POST "<your-dev-gateway-base-url>oauth2/token" \
  -u "<client_id>:<client_secret>" \
  -d "grant_type=client_credentials&scope=payment:write payment:read card:write card:read"
```

`clientSecret` is a **merchant** secret. It exists here only so `MerchantBackendSimulator` can
stand in for your server — never ship it in a real app. `MerchantBackendSimulator` itself never
reads a base URL from `DemoConfig` directly — it reads
`GopaySDK.shared.config?.environment.baseURL`, i.e. whatever the SDK is actually pointed at right
now, so it can never drift out of sync with an environment switch.

## Code references

- App entry: [`exampleApp.swift`](example/exampleApp.swift)
- Launcher + environment switcher: [`RootView.swift`](example/RootView.swift)
- Environment/credential bundles: [`DemoConfig.swift`](example/DemoConfig.swift)
- Launch-time overrides: [`DemoOverrides.swift`](example/DemoOverrides.swift)
- Demo checkout: [`Checkout/CheckoutView.swift`](example/Checkout/CheckoutView.swift),
  [`Checkout/CheckoutViewModel.swift`](example/Checkout/CheckoutViewModel.swift),
  [`Checkout/BankTransferSheet.swift`](example/Checkout/BankTransferSheet.swift),
  [`Checkout/CheckoutResultView.swift`](example/Checkout/CheckoutResultView.swift)
- Developer sandbox: [`ContentView.swift`](example/ContentView.swift)
- Simulated backend (token, create payment, card tokenization):
  [`MerchantBackendSimulator.swift`](example/MerchantBackendSimulator.swift)

For SDK API details see the top-level [README.md](../README.md).
